# UX の原則 — 人間と AI に、同じシェルを

人間には fish のような気持ちよさを、AI には推測のいらない構造を。両者が同じ評価器・同じ知識ベース・同じ安全判定を共有するので、片方だけが知っている情報がない状態を作ります。

01

同じ情報を、人には見た目で、AI には構造で

画面に出るものはすべて JSON のフィールドに対応させる。片方にしかない情報を作らない。

02

止めずに知らせる、ただし AI には止める

人が打ったコマンドは危険度を表示するだけ (block だけ 2 度押し)。AI からの confirm は承認がないと実行しない。

03

次の一手まで見せる

エラー・失敗・提案のどれにも「どう直すか」を添える。人には Alt-Enter、AI には fixes[]。

04

静かな既定値

出力は必要なときだけ。挨拶・色・右プロンプト・進行表示は意味があるときだけ出す。

05

1 つの操作体系

AI パネルのキーは 1 組、エラーの形は 1 つ、応答の型は 1 つ。覚えることを増やさない。

U1 · 人間

入力しているとき

U2 · 人間

失敗したとき

U3 · 人間

AI の提案を受けるとき

U4 · 人間

はじめてと、迷ったとき

U5 · AI

AI のセッションの流れ

U6 · AI

応答の型と出力の節約

U7 · AI

承認と共有セッション

U8 · 人間

体験をさらに上げる

U9 · 人間

リッチな UI

## 対応表

U1〜U4 の画面要素と、U5〜U7 の応答の型は 1 対 1 で対応します。片方を変えるときはもう片方も変えます。

| 人間が画面で見るもの |   | AI が受け取るフィールド |
|---|---|---|
| ✗ と 1 行の説明 | ⇄ | error.code / error.message |
| ^^^ の位置表示 | ⇄ | error.span {line, column, end} |
| did you mean … · Alt-Enter | ⇄ | error.fixes[] {input, why, rule} |
| ● safe / confirm / block | ⇄ | safety.level |
| 理由 (Tab で開く) | ⇄ | safety.reasons[] {rule, text} |
| effects: deletes target/ | ⇄ | effects[] {kind, path, size} |
| ブロックの見出し・畳んだ行の ✓ / ✗ 2 · 0.8s | ⇄ | status / duration_ms / state.cwd |
| ステータスライン・右プロンプトのジョブ数 | ⇄ | state.jobs[] |
| 補完メニューの候補と説明 | ⇄ | complete → candidates[] {text, kind, description} |
| F1 のヘルプパネル | ⇄ | help → {flags[], exclusive[], examples[]} |
| 出力が長いときの … (省略) | ⇄ | stdout.truncated / stdout.path |
| {ai} の件数 | ⇄ | history[] origin = "ai" |
