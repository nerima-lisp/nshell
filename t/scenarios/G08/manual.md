# G08: S-expression navigation and deletion

From the repository root, run `nix build`, then start nshell with `./result/bin/nshell` and wait for its interactive prompt. Here `C-` means Ctrl and `M-` means Meta (Alt). In `bind` names, `C-M-f` is `alt-ctrl-f`.
Do not press Enter on the forms. Inspect each edit in the input line, then use
`C-c` to clear it before starting the next form.

1. Type `(list (list G08_CHILD G08_TARGET) G08_AFTER)`. Use `C-a`, `C-M-d`,
   `C-M-f` twice, `C-M-b`, `C-M-d`, `C-M-f` twice, then `C-M-k`. The line should now
   show `(list (list G08_CHILD ) G08_AFTER)`. The separator before the inner
   closing parenthesis remains. This visits the child list in both directions and
   deletes its next expression.
2. Re-enter the child list with `C-a`, `C-M-d`, `C-M-f` twice, `C-M-b`,
   `C-M-d`, and `C-M-f` twice. Press `C-f` to move over the remaining separator,
   then `C-y` to restore the deleted expression. Press `C-M-u`, `C-M-f`, and `C-M-b`
   to leave the child list and traverse the next
   expression in both directions. Press `C-e`, `C-b`, type ` G08_NEW`, then
   `C-e`. The line should be
   `(list (list G08_CHILD G08_TARGET) G08_AFTER G08_NEW)`.
3. Type `(+ G08_BW_LEFT G08_BW_KILL G08_BW_RIGHT)`. Use `C-a`, `C-M-d`,
   `C-M-f` three times, then `C-M-Delete` to delete backward over
   `G08_BW_KILL`. Press `C-y` immediately to restore it, then `C-e`, `C-b`,
   type ` G08_BW_NEW`, then `C-e`. The line should show
   `(+ G08_BW_LEFT G08_BW_KILL G08_BW_RIGHT G08_BW_NEW)`.

Pass when each intermediate and final line matches the shown form, the
parentheses remain balanced, and the killed expressions
can be restored with `C-y`. Finish by clearing the line with `C-c` and entering
`exit`.
