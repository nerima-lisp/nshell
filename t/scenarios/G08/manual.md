# G08: Structural editing

Use these bindings at the interactive prompt. `C-M-Shift-Left` and
`C-M-Shift-Right` are sent as tmux keys `C-M-S-Left` and `C-M-S-Right`.
Do not press Enter on the forms. Inspect each edit in the input line, then use
`C-c` to clear it before starting the next form.

1. Type `(list (list G08_CHILD G08_TARGET) G08_AFTER)`. Use `C-a`, `C-M-d`,
   `C-M-f` twice, `C-M-b`, `C-M-d`, `C-M-f` twice, then `C-M-k`. The line should now
   show `(list (list G08_CHILD) G08_AFTER)`. This visits the child list in both
   directions and deletes its next expression.
2. Re-enter the child list with `C-a`, `C-M-d`, `C-M-f` twice, `C-M-b`,
   `C-M-d`, and `C-M-f` twice; press `C-y` to restore the deleted expression. Press
   `C-M-u`, `C-M-f`, and `C-M-b` to leave the child list and traverse the next
   expression in both directions. Press `C-e`, `C-b`, type ` G08_NEW`, then
   `C-e`. The line should be
   `(list (list G08_CHILD G08_TARGET) G08_AFTER G08_NEW)`.
3. Type `(+ G08_BW_LEFT G08_BW_KILL G08_BW_RIGHT)`. Use `C-a`, `C-M-d`,
   `C-M-f` three times, then `C-M-Delete` to delete backward over
   `G08_BW_KILL`. Press `C-y` immediately to restore it, then `C-e`, `C-b`,
   type ` G08_BW_NEW`, and press `C-e`. The line should be
   `(+ G08_BW_LEFT G08_BW_KILL G08_BW_RIGHT G08_BW_NEW)`.
4. Type `(+ G08_SF_LEFT) G08_SF_RIGHT`. Use `C-a`, `C-M-d`, `C-M-f` twice,
   then `C-M-Right`. The line should be `(+ G08_SF_LEFT G08_SF_RIGHT)`.
5. Type `(+ G08_BF_LEFT G08_BF_RIGHT)`. Use `C-a`, `C-M-d`, `C-M-f` twice,
   then `C-M-Shift-Right`. The line should be `(+ G08_BF_LEFT) G08_BF_RIGHT`.
6. Type `(list list (+ G08_SB_RIGHT))`. Use `C-a`, `C-M-d`, `C-M-f` twice,
   `C-f` twice, then `C-M-Left`. The line should be
   `(list (list + G08_SB_RIGHT))`.
7. Type `(list (list + G08_BB_LEFT G08_BB_RIGHT))`. Use `C-a`, `C-M-d`,
   `C-M-f`, `C-M-d`, then `C-M-Shift-Left`. The line should be
   `(list list (+ G08_BB_LEFT G08_BB_RIGHT))`.

Pass when each intermediate and final line matches the shown form, the
parentheses remain balanced after every slurp/barf, and the killed expressions
can be restored with `C-y`. Finish by clearing the line with `C-c` and entering
`exit`.
