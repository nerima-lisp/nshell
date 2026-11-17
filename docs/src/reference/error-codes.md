<!-- Generated from data/domain/error-codes-data.lisp by scripts/generate-error-codes-doc.lisp. Do not edit by hand. -->
# Error codes

nshell names each error and warning with a stable code. Errors start with
`E_`. The table lists their exit statuses; mode-dependent exceptions are
specified in each description. Warnings start with `W_`
and flag input that still runs but may not do what you meant; its behaviour
changes in a later release, and some of it becomes an error. Messages do not
show these codes yet.

## Errors

| Code | Exit status | Meaning | How to fix |
|---|---|---|---|
| `E_PARSE` | 2 | Syntax error, such as an unclosed parenthesis or a bare line after an S-expression. | Look at the reported start position and write the input as a single form. |
| `E_UNSUPPORTED_SYNTAX` | 2 | Removed syntax, such as bare-line control flow, here-docs, or !. | Use the equivalent S-expression shown in the message. |
| `E_PROTOCOL` | 2 | Protocol error in --serve or MCP. | - |
| `E_ARG_TYPE` | 1 | A list or another non-word value was passed as a command argument. | Splice it with ,@ or convert it with (str …). |
| `E_VALUE_POSITION` | 1 | A command was written directly where a value is expected. | Wrap it in (capture …) or (status …). |
| `E_NO_MATCH` | 1 | A glob matched nothing (from v0.9.0; v0.8 warns with W_NO_MATCH). | Quote the pattern. |
| `E_REDIRECT_TARGET` | 1 | A redirection target does not evaluate to a single value. | Make the target a single value. |
| `E_LISP_ERROR` | 1 | A Lisp error at run time. | Check the expression at the reported position and the Common Lisp message. |
| `E_NOT_IMPLEMENTED` | 1 | A form that is not implemented yet was called (out, view, clip, ?-). | Wait for the implementation. |
| `E_COMMAND_FAILED` | child's exit status | A command exited with a non-zero status. | Ignore the failure with (status CMD) or (ignore-errors …), or catch it with (handler-case … (command-failed (c) …)). |
| `E_COMMAND_NOT_FOUND` | 127 | The command was not found. | Use one of the close matches offered as fixes. |
| `E_PERMISSION` | 126 | Permission denied. | - |
| `E_TIMEOUT` | 124 | The --timeout limit was exceeded and the whole process group was stopped. | - |
| `E_INTERRUPTED` | 130 | Interrupted by SIGINT, SIGTERM, or SIGHUP. In --json mode, the exit status is 130 for all three signals and output captured so far is returned. Modes without an envelope exit with 128 plus the signal number. | - |
| `E_NEEDS_APPROVAL` | 3 | A confirm verdict has not been approved. | - |
| `E_BLOCKED_BY_POLICY` | 4 | Refused by a block verdict. | - |
| `E_WAITING_FOR_INPUT` | 5 | A child process waited for terminal input; its last output is returned. | - |
| `E_INTERACTIVE_PROGRAM` | 6 | A full-screen program was started. | Use a non-interactive form, such as git --no-pager. |
| `E_INTERNAL` | 70 | An unexpected error inside nshell itself. | - |

## Warnings

| Code | Meaning | How to fix |
|---|---|---|
| `W_RESOLUTION_ORDER` | The input changes meaning once Common Lisp names resolve before PATH, as in (last (list 1 2)). | - |
| `W_VALUE_POSITION` | ,(find …) whose head is a command in the conflict table; E_VALUE_POSITION from v0.9.0. | - |
| `W_KEYWORD_ARGUMENT` | A keyword such as :kw used as an argument is passed as the word ":kw". | - |
| `W_MID_WORD_SPECIAL` | , or \| in the middle of a word; a literal character from v0.9.0. | - |
| `W_BRACE_EXPANSION` | Brace expansion such as (echo {a,b}c); it gives ac bc from v0.9.0. | - |
| `W_LIST_SPLICE` | $xs expands to one argument per element. | - |
| `W_STATUS_AS_VALUE` | (= (cmd) 0) used to test an exit status; E_VALUE_POSITION from v0.9.0. | Use (status …). |
| `W_DEFUN_WORD_ARGS` | Words passed from an S-expression to a defun function, as in (g sym). | Define the function with defcmd. |
| `W_NO_MATCH` | A glob in command arguments matched nothing and was kept as the word; E_NO_MATCH from v0.9.0. | Quote the pattern. |
| `W_REDEFINITION` | A name that is always Lisp (such as if, let, or defun) was redefined with defun, define-shell-function, alias, or abbr; E_PARSE from v0.9.0. | - |
| `W_BARE_LINE_UNQUOTE` | ,expr in a bare line; it still runs, and is removed in v0.9.0. | - |
| `W_NAME_CONFLICT` | The same name is defined by defun and by defcmd or alias; the later definition wins. | - |
