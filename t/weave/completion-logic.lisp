;;;; The cl-prolog-kit/weave bridge: nshell's completion rules asserted as
;;;; declarative query cases.  deftest-queries expands each spec into an
;;;; independent cl-weave `it`, rebuilding the rulebase per case so no test
;;;; leaks state into the next.

(in-package #:nshell/weave)

;;; assert-query kinds used below:
;;;   :succeeds  -- the goal has at least one proof
;;;   :fails     -- the goal has no proof
;;;   :first     -- the first solution equals the given bindings alist
;;;   :ordered   -- the full solution list equals the given value, in order
(deftest-queries completion-rulebase-bridge ((built-in-rulebase))
  ("cd is recognised as a directory-taking command"
   (suggests-dir "cd") :succeeds)
  ("source takes a file argument"
   (suggests-file "source") :succeeds)
  ("git exposes its status subcommand"
   (completes "git" "status") :succeeds)
  ("git exposes its commit subcommand"
   (completes "git" "commit") :succeeds)
  ("an unknown command completes to nothing"
   (completes "definitely-not-a-command" "status") :fails)
  ("cd does not masquerade as a file-taking command"
   (suggests-file "cd") :fails)
  ("--help carries a human-readable description"
   (describes "--help" ?description)
   :first ((?description . "show command help"))))

;;; The same bridge, but reached through assert-query inside hand-written cases
;;; so a single test can make several related assertions.
(describe "completion rulebase (assert-query)"
  (it "answers flag and self-completion facts for git"
    (let ((rulebase (built-in-rulebase)))
      (assert-query rulebase (completes "git" "git") :succeeds)
      (assert-query rulebase (has-flag "git" "--help") :succeeds)
      (assert-query rulebase (command-is "." "source") :succeeds)))
  (it "complete-registration-rebuild-work-grows-linearly"
    (let* ((insert-symbol (find-symbol "RULEBASE-INSERT-CLAUSE!" "CL-PROLOG-KIT"))
           (original-insert-function (symbol-function insert-symbol))
           (inserted-clause-count 0))
      (labels ((registration-work (count)
                 (setf inserted-clause-count 0)
                 (let ((context (nshell.application:make-shell-context)))
                   (dotimes (index count)
                     (multiple-value-bind (output code)
                         (nshell.application::%builtin-complete
                          context
                          (list "-c" "counter-tool" "-l"
                                (format nil "option-~d" index)))
                       (declare (ignore output))
                       (expect 0 :to-equal code)))
                   (let* ((kb (nshell.application:shell-context-knowledge-base context))
                          (candidates
                            (nshell.domain.completion:complete
                             kb "counter-tool --")))
                     (expect count :to-equal (length candidates))
                     (list inserted-clause-count (length candidates))))))
        (unwind-protect
             (progn
               (setf (symbol-function insert-symbol)
                     (lambda (rulebase clause)
                       (incf inserted-clause-count)
                       (funcall original-insert-function rulebase clause)))
               (let* ((small (registration-work 12))
                      (large (registration-work 24)))
                 (expect 12 :to-equal (second small))
                 (expect 24 :to-equal (second large))
                 (expect (plusp (first small)) :to-be-truthy)
                 (expect (plusp (first large)) :to-be-truthy)
                 (expect (<= (first large) (* 3 (first small))) :to-be-truthy)))
          (setf (symbol-function insert-symbol) original-insert-function)))))
  (it "complete-registration-completes-thousands-of-options"
    (let ((context (nshell.application:make-shell-context)))
      (dotimes (index 2048)
        (multiple-value-bind (output code)
            (nshell.application::%builtin-complete
             context
             (list "-c" "counter-tool" "-l"
                   (format nil "option-~d" index)))
          (declare (ignore output))
          (expect 0 :to-equal code)))
      (let* ((kb (nshell.application:shell-context-knowledge-base context))
             (candidates
               (nshell.domain.completion:complete kb "counter-tool --"))
             (expected
               (loop for index below 2048
                     collect (format nil "--option-~d" index))))
        (expect 2048 :to-equal (length candidates))
        (expect (sort expected (function string<))
                :to-equal
                (sort (mapcar
                       (function nshell.domain.completion:candidate-text)
                       candidates)
                      (function string<)))))))
