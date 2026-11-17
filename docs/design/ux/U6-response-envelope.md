# AI の UX ② 応答の型と出力の節約

1 つの型を覚えれば全メソッドが読める。長い出力でもコンテキストを食いつぶさず、対話を待つコマンドで固まらない。

## 全メソッド共通の応答

常に出すキーは nshell_api・ok・status・duration_ms・stdout・stderr・effects・safety・state の 9 つ。ほかは必要なときだけ出す。JSON Schema ではトップレベルを `additionalProperties: true` にし、error.code はエラーコードの列挙型で縛る。

Schema は `conformance/envelope.schema.json` に置く。下の表にない細部は Schema で決める。stdout・stderr は text と bytes が必須。error は code だけが必須。state は cwd だけが必須。warnings[] の要素は error と同じ形 (code・message・span・fixes) で、code は W_ の列挙型。forms[] の要素は text・kind・rule (P2-2 までは null)・path。effects[].size は整数か文字列 (U7 の例は "1.2 GB")。ok が true なら status は 0 で error はない。error がないとは、キーを省くか null にすることを指す。

|   |   |   |
|---|---|---|
| nshell_api | int | 応答の型の版 |
| ok | bool | status が 0 でエラーがない |
| status | int | 終了コード (Lisp 形式を評価しただけなら 0) |
| value | any | Lisp 形式の値。レコードは JSON オブジェクト (L4.6 の規則) |
| stdout / stderr | object | text・bytes・lines・truncated・path (全文の保存先) |
| error | object? | code・message・span・fixes[] |
| warnings | array? | 移行の警告 (W_ で始まるコードと書き換え案) (L7) |
| forms | array? | explain が返す各形式の判定 (02) |
| effects | array | kind (reads / writes / deletes / network / privilege)・path・size。事実から導いた一部の一覧で、書き込みをすべて挙げるものではない。埋め込みの Lisp が行う書き込みは出ない (06 B) |
| safety | object | level (safe / confirm / block)・reasons[] {rule, text} |
| state | object | cwd・env_changed[]・jobs[]・last_status |
| duration_ms | int | 所要時間 |
| session / seq | string / int | セッション ID と通し番号 (履歴とも一致) |

例: 長い出力のビルド

```
{"nshell_api": 1, "ok": true, "status": 0, "duration_ms": 2140,
 "stdout": {"text": "Compiling nshell…\n… 9,100 lines omitted …\nok 812 tests\n",
            "bytes": 418233, "lines": 9120, "truncated": true,
            "path": "/home/me/.cache/nshell/out/s_4b1/12.txt"},
 "stderr": {"text": "", "bytes": 0},
 "effects": [{"kind": "writes", "path": "result/"}],
 "safety": {"level": "safe", "reasons": []},
 "state": {"cwd": "/home/me/src/nshell", "env_changed": []},
 "session": "s_4b1", "seq": 12}
```

本文は先頭と末尾だけ。全文は path に。

## 出力の節約 (トークンの無駄を減らす)

- ANSI の色と制御文字は除去。\r で上書きされる進行表示は最後の 1 行だけ残す。
- 上限を超えたら先頭と末尾を残し、間を「… 9,100 lines omitted …」に (切り詰めの印は英語で固定)。全文は `$XDG_CACHE_HOME/nshell/out/<session>/` に保存し、read_output に不透明な id と offset を渡して続きを読める。保存先の外は read_output で読めない。
- 上限の既定は max_output_bytes 32768 バイト。超えたら先頭 10 行と末尾 10 行を残す。片側が 16384 バイトを超えるときはバイト数で切る。行を省かずにバイト数だけ切ったときの印は「… N bytes omitted …」。
- bytes と lines は ANSI を除去し \r で上書きされた部分を除いたあとの全文の大きさ。保存するファイルの大きさと同じ。
- 全文を保存するのは切り詰めたときだけ。path・session・seq もそのときだけ出す。--json の単発実行では seq は 1 で、stdout は `<seq>.txt`、stderr は `<seq>.stderr.txt` に保存する。session は保存先のディレクトリ名 (`s_` と 6 文字)。
- MCP の run は、切り詰めの有無にかかわらず envelope に session と seq を常に入れる。seq は同じサーバープロセスで始めた run の回数で、承認されず実行しなかった run と、実行の中で E_INTERNAL になった run も数える。引数が不正な run、承認待ちのあいだに取り消された run、セッションが使えなくなったあとに E_INTERNAL で断った run は数えない。run 以外のツールの envelope には入れず、session の ID は initialize と state の value に出る。
- 保存先を安全に作れないとき (シンボリックリンク、他人の所有、group か other に権限がある) は保存せず、path も出さない。
- --timeout は --json と一緒のときだけ受け付ける。
- 全文の保存は直近 50 セッション分だけ残す。--private では保存しない。
- 同じ行が続くときは 1 行と回数にまとめる。
- バイナリは中身を返さず、種類とサイズだけ。
- max_output_bytes と tail_lines は呼び出しごとに指定できる。

