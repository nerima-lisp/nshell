(in-package #:nshell/test)

(progn
  (defun %read-execution-sexp-command (source)
    (let ((reader-result
           (first
            (nshell.domain.parsing:read-submission source :reader-context :sexp))))
      (nshell.domain.parsing:command-form->ast source
                                               (nshell.domain.parsing:reader-result-form
                                                reader-result)
                                               (nshell.domain.parsing:reader-result-form-span-map
                                                reader-result)
                                               (lambda (head)
                                                 (declare (ignore head))
                                                 :command-island))))
  (describe "sexp-reader-execution-tests"
            (it "executes-sexp-command-islands-through-public-pipeline-api"
                (let* ((true-node (%read-execution-sexp-command "(true)"))
                       (printf-node
                        (%read-execution-sexp-command
                         "(printf %s pipeline-api)"))
                       (true-code
                        (nshell.application:execute-pipeline-use-case true-node))
                       (printf-code nil)
                       (output
                        (with-output-to-string (*standard-output*)
                          (setf printf-code (nshell.application:execute-pipeline-use-case
                                             printf-node)))))
                  (expect 0 :to-equal true-code)
                  (expect 0 :to-equal printf-code)
                  (expect "pipeline-api" :to-equal output)))
            (it "executes-sexp-pipeline-nodes-through-public-pipeline-api"
                (let* ((node
                        (%read-execution-sexp-command
                         "(| (printf %s pipeline-api) (cat))"))
                       (code nil)
                       (output
                        (with-output-to-string (*standard-output*)
                          (setf code (nshell.application:execute-pipeline-use-case
                                      node)))))
                  (expect 0 :to-equal code)
                  (expect "pipeline-api" :to-equal output)))
            (it "executes-bare-line-pipe-ampersand-through-public-pipeline-api"
                (let* ((source "sh -c \"printf error >&2\" |& cat")
                       (reader-result
                        (first (nshell.domain.parsing:read-submission source)))
                       (node (nshell.domain.parsing:reader-result-form reader-result))
                       (code nil)
                       (output
                        (with-output-to-string (*standard-output*)
                          (setf code
                                (nshell.application:execute-pipeline-use-case
                                 node)))))
                  (expect 0 :to-equal code)
                  (expect "error" :to-equal output)))
            (it "executes-a-quoted-bare-line-argument-as-one-literal-value"
                (let* ((source "printf '%s' \"two words\"")
                       (reader-result
                        (first (nshell.domain.parsing:read-submission source)))
                       (node
                        (nshell.domain.parsing:reader-result-form reader-result))
                       (code nil)
                       (output
                        (with-output-to-string (*standard-output*)
                          (setf code (nshell.application:execute-pipeline-use-case
                                      node)))))
                  (expect 0 :to-equal code)
                  (expect "two words" :to-equal output))))
  (describe "sexp-reader-compatibility-tests"
            (it "preserves-lowercase-keyword-interning-without-uppercase-twins"
                (let* ((name
                        (concatenate 'string
                                     "nshell-reader-keyword-probe-"
                                     (string-downcase (symbol-name (gensym)))))
                       (uppercase-name (string-upcase name))
                       (source (format nil "(printf %s :~a)" name))
                       (reader-result
                        (first
                         (nshell.domain.parsing:read-submission source
                                                                :reader-context
                                                                :sexp)))
                       (node
                        (nshell.domain.parsing:command-form->ast source
                                                                 (nshell.domain.parsing:reader-result-form
                                                                  reader-result)
                                                                 (nshell.domain.parsing:reader-result-form-span-map
                                                                  reader-result)
                                                                 (lambda (head)
                                                                   (declare (ignore
                                                                             head))
                                                                   :command-island)))
                       (symbol nil)
                       (status nil))
                  (expect nil :to-equal (find-symbol uppercase-name "KEYWORD"))
                  (multiple-value-setq (symbol status) (find-symbol name
                                                                    "KEYWORD"))
                  (expect :external :to-equal status)
                  (expect (find-package "KEYWORD")
                          :to-equal
                          (symbol-package symbol))
                  (expect nil :to-equal (find-symbol uppercase-name "KEYWORD"))
                  (expect (list "%s" name)
                          :to-equal
                          (nshell.domain.parsing:command-node-arg-values node))))
            (it "does-not-call-the-bare-line-parser-for-sexp-command-islands"
                (with-temporary-function
                 ('nshell.domain.parsing::parse-command-line
                  (lambda (&rest arguments)
                    (declare (ignore arguments))
                    (error "The bare-line parser was called.")))
                 (let ((node
                         (%read-execution-sexp-command
                          "(printf %s active-reader)")))
                   (expect "printf"
                           :to-equal
                           (nshell.domain.parsing:command-node-command node))
                   (expect '("%s" "active-reader")
                           :to-equal
                           (nshell.domain.parsing:command-node-arg-values node)))))))
