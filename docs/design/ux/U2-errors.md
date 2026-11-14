# 人間の UX ② 失敗したとき

いまのエラーは 1 行の英文と列番号だけ。何が悪く、どう直せばよいかまで 1 画面で分かるようにします。

見つからないコマンド

現在

```
~/src/nshell main ❯ gti status
nshell: gti: command not found
```

提案

```
~/src/nshell main ❯ gti status
✗ gti: command not found            E_COMMAND_NOT_FOUND
  did you mean git status  ·  Alt-Enter で置き換え
```

S式の書き間違い

現在

```
~/src/nshell main ❯ (-> (jobs) (where (< :id)))
nshell: syntax error: WHERE supports only (= :key
word value) at column 1
```

提案

```
~/src/nshell main ❯ (-> (jobs) (where (< :id)))
✗ where: 比較には 2 つの値が必要です      E_PARSE
  (-> (jobs) (where (< :id)))
                    ^^^^^^
  例: (where (< :id 3))
```

*失敗のあと: status の横にヒント、ai why は規則で即答*

```
~/src/nshell main ❯ make tset
make: *** No rule to make target 'tset'.  Stop.
✗ 2  · ai why で原因を調べる (Alt-W)

~/src/nshell main ❯ ai why
  打ち間違い (規則 diagnose/typo · オフライン)
  ╭ fix · ● safe
  │ make test
  ╰ Enter 実行 · Alt-E 編集 · Esc 閉じる
```

## エラー表示の決まり

- 1 行目: ✗ と何が起きたか。右端にエラーコード (AI 側と同じコード)。
- 2 行目以降: 位置 (^^^)、正しい例、もしかしての候補。
- 修正候補が 1 つなら Alt-Enter で入力欄に適用。実行はしない。
- 外部コマンドの失敗は出力をそのまま見せ、nshell は最後に ✗ status と次の一手だけを添える。
- メッセージは英語を既定、LANG が ja なら日本語 (コードは常に英字で同じ)。
