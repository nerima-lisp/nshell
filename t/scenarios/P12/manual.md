# P12: Public API stability

## Procedure

Prerequisite: the candidate tree and the immediately preceding supported release are available as separate source directories. Record the previous release's version and source revision; if no supported release is available, record this UC as not run.

1. In a separate temporary directory, create one ASDF consumer script. It explicitly loads the `nshell.asd` below `NSHELL_ROOT`, then calls `nshell.domain.parsing:parse-command-line` with `(echo P12_API_OK)`.
2. In the consumer, check `nshell.domain.parsing:parse-complete-p` and `nshell.domain.parsing:parse-result-ast` on the returned result. Use single-colon package references so the Lisp reader requires each symbol to be external. The consumer body can be:

   ```lisp
   (asdf:load-asd
    (merge-pathnames "nshell.asd"
                     (uiop:ensure-directory-pathname (uiop:getenv "NSHELL_ROOT"))))
   (asdf:load-system "nshell")
   (let ((result (nshell.domain.parsing:parse-command-line "(echo P12_API_OK)")))
     (unless (nshell.domain.parsing:parse-complete-p result)
       (error "parser did not complete"))
     (unless (nshell.domain.parsing:parse-result-ast result)
       (error "parser returned no AST")))
   ```

3. Run the same script in a fresh SBCL process with `NSHELL_ROOT` set to the candidate tree, then in another fresh process with it set to the previous-release tree. For example: `NSHELL_ROOT=/path/to/candidate sbcl --script /tmp/p12-consumer.lisp` and `NSHELL_ROOT=/path/to/previous-release sbcl --script /tmp/p12-consumer.lisp`.
4. Check that the consumer uses no `INTERNALS` package reference or implementation-private symbol.

## Pass condition

The package and exported symbols remain externally accessible, the consumer works against both versions, and both results are complete parse results with an AST. A consumer that requires an internal symbol fails this scenario.
