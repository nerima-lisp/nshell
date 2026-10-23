# G08: Structural editing

Prerequisite: check the public key-binding documentation, starting with `docs/src/guide/customization.md`. If it does not document a binding for an action, record that action as unsupported; do not infer a private binding from implementation code.

1. Enter `(list (one) (two))`, place the cursor before `(two)`, and use the keymap's forward-expression action to move past that whole form.
2. Return to `(list (one) (two))`, select `(two)` with the documented structural selection action, and delete it. The result must be `(list (one))`.
3. Enter `(list (one) two)`, place the cursor immediately after `(one)`, and slurp the following sibling. The result must be `(list (one two))`.
4. Barf the final element back out. The result must return to `(list (one) two)`.
5. Record the key sequence and resulting form for each action.

Pass when movement and deletion select the stated expressions, slurp and barf produce the exact forms above, and each result remains balanced.
