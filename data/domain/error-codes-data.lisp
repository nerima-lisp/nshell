(in-package #:nshell.domain.error-codes)

;;; Each entry: (NAME KIND EXIT-CODE SUMMARY-EN SUMMARY-JA FIX-EN FIX-JA).
;;; EXIT-CODE is :CHILD when the child's exit status is used, and NIL for
;;; warnings. FIX-EN and FIX-JA are NIL when the design gives no fix.
;;;
;;; The design fixes only the W_ prefix for warnings (proposal/02), so the W_*
;;; names below are assigned here, one per v0.8 warning in language/L7 7.2 and
;;; language/L2 2.1.
(defparameter +error-codes+
  '(("E_PARSE" :error 2
     "Syntax error, such as an unclosed parenthesis or a bare line after an S-expression."
     "構文エラー。閉じていない括弧、S式の後ろに続く bare-line など"
     "Look at the reported start position and write the input as a single form."
     "示した開始位置を見て、1 つにまとめた書き方にする")
    ("E_UNSUPPORTED_SYNTAX" :error 2
     "Removed syntax, such as bare-line control flow, here-docs, or !."
     "削除した構文。bare-line の制御構文・here-doc・! など"
     "Use the equivalent S-expression shown in the message."
     "示した同じ意味の S式に書き換える")
    ("E_PROTOCOL" :error 2
     "Protocol error in --serve or MCP."
     "--serve・MCP のプロトコルのエラー"
     nil nil)
    ("E_ARG_TYPE" :error 1
     "A list or another non-word value was passed as a command argument."
     "リストなどをコマンドの引数にした"
     "Splice it with ,@ or convert it with (str …)."
     ",@ を使う、または (str …) で変換する")
    ("E_VALUE_POSITION" :error 1
     "A command was written directly where a value is expected."
     "値の位置にコマンドを直接書いた"
     "Wrap it in (capture …) or (status …)."
     "(capture …) か (status …) で囲む")
    ("E_NO_MATCH" :error 1
     "A glob matched nothing (from v0.9.0; v0.8 warns with W_NO_MATCH)."
     "glob が一致しない (v0.9.0 から。v0.8 は W_NO_MATCH の警告)"
     "Quote the pattern."
     "引用する")
    ("E_REDIRECT_TARGET" :error 1
     "A redirection target does not evaluate to a single value."
     "リダイレクトの対象が 1 つの値にならない"
     "Make the target a single value."
     "対象を 1 つにする")
    ("E_LISP_ERROR" :error 1
     "A Lisp error at run time."
     "Lisp の実行時エラー"
     "Check the expression at the reported position and the Common Lisp message."
     "示した式の位置と CL のメッセージを確かめる")
    ("E_NOT_IMPLEMENTED" :error 1
     "A form that is not implemented yet was called (out, view, clip, ?-)."
     "まだ実装していない形式を呼んだ (out・view・clip・?-)"
     "Wait for the implementation."
     "実装を待つ")
    ("E_COMMAND_FAILED" :error :child
     "A command exited with a non-zero status."
     "コマンドが 0 以外の終了コードで終わった"
     "Ignore the failure with (status CMD) or (ignore-errors …), or catch it with (handler-case … (command-failed (c) …))."
     "無視するなら (status CMD) か (ignore-errors …)、捕まえるなら (handler-case … (command-failed (c) …))")
    ("E_COMMAND_NOT_FOUND" :error 127
     "The command was not found."
     "コマンドが見つからない"
     "Use one of the close matches offered as fixes."
     "fixes に示した近い候補を使う")
    ("E_PERMISSION" :error 126
     "Permission denied."
     "権限不足"
     nil nil)
    ("E_TIMEOUT" :error 124
     "The --timeout limit was exceeded and the whole process group was stopped."
     "--timeout 超過。プロセスグループごと停止した"
     nil nil)
    ("E_INTERRUPTED" :error 130
     "Interrupted by SIGINT or a similar signal."
     "SIGINT などで中断した"
     nil nil)
    ("E_NEEDS_APPROVAL" :error 3
     "A confirm verdict has not been approved."
     "confirm 判定で承認が得られていない"
     nil nil)
    ("E_BLOCKED_BY_POLICY" :error 4
     "Refused by a block verdict."
     "block 判定で拒否した"
     nil nil)
    ("E_WAITING_FOR_INPUT" :error 5
     "A child process waited for terminal input; its last output is returned."
     "子プロセスが端末からの入力を待った。最後の出力を返す"
     nil nil)
    ("E_INTERACTIVE_PROGRAM" :error 6
     "A full-screen program was started."
     "全画面のプログラムを起動した"
     "Use a non-interactive form, such as git --no-pager."
     "代わりの書き方 (git --no-pager など) を使う")
    ("E_INTERNAL" :error 70
     "An unexpected error inside nshell itself."
     "nshell 自身の想定外のエラー"
     nil nil)
    ("W_RESOLUTION_ORDER" :warning nil
     "The input changes meaning once Common Lisp names resolve before PATH, as in (last (list 1 2))."
     "名前解決の順序 (PATH より CL) で意味が変わる入力。(last (list 1 2)) など"
     nil nil)
    ("W_VALUE_POSITION" :warning nil
     ",(find …) whose head is a command in the conflict table; E_VALUE_POSITION from v0.9.0."
     ",(find …) の find が衝突表でコマンドになる。v0.9.0 から E_VALUE_POSITION"
     nil nil)
    ("W_KEYWORD_ARGUMENT" :warning nil
     "A keyword such as :kw used as an argument is passed as the word \":kw\"."
     ":kw を引数にすると \":kw\" として渡す"
     nil nil)
    ("W_MID_WORD_SPECIAL" :warning nil
     ", or | in the middle of a word; a literal character from v0.9.0."
     "語の途中の , と |。v0.9.0 から文字として扱う"
     nil nil)
    ("W_BRACE_EXPANSION" :warning nil
     "Brace expansion such as (echo {a,b}c); it gives ac bc from v0.9.0."
     "(echo {a,b}c) の brace 展開。v0.9.0 から ac bc になる"
     nil nil)
    ("W_LIST_SPLICE" :warning nil
     "$xs expands to one argument per element."
     "$xs が要素ごとの引数になる"
     nil nil)
    ("W_STATUS_AS_VALUE" :warning nil
     "(= (cmd) 0) used to test an exit status; E_VALUE_POSITION from v0.9.0."
     "(= (cmd) 0) で終了コードを調べた。v0.9.0 から E_VALUE_POSITION"
     "Use (status …)."
     "(status …) を使う")
    ("W_DEFUN_WORD_ARGS" :warning nil
     "Words passed from an S-expression to a defun function, as in (g sym)."
     "S式から defun の関数に語を渡した ((g sym) など)"
     "Define the function with defcmd."
     "defcmd で定義する")
    ("W_NO_MATCH" :warning nil
     "A glob in command arguments matched nothing and was kept as the word; E_NO_MATCH from v0.9.0."
     "コマンド引数の glob が一致せず、語のまま渡した。v0.9.0 から E_NO_MATCH"
     "Quote the pattern."
     "引用する")
    ("W_REDEFINITION" :warning nil
     "A name that is always Lisp (such as if, let, or defun) was redefined with defun, define-shell-function, alias, or abbr; E_PARSE from v0.9.0."
     "いつでも Lisp になる名前 (if・let・defun など) を defun・define-shell-function・alias・abbr で再定義した。v0.9.0 から E_PARSE"
     nil nil)
    ("W_BARE_LINE_UNQUOTE" :warning nil
     ",expr in a bare line; it still runs, and is removed in v0.9.0."
     "bare-line の ,expr。今までどおり動かすが、v0.9.0 で削る"
     nil nil)
    ("W_NAME_CONFLICT" :warning nil
     "The same name is defined by defun and by defcmd or alias; the later definition wins."
     "同じ名前を defun と、defcmd または alias の両方で定義した。後の定義を採る"
     nil nil)))
