/**
 * bridge.gs — LLM 観測ブリッジ（wiki #398 / observability-plan §5 系統 4）
 *
 * Drive の evolution JSONL（llm_requests.jsonl / balance_snapshots.jsonl）を読み:
 *   1. Langfuse ingestion API に POST（トレース化 — モデル別の可視化が Langfuse でできる）
 *   2. Google Sheets にダッシュボード（requests 全行 + model 別サマリ）を書き出し
 *
 * Script Properties（プロジェクト設定 → スクリプト プロパティ）:
 *   LANGFUSE_HOST        例: https://cloud.langfuse.com
 *   LANGFUSE_PUBLIC_KEY  pk-lf-...
 *   LANGFUSE_SECRET_KEY  sk-lf-...
 *   EVOLUTION_FOLDER_ID  Drive フォルダ ID（wiki/.metadata/evolution の URL から取得）
 *
 * 使い方:
 *   1. setupTriggers() を 1 回実行 → 時間トリガー（毎時）を設置
 *   2. bridgeLangfuseNow() / updateSheetNow() で手動即実行も可
 *
 * 状態管理: LAST_LANGFUSE_TS（前回成功時点の timestamp）。成功後に更新するため
 * 失敗時は再実行で取れる。Langfuse 側は trace id で重複排除するので二重 POST も安全。
 */

var PROPS = PropertiesService.getScriptProperties();
var REQUESTS_FILE = 'llm_requests.jsonl';
var SHEET_NAME = 'observability-dashboard';

function getConfig() {
  return {
    host: (PROPS.getProperty('LANGFUSE_HOST') || 'https://cloud.langfuse.com').replace(/\/+$/, ''),
    pk: PROPS.getProperty('LANGFUSE_PUBLIC_KEY') || '',
    sk: PROPS.getProperty('LANGFUSE_SECRET_KEY') || '',
    folderId: PROPS.getProperty('EVOLUTION_FOLDER_ID') || ''
  };
}

function getEvolutionFolder_() {
  var id = getConfig().folderId;
  if (!id) throw new Error('EVOLUTION_FOLDER_ID が未設定です（Script Properties）');
  return DriveApp.getFolderById(id);
}

/** 指定名の JSONL（同一名があれば最新）を読み、行オブジェクト配列にパース */
function readJsonl_(folder, name) {
  var it = folder.getFilesByName(name);
  if (!it.hasNext()) return [];
  var text = it.next().getBlob().getDataAsString('utf-8');
  var rows = [];
  String(text).split('\n').forEach(function (line) {
    if (!line.trim()) return;
    try { rows.push(JSON.parse(line)); } catch (e) { /* 壊れた行はスキップ */ }
  });
  return rows;
}

/** Langfuse ingestion API（basic auth、batch 形式） */
function postIngestion_(cfg, batch) {
  var auth = Utilities.base64Encode(cfg.pk + ':' + cfg.sk, Utilities.Charset.UTF_8);
  var res = UrlFetchApp.fetch(cfg.host + '/api/public/ingestion', {
    method: 'post',
    contentType: 'application/json',
    headers: { Authorization: 'Basic ' + auth },
    payload: JSON.stringify({ batch: batch, metadata: { source: 'gas-bridge' } }),
    muteHttpExceptions: true
  });
  if (res.getResponseCode() >= 300) {
    throw new Error('Langfuse ingestion failed: ' + res.getResponseCode() +
      ' ' + res.getContentText().slice(0, 300));
  }
}

