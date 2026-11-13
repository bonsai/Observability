# W&B × Kaggle セットアップ（セキュア版）

Weights & Biases の API key を **Kaggle Secrets** 経由で使う手順。
（鍵はコード・チャット・repo に貼らない。Secrets に保存 → ノートブックから取得）

## 手順

1. **鍵を Kaggle Secrets に保存**（Kaggle の UI で行う — ノートブック外）
   - ノートブックを開く → 右ペイン **Add-ons → Secrets**
   - Label: `WANDB_API_KEY` / Value: API key を貼り付け → **Attach to notebook** を有効化
   - ノートブック設定で **Internet** を ON
2. 検証セル（鍵はコードに現れない）:

```python
%pip install -q -U wandb

import wandb
from kaggle_secrets import UserSecretsClient

wandb.login(key=UserSecretsClient().get_secret("WANDB_API_KEY"))

with wandb.init(project="kaggle-test", name="connection-check") as run:
    run.log({"test_metric": 1})
print("run:", run.url)
```

3. 表示された W&B の run リンクで接続を確認

## 進化・分析 run への組み込み（次ステップ）

- ファイル進化計画の分析（P11/P12 の churn 観測など）を Kaggle で回すとき、
  `run.log({"churn": ..., "events": ...})` を差し込むと W&B 側に時系列が蓄積する
- repo_snapshots / file_manifests / events の各 JSONL は repo（data/evolution/）と
  Drive にあるので、ノートブックからは git pull → 読み込みで使える

## セキュリティ

- 鍵をチャット・コードセル・repo に貼った場合は、W&B の API Keys ページで
  **再生成（rotate）** して Kaggle Secrets を差し替える
- Secrets はノートブックに Attach した人だけが読める（コードには出てこない）
