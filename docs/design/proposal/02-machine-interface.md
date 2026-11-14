# AI がシェルを使いやすくする

エージェントは画面を読むより、構造化された結果を受け取る方が正確です。対話 REPL と同じ評価器の上に、機械向けの入口を 2 つ足します。

追加

### --json 単発実行

1 コマンドを実行し、結果を 1 つの JSON で返す。CI・スクリプト・ツール呼び出し向け。

```
$ nshell --json --command '(| (git status --short) (wc -l))'
{"ok": true, "status": 0, "duration_ms": 41,
 "stdout": {"text": "3\n", "bytes": 2, "lines": 1,
            "truncated": false},
 "stderr": {"text": "", "bytes": 0},
 "effects": [{"kind": "reads", "path": "."}],
 "safety": {"level": "safe", "reasons": []},
 "state": {"cwd": "/home/me/src/nshell"}}
```

追加

### --serve セッション

cd・変数・ジョブなどの状態を保持したまま、JSON Lines で何度でも実行できる。エージェントが「同じシェル」を使い続けられる。

```
$ nshell --serve          # stdio 上の JSON Lines。セッション状態を保持
> {"id":1,"method":"run","params":{"input":"cd src"}}
< {"id":1,"result":{"ok":true,"status":0,
                    "state":{"cwd":"/home/me/src/nshell/src"}}}
> {"id":2,"method":"run","params":{"input":"(jobs)"}}
< {"id":2,"result":{"ok":true,"status":0,"value":[]}}
> {"id":3,"method":"explain","params":{"input":"rm -rf build"}}
< {"id":3,"result":{"ok":true,
    "effects":[{"kind":"deletes","path":"build/"}],
    "safety":{"level":"confirm","reasons":[
      {"rule":"classify/delete-dir","text":"recursive delete"}]}}}
```

## 同じメソッドを MCP ツールとして公開

既存の --mcp は read_state だけ。--serve と同じ 10 メソッドを MCP ツールにし、Claude Code などから nshell をそのまま使えるようにする。応答の形は U6 の共通の型。

|   |   |
|---|---|
| run | 入力を評価。status / stdout / stderr / value / error を返す |
| explain | 実行せずに AST・危険度 (safe / confirm / block)・理由を返す |
| complete | LINE とカーソル位置から補完候補と説明を返す |
| state | cwd・変更された環境変数・ジョブ・直前の status |
| history | 検索条件つきで履歴をレコードとして返す |
| help | ビルトインの仕様 (引数・オプション・例) を返す |
| initialize | 版・メソッド・制限・ポリシーの要約 (U5) |
| policy | 安全規則の一覧 (U7) |
| read_output | 省略された出力の続き (U6) |
| query | 知識ベースへの問い合わせ (06-F) |

実行ポリシー

- safe: そのまま実行
- confirm: 人の承認が必要。承認手段がなければ E_NEEDS_APPROVAL で返し、実行しない
- block: 常に拒否 (E_BLOCKED_BY_POLICY)
- 既存の safety 分類と redaction (秘匿化) をそのまま流用

追加

## 構造化エラー

人間向けには U2 の表示、JSON では安定したコード・位置・修正候補を返す。言語のエラーコード (E_ARG_TYPE など) は L6。

```
{
  "status": 127,
  "error": {
    "code": "E_COMMAND_NOT_FOUND",
    "message": "gti: command not found",
    "span": {"line": 1, "column": 1, "end": 4},
    "fixes": [{"input": "git status",
               "why": "edit distance 1",
               "rule": "diagnose/typo"}]
  }
}
```

|   |   |
|---|---|
| E_PARSE | 構文エラー。span で位置を示す |
| E_COMMAND_NOT_FOUND | コマンドが見つからない。近い候補を fixes に |
| E_PERMISSION | 権限不足 |
| E_TIMEOUT | --timeout 超過。プロセスグループごと停止 |
| E_INTERRUPTED | SIGINT などで中断 |
| E_NEEDS_APPROVAL | confirm 判定で承認が得られていない |
| E_BLOCKED_BY_POLICY | block 判定 |
| E_WAITING_FOR_INPUT | 子プロセスが端末からの入力を待った (U6) |
| E_INTERACTIVE_PROGRAM | 全画面のプログラムを起動した (U6) |

追加

## 非対話時は決定的に

- TTY でない、または NSHELL_AGENT=1 のとき: 色・プロンプト・ページャ・autosuggest を無効化
- 出力が上限を超えたら先頭と末尾を残して truncated: true、全文は一時ファイルに保存してパスを返す
- --timeout SEC を標準装備 (既存の SIGTERM → SIGKILL エスカレーションを流用)
- 対話モードでは OSC 133 (セマンティックプロンプト) を出し、端末上のエージェントがプロンプト・入力・出力を区別できるようにする

追加

## 自己記述とレコードを返すビルトイン

help --json / type --json NAME / complete -C LINE --json で、AI が推測せずに仕様を引ける。jobs・history などは値位置でレコードを返し、ファイル一覧は (files …) で取る。テキストを解析させない (L4)。

```
(-> (jobs) (where (= :state "stopped")) (select :id :command) (to-json))
(-> (files "src") (where (> :size 10000)) (select :name :size))
(-> (history :limit 20) (where (/= :status 0)))
```
