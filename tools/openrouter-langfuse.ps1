<#
.SYNOPSIS
  OpenRouter の observability destination（Langfuse）を API で一覧・検証・作成する。

.DESCRIPTION
  前提:
    - OpenRouter の **Management API key**（https://openrouter.ai/settings/management-keys）が必要。
      推論用の sk-or-v1-... （/api/v1/chat/completions 用）では 401 になる。
    - Langfuse プロジェクトの baseUrl / publicKey(pk-lf-...) / secretKey(sk-lf-...) が必要。
      値は引数か環境変数で渡す。このスクリプトは秘密を保存しない。

  環境変数:
    OPENROUTER_MANAGEMENT_KEY, LANGFUSE_BASE_URL, LANGFUSE_PUBLIC_KEY, LANGFUSE_SECRET_KEY

.EXAMPLE
  # 1) 既存 destination の一覧（疎通確認を兼ねる）
  .\openrouter-langfuse.ps1 -Action List

.EXAMPLE
  # 2) Langfuse 側の鍵が生きているか先に確認
  .\openrouter-langfuse.ps1 -Action Verify

.EXAMPLE
  # 3) 作成（まず DryRun で本文を確認）
  .\openrouter-langfuse.ps1 -Action Create -DryRun
  .\openrouter-langfuse.ps1 -Action Create -Name "bonsai workspace" -EnableCostBroadcast
#>

[CmdletBinding()]
param(
    [ValidateSet('List', 'Verify', 'Create')]
    [string]$Action = 'List',

    [string]$ManagementKey = $env:OPENROUTER_MANAGEMENT_KEY,

    [string]$LangfuseBaseUrl = $(if ($env:LANGFUSE_BASE_URL) { $env:LANGFUSE_BASE_URL } else { 'https://us.cloud.langfuse.com' }),
    [string]$LangfusePublicKey = $env:LANGFUSE_PUBLIC_KEY,
    [string]$LangfuseSecretKey = $env:LANGFUSE_SECRET_KEY,

    [string]$Name = 'Langfuse',
    [string]$WorkspaceId,

    # 生成メタデータの同梱（既定はすべて false = OpenRouter の既定値）
    [switch]$EnableCostBroadcast,
    [switch]$EnableCostAllocation,
    [switch]$EnableIdentity,
    [switch]$EnableRequestContext,

    [switch]$PrivacyMode,
    [ValidateRange(0.0001, 1)]
    [double]$SamplingRate = 1,
    [string[]]$Regions = @('global'),

    [switch]$DryRun,

    # KEY=VALUE 形式の env ファイル（例: "$env:USERPROFILE\.openrouter-langfuse.env"）。
    # 既に引数/環境変数で渡された値が優先される。
    [string]$EnvFile
)

$ErrorActionPreference = 'Stop'
$ApiBase = 'https://openrouter.ai/api/v1'
$DestinationsUrl = "$ApiBase/observability/destinations"

if ($EnvFile) {
    if (-not (Test-Path $EnvFile)) {
        Write-Host "NG: env ファイルが見つかりません: $EnvFile" -ForegroundColor Red
        exit 1
    }
    $kv = @{}
    Get-Content $EnvFile | ForEach-Object {
        $line = $_.Trim()
        if (-not $line -or $line.StartsWith('#')) { return }
        $i = $line.IndexOf('=')
        if ($i -lt 1) { return }
        $kv[$line.Substring(0, $i).Trim()] = $line.Substring($i + 1).Trim()
    }
    if ([string]::IsNullOrWhiteSpace($ManagementKey)) { $ManagementKey = $kv['OPENROUTER_MANAGEMENT_KEY'] }
    if ([string]::IsNullOrWhiteSpace($LangfusePublicKey)) { $LangfusePublicKey = $kv['LANGFUSE_PUBLIC_KEY'] }
    if ([string]::IsNullOrWhiteSpace($LangfuseSecretKey)) { $LangfuseSecretKey = $kv['LANGFUSE_SECRET_KEY'] }
    if (-not $PSBoundParameters.ContainsKey('LangfuseBaseUrl') -and $kv['LANGFUSE_BASE_URL']) {
        $LangfuseBaseUrl = $kv['LANGFUSE_BASE_URL']
    }
}

function Show-ApiError($err) {
    $msg = $err.Exception.Message
    if ($err.ErrorDetails.Message) { $msg = "$msg`n$($err.ErrorDetails.Message)" }
    Write-Host "NG: $msg" -ForegroundColor Red
}

function Assert-Key($value, $envName, $hint) {
    if (-not [string]::IsNullOrWhiteSpace($value)) { return }
    Write-Host "NG: $envName が未設定です。" -ForegroundColor Red
    Write-Host "    $hint" -ForegroundColor Yellow
    exit 1
}

