(require "asdf")

(asdf:load-system "nshell")
(progn
  (asdf:load-asd
   (merge-pathnames
    "nshell.asd"
    (uiop:ensure-directory-pathname (uiop:getenv "NSHELL_ROOT"))))
  (asdf:load-system "nshell")
  (let ((result
          (nshell.domain.parsing:parse-command-line "(echo P12_API_OK)")))
    (unless (nshell.domain.parsing:parse-complete-p result)
      (error "parser did not complete"))
    (unless (nshell.domain.parsing:parse-result-ast result)
      (error "parser returned no AST"))
    (format t "P12_API_OK~%")))
