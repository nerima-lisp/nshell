(in-package #:nshell/test)

(defmacro with-fresh-input-dispatch-bindings (&body body)
  `(let ((nshell.presentation::*input-dispatch-bindings*
           (let ((table (make-hash-table :test 'eq)))
             (dolist (entry nshell.presentation::+default-input-dispatch-bindings+ table)
               (setf (gethash (car entry) table) (cdr entry))))))
     ,@body))

(defmacro with-bind-builtin-context ((context) &body body)
  `(with-fresh-input-dispatch-bindings
     (let ((nshell.application:*bind-table-handler*
             (function nshell.presentation::bind-dispatch-handler)))
       (with-builtins-context (,context)
         ,@body))))

(defun %dispatch-action-kind-for-key (key-type)
  (nshell.presentation::input-dispatch-action-kind
   (nshell.presentation::input-dispatch-action-for-key-event
    (nshell.domain.input:make-key-event key-type))))

(defun %dispatch-action-value-for-key (key-type)
  (nshell.presentation::input-dispatch-action-value
   (nshell.presentation::input-dispatch-action-for-key-event
    (nshell.domain.input:make-key-event key-type))))

(describe "input-dispatch-table-tests"
  (it "seeded-table-matches-the-historical-action-for-ctrl-r"
    (with-fresh-input-dispatch-bindings
      (expect :start-history-search :to-equal (%dispatch-action-kind-for-key :ctrl-r))))

  (it "seeded-table-matches-the-historical-action-for-tab"
    (with-fresh-input-dispatch-bindings
      (expect :cycle-completion :to-equal (%dispatch-action-kind-for-key :tab))
      (expect 1 :to-equal (%dispatch-action-value-for-key :tab))))

  (it "seeded-table-matches-the-historical-action-for-alt-e"
    (with-fresh-input-dispatch-bindings
      (expect :emit :to-equal (%dispatch-action-kind-for-key :alt-e))
      (expect :edit-command :to-equal (%dispatch-action-value-for-key :alt-e))))

  (it "seeded-table-matches-the-historical-action-for-right"
    (with-fresh-input-dispatch-bindings
      (expect :accept-suggestion :to-equal (%dispatch-action-kind-for-key :right))))

  (it "seeded-table-matches-the-historical-action-for-ctrl-u"
    (with-fresh-input-dispatch-bindings
      (expect :kill-to-bol :to-equal (%dispatch-action-kind-for-key :ctrl-u))))

  (it "an-unbound-key-dispatches-none"
    (with-fresh-input-dispatch-bindings
      (expect :none :to-equal (%dispatch-action-kind-for-key :unknown))))

  (it "rebinding-a-key-changes-its-action"
    (with-fresh-input-dispatch-bindings
      (expect :ok :to-equal
              (nshell.presentation::input-dispatch-set-binding "ctrl-t" "clear-input"))
      (expect :clear-input :to-equal (%dispatch-action-kind-for-key :ctrl-t))))

  (it "erasing-a-binding-falls-back-to-none"
    (with-fresh-input-dispatch-bindings
      (expect :ok :to-equal (nshell.presentation::input-dispatch-erase-binding "ctrl-t"))
      (expect :none :to-equal (%dispatch-action-kind-for-key :ctrl-t))))

  (it "reset-restores-the-default-bindings"
    (with-fresh-input-dispatch-bindings
      (nshell.presentation::input-dispatch-set-binding "ctrl-t" "clear-input")
      (nshell.presentation::input-dispatch-reset-bindings)
      (expect :transpose-chars :to-equal (%dispatch-action-kind-for-key :ctrl-t))))

  (it "the-listing-includes-a-known-binding"
    (with-fresh-input-dispatch-bindings
      (let ((row (assoc "ctrl-r" (nshell.presentation::input-dispatch-bindings-listing)
                        :test #'string=)))
        (expect row :to-be-truthy)
        (expect "start-history-search" :to-equal (cdr row))))))

(describe "builtin-bind-tests"
  (it "bind-without-a-handler-reports-interactive-mode-unavailable"
    (with-builtins-context (context)
      (let ((nshell.application:*bind-table-handler* nil))
        (assert-builtin-call (context "bind" '())
          :code 2
          :contains '("interactive mode is unavailable")))))

  (it "bind-lists-every-binding-including-a-known-one"
    (with-bind-builtin-context (context)
      (assert-builtin-call (context "bind" '())
        :code 0
        :contains '("ctrl-r" "start-history-search"))))

  (it "bind-prints-a-single-binding-for-a-known-key"
    (with-bind-builtin-context (context)
      (assert-builtin-call (context "bind" '("ctrl-r"))
        :code 0
        :contains '("ctrl-r" "start-history-search"))))

  (it "bind-rebinds-a-key-to-a-different-action"
    (with-bind-builtin-context (context)
      (assert-builtin-call (context "bind" '("ctrl-t" "clear-input"))
        :code 0)
      (expect :clear-input :to-equal (%dispatch-action-kind-for-key :ctrl-t))))

  (it "bind-erases-a-binding-falling-back-to-none"
    (with-bind-builtin-context (context)
      (assert-builtin-call (context "bind" '("-e" "ctrl-t"))
        :code 0)
      (expect :none :to-equal (%dispatch-action-kind-for-key :ctrl-t))))

  (it "bind-reset-restores-the-defaults"
    (with-bind-builtin-context (context)
      (call-builtin context "bind" '("ctrl-t" "clear-input"))
      (assert-builtin-call (context "bind" '("--reset"))
        :code 0)
      (expect :transpose-chars :to-equal (%dispatch-action-kind-for-key :ctrl-t))))

  (it "bind-rejects-an-unknown-key-with-exit-2"
    (with-bind-builtin-context (context)
      (assert-builtin-call (context "bind" '("nosuchkey" "clear-input"))
        :code 2
        :contains '("unknown key" "nosuchkey"))))

  (it "bind-rejects-an-unknown-action-with-exit-2"
    (with-bind-builtin-context (context)
      (assert-builtin-call (context "bind" '("ctrl-t" "nosuchaction"))
        :code 2
        :contains '("unknown action" "nosuchaction")))))
