# 実行・エラー・スクリプト

## 6.1 スクリプト

ファイル全体を読んでから実行する。構文エラーがあれば何も実行せず、終了コード 2 と E_PARSE。

引数は $argv。$0 はスクリプトのパス。

終了コードは最後に実行したコマンドの終了コード。

## 6.2 表示

```
✗ 構文エラー: ( が閉じていません        E_PARSE
  case.nsh:1:1
  (echo a
  ^

✗ 値の位置にコマンドは書けません  E_VALUE_POSITION
  (let ((x (date))) …)
            ^^^^^^
  例: (let ((x (capture (date)))) …)
```

エラーは 1 回だけ表示する (現在は同じメッセージが 2 回出る)。

位置は原因の開始位置を指す (現在は閉じ括弧の不足を 1:8 と報告する)。

--json では error.code・error.span・error.fixes で返す (U6)。

## 6.3 失敗の扱い

| 起きたこと | トップレベル | 関数の本体 | コード |
|---|---|---|---|
| コマンドが 0 以外で終了 | $status に入れて続行 (-e なら終了) | command-failed を信号。対話では restart を選べる | E_COMMAND_FAILED |
| コマンドが見つからない | 127 で続行 | 同上 | E_COMMAND_NOT_FOUND |
| Lisp のエラー | 対話ではプロンプトへ、スクリプトでは終了 (1) | 同じ | E_LISP_ERROR |
| 構文エラー | 実行しない (2) | — | E_PARSE |
| Ctrl-C | 130 | 同じ | E_INTERRUPTED |

失敗を無視したいときは (status CMD) か (ignore-errors …)。捕まえるなら (handler-case … (command-failed (c) …))。

## 6.4 言語のエラーコード

| コード | いつ | 表示する直し方の例 |
|---|---|---|
| E_PARSE | 閉じていない括弧、S式のあとの余分な語など | 開始位置と、1 つにまとめた書き方 |
| E_UNSUPPORTED_SYNTAX | bare-line の制御構文 | 同じ意味の S式 (L5.3) |
| E_ARG_TYPE | リストなどを引数にした | ,@ を使う、または (str …) |
| E_VALUE_POSITION | 値の位置にコマンドを直接書いた | (capture …)・(status …) |
| E_NO_MATCH | glob が一致しない | 引用する |
| E_REDIRECT_TARGET | リダイレクトの対象が 1 つの値にならない | 対象を 1 つにする |
| E_LISP_ERROR | Lisp の実行時エラー | 式の位置と、CL のメッセージ |
