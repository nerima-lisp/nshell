# AI の UX ② 応答の型と出力の節約

1 つの型を覚えれば全メソッドが読める。長い出力でもコンテキストを食いつぶさず、対話を待つコマンドで固まらない。

## 全メソッド共通の応答

|   |   |   |
|---|---|---|
| ok | bool | status が 0 でエラーがない |
| status | int | 終了コード (Lisp 形式を評価しただけなら 0) |
| value | any | Lisp 形式の値。レコードは JSON オブジェクト (L4.6 の規則) |
| stdout / stderr | object | text・bytes・lines・truncated・path (全文の保存先) |
| error | object? | code・message・span・fixes[] |
| effects | array | kind (reads / writes / deletes / network / privilege)・path・size |
| safety | object | level (safe / confirm / block)・reasons[] {rule, text} |
| state | object | cwd・env_changed[]・jobs[]・last_status |
| duration_ms | int | 所要時間 |
| session / seq | string / int | セッション ID と通し番号 (履歴とも一致) |

例: 長い出力のビルド

```
{"ok": true, "status": 0, "duration_ms": 2140,
 "stdout": {"text": "Compiling nshell…\n…\nok 812 tests\n",
            "bytes": 418233, "lines": 9120, "truncated": true,
            "path": "/tmp/nshell-s_4b1/out-12.txt"},
 "effects": [{"kind": "writes", "path": "result/"}],
 "safety": {"level": "safe", "reasons": []},
 "state": {"cwd": "/home/me/src/nshell", "env_changed": []},
 "session": "s_4b1", "seq": 12}
```

本文は先頭と末尾だけ。全文は path に。

## 出力の節約 (トークンの無駄を減らす)

- ANSI の色と制御文字は除去。\r で上書きされる進行表示は最後の 1 行だけ残す。
- 上限を超えたら先頭と末尾を残し、間を「… 9,100 行省略 …」に。全文は path に保存し read_output で続きを読める。
- 同じ行が続くときは 1 行と回数にまとめる。
- バイナリは中身を返さず、種類とサイズだけ。
- max_output_bytes と tail_lines は呼び出しごとに指定できる。

## 非対話で詰まらないように

- PAGER=cat・GIT_PAGER=cat・TERM=dumb・NO_COLOR=1・stdin は /dev/null を既定にする。
- 子プロセスが端末からの入力を待ったら E_WAITING_FOR_INPUT で止め、最後の出力 (例: Password:) を返す。
- vim・less・top など全画面のプログラムは E_INTERACTIVE_PROGRAM。代わりの書き方 (git --no-pager など) を fixes に。
- timeout は必ずかかる。超えたらプロセスグループごと止めて E_TIMEOUT、そこまでの出力は返す。
