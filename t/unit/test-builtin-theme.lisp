(in-package #:nshell/test)

(describe "builtin-theme-tests"
  (it "theme-list-shows-every-preset-and-marks-the-current-one"
    (with-builtins-context (context)
      (multiple-value-bind (output code)
          (call-builtin context "theme" '("list"))
        (expect 0 :to-equal code)
        (dolist (name (nshell.domain.configuration:theme-preset-names))
          (expect (search name output) :to-be-truthy))
        (expect (search "* nshell" output) :to-be-truthy))))

  (it "theme-use-applies-the-named-preset-through-the-handler"
    (let ((applied nil))
      (let ((nshell.application:*theme-apply-handler*
              (lambda (theme) (setf applied theme))))
        (with-builtins-context (context)
          (multiple-value-bind (output code)
              (call-builtin context "theme" '("use" "dracula"))
            (declare (ignore output))
            (expect 0 :to-equal code)
            (expect "dracula" :to-equal
                    (nshell.domain.configuration:theme-name applied)))))))

  (it "theme-use-rejects-an-unknown-theme-name"
    (with-builtins-context (context)
      (assert-builtin-call (context "theme" '("use" "nosuchtheme"))
        :code 2
        :contains '("unknown theme" "theme list"))))

  (it "theme-set-updates-the-role-spec-through-the-handler"
    (let ((applied nil))
      (let ((nshell.application:*theme-apply-handler*
              (lambda (theme) (setf applied theme))))
        (with-builtins-context (context)
          (multiple-value-bind (output code)
              (call-builtin context "theme" '("set" "command" "red" "--bold"))
            (declare (ignore output))
            (expect 0 :to-equal code)
            (expect "red --bold" :to-equal
                    (nshell.domain.configuration:theme-color applied :command)))))))

  (it "theme-set-rejects-an-invalid-spec-with-the-parser-reason"
    (with-builtins-context (context)
      (multiple-value-bind (output code)
          (call-builtin context "theme" '("set" "command" "not-a-color"))
        (expect 2 :to-equal code)
        (expect (search "unknown token" output) :to-be-truthy))))

  (it "theme-set-rejects-an-unknown-role"
    (with-builtins-context (context)
      (assert-builtin-call (context "theme" '("set" "nosuchrole" "red"))
        :code 2
        :contains '("unknown role" "nosuchrole"))))

  (it "theme-show-lists-the-command-role-and-its-spec"
    (with-builtins-context (context)
      (multiple-value-bind (output code)
          (call-builtin context "theme" '("show"))
        (expect 0 :to-equal code)
        (expect (search "command" output) :to-be-truthy)
        (expect (search "5fafff --bold" output) :to-be-truthy))))

  (it "theme-rejects-an-unrecognized-subcommand"
    (with-builtins-context (context)
      (assert-builtin-call (context "theme" '("frobnicate"))
        :code 1
        :contains '("usage")))))
