(in-package #:nshell/test)

(defparameter +prompt-format-segment-names+
  '("path" "git" "host" "user" "status" "exit" "duration" "time" "jobs" "ai")
  "Every segment name PARSE-PROMPT-FORMAT must recognize.")

(defun %make-prompt-format-test-model (&key (exit-code 0) user)
  "A model over a directory the default *GIT-STATUS-RESOLVER* (no branch)
covers. %GIT-STATUS-SEGMENT resolves lazily at render time, so a test that
needs a branch must bind *GIT-STATUS-RESOLVER* itself around its render
call, not just around this constructor."
  (nshell.domain.prompting:make-prompt-model
   :hostname "host1" :cwd "/repo" :directory "/repo/"
   :exit-code exit-code :user user))

(describe "prompt-format-tests"
  (it "parses-literal-text-and-segments-in-order"
    (expect '((:literal "a/") (:segment "path") (:literal " ") (:segment "git"))
            :to-equal
            (nshell.domain.prompting:parse-prompt-format "a/{path} {git}")))

  (it "parses-a-format-with-no-segments-as-a-single-literal"
    (expect '((:literal "just text"))
            :to-equal (nshell.domain.prompting:parse-prompt-format "just text")))

  (it "parses-an-empty-format-as-no-tokens"
    (expect nil :to-equal (nshell.domain.prompting:parse-prompt-format "")))

  (it "treats-doubled-braces-as-literal-braces"
    (expect '((:literal "{}")) :to-equal (nshell.domain.prompting:parse-prompt-format "{{}}"))
    (expect '((:literal "a{b") (:segment "path") (:literal "c}d"))
            :to-equal (nshell.domain.prompting:parse-prompt-format "a{{b{path}c}}d")))

  (it "recognizes-every-documented-segment-name"
    (dolist (name +prompt-format-segment-names+)
      (expect (list (list :segment name))
              :to-equal (nshell.domain.prompting:parse-prompt-format
                         (format nil "{~a}" name)))))

  (it "signals-invalid-prompt-format-naming-the-unknown-segment"
    (handler-case
        (progn (nshell.domain.prompting:parse-prompt-format "{nope}")
               (expect nil :to-be-truthy))
      (nshell.domain.prompting:invalid-prompt-format (condition)
        (expect "nope" :to-equal
                (nshell.domain.prompting:invalid-prompt-format-segment condition)))))

  (it "signals-invalid-prompt-format-for-an-unterminated-segment"
    (expect (lambda () (nshell.domain.prompting:parse-prompt-format "{path"))
            :to-throw 'nshell.domain.prompting:invalid-prompt-format))

  (it "collapses-one-adjacent-space-run-around-an-empty-segment"
    "An absent git segment drops one flanking space, not both, so path and
status stay separated by exactly one space."
    (let* ((pm (%make-prompt-format-test-model))
           (result (nshell.domain.prompting:render-prompt-format
                    "{path} {git} {status}" pm)))
      (expect '(:path :literal :exit)
              :to-equal (mapcar #'nshell.domain.prompting:prompt-segment-kind result))
      (expect " " :to-equal (nshell.domain.prompting:prompt-segment-text (second result)))))

  (it "collapses-every-flanking-space-when-every-optional-segment-is-empty"
    (let* ((pm (%make-prompt-format-test-model))
           (nshell.domain.prompting:*prompt-time-resolver* (lambda () nil))
           (result (nshell.domain.prompting:render-prompt-format
                    "{exit} {duration} {time} {ai}" pm)))
      (expect nil :to-equal result)))

  (it "renders-path-and-status-like-the-built-in-left-prompt"
    (let* ((pm (%make-prompt-format-test-model :exit-code 0))
           (result (nshell.domain.prompting:render-prompt-format "{path}{status}" pm)))
      (expect "/repo" :to-equal (nshell.domain.prompting:prompt-segment-text (first result)))
      (expect :path :to-be (nshell.domain.prompting:prompt-segment-kind (first result)))
      (expect "❯" :to-equal (nshell.domain.prompting:prompt-segment-text (second result)))
      (expect :exit :to-be (nshell.domain.prompting:prompt-segment-kind (second result)))))

  (it "renders-the-error-prompt-character-for-a-nonzero-exit-code"
    (let* ((pm (%make-prompt-format-test-model :exit-code 7))
           (result (nshell.domain.prompting:render-prompt-format "{status}" pm)))
      (expect :exit-error :to-be (nshell.domain.prompting:prompt-segment-kind (first result)))))

  (it "renders-git-with-a-dirty-marker-when-the-resolver-reports-one"
    (let ((nshell.domain.prompting:*git-status-resolver*
            (lambda (dir) (declare (ignore dir)) (values "main" t))))
      (let* ((pm (%make-prompt-format-test-model))
             (result (nshell.domain.prompting:render-prompt-format "{git}" pm)))
        (expect "main*" :to-equal (nshell.domain.prompting:prompt-segment-text (first result)))
        (expect :git-dirty :to-be (nshell.domain.prompting:prompt-segment-kind (first result))))))

  (it "renders-host-and-user-independently-of-remote-session-state"
    (let* ((pm (%make-prompt-format-test-model :user "alice"))
           (result (nshell.domain.prompting:render-prompt-format "{user}@{host}" pm)))
      (expect '("alice" "@" "host1")
              :to-equal (mapcar #'nshell.domain.prompting:prompt-segment-text result))
      (expect :user :to-be (nshell.domain.prompting:prompt-segment-kind (first result)))
      (expect :host :to-be (nshell.domain.prompting:prompt-segment-kind (third result)))))

  (it "omits-the-user-segment-when-no-user-resolves"
    (let* ((pm (%make-prompt-format-test-model))
           (result (nshell.domain.prompting:render-prompt-format "{user}x" pm)))
      (expect '("x") :to-equal (mapcar #'nshell.domain.prompting:prompt-segment-text result))))

  (it "keeps-the-failure-explain-form-for-the-exit-segment"
    (let ((pm (%make-prompt-format-test-model :exit-code 3)))
      (expect "[3 · ?]"
              :to-equal
              (nshell.domain.prompting:prompt-segment-text
               (first (nshell.domain.prompting:render-prompt-format
                       "{exit}" pm :failure-explain-p t))))
      (expect "[3]"
              :to-equal
              (nshell.domain.prompting:prompt-segment-text
               (first (nshell.domain.prompting:render-prompt-format
                       "{exit}" pm :failure-explain-p nil))))))

  (it "renders-the-jobs-segment-only-when-the-count-is-positive"
    (let ((pm (%make-prompt-format-test-model)))
      (expect nil :to-equal (nshell.domain.prompting:render-prompt-format
                             "{jobs}" pm :jobs-count 0))
      (let ((result (nshell.domain.prompting:render-prompt-format
                     "{jobs}" pm :jobs-count 2)))
        (expect "2" :to-equal (nshell.domain.prompting:prompt-segment-text (first result)))
        (expect :jobs :to-be (nshell.domain.prompting:prompt-segment-kind (first result))))))

  (it "renders-the-ai-segment-only-when-assistant-text-is-supplied"
    (let ((pm (%make-prompt-format-test-model)))
      (expect nil :to-equal (nshell.domain.prompting:render-prompt-format
                             "{ai}" pm :assistant-text nil))
      (let ((result (nshell.domain.prompting:render-prompt-format
                     "{ai}" pm :assistant-text "AI 12s")))
        (expect "AI 12s" :to-equal (nshell.domain.prompting:prompt-segment-text (first result)))
        (expect :assistant :to-be (nshell.domain.prompting:prompt-segment-kind (first result)))))))

(describe "prompt-builtin-tests"
  (it "prompt-with-no-args-shows-the-documented-defaults-with-no-handler-installed"
    (let ((nshell.application:*prompt-format-query-handler* nil))
      (with-builtins-context (context)
        (multiple-value-bind (output code) (call-builtin context "prompt" nil)
          (expect 0 :to-equal code)
          (expect (search nshell.domain.prompting:+default-left-prompt-format+ output)
                  :to-be-truthy)
          (expect (search nshell.domain.prompting:+default-right-prompt-format+ output)
                  :to-be-truthy)))))

  (it "prompt-show-reads-the-live-formats-through-the-query-handler"
    (let ((nshell.application:*prompt-format-query-handler*
            (lambda () (values "{user}$ " "{time}"))))
      (with-builtins-context (context)
        (assert-builtin-call (context "prompt" '("show"))
          :code 0
          :contains '("{user}$ " "{time}")))))

  (it "prompt-left-installs-the-format-through-the-apply-handler"
    (let ((installed nil))
      (let ((nshell.application:*prompt-format-apply-handler*
              (lambda (side value) (push (cons side value) installed))))
        (with-builtins-context (context)
          (multiple-value-bind (output code)
              (call-builtin context "prompt" '("left" "{user}@{host} $ "))
            (declare (ignore output))
            (expect 0 :to-equal code)
            (expect '((:left . "{user}@{host} $ ")) :to-equal installed))))))

  (it "prompt-right-installs-the-format-through-the-apply-handler"
    (let ((installed nil))
      (let ((nshell.application:*prompt-format-apply-handler*
              (lambda (side value) (push (cons side value) installed))))
        (with-builtins-context (context)
          (multiple-value-bind (output code)
              (call-builtin context "prompt" '("right" "{time}"))
            (declare (ignore output))
            (expect 0 :to-equal code)
            (expect '((:right . "{time}")) :to-equal installed))))))

  (it "prompt-reset-clears-both-sides-through-the-apply-handler"
    (let ((installed nil))
      (let ((nshell.application:*prompt-format-apply-handler*
              (lambda (side value) (push (cons side value) installed))))
        (with-builtins-context (context)
          (assert-builtin-call (context "prompt" '("reset"))
            :code 0 :output-null t)
          (expect '((:right . nil) (:left . nil)) :to-equal installed)))))

  (it "prompt-left-rejects-an-invalid-format-without-calling-the-apply-handler"
    (let ((installed nil))
      (let ((nshell.application:*prompt-format-apply-handler*
              (lambda (side value) (push (cons side value) installed))))
        (with-builtins-context (context)
          (assert-builtin-call (context "prompt" '("left" "{nope}"))
            :code 2 :contains '("nope"))
          (expect nil :to-equal installed)))))

  (it "prompt-preview-renders-through-the-preview-handler-without-installing"
    (let ((apply-calls 0)
          (preview-argument nil))
      (let ((nshell.application:*prompt-format-apply-handler*
              (lambda (side value) (declare (ignore side value)) (incf apply-calls)))
            (nshell.application:*prompt-preview-handler*
              (lambda (format) (setf preview-argument format) "PREVIEW-TEXT")))
        (with-builtins-context (context)
          (assert-builtin-call (context "prompt" '("preview" "{path}$"))
            :code 0 :contains '("PREVIEW-TEXT"))
          (expect "{path}$" :to-equal preview-argument)
          (expect 0 :to-equal apply-calls)))))

  (it "prompt-preview-rejects-an-invalid-format"
    (with-builtins-context (context)
      (assert-builtin-call (context "prompt" '("preview" "{nope}"))
        :code 2 :contains '("nope"))))

  (it "prompt-with-an-unrecognized-subcommand-prints-usage-and-exits-1"
    (with-builtins-context (context)
      (assert-builtin-call (context "prompt" '("frobnicate"))
        :code 1 :contains '("usage"))))

  (it "prompt-left-with-no-format-is-a-usage-error"
    (with-builtins-context (context)
      (assert-builtin-call (context "prompt" '("left"))
        :code 1 :contains '("usage")))))

(describe "prompt-format-error-reporting-tests"
  (it "an-unterminated-brace-reports-a-syntax-error-not-an-unknown-segment"
    (expect :unterminated
            :to-be
            (handler-case
                (progn (nshell.domain.prompting:parse-prompt-format "{path") :none)
              (nshell.domain.prompting:invalid-prompt-format (condition)
                (nshell.domain.prompting:invalid-prompt-format-segment condition))))
    (expect "bogus"
            :to-equal
            (handler-case
                (progn (nshell.domain.prompting:parse-prompt-format "{bogus}") :none)
              (nshell.domain.prompting:invalid-prompt-format (condition)
                (nshell.domain.prompting:invalid-prompt-format-segment condition)))))

  (it "prompt-show-quotes-each-format-so-a-trailing-space-is-visible"
    (with-builtins-context (context)
      (let ((nshell.application:*prompt-format-query-handler*
              (lambda () (values "{path} " "{time}"))))
        (assert-builtin-call (context "prompt" nil)
          :code 0
          :contains (list "left:  '{path} '" "right: '{time}'"))))))
