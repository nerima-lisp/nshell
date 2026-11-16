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
| effects | array | kind (reads / writes / deletes / network / privilege)・path・size |
| safety | object | level (safe / confirm / block)・reasons[] {rule, text} |
| state | object | cwd・env_changed[]・jobs[]・last_status |
| duration_ms | int | 所要時間 |
| session / seq | string / int | セッション ID と通し番号 (履歴とも一致) |

例: 長い出力のビルド

```
{"nshell_api": 1, "ok": true, "status": 0, "duration_ms": 2140,
 "stdout": {"text": "Compiling nshell…\n…\nok 812 tests\n",
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
- 全文の保存は直近 50 セッション分だけ残す。--private では保存しない。
- 同じ行が続くときは 1 行と回数にまとめる。
- バイナリは中身を返さず、種類とサイズだけ。
- max_output_bytes と tail_lines は呼び出しごとに指定できる。

## 非対話で詰まらないように

- 機械向けモード (--json・--serve・MCP) と NSHELL_AGENT=1 のときは、PAGER=cat・GIT_PAGER=cat・TERM=dumb・NO_COLOR=1・stdin は /dev/null を既定にする。
- 子プロセスが端末からの入力を待ったら E_WAITING_FOR_INPUT で止め、最後の出力 (例: Password:) を返す。子を PTY と背景プロセスグループで動かし、SIGTTIN と WUNTRACED で検出する。
- vim・less・top など全画面のプログラムは E_INTERACTIVE_PROGRAM。コマンド名の表と `ESC[?1049h` で検出する。代わりの書き方 (git --no-pager など) を fixes に。
- timeout は必ずかかる。--timeout は実行全体の期限で、--json の既定は 120 秒 (initialize の応答で知らせる)。超えたらプロセスグループごと止めて E_TIMEOUT、そこまでの出力は返す。
