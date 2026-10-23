(in-package #:nshell/test)

(describe "sexp-reader-prototype-tests"
          (it "turns-a-command-island-into-the-existing-command-node"
              (let ((node
                     (nshell.domain.parsing::parse-sexp-reader-prototype
                      "(printf %s pipeline-api)")))
                (expect (nshell.domain.parsing:command-node-p node)
                        :to-be-truthy)
                (expect "printf"
                        :to-equal
                        (nshell.domain.parsing:command-node-command node))
                (expect '("%s" "pipeline-api")
                        :to-equal
                        (nshell.domain.parsing:command-node-arg-values node))
                (expect '(0 24)
                        :to-equal
                        (nshell.domain.parsing:ast-node-span node))))
          (it
           "preserves-command-spelling-and-detects-lowercase-cl-special-forms"
           (let ((pair
                  (multiple-value-list
                   (nshell.domain.parsing::%sexp-reader-prototype-read-pair
                    "(if t nil)"))))
             (expect "if" :to-equal (symbol-name (first (first pair))))
             (expect (eq 'cl:if (first (second pair))) :to-be-truthy))
           (expect
            (lambda ()
              (nshell.domain.parsing::parse-sexp-reader-prototype "(if t nil)"))
            :to-throw
            'error)
           (let ((node
                  (nshell.domain.parsing::parse-sexp-reader-prototype
                   "(Echo -La)")))
             (expect "Echo"
                     :to-equal
                     (nshell.domain.parsing:command-node-command node))
             (expect '("-La")
                     :to-equal
                     (nshell.domain.parsing:command-node-arg-values node))))
          (it "requires-an-explicit-unquote-callback-for-dollar-and-comma"
              (expect
               (lambda ()
                 (nshell.domain.parsing::parse-sexp-reader-prototype
                  "(printf $format ,payload)"))
               :to-throw
               'error)
              (let ((calls nil)
                    (node nil))
                (setf node (nshell.domain.parsing::parse-sexp-reader-prototype
                            "(printf $format ,payload)"
                            :unquote-evaluator
                            (lambda (kind form)
                              (setf calls (append calls
                                                  (list
                                                   (list kind
                                                         (symbol-name form)))))
                              (format nil "~(~a~):~a" kind (symbol-name form)))))
                (expect '((:dollar "format") (:comma "payload"))
                        :to-equal
                        calls)
                (expect '("dollar:format" "comma:payload")
                        :to-equal
                        (nshell.domain.parsing:command-node-arg-values node))))
          (it "disables-reader-dispatch-evaluation"
              (let ((side-effect nil))
                (expect
                 (lambda ()
                   (let ((*read-eval* t))
                     (nshell.domain.parsing::parse-sexp-reader-prototype
                      "(printf #.(setq side-effect t))")))
                 :to-throw
                 'error)
                (expect side-effect :to-be-null)))
          (it "keeps-the-caret-marker-in-prototype-metadata"
              (multiple-value-bind (node metadata)
                  (nshell.domain.parsing::parse-sexp-reader-prototype "(^if t)")
                (expect "if"
                        :to-equal
                        (nshell.domain.parsing:command-node-command node))
                (expect '("t")
                        :to-equal
                        (nshell.domain.parsing:command-node-arg-values node))
                (expect t
                        :to-equal
                        (nshell.domain.parsing::command-node-force-external-p node))
                (expect
                 (eq node
                     (nshell.domain.parsing::sexp-reader-prototype-command-metadata-command-node
                      (first metadata)))
                 :to-be-truthy)
                (expect
                 (nshell.domain.parsing::sexp-reader-prototype-command-metadata-force-external-p
                  (first metadata))
                 :to-be-truthy))
              (let ((node
                     (nshell.domain.parsing::parse-sexp-reader-prototype "^echo t")))
                (expect "echo"
                        :to-equal
                        (nshell.domain.parsing:command-node-command node))
                (expect t
                        :to-equal
                        (nshell.domain.parsing::command-node-force-external-p node)))
              (let ((node
                     (nshell.domain.parsing::parse-sexp-reader-prototype "(echo t)")))
                (expect nil
                        :to-equal
                        (nshell.domain.parsing::command-node-force-external-p node))))
          (it "preserves-escaped-symbol-arguments-and-their-glob-boundary"
              (let* ((node
                      (nshell.domain.parsing::parse-sexp-reader-prototype
                       "(echo |a*B| ordinary \"literal*\" 42 ,value)"
                       :unquote-evaluator
                       (lambda (kind form)
                         (declare (ignore kind form))
                         "quoted*")))
                     (arguments (nshell.domain.parsing:command-node-args node)))
                (expect '("a*B" "ordinary" "literal*" "42" "quoted*")
                        :to-equal
                        (nshell.domain.parsing:command-node-arg-values node))
                (expect '(nil t nil nil nil)
                        :to-equal
                        (mapcar #'nshell.domain.parsing::command-arg-glob-p
                                arguments)))
              (let ((node
                     (nshell.domain.parsing::parse-sexp-reader-prototype
                      "(|^if| t)")))
                (expect "^if"
                        :to-equal
                        (nshell.domain.parsing:command-node-command node))
                (expect '("t")
                        :to-equal
                        (nshell.domain.parsing:command-node-arg-values node))
                (expect nil
                        :to-equal
                        (nshell.domain.parsing::command-node-force-external-p node))))
          (it "preserves-a-bare-pipe-as-a-command-argument"
              (let* ((node
                      (nshell.domain.parsing::parse-sexp-reader-prototype "(echo |)"))
                     (argument (first (nshell.domain.parsing:command-node-args node))))
                (expect '("|")
                        :to-equal
                        (nshell.domain.parsing:command-node-arg-values node))
                (expect nil
                        :to-equal
                        (nshell.domain.parsing::command-arg-glob-p argument))))
          (it "builds-pipeline-and-sequence-factories-from-bare-line-operators"
              (let* ((input "printf %s one | cat && true || false; echo done")
                     (node
                      (nshell.domain.parsing::parse-sexp-reader-prototype input))
                     (commands
                      (nshell.domain.parsing:sequence-node-commands node)))
                (expect (nshell.domain.parsing:sequence-node-p node)
                        :to-be-truthy)
                (expect 4 :to-equal (length commands))
                (expect (nshell.domain.parsing:pipeline-node-p (first commands))
                        :to-be-truthy)
                (expect '(:and :or :semi)
                        :to-equal
                        (nshell.domain.parsing:sequence-node-separators node))
                (expect (list 0 (length input))
                        :to-equal
                        (nshell.domain.parsing:ast-node-span node))))
          (it "keeps-bare-line-redirections-and-ignores-trailing-comments"
              (let* ((input "printf %s redirected > out.txt # ignored")
                     (node
                      (nshell.domain.parsing::parse-sexp-reader-prototype input)))
                (expect (nshell.domain.parsing:command-node-p node)
                        :to-be-truthy)
                (expect '("%s" "redirected" ">" "out.txt")
                        :to-equal
                        (nshell.domain.parsing:command-node-arg-values node))
                (expect (list 0 (+ (search "out.txt" input) (length "out.txt")))
                        :to-equal
                        (nshell.domain.parsing:ast-node-span node))))
          (it "accepts-common-lisp-semicolon-comments-after-a-command-island"
              (let* ((input "(printf %s island) ; ignored")
                     (node
                      (nshell.domain.parsing::parse-sexp-reader-prototype input)))
                (expect '("%s" "island")
                        :to-equal
                        (nshell.domain.parsing:command-node-arg-values node))
                (expect (list 0 (length "(printf %s island)"))
                        :to-equal
                        (nshell.domain.parsing:ast-node-span node))))
          (it "builds-a-pipeline-node-from-the-symbolic-pipe-form"
              (let* ((input "(| (printf %s sexp) (cat))")
                     (node
                      (nshell.domain.parsing::parse-sexp-reader-prototype input))
                     (stages
                      (nshell.domain.parsing:pipeline-node-commands node))
                     (first-start (search "(printf" input))
                     (first-end (+ first-start (length "(printf %s sexp)")))
                     (second-start (search "(cat)" input)))
                (expect (nshell.domain.parsing:pipeline-node-p node)
                        :to-be-truthy)
                (expect 2 :to-equal (length stages))
                (expect "printf"
                        :to-equal
                        (nshell.domain.parsing:command-node-command
                         (first stages)))
                (expect "cat"
                        :to-equal
                        (nshell.domain.parsing:command-node-command
                         (second stages)))
                (expect (list first-start first-end)
                        :to-equal
                        (nshell.domain.parsing:ast-node-span (first stages)))
                (expect (list second-start (+ second-start (length "(cat)")))
                        :to-equal
                        (nshell.domain.parsing:ast-node-span (second stages)))
                (expect (list 0 (length input))
                        :to-equal
                        (nshell.domain.parsing:ast-node-span node))))
          (it "reads-delimited-pipe-symbols-as-command-names"
              (let ((node
                     (nshell.domain.parsing::parse-sexp-reader-prototype
                      "(|Echo| -La)")))
                (expect "Echo"
                        :to-equal
                        (nshell.domain.parsing:command-node-command node))
                (expect '("-La")
                        :to-equal
                        (nshell.domain.parsing:command-node-arg-values node))))
          (it "preserves-quote-metadata-for-bare-line-arguments"
              (let* ((node
                      (nshell.domain.parsing::parse-sexp-reader-prototype
                       "printf '%s' \"two words\""))
                     (args (nshell.domain.parsing:command-node-args node)))
                (expect '("%s" "two words")
                        :to-equal
                        (nshell.domain.parsing:command-node-arg-values node))
                (expect :single
                        :to-equal
                        (nshell.domain.parsing:command-arg-quote-style
                         (first args)))
                (expect :double
                        :to-equal
                        (nshell.domain.parsing:command-arg-quote-style
                         (second args)))))
          (it "treats-s-expression-string-arguments-as-opaque-literals"
              (let* ((node
                      (nshell.domain.parsing::parse-sexp-reader-prototype
                       "(printf \"%s\" \"a * b\")"))
                     (argument
                      (second (nshell.domain.parsing:command-node-args node))))
                (expect "a * b"
                        :to-equal
                        (nshell.domain.parsing:arg-value argument))
                (expect :single
                        :to-equal
                        (nshell.domain.parsing:arg-quote-style argument))))
          (it "rejects-redirections-without-targets"
              (expect
               (lambda ()
                 (nshell.domain.parsing::parse-sexp-reader-prototype "echo >"))
               :to-throw
               'error))
          (it "retains-the-stderr-merge-before-a-pipe-ampersand"
              (let* ((node
                      (nshell.domain.parsing::parse-sexp-reader-prototype
                       "echo error |& cat"))
                     (first-stage
                      (first
                       (nshell.domain.parsing:pipeline-node-commands node))))
                (expect '("error" "2>&1")
                        :to-equal
                        (nshell.domain.parsing:command-node-arg-values
                         first-stage))
                (expect
                 (lambda ()
                   (nshell.domain.parsing::parse-sexp-reader-prototype
                    "echo error | & cat"))
                 :to-throw
                 'error)))
          (it "accepts-a-trailing-bare-line-semicolon"
              (let ((node
                     (nshell.domain.parsing::parse-sexp-reader-prototype
                      "echo done;")))
                (expect (nshell.domain.parsing:command-node-p node)
                        :to-be-truthy)
                (expect '("done")
                        :to-equal
                        (nshell.domain.parsing:command-node-arg-values node))))
          (it "preserves-common-lisp-keyword-interning-without-uppercase-twins"
              (let* ((name (concatenate
                            'string
                            "nshell-wp-l00-keyword-probe-"
                            (string-downcase (symbol-name (gensym)))))
                     (uppercase-name (string-upcase name))
                     (node nil)
                     (symbol nil)
                     (status nil))
                (expect nil :to-equal (find-symbol name "KEYWORD"))
                (expect nil :to-equal (find-symbol uppercase-name "KEYWORD"))
                (setf node
                      (nshell.domain.parsing::parse-sexp-reader-prototype
                       (format nil "(printf %s :~a)" name)))
                (multiple-value-setq (symbol status)
                  (find-symbol name "KEYWORD"))
                (expect :external :to-equal status)
                (expect (find-package "KEYWORD")
                        :to-equal
                        (symbol-package symbol))
                (expect nil :to-equal (find-symbol uppercase-name "KEYWORD"))
                (expect (list "%s" name)
                        :to-equal
                        (nshell.domain.parsing:command-node-arg-values node))))
          (it "represents-a-trailing-background-ampersand"
              (let ((node
                     (nshell.domain.parsing::parse-sexp-reader-prototype
                      "true &")))
                (expect (nshell.domain.parsing:sequence-node-p node)
                        :to-be-truthy)
                (expect '(:amp)
                        :to-equal
                        (nshell.domain.parsing:sequence-node-separators node))))
          (it "does-not-call-or-replace-the-default-parser"
              (with-temporary-function
               ('nshell.domain.parsing::parse-command-line
                (lambda (&rest arguments)
                  (declare (ignore arguments))
                  (error "The default parser was called.")))
               (let ((node
                      (nshell.domain.parsing::parse-sexp-reader-prototype
                       "printf %s prototype")))
                 (expect "printf"
                         :to-equal
                         (nshell.domain.parsing:command-node-command node))))))