switch ($Action) {

    'Verify' {
        Assert-Key $LangfusePublicKey 'LANGFUSE_PUBLIC_KEY' 'Langfuse のプロジェクト設定 > API Keys の pk-lf-... を入れてください。'
        Assert-Key $LangfuseSecretKey 'LANGFUSE_SECRET_KEY' '同ページの sk-lf-... を入れてください。'
        $token = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${LangfusePublicKey}:${LangfuseSecretKey}"))
        $url = "$($LangfuseBaseUrl.TrimEnd('/'))/api/public/projects"
        try {
            $r = Invoke-RestMethod -Uri $url -Headers @{ Authorization = "Basic $token" } -TimeoutSec 30
            Write-Host "OK: Langfuse 認証成功 ($url)" -ForegroundColor Green
            $r.data | ForEach-Object { "  project: $($_.name)  id=$($_.id)" }
        } catch {
            Show-ApiError $_
            Write-Host "hint: baseUrl ($LangfuseBaseUrl) と鍵の組を確認。EU なら https://cloud.langfuse.com、US なら https://us.cloud.langfuse.com。" -ForegroundColor Yellow
            exit 1
        }
    }

    'List' {
        Assert-Key $ManagementKey 'OPENROUTER_MANAGEMENT_KEY' 'https://openrouter.ai/settings/management-keys で作成してください（推論用 API キーでは 401）。'
        $url = "${DestinationsUrl}?limit=100"
        if ($WorkspaceId) { $url += "&workspace_id=$WorkspaceId" }
        try {
            $r = Invoke-RestMethod -Uri $url -Headers @{ Authorization = "Bearer $ManagementKey" } -TimeoutSec 30
        } catch {
            Show-ApiError $_
            Write-Host "hint: Management key か確認（推論キーは 401 / 期限切れは 'API key expired'）。" -ForegroundColor Yellow
            exit 1
        }
        "count: $($r.total_count)"
        $r.data | ForEach-Object {
            $cfg = $_.config
            $shown = (@($cfg.PSObject.Properties | ForEach-Object {
                if ($_.Name -match 'secret|token|key') { "$($_.Name)=***" } else { "$($_.Name)=$($_.Value)" }
            }) -join ', ')
            "  [$($_.type)] $($_.name)  enabled=$($_.enabled) privacy=$($_.privacy_mode) id=$($_.id)  $shown"
        }
    }

    'Create' {
        Assert-Key $LangfusePublicKey 'LANGFUSE_PUBLIC_KEY' 'Langfuse の pk-lf-... を入れてください。'
        Assert-Key $LangfuseSecretKey 'LANGFUSE_SECRET_KEY' 'Langfuse の sk-lf-... を入れてください。'

        $body = [ordered]@{
            type                        = 'langfuse'
            name                        = $Name
            config                      = [ordered]@{
                baseUrl   = $LangfuseBaseUrl.TrimEnd('/')
                publicKey = $LangfusePublicKey
                secretKey = $LangfuseSecretKey
            }
            enabled                     = $true
            privacy_mode                = [bool]$PrivacyMode
            sampling_rate               = $SamplingRate
            regions                     = @($Regions)
            broadcast_generation_cost             = [bool]$EnableCostBroadcast
            broadcast_generation_cost_allocation  = [bool]$EnableCostAllocation
            broadcast_generation_identity         = [bool]$EnableIdentity
            broadcast_generation_request_context  = [bool]$EnableRequestContext
        }
        if ($WorkspaceId) { $body.workspace_id = $WorkspaceId }
        $json = $body | ConvertTo-Json -Depth 6

        if ($DryRun) {
            $masked = $json -replace '("(secretKey|publicKey)"\s*:\s*")[^"]+', '$1***'
            Write-Host '--- DryRun: 送信内容（鍵は伏字）---' -ForegroundColor Cyan
            $masked
            Write-Host "POST $DestinationsUrl"
            return
        }

        Assert-Key $ManagementKey 'OPENROUTER_MANAGEMENT_KEY' 'https://openrouter.ai/settings/management-keys で作成してください。'
        try {
            $r = Invoke-RestMethod -Method Post -Uri $DestinationsUrl -TimeoutSec 60 `
                -Headers @{ Authorization = "Bearer $ManagementKey"; 'Content-Type' = 'application/json' } `
                -Body ([Text.Encoding]::UTF8.GetBytes($json))
        } catch {
            Show-ApiError $_
            exit 1
        }
        $d = $r.data
        Write-Host "OK: destination を作成しました" -ForegroundColor Green
        "  id=$($d.id)  type=$($d.type)  name=$($d.name)  enabled=$($d.enabled)"
        "  regions=$($d.regions -join ',')  sampling=$($d.sampling_rate)  privacy=$($d.privacy_mode)"
        Write-Host "次: OpenRouter observability > Destinations で status を確認 → Langfuse の Tracing に届くか数リクエスト流して確認。" -ForegroundColor Cyan
    }
}
