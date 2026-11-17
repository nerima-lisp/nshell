# AI がシェルを使いやすくする

エージェントは画面を読むより、構造化された結果を受け取る方が正確です。対話 REPL と同じ評価器の上に、機械向けの入口を 2 つ足します。

追加

### --json 単発実行

1 コマンドを実行し、結果を 1 つの JSON で返す。CI・スクリプト・ツール呼び出し向け。

以下は応答の仕様例。この S式は `^` で外部コマンドを明示していないので、`classify/sexp-not-forced` により confirm になる。

```
$ nshell --json --command '(| (git status --short) (wc -l))'
{"nshell_api": 1, "ok": true, "status": 0, "duration_ms": 41,
 "stdout": {"text": "3\n", "bytes": 2, "lines": 1,
            "truncated": false},
 "stderr": {"text": "", "bytes": 0},
 "effects": [{"kind": "reads", "path": "."}],
 "safety": {"level": "confirm", "reasons": [
   {"rule": "classify/sexp-not-forced",
    "text": "S-expression command requires explicit force and has no redirects"}]},
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
    "effects":[{"kind":"deletes","path":"build"}],
    "safety":{"level":"confirm","reasons":[
      {"rule":"classify/delete-dir","text":"deletes a directory"}]}}}
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
- セッションは 1 つのサーバープロセスに 1 つ。cwd・変数・関数は run の呼び出しをまたいで続く。
- ツールの結果は U6 の envelope。`structuredContent` に envelope の object、`content[0]` の text に同じ JSON を入れ、`isError` は ok が false のときだけ true。
- 未知のツール名は JSON-RPC のエラー -32602。ツールの引数が不正なときは、E_PROTOCOL の ok:false の envelope を返す。
- プロトコルの失敗は、JSON-RPC の整数のコードで返す (U6)。
- JSON の object でないメッセージには、id を null にして -32600 を返す。
- E_TIMEOUT の run で、その run を実行するスレッドを止められなかったときは、シェルの状態がまだ変わりうるため、サーバーのプロセスを起動し直すまで run・explain・complete・state は E_INTERNAL を返す。history・help・policy・initialize・query・read_output と非推奨のツールは使える。
- 出力の保存先のセッションのディレクトリは、ほかのプロセスに消されても作り直す。保存に失敗したときは標準エラー出力にだけ知らせる。
- run の引数は `input` と `timeout` (秒。既定は --json と同じ)。U6 の max_output_bytes と tail_lines は MCP の run ではまだ使わず、知らない引数は無視する。tools/list のツールの並びは、initialize ツールの value の `methods` と同じ順 (U5)。

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
| read_output | 省略された出力の続き。不透明な id と offset で読み、出力の保存先の外は拒否する。引数・単位・上限・エラーは U6「read_output で続きを読む」 |
| query | 知識ベースへの問い合わせ (06-F) |

### MCP での承認

- elicitation/create を送るのは、MCP の initialize 要求でネゴシエートした版が 2025-06-18 で、クライアントが elicitation の capability を宣言したときだけ。それ以外のクライアント (2024-11-05 のもの、capability を宣言しないもの) には、confirm の入力に E_NEEDS_APPROVAL を返す。`requestedSchema` は `{approve: boolean}`。
- 承認画面の message は、先頭に `nshell asks to run this confirm input:` の行を置き、次の行に入力を二重引用符で囲んで 1 行で示し、そのあとに理由を `- text (rule)` の 1 行ずつで並べる。人が承認するものを、見たとおりの文字列にするため。
- 入力と理由の文字は、画面で見える形にエスケープする。LF・CR・TAB・ESC は `\n`・`\r`・`\t`・`\e`、そのほかの制御文字・書式文字 (双方向の制御を含む)・行と段落の区切り・私用領域と未割り当ての文字は `\uXXXX` (U+FFFF を超えるときは `\u{XXXXX}`)、バックスラッシュと二重引用符は `\\` と `\"`。
- 実行するのは、action が accept で approve が true のときだけ。decline・cancel・approve が false・エラー応答・入力の終わりは、E_NEEDS_APPROVAL を返す。
- 承認が及ぶのは、承認画面に示した判定 (level と reasons) だけ。承認の応答を受け取ったあと、実行の直前にもう一度判定し、示した判定と違えば実行せず E_NEEDS_APPROVAL を返す。
- MCP では承認 ID (`ap_…`) を P1 では発行しない。
- 応答を待つあいだに届いた要求は保留し、その run のあとで届いた順に処理する。
- 待っているあいだに、その tools/call への notifications/cancelled が届けば、その run は実行せず、seq も履歴も使わず、応答も返さない。保留中の要求への cancelled は、その要求を捨てる。完了したあとの cancelled は無視する。