/** メイン: 新着の llm_requests を Langfuse トレースとして投稿（毎時トリガー） */
function bridgeLangfuseNow() {
  var cfg = getConfig();
  if (!cfg.pk || !cfg.sk) throw new Error('Langfuse 鍵が未設定です（Script Properties）');
  var rows = readJsonl_(getEvolutionFolder_(), REQUESTS_FILE);
  var lastTs = PROPS.getProperty('LAST_LANGFUSE_TS') || '';
  var pending = rows.filter(function (r) {
    return (!lastTs || String(r.timestamp || '') > lastTs);
  });
  if (!pending.length) {
    Logger.log('新着なし（rows=' + rows.length + ' LAST_TS=' + lastTs + '）');
    return;
  }
  var batch = pending.map(function (r) {
    return {
      id: Utilities.getUuid(),
      type: 'trace',
      timestamp: r.timestamp,
      body: {
        id: String(r.run_id || 'req') + ':' + String(r.id),
        name: String(r.model || 'unknown'),
        timestamp: r.timestamp,
        input: String(r.prompt || ''),
        output: String(r.response || ''),
        metadata: {
          run_id: r.run_id, provider: r.provider, task: r.task,
          smartness: r.smartness, response_time_ms: r.response_time_ms,
          cost_usd: r.cost_usd, error: r.error
        },
        sessionId: String(r.run_id || '')
      }
    };
  });
  for (var i = 0; i < batch.length; i += 100) { // payload 制限の保険で 100 件ずつ
    postIngestion_(cfg, batch.slice(i, i + 100));
  }
  var maxTs = pending.map(function (r) { return String(r.timestamp || ''); }).sort().pop();
  PROPS.setProperty('LAST_LANGFUSE_TS', maxTs);
  Logger.log('Langfuse posted: ' + batch.length + ' traces（LAST_TS=' + maxTs + '）');
}

/** Sheets ダッシュボード（requests 全行 + model 別サマリ） */
function updateSheetNow() {
  var folder = getEvolutionFolder_();
  var rows = readJsonl_(folder, REQUESTS_FILE);
  var ss = getOrCreateSpreadsheet_(SHEET_NAME, folder);
  writeSheet_(ss, 'requests', rows);
  writeSheet_(ss, 'summary', summarize_(rows));
  Logger.log('sheets updated: requests ' + rows.length + ' rows');
}

/** model 別サマリ（件数 / エラー数 / 平均 smartness / 平均応答 ms / cost 合計） */
function summarize_(rows) {
  var byModel = {};
  rows.forEach(function (r) {
    var m = r.model || 'unknown';
    byModel[m] = byModel[m] || { model: m, count: 0, errors: 0,
      smartnessSum: 0, timeSum: 0, costSum: 0 };
    var b = byModel[m];
    b.count += 1;
    if (r.error) b.errors += 1;
    b.smartnessSum += Number(r.smartness || 0);
    b.timeSum += Number(r.response_time_ms || 0);
    b.costSum += Number(r.cost_usd || 0);
  });
  var out = [['model', 'requests', 'errors', 'avg_smartness', 'avg_response_ms', 'total_cost_usd']];
  Object.keys(byModel).sort().forEach(function (m) {
    var b = byModel[m];
    out.push([m, b.count, b.errors,
      (b.smartnessSum / b.count).toFixed(2), Math.round(b.timeSum / b.count), b.costSum]);
  });
  return out;
}

function getOrCreateSpreadsheet_(name, folder) {
  var it = folder.getFilesByName(name);
  if (it.hasNext()) return SpreadsheetApp.openById(it.next().getId());
  var ss = SpreadsheetApp.create(name);
  folder.addFile(DriveApp.getFileById(ss.getId()));
  DriveApp.getRootFolder().removeFile(DriveApp.getFileById(ss.getId()));
  return ss;
}

function writeSheet_(ss, sheetName, data) {
  var sh = ss.getSheetByName(sheetName) || ss.insertSheet(sheetName);
  sh.clear();
  if (!data.length) return;
  var header = data[0] instanceof Array ? data[0] : Object.keys(data[0]);
  sh.getRange(1, 1, 1, header.length).setValues([header]);
  var body = data.map(function (r) {
    return r instanceof Array ? r : header.map(function (k) { return r[k]; });
  });
  sh.getRange(2, 1, body.length, header.length).setValues(body);
}

/** トリガー設置（1 回だけ実行）: 毎時 bridgeLangfuseNow + updateSheetNow */
function setupTriggers() {
  ScriptApp.getProjectTriggers().forEach(function (t) { ScriptApp.deleteTrigger(t); });
  ScriptApp.newTrigger('bridgeLangfuseNow').timeBased().everyHours(1).create();
  ScriptApp.newTrigger('updateSheetNow').timeBased().everyHours(1).create();
  Logger.log('triggers set: bridgeLangfuseNow / updateSheetNow（毎時）');
}
