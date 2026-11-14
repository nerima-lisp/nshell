# AI がシェルを使いやすくする

エージェントは画面を読むより、構造化された結果を受け取る方が正確です。対話 REPL と同じ評価器の上に、機械向けの入口を 2 つ足します。

追加

### --json 単発実行

1 コマンドを実行し、結果を 1 つの JSON で返す。CI・スクリプト・ツール呼び出し向け。

```
$ nshell --json --command '(| (git status --short) (wc -l))'
{"nshell_api": 1, "ok": true, "status": 0, "duration_ms": 41,
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

- 要求は届いた順に 1 つずつ処理する。
- 要求そのものを処理できない失敗 (要求の形が不正、未知のメソッド、E_PROTOCOL など) は、トップレベルの `{"id":…,"error":{"code":"E_…"}}` の形で返す。
- 実行したコマンドの失敗 (E_COMMAND_NOT_FOUND など) は、`result` の envelope (`ok:false`・`status`・`error.code`) で返す (U5、U7 の例)。
- バックグラウンドジョブの出力はプロトコルの標準出力に出さず、read_output で返す。
- 人が開いている対話セッションにつなぐときは `--attach [PATH|ID]` を使う (U7)。`--mcp` にも付けられる。

## 同じメソッドを MCP ツールとして公開

既存の --mcp は list_sessions と read_state だけ。--serve と同じ 10 メソッドを MCP ツールにし、Claude Code などから nshell をそのまま使えるようにする。応答の形は U6 の共通の型。

- 承認画面 (elicitation) を使うため、MCP のプロトコルを 2025-06-18 に上げる。
- list_sessions と read_state は 1 リリースのあいだ非推奨として残す。
- query は知識ベースへの問い合わせ (P4) ができるまで、E_NOT_IMPLEMENTED (isError) を返す。
- セッションは 1 つのサーバープロセスに 1 つ。

|   |   |
|---|---|
| run | 入力を評価。status / stdout / stderr / value / error を返す |
| explain | 実行せずに AST・危険度 (safe / confirm / block)・理由を返す。forms には各形式の kind を入れる (名前解決の rule は言語仕様の実装 (P2) までは null)。CLI では `nshell [--json] explain '…'` |
| complete | LINE とカーソル位置から補完候補と説明を返す |
| state | cwd・変更された環境変数・ジョブ・直前の status |
| history | 検索条件つきで履歴をレコードとして返す |
| help | ビルトインの仕様 (引数・オプション・例) を返す |
| initialize | 版・メソッド・制限・ポリシーの要約 (U5) |
| policy | 安全規則の一覧 (U7) |
| read_output | 省略された出力の続き。不透明な id と offset で読み、出力の保存先の外は拒否する (U6) |
| query | 知識ベースへの問い合わせ (06-F) |

実行ポリシー

承認を求めるのは、NSHELL_AGENT=1 のとき、MCP、--serve の 3 つ。既存の origin 判定を通す。--json の単発実行は危険度を報告するだけで、承認は求めない。

- safe: そのまま実行。MCP でも承認なしで実行する
- confirm: 人の承認が必要。承認 ID がなければ E_NEEDS_APPROVAL を返し、実行しない。承認できる人がいないときは、承認 ID を付けずに E_NEEDS_APPROVAL を返す
- block: 常に拒否 (E_BLOCKED_BY_POLICY)
- 既存の safety 分類と redaction (秘匿化) をそのまま流用

危険度の基本は次のとおり (規則は 06-A)。

| 入力 | 危険度 |
|---|---|
| 読むだけの既知のコマンド (git status・git log・git diff・ls・cat など) | safe |
| 未知のコマンド | confirm |
| ルート以外への rm -r (rm -rf build など) | confirm |
| ルートの再帰削除 | block |

承認 ID は `ap_` と 16 進 16 桁で、有効期限は 120 秒、1 回だけ使える。セッション・入力のバイト列・cwd に結びつけるので、どれかが違えば使えない。期限が切れていれば、新しい ID つきの E_NEEDS_APPROVAL を返す (U7)。

追加

## 構造化エラー

人間向けには U2 の表示、JSON では安定したコード・位置・修正候補を返す。言語のエラーコード (E_ARG_TYPE など) は L6。error.code は列挙型で、エラーコードの一覧にないコードは返さない。

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

| コード | 意味 | 終了コード |
|---|---|---|
| E_PARSE | 構文エラー。span で位置を示す | 2 |
| E_UNSUPPORTED_SYNTAX | 削除した構文 (bare-line の制御構文など)。同じ意味の S式を示す (L5) | 2 |
| E_PROTOCOL | --serve・MCP のプロトコルのエラー | 2 |
| E_ARG_TYPE・E_VALUE_POSITION・E_NO_MATCH・E_REDIRECT_TARGET・E_LISP_ERROR | 言語のエラー (L6) | 1 |
| E_NOT_IMPLEMENTED | まだ実装していない機能 | 1 |
| E_COMMAND_FAILED | 外部コマンドが失敗した | 子の終了コード |
| E_COMMAND_NOT_FOUND | コマンドが見つからない。近い候補を fixes に | 127 |
| E_PERMISSION | 権限不足 | 126 |
| E_TIMEOUT | --timeout 超過。プロセスグループごと停止 | 124 |
| E_INTERRUPTED | SIGINT などで中断 | 130 |
| E_NEEDS_APPROVAL | confirm 判定で承認が得られていない | 3 |
| E_BLOCKED_BY_POLICY | block 判定 | 4 |
| E_WAITING_FOR_INPUT | 子プロセスが端末からの入力を待った (U6) | 5 |
| E_INTERACTIVE_PROGRAM | 全画面のプログラムを起動した (U6) | 6 |
| E_INTERNAL | nshell 自身の想定外のエラー | 70 |

警告には W_ で始まるコードを付ける。v0.7 の AI の承認ゲートは 126 で終了するが、P1 で E_NEEDS_APPROVAL の 3 と E_BLOCKED_BY_POLICY の 4 に変え、リリースノートに書く。

追加

## 非対話時は決定的に

- 機械向けモード (--json・--serve・MCP) と NSHELL_AGENT=1 のときだけ、色・プロンプト・ページャ・autosuggest を無効にし、U6 の既定環境 (PAGER=cat など) に変える。それ以外のバッチ (TTY でない入力) の挙動は変えない
- 出力が上限を超えたら先頭と末尾を残して truncated: true。切り詰めの印は英語で固定
- --json の全出力は `$XDG_CACHE_HOME/nshell/out/<session>/` に保存する。ディレクトリは mkdtemp で 0700 に作り、ファイルは 0600。直近 50 セッション分だけ残し、--private では保存しない
- --timeout SEC は実行全体の期限。--json の既定は 120 秒で、超えたらプロセスグループごと止めて E_TIMEOUT を返す。既定値は initialize の応答で知らせる。通常のバッチは今のまま (外部コマンドごとに 3600 秒)。停止には既存の SIGTERM → SIGKILL エスカレーションを流用
- 入力待ちは、子を PTY と背景プロセスグループで動かし、SIGTTIN と WUNTRACED で検出する。全画面のプログラムは、コマンド名の表と `ESC[?1049h` で検出する
- 対話モードでは OSC 133 (セマンティックプロンプト) を出し、端末上のエージェントがプロンプト・入力・出力を区別できるようにする

追加

## 自己記述とレコードを返すビルトイン

help --json / type --json NAME / complete -C LINE --json で、AI が推測せずに仕様を引ける。jobs・history などは値位置でレコードを返し、ファイル一覧は (files …) で取る。テキストを解析させない (L4)。

```
(-> (jobs) (where (= :state "stopped")) (select :id :command) (to-json))
(-> (files "src") (where (> :size 10000)) (select :name :size))
(-> (history :limit 20) (where (/= :status 0)))
```
