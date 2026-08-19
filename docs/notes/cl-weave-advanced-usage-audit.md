# cl-weave advanced-usage audit

What "advanced cl-weave usage" means in this tree, with reproducible source
queries so the claim is checkable rather than a single example standing in for
the whole suite.

## Mutation testing — cl-weave's most advanced facility

`t/unit/test-mutation.lisp`'s own docstring: mutation tests ask "would a test
have *caught* a bug here?" rather than "did a test run this code?"
`run-mutations` rewrites each arithmetic/comparison/boolean/conditional site
in a form and re-checks it against an oracle; `assert-mutation-score` demands
a perfect `1.0` -- every mutant killed. Three sites use it directly
(glob character-range membership, string-prefix length bound, arithmetic
precedence), and two more (`test-tokenizer.lisp`, `test-input-state-search.lisp`)
apply the same technique to their own boundary conditions.

## Property-based testing with shrinking

`t/support/pbt.lisp` supplies domain-specific generators
(`gen-shell-word`, `gen-shell-command`, `gen-prompt-text`, `gen-shell-operator-only-input`,
...) and shrinkers (e.g. `shrink-shell-word`), used through `check-property`
with an explicit trial count -- `(check-property (:trials 50) ((cmd
(gen-shell-command) #'shrink-shell-word)) ...)`. The inventory is reproducible
with `rg -n "check-property" t/unit t/weave`, covering the parser, tokenizer, arithmetic
expansion, glob expansion, abbreviation expansion, environment, completion (context, cycling,
and a dedicated `test-completion-properties.lisp` with 12), four separate
input-state property files (core, navigation, kill-yank, search, completion),
autosuggest, prompt rendering, and CPS.

## cl-prolog-kit-query integration — a second suite dedicated to it

`nshell/weave` (`nshell.asd`, `t/weave/`) is a whole second ASDF system,
separate from `nshell/test`, whose own description is "property-based,
fixture, benchmark, and cl-prolog-kit-query coverage of the completion engine".
It depends on `cl-prolog-kit/weave` specifically for this. The weave tests use
`prove`/`assert-fact!`/prolog querying against the completion rulebase
exported by `nshell.domain.completion` (`#:completes #:describes #:has-flag
#:command-is ...` -- see `nerima-lisp-package-audit.md`), letting tests write
goals such as `(completes "git" ?c)` that unify against the same rulebase the
completion engine itself queries at runtime, rather than re-implementing the
same logic as assertions.

The completion engine now applies the candidate prefix before requesting
human-readable descriptions from the rulebase. This keeps the runtime query
path data-first and avoids description work when a prefix has no matching
solutions; `t/unit/test-completion-rule-prover-boundaries.lisp` locks that
boundary down with a temporary description-query counter.

## Table-driven suites

`it-each`/`describe-each` fold parametrically-identical cases into one
table (6 files; see the `execution-domain` value-boundary consolidation in
this session's history for a worked example), and `it-fails` documents a
currently-failing case as an assertion about *that*, not a silently-skipped
test.

## Conclusion

"cl-weave を利用して高度な使い方をしてほしい" is satisfied by breadth, not
one showcase: mutation testing (the framework's own stated "most advanced
facility"), property-based trials with custom generators and shrinkers,
a second whole ASDF system dedicated to cl-prolog-kit-query integration, and
table-driven consolidation, all exercised by the existing suite rather than
being demonstrated once and left unused elsewhere.