### MCP ツールの value (P1 の最小の形)

詳細な形はまだ決めていない。

| ツール | 入力 | value |
|---|---|---|
| complete | input、cursor (0 から input の長さまで。既定は末尾。範囲外は E_PROTOCOL) | `{candidates:[{text, kind, description}]}`。行エディタの順。kind と description は、なければ null |
| state | なし | `{cwd, session:{id, seq}, last_status}`。seq は run の回数で、run の前は 0。last_status は直前の run の status で、run の前は null。envelope の state.last_status にも同じ値を入れる |
| history | query (大文字小文字を区別する部分一致)、limit (正の整数。どちらも不正なら E_PROTOCOL) | `{entries:[{seq, input, status}]}`。新しい順に、query で絞ってから limit 件まで。承認されず実行しなかった run も入る。このサーバーの run の記録で、永続する履歴ファイルではない |
| help | topic (ビルトインの名前。大文字小文字を区別する完全一致) | `{topic, text}`。topic がなければ topic は null で、text はビルトインの概要。text は help が出力する文で、末尾の改行を含む。help を持たない topic は E_PROTOCOL (U6 は E_NO_MATCH を glob 用とする) |

list_sessions と read_state の応答は envelope にせず、従来の形のまま。説明は `Deprecated:` で始める。

実行ポリシー

承認を求めるのは、NSHELL_AGENT=1 のとき、MCP、--serve の 3 つ。既存の origin 判定を通す。--json の単発実行は危険度を報告するだけで、承認は求めない。

- safe: そのまま実行。MCP でも承認なしで実行する
- confirm: 人の承認が必要。承認 ID がなければ E_NEEDS_APPROVAL を返し、実行しない。承認できる人がいないときは、承認 ID を付けずに E_NEEDS_APPROVAL を返す
- block: 常に拒否 (E_BLOCKED_BY_POLICY)
- 危険度は 06-A の規則で判定する。redaction (秘匿化) は既存のものをそのまま流用

危険度の基本は次のとおり (規則は 06-A)。

| 入力 | 危険度 |
|---|---|
| コマンド名・すべての引数・リダイレクト・代入の前置きが許可仕様 (spec) に一致するもの | safe |
| 未知のコマンドや spec に一致しないもの | confirm |
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

v0.8 の警告コードは次の 12 個。

| コード | 当たる規則 |
|---|---|
| W_RESOLUTION_ORDER | L7.2「名前解決の順序 (PATH より CL)」 |
| W_VALUE_POSITION | L7.2「,(find …) (find は衝突表でコマンド)」 |
| W_KEYWORD_ARGUMENT | L7.2「:kw を引数にしたとき」 |
| W_MID_WORD_SPECIAL | L7.2「語の途中の , と \|」 |
| W_BRACE_EXPANSION | L7.2「(echo {a,b}c) の brace 展開」 |
| W_LIST_SPLICE | L7.2「$xs が要素ごとの引数になる」 |
| W_STATUS_AS_VALUE | L7.2「(= (cmd) 0) で終了コード」 |
| W_DEFUN_WORD_ARGS | L7.2「S式から defun の関数に語を渡す」 |
| W_NO_MATCH | L7.2「一致しない glob」 |
| W_REDEFINITION | L7.2「L2.2 の名前の再定義」 (defun・define-shell-function・alias・abbr のとき) |
| W_BARE_LINE_UNQUOTE | L7.2「bare-line の ,expr」 |
| W_NAME_CONFLICT | L2.1「同じ名前を defun と、defcmd または alias の両方で定義したとき」 |

追加

## 非対話時は決定的に

- 機械向けモード (--json・--serve・MCP) と NSHELL_AGENT=1 のときだけ、色・プロンプト・ページャ・autosuggest を無効にし、U6 の既定環境 (PAGER=cat など) に変える。それ以外のバッチ (TTY でない入力) の挙動は変えない
- P1-3 で既定を変えるのは機械向けモードと NSHELL_AGENT=1 のバッチだけで、対話シェルで NSHELL_AGENT=1 を設定したときは扱わない
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
