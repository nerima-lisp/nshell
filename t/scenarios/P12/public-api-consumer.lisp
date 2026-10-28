(require "asdf")

(progn
  (asdf:clear-source-registry)
  (asdf:initialize-source-registry
   `(:source-registry
     (:directory ,(uiop:ensure-directory-pathname (uiop:getenv "NSHELL_ROOT")))
     :inherit-configuration))
  (asdf:clear-system "nshell")
  (asdf:load-asd
   (merge-pathnames
    "nshell.asd"
    (uiop:ensure-directory-pathname (uiop:getenv "NSHELL_ROOT")))))
(progn
  (asdf:load-system "nshell")
  (unless (equal
           (truename (asdf:system-source-file (asdf:find-system "nshell")))
           (truename
            (merge-pathnames
             "nshell.asd"
             (uiop:ensure-directory-pathname (uiop:getenv "NSHELL_ROOT")))))
    (error "P12 loaded nshell from unexpected source root"))
  (format t "P12_SOURCE_ROOT_OK~%"))
(let ((result (nshell.domain.parsing:parse-command-line "(echo P12_API_OK)")))
  (unless (nshell.domain.parsing:parse-complete-p result)
    (error "parser did not complete"))
  (unless (nshell.domain.parsing:parse-result-ast result)
    (error "parser returned no AST"))
  (format t "P12_API_OK~%"))
