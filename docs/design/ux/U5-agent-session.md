# AI の UX ① セッションの流れ

エージェントが「知る → 確かめる → 動かす → 読む → 直す」を最短で回せるようにします。--serve でも MCP でも同じメソッドです。

STEP 1

知る

initialize

版・使えるメソッド・制限・ポリシーの要約・cwd と OS を 1 回で受け取る

›

STEP 2

確かめる

explain

実行せずに AST・効果・危険度と理由を得る

›

STEP 3

動かす

run

timeout と出力上限を指定して実行

›

STEP 4

読む

結果

status・stdout・value・effects を構造で受け取る

›

STEP 5

直す

fixes[]

エラーコードと修正候補から次の run を組む

initialize

```
> {"id":1,"method":"initialize","params":{"client":"claude-code"}}
< {"id":1,"result":{
    "nshell_api": 1, "version": "0.8.0",
    "methods": ["run","explain","complete","state","history",
                "help","query","read_output","policy"],
    "limits": {"timeout_s": 120, "max_output_bytes": 32768},
    "policy": {"block": 14, "confirm": 31, "user_rules": 2},
    "session": {"id": "s_4b1", "cwd": "/home/me/src/nshell",
                "os": "linux", "attached": false}}}
```

最初の 1 回で、推測に必要な情報をすべて渡す。

失敗から直すまで

```
> {"id":7,"method":"run","params":{"input":"gti status"}}
< {"id":7,"result":{"ok":false,"status":127,
    "error":{"code":"E_COMMAND_NOT_FOUND",
             "message":"gti: command not found",
             "fixes":[{"input":"git status",
                       "why":"edit distance 1 to a known command",
                       "rule":"diagnose/typo"}]}}}
> {"id":8,"method":"run","params":{"input":"git status"}}
```

fixes をそのまま次の入力にできる。

## AI のための約束

- 応答の形は全メソッドで同じ (U6)。フィールドの追加はしても、意味の変更や削除は nshell_api を上げる。
- エラーコードは列挙型で固定。メッセージ文は人向けで、AI は code と fixes を見る。
- 同じ入力・同じ状態なら同じ結果 (色・幅・ロケール・ページャを固定)。
- help と query で仕様と事実を引けるので、AI はフラグを推測しなくてよい。
- explain と run の判定は同じ規則から出る。explain で safe なら run でも止まらない。