### read_output で続きを読む

- 引数は次のとおり。
  - id: 応答の session の文字列 (例 `s_ab12cd`)。要求そのものの id とは別。クライアントは中身を解釈しない。サーバーは `s_` と英数字 6 文字であることを確かめる。
  - seq: 正の整数。既定は 1。
  - stream: "stdout" か "stderr"。既定は "stdout"。
  - offset: 0 以上の整数。既定は 0。
  - limit: 1 から 32768 の整数。既定は 32768。
- 読むファイルの名前はサーバーが seq と stream から作る (`<seq>.txt` か `<seq>.stderr.txt`)。クライアントの入力のうちパスに入るのは、確かめた id だけ。
- offset と limit の単位は保存したファイルの UTF-8 のバイト。応答の stdout.bytes・stderr.bytes と同じ単位。
- 文字の途中で切らないよう、終わりは文字の境目まで戻す。ただし offset がファイルの終わりより前なら、limit より長い文字でも 1 文字は必ず返す。このとき next_offset と offset の差は limit を超える。
- 成功すると value に次の object を入れる。応答の stdout と stderr は空。
  - id・seq・stream・offset: 要求の値。
  - next_offset: 次に読む位置。
  - bytes: ファイル全体のバイト数。
  - eof: next_offset が bytes に達したら true。
  - text: 読んだ部分。
- offset が bytes と同じなら、text は空で eof は true。
- 要求の形が不正なら E_PROTOCOL。id が文字列でないか規則に合わない、seq が正の整数でない、stream が 2 つのどちらでもない、offset が負か整数でない、limit が範囲外、offset がファイルの大きさを超える、offset が文字の途中を指す、のいずれか。
- 保存先の状態のために読めないときは E_PERMISSION。保存先のルート・セッションのディレクトリ・ファイルのどれかが、ない (存在しない id、--private で保存していない、その seq と stream のファイルがない)、シンボリックリンク、自分の所有でない、group か other に権限がある、のいずれか。セッションがディレクトリでないときと、ファイルが通常のファイルでない (FIFO・デバイス) ときも同じ。message にはどれに当たったかを書き、保存先のパスは出さない (示すのは id とファイル名だけ)。ないときも E_PERMISSION にするのは、error.code の enum に「ない」を表すコードがないため。E_NO_MATCH は glob 用なので使わない。
- ルート・セッション・ファイルはどれもシンボリックリンクをたどらずに開き、開いた記述子で種類・所有者・権限を確かめる。セッションとファイルは上のディレクトリの記述子からの相対で開く (openat)。確かめたあとにパスを解決し直さず、読むのは確かめたファイルの記述子からだけ。
- MCP のツールの失敗は ok:false の envelope で返し、isError を true にする。MCP のプロトコルの失敗は、JSON-RPC の整数のコードで返す。-32700 は JSON の構文、-32600 は不正な要求、-32601 は未知のメソッド、-32602 は未知のツール、-32603 は内部エラー。--serve ができるまでは、--serve のエラーも ok:false の応答の形で返し、proposal/02 のトップレベルの `{"id":…,"error":…}` の形は --serve ができてから使う。

## 非対話で詰まらないように

- 機械向けモード (--json・--serve・MCP) と NSHELL_AGENT=1 のときは、PAGER=cat・GIT_PAGER=cat・TERM=dumb・NO_COLOR=1・stdin は /dev/null を既定にする。
- stdin を常に /dev/null にするのは、エージェントの stdin が閉じないパイプであることが多く、端末のときだけに絞ると子がそのパイプを読んで止まる経路が残るため。
- 子プロセスが端末からの入力を待ったら E_WAITING_FOR_INPUT で止め、最後の出力 (例: Password:) を返す。子を PTY と背景プロセスグループで動かし、SIGTTIN と WUNTRACED で検出する。
- vim・less・top など全画面のプログラムは E_INTERACTIVE_PROGRAM。コマンド名の表と `ESC[?1049h` で検出する。代わりの書き方 (git --no-pager など) を fixes に。
- timeout は必ずかかる。--timeout は実行全体の期限で、--json の既定は 120 秒 (initialize の応答で知らせる)。超えたらプロセスグループごと止めて E_TIMEOUT、そこまでの出力は返す。
