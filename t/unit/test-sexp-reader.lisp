(in-package #:nshell/test)

(defvar *sexp-reader-test-side-effect*
  nil)

(defstruct sexp-reader-test-structure
  (value nil)
  (observed
   (setf *sexp-reader-test-side-effect* t)))

(defun %sexp-reader-test-capture-error (thunk)
  (handler-case (progn
                  (funcall thunk)
                  nil)
    (nshell.domain.parsing:sexp-reader-error (condition)
      condition)))

(defun %sexp-reader-test-origin-at-span (reader-result span)
  (loop for marker being the hash-keys of (nshell.domain.parsing:reader-result-symbol-origins
                                           reader-result) using (hash-value
                                                                 origin)
        when (equal span (getf origin :source-span))
          return (cons marker origin)))
(describe "sexp-reader-bare-line-contracts"
  (it "converts-bare-line-dollar-and-whole-double-quoted-values"
    (let* ((source "echo $x \"$HOME\"")
           (result (first (nshell.domain.parsing:read-submission source)))
           (command (nshell.domain.parsing:reader-result-form result))
           (forms (nshell.domain.parsing:command-node-argument-forms command))
           (dollar-start (search "$x" source))
           (quoted-start (search "\"$HOME\"" source)))
      (expect (nshell.domain.parsing:command-node-p command) :to-be-truthy)
      (expect "echo" :to-equal
              (nshell.domain.parsing:command-node-command command))
      (expect nil :to-equal (nshell.domain.parsing:command-node-args command))
      (expect 2 :to-equal (length forms))
      (expect '(t t) :to-equal
              (mapcar #'nshell.domain.parsing:command-value-form-p forms))
      (expect '(:value :value) :to-equal
              (mapcar #'nshell.domain.parsing:command-value-form-kind forms))
      (expect "x" :to-equal
              (symbol-name
               (nshell.domain.parsing:command-value-form-form (first forms))))
      (expect "HOME" :to-equal
              (symbol-name
               (nshell.domain.parsing:command-value-form-form (second forms))))
      (expect (list dollar-start (+ dollar-start (length "$x")))
              :to-equal
              (nshell.domain.parsing:command-value-form-source-span
               (first forms)))
      (expect (list quoted-start (+ quoted-start (length "\"$HOME\"")))
              :to-equal
              (nshell.domain.parsing:command-value-form-source-span
               (second forms)))))

  (it "builds-bare-line-sequence-and-pipeline-ast-including-background-semicolon"
    (let* ((source "one |& two && three || four; five &; six")
           (result (first (nshell.domain.parsing:read-submission source)))
           (sequence (nshell.domain.parsing:reader-result-form result))
           (items (nshell.domain.parsing:sequence-node-commands sequence))
           (pipeline (first items)))
      (expect (nshell.domain.parsing:sequence-node-p sequence) :to-be-truthy)
      (expect '(:and :or :semi :amp) :to-equal
              (nshell.domain.parsing:sequence-node-separators sequence))
      (expect 5 :to-equal (length items))
      (expect (nshell.domain.parsing:pipeline-node-p pipeline) :to-be-truthy)
      (expect '("one" "two") :to-equal
              (mapcar #'nshell.domain.parsing:command-node-command
                      (nshell.domain.parsing:pipeline-node-commands pipeline)))
      (expect '(:pipe-stderr-to-stdout) :to-equal
              (mapcar #'nshell.domain.parsing:pipeline-edge-kind
                      (nshell.domain.parsing:pipeline-node-edges pipeline)))
      (expect '("three" "four" "five" "six") :to-equal
              (mapcar #'nshell.domain.parsing:command-node-command
                      (rest items)))
      (expect (list 0 (length source)) :to-equal
              (nshell.domain.parsing:ast-node-span sequence))))

  (it "builds-bare-line-typed-file-redirects-in-source-order"
    (let* ((source "cat < input >> log 3>dup.txt")
           (result (first (nshell.domain.parsing:read-submission source)))
           (command (nshell.domain.parsing:reader-result-form result))
           (redirects (nshell.domain.parsing:command-node-redirects command))
           (island-command
             (let* ((island-source "(cat 3> dup.txt)")
                    (island-result
                      (first
                       (nshell.domain.parsing:read-submission
                        island-source :reader-context :sexp))))
               (nshell.domain.parsing:command-form->ast
                island-source
                (nshell.domain.parsing:reader-result-form island-result)
                (nshell.domain.parsing:reader-result-form-span-map island-result)
                (lambda (head)
                  (declare (ignore head))
                  :command-island)))))
      (expect (nshell.domain.parsing:command-node-p command) :to-be-truthy)
      (expect "cat" :to-equal
              (nshell.domain.parsing:command-node-command command))
      (expect nil :to-equal (nshell.domain.parsing:command-node-args command))
      (expect '(:input-file :append-output-file :output-file) :to-equal
              (mapcar #'nshell.domain.parsing:ast-redirect-entry-kind redirects))
      (expect '(0 1 3) :to-equal
              (mapcar #'nshell.domain.parsing:ast-redirect-entry-file-descriptor redirects))
      (expect '("input" "log" "dup.txt") :to-equal
              (mapcar
               (lambda (redirect)
                 (nshell.domain.parsing:command-arg-value
                  (nshell.domain.parsing:ast-redirect-entry-target redirect)))
               redirects))
      (expect (list (list (search "<" source)
                          (+ (search "input" source) (length "input")))
                    (list (search ">>" source)
                          (+ (search "log" source) (length "log")))
                    (list (search "3>" source)
                          (+ (search "dup.txt" source) (length "dup.txt"))))
              :to-equal
              (mapcar #'nshell.domain.parsing:ast-redirect-entry-source-span
                      redirects))
      (expect '("3>" "dup.txt") :to-equal
              (mapcar #'nshell.domain.parsing:command-arg-value
                      (nshell.domain.parsing:command-node-args island-command)))))
  (it "builds-bare-line-inline-fd-duplication-redirect"
    (let* ((source "cat 1>&3")
           (result (first (nshell.domain.parsing:read-submission source)))
           (command (nshell.domain.parsing:reader-result-form result))
           (redirect (first (nshell.domain.parsing:command-node-redirects command)))
           (target (nshell.domain.parsing:ast-redirect-entry-target redirect)))
      (expect (nshell.domain.parsing:command-node-p command) :to-be-truthy)
      (expect "cat" :to-equal
              (nshell.domain.parsing:command-node-command command))
      (expect nil :to-equal (nshell.domain.parsing:command-node-args command))
      (expect :duplicate-output-fd :to-equal
              (nshell.domain.parsing:ast-redirect-entry-kind redirect))
      (expect 1 :to-equal
              (nshell.domain.parsing:ast-redirect-entry-file-descriptor redirect))
      (expect (nshell.domain.parsing:redirect-fd-target-p target) :to-be-truthy)
      (expect 3 :to-equal
              (nshell.domain.parsing:redirect-fd-target-file-descriptor target))
      (expect (list (search "1>&3" source)
                    (+ (search "1>&3" source) (length "1>&3")))
              :to-equal
              (nshell.domain.parsing:ast-redirect-entry-source-span redirect))))
  (it "builds-bare-line-force-output-file-redirect"
    (let* ((source "cat >| force.txt")
           (result (first (nshell.domain.parsing:read-submission source)))
           (command (nshell.domain.parsing:reader-result-form result))
           (redirect (first (nshell.domain.parsing:command-node-redirects command)))
           (target (nshell.domain.parsing:ast-redirect-entry-target redirect))
           (separated-operator-error
             (%sexp-reader-test-capture-error
              (lambda ()
                (nshell.domain.parsing:read-submission "cat > | force.txt")))))
      (expect (nshell.domain.parsing:command-node-p command) :to-be-truthy)
      (expect "cat" :to-equal
              (nshell.domain.parsing:command-node-command command))
      (expect nil :to-equal (nshell.domain.parsing:command-node-args command))
      (expect :force-output-file :to-equal
              (nshell.domain.parsing:ast-redirect-entry-kind redirect))
      (expect 1 :to-equal
              (nshell.domain.parsing:ast-redirect-entry-file-descriptor redirect))
      (expect "force.txt" :to-equal
              (nshell.domain.parsing:command-arg-value target))
      (expect (list (search ">|" source)
                    (+ (search "force.txt" source) (length "force.txt")))
              :to-equal
              (nshell.domain.parsing:ast-redirect-entry-source-span redirect))
      (expect (typep separated-operator-error
                     'nshell.domain.parsing:sexp-reader-error)
              :to-be-truthy)))

  (it "rejects-bare-line-trailing-operators-and-redirects-with-reader-errors"
    (dolist (source '("echo &&" "echo ||" "echo |" "echo |&" "echo >" "sleep &;; wait" "echo && ; next"))
      (let ((condition
              (%sexp-reader-test-capture-error
               (lambda () (nshell.domain.parsing:read-submission source)))))
        (expect (typep condition 'nshell.domain.parsing:sexp-reader-error)
                :to-be-truthy))))

  (it "preserves-force-external-and-mixed-case-command-heads"
    (let* ((bare-source "^MiXeD arg")
           (bare-result
             (first (nshell.domain.parsing:read-submission bare-source)))
           (bare-command (nshell.domain.parsing:reader-result-form bare-result))
           (sexp-source "(^MiXeD arg)")
           (sexp-result
             (first
              (nshell.domain.parsing:read-submission
               sexp-source :reader-context :sexp)))
           (classifier-calls nil)
           (sexp-command
             (nshell.domain.parsing:command-form->ast
              sexp-source
              (nshell.domain.parsing:reader-result-form sexp-result)
              (nshell.domain.parsing:reader-result-form-span-map sexp-result)
              (lambda (head)
                (push head classifier-calls)
                :command-island))))
      (expect "MiXeD" :to-equal
              (nshell.domain.parsing:command-node-command bare-command))
      (expect t :to-equal
              (nshell.domain.parsing:command-node-force-external-p bare-command))
      (expect '("arg") :to-equal
              (nshell.domain.parsing:command-node-arg-values bare-command))
      (expect "MiXeD" :to-equal
              (nshell.domain.parsing:command-node-command sexp-command))
      (expect t :to-equal
              (nshell.domain.parsing:command-node-force-external-p sexp-command))
      (expect nil :to-equal classifier-calls))
    (let* ((source "(echo MiXeD* |Wild*|)")
           (result
             (first
              (nshell.domain.parsing:read-submission
               source :reader-context :sexp)))
           (command
             (nshell.domain.parsing:command-form->ast
              source
              (nshell.domain.parsing:reader-result-form result)
              (nshell.domain.parsing:reader-result-form-span-map result)
              (lambda (head)
                (declare (ignore head))
                :command-island)))
           (arguments (nshell.domain.parsing:command-node-args command)))
      (expect '("MiXeD*" "Wild*") :to-equal
              (nshell.domain.parsing:command-node-arg-values command))
      (expect '(t nil) :to-equal
              (mapcar
               #'nshell.domain.parsing:command-arg-expand-p
               arguments))))

  (it "read-submission-fuzzes-one-hundred-thousand-fixed-seed-byte-strings"
    (let ((state #x6d2b79f5)
          (case-count 0))
      (labels ((next-byte ()
                 (setf state (logand #xffffffff (logxor state (ash state 13))))
                 (setf state (logand #xffffffff (logxor state (ash state -17))))
                 (setf state (logand #xffffffff (logxor state (ash state 5))))
                 (logand state #xff))
               (next-source ()
                 (let* ((length (mod (next-byte) 17))
                        (source (make-string length)))
                   (dotimes (position length source)
                     (setf (char source position) (code-char (next-byte)))))))
        (dotimes (case-index 100000)
          (let ((source (next-source)))
            (handler-case
                (let ((results (nshell.domain.parsing:read-submission source)))
                  (unless (and (listp results)
                               (every (function nshell.domain.parsing:reader-result-p) results))
                    (error "Reader fuzz case ~D returned a non-result: ~S for ~S"
                           case-index results source)))
              (nshell.domain.parsing:sexp-reader-error () nil))
            (progn
              (incf case-count)
              #+sbcl
              (when (zerop (mod (1+ case-index) 1000))
                (format *error-output* "reader-fuzz-case=~D~%" (1+ case-index))
                (finish-output *error-output*))
              #+sbcl
              (when (zerop (mod (1+ case-index) 10000))
                (sb-ext:gc :full t)))))
        (expect 100000 :to-equal case-count))))
  (it "drops-a-terminal-bare-line-semicolon-from-result-span"
    (let* ((source "done;")
           (results (nshell.domain.parsing:read-submission source))
           (result (first results)))
      (expect 1 :to-equal (length results))
      (expect (list 0 (length "done")) :to-equal
              (nshell.domain.parsing:reader-result-source-span result))
      (expect (list 0 (length "done")) :to-equal
              (nshell.domain.parsing:ast-node-span
               (nshell.domain.parsing:reader-result-form result))))))

(describe "sexp-reader-contracts"
          (it "retains-reader-forms-spans-source-and-symbol-origins"
              (let* ((source "  '(call |MiXeD*| nil)  #(item)")
                     (results
                      (nshell.domain.parsing:read-submission source
                                                             :reader-context
                                                             :sexp
                                                             :source-path
                                                             "input.lisp"))
                     (first-result (first results))
                     (second-result (second results))
                     (form
                      (nshell.domain.parsing:reader-result-form first-result))
                     (operand (second form))
                     (quote-start (search "'(" source))
                     (list-start (search "(call" source))
                     (list-end (1+ (position #\) source :start list-start)))
                     (vector-start (search "#(" source))
                     (escaped-span
                      (let ((start (search "|MiXeD*|" source)))
                        (list start (+ start (length "|MiXeD*|")))))
                     (escaped-origin
                      (%sexp-reader-test-origin-at-span first-result
                                                        escaped-span))
                     (nil-marker (third operand))
                     (first-map
                      (nshell.domain.parsing:reader-result-form-span-map
                       first-result))
                     (second-map
                      (nshell.domain.parsing:reader-result-form-span-map
                       second-result)))
                (expect 2 :to-equal (length results))
                (expect source
                        :to-equal
                        (nshell.domain.parsing:reader-result-source
                         first-result))
                (expect "input.lisp"
                        :to-equal
                        (nshell.domain.parsing:reader-result-source-path
                         first-result))
                (expect (not (nshell.domain.parsing:command-node-p form))
                        :to-be-truthy)
                (expect (list quote-start list-end)
                        :to-equal
                        (nshell.domain.parsing:reader-result-source-span
                         first-result))
                (expect (list quote-start list-end)
                        :to-equal
                        (gethash form first-map))
                (expect (list list-start list-end)
                        :to-equal
                        (gethash operand first-map))
                (expect (eq (hash-table-test first-map) 'eq) :to-be-truthy)
                (expect
                 (vectorp
                  (nshell.domain.parsing:reader-result-form second-result))
                 :to-be-truthy)
                (expect (list vector-start (length source))
                        :to-equal
                        (nshell.domain.parsing:reader-result-source-span
                         second-result))
                (expect (list vector-start (length source))
                        :to-equal
                        (gethash
                         (nshell.domain.parsing:reader-result-form
                          second-result)
                         second-map))
                (expect escaped-origin :to-be-truthy)
                (expect "MiXeD*"
                        :to-equal
                        (getf (cdr escaped-origin) :source-name))
                (expect t :to-equal (getf (cdr escaped-origin) :escaped-p))
                (expect nil
                        :to-equal
                        (getf (cdr escaped-origin) :package-qualifier))
                (expect escaped-span
                        :to-equal
                        (getf (cdr escaped-origin) :source-span))
                (expect nil :to-equal (symbol-package (car escaped-origin)))
                (expect (symbolp nil-marker) :to-be-truthy)
                (expect (not (eq cl:nil nil-marker)) :to-be-truthy)
                (expect nil :to-equal (symbol-package nil-marker))))
          (it "reads-without-evaluating-forms-and-ignores-empty-input"
              (let* ((*sexp-reader-test-side-effect* nil)
                     (source "(setq *sexp-reader-test-side-effect* t)")
                     (results (nshell.domain.parsing:read-submission source)))
                (expect 1 :to-equal (length results))
                (expect
                 (consp
                  (nshell.domain.parsing:reader-result-form (first results)))
                 :to-be-truthy)
                (expect nil :to-equal *sexp-reader-test-side-effect*)
                (expect nil
                        :to-equal
                        (nshell.domain.parsing:read-submission "   "))))
          (it
           "uses-active-features-for-conditionals-without-evaluating-payloads"
           (let* ((*sexp-reader-test-side-effect* nil)
                  (source
                   (format nil
                           "#+reader-test-feature (setq *sexp-reader-test-side-effect* t)~%#-reader-test-feature (setq *sexp-reader-test-side-effect* t)"))
                  (newline (position #\Newline source))
                  (excluded-start (search "#-" source)))
             (let ((cl:*features* '(:reader-test-feature)))
               (let* ((results
                       (nshell.domain.parsing:read-submission source
                                                              :reader-context
                                                              :sexp))
                      (result (first results)))
                 (expect 1 :to-equal (length results))
                 (expect (list 0 newline)
                         :to-equal
                         (nshell.domain.parsing:reader-result-source-span
                          result))))
             (let ((cl:*features* nil))
               (let* ((results
                       (nshell.domain.parsing:read-submission source
                                                              :reader-context
                                                              :sexp))
                      (result (first results)))
                 (expect 1 :to-equal (length results))
                 (expect (list excluded-start (length source))
                         :to-equal
                         (nshell.domain.parsing:reader-result-source-span
                          result))))
             (expect nil :to-equal *sexp-reader-test-side-effect*)))
          (it "rejects-reader-evaluation-and-shared-label-dispatch"
              (let ((*sexp-reader-test-side-effect* nil))
                (dolist
                    (case (list
                           (list "#.(setq *sexp-reader-test-side-effect* t)"
                                 '(0 2))
                           (list "#1=(payload)" '(0 3))
                           (list "#1#" '(0 3))))
                  (let* ((source (first case))
                         (expected-span (second case))
                         (condition
                          (%sexp-reader-test-capture-error
                           (lambda ()
                             (let ((*read-eval* t))
                               (nshell.domain.parsing:read-submission source
                                                                      :reader-context
                                                                      :sexp
                                                                      :source-path
                                                                      "unsafe.lisp"))))))
                    (expect condition :to-be-truthy)
                    (expect expected-span
                            :to-equal
                            (nshell.domain.parsing:sexp-reader-error-source-span
                             condition))
                    (expect "unsafe.lisp"
                            :to-equal
                            (nshell.domain.parsing:sexp-reader-error-source-path
                             condition))))
                (expect nil :to-equal *sexp-reader-test-side-effect*)))
          (it "allows-character-dispatch-in-host-forms"
              (let* ((source "#\\A")
                     (result
                      (first
                       (nshell.domain.parsing:read-submission source
                                                              :reader-context
                                                              :sexp))))
                (expect #\A
                        :to-equal
                        (nshell.domain.parsing:reader-result-form result))
                (expect (list 0 (length source))
                        :to-equal
                        (nshell.domain.parsing:reader-result-source-span result))))
          (it "keeps-structure-dispatch-as-an-opaque-source-backed-marker"
              (let* ((*sexp-reader-test-side-effect* nil)
                     (source "#S(sexp-reader-test-structure :value 1)")
                     (span (list 0 (length source)))
                     (results
                      (nshell.domain.parsing:read-submission source
                                                             :reader-context
                                                             :sexp))
                     (reader-result (first results))
                     (marker
                      (nshell.domain.parsing:reader-result-form reader-result))
                     (origin
                      (%sexp-reader-test-origin-at-span reader-result span)))
                (expect 1 :to-equal (length results))
                (expect (symbolp marker) :to-be-truthy)
                (expect nil :to-equal (symbol-package marker))
                (expect origin :to-be-truthy)
                (expect source :to-equal (getf (cdr origin) :source-name))
                (expect t :to-equal (getf (cdr origin) :opaque-dispatch-p))
                (expect span :to-equal (getf (cdr origin) :source-span))
                (expect span
                        :to-equal
                        (nshell.domain.parsing:reader-result-source-span
                         reader-result))
                (expect nil :to-equal *sexp-reader-test-side-effect*)))
          (it "rejects-reader-evaluation-dispatch-inside-structure-payload"
              (let* ((*sexp-reader-test-side-effect* nil)
                     (source
                      "#S(sexp-reader-test-structure :value #.(setq *sexp-reader-test-side-effect* t))")
                     (dispatch-start (search "#." source))
                     (condition
                      (%sexp-reader-test-capture-error
                       (lambda ()
                         (let ((*read-eval* t))
                           (nshell.domain.parsing:read-submission source
                                                                  :reader-context
                                                                  :sexp))))))
                (expect condition :to-be-truthy)
                (expect (list dispatch-start (+ dispatch-start 2))
                        :to-equal
                        (nshell.domain.parsing:sexp-reader-error-source-span
                         condition))
                (expect nil :to-equal *sexp-reader-test-side-effect*)))
          (it "preserves-opaque-command-island-markers-as-direct-arguments"
              (let* ((source "(echo #qvendor .)")
                     (reader-result
                      (first
                       (nshell.domain.parsing:read-submission source
                                                              :reader-context
                                                              :sexp)))
                     (unknown-start (search "#qvendor" source))
                     (unknown-span
                      (list unknown-start (+ unknown-start (length "#qvendor"))))
                     (dot-start (search ".)" source))
                     (dot-span (list dot-start (1+ dot-start)))
                     (unknown-origin
                      (%sexp-reader-test-origin-at-span reader-result
                                                        unknown-span))
                     (dot-origin
                      (%sexp-reader-test-origin-at-span reader-result dot-span))
                     (classifier-calls nil)
                     (node
                      (nshell.domain.parsing:command-form->ast source
                                                               (nshell.domain.parsing:reader-result-form
                                                                reader-result)
                                                               (nshell.domain.parsing:reader-result-form-span-map
                                                                reader-result)
                                                               (lambda (head)
                                                                 (push head
                                                                       classifier-calls)
                                                                 :command-island))))
                (expect '("#qvendor" ".")
                        :to-equal
                        (nshell.domain.parsing:command-node-arg-values node))
                (expect nil :to-equal classifier-calls)
                (expect unknown-origin :to-be-truthy)
                (expect t
                        :to-equal
                        (getf (cdr unknown-origin) :opaque-dispatch-p))
                (expect unknown-span
                        :to-equal
                        (getf (cdr unknown-origin) :source-span))
                (expect dot-origin :to-be-truthy)
                (expect t :to-equal (getf (cdr dot-origin) :opaque-dot-p))
                (expect dot-span :to-equal (getf (cdr dot-origin) :source-span))))
          (it "converts-command-island-pathname-and-value-argument-contracts"
              (let* ((source
                      "(echo plain file*.txt \"literal*\" |Wild*| 0755 $value ,@values)")
                     (reader-result
                      (first
                       (nshell.domain.parsing:read-submission source
                                                              :reader-context
                                                              :sexp)))
                     (classifier-calls nil)
                     (node
                      (nshell.domain.parsing:command-form->ast source
                                                               (nshell.domain.parsing:reader-result-form
                                                                reader-result)
                                                               (nshell.domain.parsing:reader-result-form-span-map
                                                                reader-result)
                                                               (lambda (head)
                                                                 (push head
                                                                       classifier-calls)
                                                                 :command-island)))
                     (arguments (nshell.domain.parsing:command-node-args node))
                     (argument-forms
                      (nshell.domain.parsing:command-node-argument-forms node))
                     (value-form (sixth argument-forms))
                     (splice-form (seventh argument-forms)))
                (expect '("plain" "file*.txt" "literal*" "Wild*" "0755")
                        :to-equal
                        (nshell.domain.parsing:command-node-arg-values node))
                (expect '(t t nil nil nil)
                        :to-equal
                        (mapcar
                         #'nshell.domain.parsing:command-arg-expand-p
                         arguments))
                (expect '(t t nil nil nil)
                        :to-equal
                        (mapcar #'nshell.domain.parsing:command-arg-glob-p
                                arguments))
                (expect :double
                        :to-equal
                        (nshell.domain.parsing:command-arg-quote-style
                         (third arguments)))
                (expect '(nil nil nil nil nil :value :splice)
                        :to-equal
                        (mapcar
                         (lambda (form)
                           (when
                               (nshell.domain.parsing:command-value-form-p form)
                             (nshell.domain.parsing:command-value-form-kind
                              form)))
                         argument-forms))
                (expect
                 (list (search "$value" source)
                       (+ (search "$value" source) (length "$value")))
                 :to-equal
                 (nshell.domain.parsing:command-value-form-source-span
                  value-form))
                (expect
                 (list (search ",@values" source)
                       (+ (search ",@values" source) (length ",@values")))
                 :to-equal
                 (nshell.domain.parsing:command-value-form-source-span
                  splice-form))
                (expect "value"
                        :to-equal
                        (symbol-name
                         (nshell.domain.parsing:command-value-form-form
                          value-form)))
                (expect "values"
                        :to-equal
                        (symbol-name
                         (nshell.domain.parsing:command-value-form-form
                          splice-form)))
                (expect nil :to-equal classifier-calls)))
          (it "builds-bare-line-pipelines-with-leading-environment-assignments"
              (let* ((source "  FOO=1 echo file*.txt | cat # trailing note")
                     (results (nshell.domain.parsing:read-submission source))
                     (reader-result (first results))
                     (pipeline
                      (nshell.domain.parsing:reader-result-form reader-result))
                     (commands
                      (nshell.domain.parsing:pipeline-node-commands pipeline))
                     (first-command (first commands))
                     (second-command (second commands))
                     (assignment-start (search "FOO=1" source))
                     (last-command-start (search "cat" source))
                     (pipeline-span
                      (list assignment-start (+ last-command-start 3))))
                (expect 1 :to-equal (length results))
                (expect (nshell.domain.parsing:pipeline-node-p pipeline)
                        :to-be-truthy)
                (expect '("echo" "cat")
                        :to-equal
                        (mapcar #'nshell.domain.parsing:command-node-command
                                commands))
                (expect '("FOO=1")
                        :to-equal
                        (mapcar #'nshell.domain.parsing:command-arg-value
                                (nshell.domain.parsing:command-node-environment-assignments
                                 first-command)))
                (expect nil
                        :to-equal
                        (nshell.domain.parsing:command-node-environment-assignments
                         second-command))
                (expect '("file*.txt")
                        :to-equal
                        (nshell.domain.parsing:command-node-arg-values
                         first-command))
                (expect nil
                        :to-equal
                        (nshell.domain.parsing:command-node-args second-command))
                (expect pipeline-span
                        :to-equal
                        (nshell.domain.parsing:reader-result-source-span
                         reader-result))
                (expect pipeline-span
                        :to-equal
                        (nshell.domain.parsing:ast-node-span pipeline))
                (expect
                 (list assignment-start (+ assignment-start (length "FOO=1")))
                 :to-equal
                 (nshell.domain.parsing:command-arg-source-span
                  (first
                   (nshell.domain.parsing:command-node-environment-assignments
                    first-command))))))
          (it "classifies-only-simple-pipeline-stage-heads"
              (let* ((source "(| (cat) (grep term))")
                     (reader-result
                      (first
                       (nshell.domain.parsing:read-submission source
                                                              :reader-context
                                                              :sexp)))
                     (calls nil)
                     (node
                      (nshell.domain.parsing:command-form->ast source
                                                               (nshell.domain.parsing:reader-result-form
                                                                reader-result)
                                                               (nshell.domain.parsing:reader-result-form-span-map
                                                                reader-result)
                                                               (lambda (head)
                                                                 (push head
                                                                       calls)
                                                                 :command-island))))
                (expect (nshell.domain.parsing:pipeline-node-p node)
                        :to-be-truthy)
                (expect '("cat" "grep") :to-equal (nreverse calls))
                (expect '("cat" "grep")
                        :to-equal
                        (mapcar #'nshell.domain.parsing:command-node-command
                                (nshell.domain.parsing:pipeline-node-commands
                                 node)))))
          (it "rejects-host-and-computed-pipeline-stage-heads-at-their-spans"
              (let* ((source "(| (cat) (format nil \"value\"))")
                     (reader-result
                      (first
                       (nshell.domain.parsing:read-submission source
                                                              :reader-context
                                                              :sexp)))
                     (calls nil)
                     (stage-start (search "(format" source))
                     (stage-end (1+ (position #\) source :start stage-start)))
                     (condition
                      (%sexp-reader-test-capture-error
                       (lambda ()
                         (nshell.domain.parsing:command-form->ast source
                                                                  (nshell.domain.parsing:reader-result-form
                                                                   reader-result)
                                                                  (nshell.domain.parsing:reader-result-form-span-map
                                                                   reader-result)
                                                                  (lambda (head)
                                                                    (push head
                                                                          calls)
                                                                    (if (string=
                                                                         head
                                                                         "format")
                                                                        :host-form
                                                                        :command-island)))))))
                (expect condition :to-be-truthy)
                (expect '("cat" "format") :to-equal (nreverse calls))
                (expect (list stage-start stage-end)
                        :to-equal
                        (nshell.domain.parsing:sexp-reader-error-source-span
                         condition)))
              (let* ((source "(| (cat) ((computed) arg))")
                     (reader-result
                      (first
                       (nshell.domain.parsing:read-submission source
                                                              :reader-context
                                                              :sexp)))
                     (calls nil)
                     (stage-start (search "((computed)" source))
                     (stage-end
                      (1+ (position #\) source :start (search " arg" source))))
                     (condition
                      (%sexp-reader-test-capture-error
                       (lambda ()
                         (nshell.domain.parsing:command-form->ast source
                                                                  (nshell.domain.parsing:reader-result-form
                                                                   reader-result)
                                                                  (nshell.domain.parsing:reader-result-form-span-map
                                                                   reader-result)
                                                                  (lambda (head)
                                                                    (push head
                                                                          calls)
                                                                    :command-island))))))
                (expect condition :to-be-truthy)
                (expect '("cat") :to-equal (nreverse calls))
                (expect (list stage-start stage-end)
                        :to-equal
                        (nshell.domain.parsing:sexp-reader-error-source-span
                         condition))))
          (it
           "classifies-process-substitution-stage-heads-without-rechecking-the-outer-command"
           (let* ((source "(cat <(producer))")
                  (reader-result
                   (first
                    (nshell.domain.parsing:read-submission source
                                                           :reader-context
                                                           :sexp)))
                  (calls nil)
                  (node
                   (nshell.domain.parsing:command-form->ast source
                                                            (nshell.domain.parsing:reader-result-form
                                                             reader-result)
                                                            (nshell.domain.parsing:reader-result-form-span-map
                                                             reader-result)
                                                            (lambda (head)
                                                              (push head calls)
                                                              :command-island))))
             (expect (nshell.domain.parsing:command-node-p node) :to-be-truthy)
             (expect '("producer") :to-equal (nreverse calls))))
          (it
           "rejects-reader-input-over-the-nesting-budget-at-the-first-excess-opener"
           (let* ((depth nshell.domain.parsing::+sexp-reader-max-nesting-depth+)
                  (source
                   (concatenate 'string
                                (make-string (1+ depth) :initial-element #\()
                                "leaf"
                                (make-string (1+ depth) :initial-element #\))))
                  (result :not-returned)
                  (condition
                   (%sexp-reader-test-capture-error
                    (lambda ()
                      (setf result (nshell.domain.parsing:read-submission source
                                                                          :reader-context
                                                                          :sexp))))))
             (expect (typep condition 'nshell.domain.parsing:sexp-reader-error)
                     :to-be-truthy)
             (expect :not-returned :to-equal result)
             (expect (list 256 257)
                     :to-equal
                     (nshell.domain.parsing:sexp-reader-error-source-span
                      condition)))))
