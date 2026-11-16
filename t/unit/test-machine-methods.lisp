(in-package #:nshell/test)

;;; The machine methods explain, initialize and policy (task P1-4). Every
;;; response is validated against docs/design/conformance/envelope.schema.json
;;; with the helpers of test-machine-envelope.lisp.

(defun %machine-explain (text &optional (context (make-test-shell-context)))
  (nshell.feature.machine:explain-input context text))

(defun %machine-parsed (envelope)
  "Return ENVELOPE written as JSON and parsed back, after checking that the
schema accepts it."
  (let ((parsed (machine-envelope-parse envelope)))
    (expect (machine-envelope-failures parsed) :to-be-null)
    parsed))

(defun %machine-list (vector-or-nil)
  (coerce (or vector-or-nil #()) 'list))

(defun %machine-form-summaries (parsed)
  (mapcar (lambda (form)
            (list (gethash "text" form)
                  (gethash "kind" form)
                  (json-kit:json-null-p (gethash "rule" form))))
          (%machine-list (gethash "forms" parsed))))

(defun %machine-effect-summaries (parsed)
  (mapcar (lambda (effect)
            (list (gethash "kind" effect) (gethash "path" effect)))
          (%machine-list (gethash "effects" parsed))))

(defun %machine-reason-rules (parsed)
  (mapcar (lambda (reason) (gethash "rule" reason))
          (%machine-list (gethash "reasons" (gethash "safety" parsed)))))

(describe "machine explain"
  (it "classifies a pipeline without running it"
    (let ((parsed (%machine-parsed (%machine-explain "ls | grep foo > out.txt"))))
      (expect (gethash "ok" parsed) :to-be t)
      (expect (gethash "status" parsed) :to-equal 0)
      (expect (gethash "text" (gethash "stdout" parsed)) :to-equal "")
      (expect (%machine-form-summaries parsed)
              :to-equal '(("ls | grep foo > out.txt" "syntax" t)))
      (expect (%machine-effect-summaries parsed) :to-equal '(("writes" "out.txt")))
      (expect (gethash "level" (gethash "safety" parsed)) :to-equal "confirm")
      (expect (member "classify/output-redirect" (%machine-reason-rules parsed)
                      :test #'equal)
              :to-be-truthy)))

  (it "returns one form per top-level list with its kind"
    (expect (%machine-form-summaries (%machine-parsed (%machine-explain "(ls) (pwd)")))
            :to-equal '(("(ls)" "command" t) ("(pwd)" "command" t)))
    (expect (%machine-form-summaries
             (%machine-parsed (%machine-explain "(format t \"x\")")))
            :to-equal '(("(format t \"x\")" "lisp" t)))
    (expect (%machine-form-summaries (%machine-parsed (%machine-explain "git status")))
            :to-equal '(("git status" "command" t)))
    (expect (%machine-form-summaries
             (%machine-parsed (%machine-explain "(| (ls) (wc -l))")))
            :to-equal '(("(| (ls) (wc -l))" "syntax" t))))

  (it "reports the deletion of a sequence and the command's verdict"
    (let ((parsed (%machine-parsed (%machine-explain "ls; rm -r build"))))
      (expect (%machine-form-summaries parsed) :to-equal '(("ls; rm -r build" "syntax" t)))
      (expect (%machine-effect-summaries parsed) :to-equal '(("deletes" "build")))
      (expect (gethash "level" (gethash "safety" parsed)) :to-equal "confirm")
      (expect (%machine-reason-rules parsed) :to-equal '("classify/delete-dir"))))

  (it "reports the effects of S-expression command forms"
    (let ((parsed (%machine-parsed (%machine-explain "(curl -o page http://x)"))))
      (expect (%machine-effect-summaries parsed) :to-equal '(("network" nil)))))

  (it "gives the verdict of the Enter classifier"
    ;; explain reuses classify-ast with the executor's resolver; it has no
    ;; rules of its own, so both give the same level and reasons.
    (let ((context (make-test-shell-context)))
      (dolist (text '("git status" "ls | grep foo > out.txt" "ls; rm -r build"
                      "(sort data.txt)" "(ls) (pwd)" "curl -o p http://x"
                      "rm -r /" "echo $(rm -r /)"))
        (let* ((verdict (nshell.feature.assistant:classify-ast
                         (nshell.domain.parsing:read-submission text)
                         :resolve (nshell.application:assistant-command-resolver
                                   context)))
               (parsed (%machine-parsed (%machine-explain text context))))
          (expect (list text
                        (gethash "level" (gethash "safety" parsed))
                        (%machine-reason-rules parsed))
                  :to-equal
                  (list text
                        (string-downcase
                         (symbol-name
                          (nshell.feature.assistant:assistant-safety-result-classification
                           verdict)))
                        (mapcar #'car
                                (nshell.feature.assistant:assistant-safety-result-reasons
                                 verdict))))))))

  (it "answers E_PARSE for input it cannot read"
    (let ((parsed (%machine-parsed (%machine-explain (format nil "ls~%(echo"))))
          (error-object nil))
      (setf error-object (gethash "error" parsed))
      (expect (json-kit:json-false-p (gethash "ok" parsed)) :to-be-truthy)
      (expect (gethash "status" parsed) :to-equal 2)
      (expect (gethash "code" error-object) :to-equal "E_PARSE")
      (expect (gethash "line" (gethash "span" error-object)) :to-be-truthy)))

  (it "answers E_PARSE for empty input"
    (dolist (text '("" "   "))
      (let ((parsed (%machine-parsed (%machine-explain text))))
        (expect (gethash "code" (gethash "error" parsed)) :to-equal "E_PARSE")
        (expect (gethash "status" parsed) :to-equal 2))))

  (it "leaves the execution gate's state alone"
    ;; D-81: the verdict of explain is shown only; it never approves a run.
    (let ((nshell.application:*execution-origin* :proposal)
          (nshell.application:*execution-approval* nil)
          (nshell.application:*execution-gate-stopped-p* nil))
      (%machine-parsed (%machine-explain "git status"))
      (expect nshell.application:*execution-approval* :to-be nil)
      (expect nshell.application:*execution-gate-stopped-p* :to-be nil)
      (expect nshell.application:*execution-origin* :to-be :proposal))))

(describe "machine explain examples"
  (it "matches the explain example of proposal/02"
    (let ((parsed (%machine-parsed (%machine-explain "rm -rf build"))))
      (expect (gethash "ok" parsed) :to-be t)
      (expect (%machine-form-summaries parsed) :to-equal '(("rm -rf build" "command" t)))
      (expect (%machine-effect-summaries parsed) :to-equal '(("deletes" "build")))
      (expect (gethash "level" (gethash "safety" parsed)) :to-equal "confirm")
      (expect (mapcar (lambda (reason) (list (gethash "rule" reason) (gethash "text" reason)))
                      (%machine-list (gethash "reasons" (gethash "safety" parsed))))
              :to-equal '(("classify/delete-dir" "deletes a directory")))))

  (it "matches the forms of the language/L2 2.5 example"
    ;; path depends on PATH; the other fields do not.
    (let ((parsed (%machine-parsed (%machine-explain "(sort data.txt)"))))
      (expect (%machine-form-summaries parsed)
              :to-equal '(("(sort data.txt)" "command" t)))))

  (it "reports the effects of an S-expression command"
    (expect (%machine-effect-summaries
             (%machine-parsed (%machine-explain "(rm -rf build)")))
            :to-equal '(("deletes" "build"))))

  (it "runs nothing it explains"
    (host-kit:with-temporary-directory (directory)
      (let ((marker (namestring (merge-pathnames "made" directory))))
        (dolist (text (list (format nil "touch ~a" marker)
                            (format nil "(touch ~a)" marker)
                            (format nil "echo x > ~a" marker)
                            (format nil "(with-open-file (s ~s :direction :output) (print 1 s))"
                                    marker)))
          (%machine-parsed (%machine-explain text)))
        (expect (probe-file marker) :to-be nil)))))

(describe "machine explain loads no function file"
  (it "classifies a name a function file defines without evaluating the file"
    (host-kit:with-temporary-directory (directory)
      (let ((marker (merge-pathnames "loaded" directory)))
        (%safety-view-write-function-file directory "echo" marker)
        (%safety-view-write-function-file directory "greet" marker)
        (let ((context (%safety-view-autoload-context directory)))
          (dolist (text '("echo hi" "(echo hi)" "greet" "(greet)" "ls | echo"))
            (let ((parsed (%machine-parsed (%machine-explain text context))))
              (expect (list text (gethash "level" (gethash "safety" parsed)))
                      :to-equal (list text "confirm"))))
          (expect (%safety-view-registered-count context) :to-equal 0))
        (expect (probe-file marker) :to-be nil)))))

(describe "machine initialize"
  (it "announces the version, the implemented methods and the --json timeout"
    (let* ((parsed (%machine-parsed
                    (nshell.feature.machine:initialize-envelope :cwd "/tmp")))
           (value (gethash "value" parsed)))
      (expect (gethash "ok" parsed) :to-be t)
      (expect (gethash "version" value)
              :to-equal (asdf:component-version (asdf:find-system "nshell")))
      (expect (%machine-list (gethash "methods" value))
              :to-equal '("explain" "initialize" "policy"))
      (expect (gethash "timeout_s" (gethash "limits" value)) :to-equal 120)
      (expect (gethash "cwd" (gethash "session" value)) :to-equal "/tmp")
      (expect (stringp (gethash "os" (gethash "session" value))) :to-be-truthy)
      (expect (json-kit:json-false-p (gethash "attached" (gethash "session" value)))
              :to-be-truthy)))

  (it "summarizes the policy the policy method lists"
    (let* ((policy (gethash "value" (%machine-parsed
                                     (nshell.feature.machine:policy-envelope
                                      :cwd "/tmp"))))
           (summary (gethash "policy"
                             (gethash "value"
                                      (%machine-parsed
                                       (nshell.feature.machine:initialize-envelope
                                        :cwd "/tmp")))))
           (levels (mapcar (lambda (rule) (gethash "level" rule))
                           (%machine-list (gethash "rules" policy)))))
      (expect (gethash "block" summary) :to-equal (count "block" levels :test #'equal))
      (expect (gethash "confirm" summary)
              :to-equal (count "confirm" levels :test #'equal))
      (expect (plusp (gethash "block" summary)) :to-be-truthy)
      (expect (gethash "user_rules" summary) :to-equal 0))))

(describe "machine policy"
  (it "lists every built-in rule once with its level and description"
    (let* ((parsed (%machine-parsed (nshell.feature.machine:policy-envelope :cwd "/tmp")))
           (rules (%machine-list (gethash "rules" (gethash "value" parsed))))
           (names (mapcar (lambda (rule) (gethash "name" rule)) rules)))
      (expect (length names) :to-equal (length (remove-duplicates names :test #'equal)))
      (expect (every (lambda (rule)
                       (member (gethash "level" rule) '("safe" "confirm" "block")
                               :test #'equal))
                     rules)
              :to-be-truthy)
      (let ((root (find "classify/root-recursive-delete" rules
                        :key (lambda (rule) (gethash "name" rule)) :test #'equal))
            (unparsable (find "classify/unparsable" rules
                              :key (lambda (rule) (gethash "name" rule)) :test #'equal)))
        (expect (gethash "level" root) :to-equal "block")
        (expect (gethash "description" root)
                :to-equal "recursive deletion of the filesystem root is blocked")
        ;; The text of this rule comes from the input it judged.
        (expect (json-kit:json-null-p (gethash "description" unparsable)) :to-be-truthy))
      (expect (member "classify/read-only" names :test #'equal) :to-be-truthy)
      (expect (gethash "user_rules" (gethash "value" parsed)) :to-equal 0)))

  (it "counts the injected user rules"
    (let ((nshell.feature.kb:*user-classify-rulebase*
            (nshell.feature.kb:make-user-classify-rulebase
             '(((nshell.feature.kb::classify ?c :confirm "user/no-make"
                                              "make needs confirmation")
                (nshell.feature.kb::command ?c "make"))))))
      (let ((parsed (%machine-parsed (nshell.feature.machine:policy-envelope :cwd "/tmp"))))
        (expect (gethash "user_rules" (gethash "value" parsed)) :to-equal 1)))))

(defun %machine-cli-run (arguments)
  "Run NSHELL::MAIN with ARGUMENTS; return (EXIT-STATUS STDOUT)."
  (let ((stdout (make-string-output-stream)))
    (let ((status (let ((*standard-output* stdout))
                    (%bug-report-main arguments))))
      (list status (get-output-stream-string stdout)))))

(defun %machine-cli-run-untimed (arguments)
  "Like %machine-cli-run, with the duration_ms value replaced by 0: two runs
of the same input differ only in how long they took."
  (destructuring-bind (status output) (%machine-cli-run arguments)
    (let* ((key "\"duration_ms\":")
           (start (search key output)))
      (assert start () "The envelope has no duration_ms: ~S" output)
      (let* ((value-start (+ start (length key)))
             (value-end (position-if-not #'digit-char-p output :start value-start)))
        (list status
              (concatenate 'string (subseq output 0 value-start) "0"
                           (subseq output value-end)))))))

(describe "nshell explain"
  (it "is a reserved subcommand"
    (expect (nshell.feature.command-line:find-subcommand "explain") :to-be-truthy))

  (it "prints the envelope with --json"
    (destructuring-bind (status output) (%machine-cli-run '("--json" "explain" "git status"))
      (let ((parsed (json-kit:parse output)))
        (expect status :to-equal 0)
        (expect (machine-envelope-failures parsed) :to-be-null)
        (expect (gethash "level" (gethash "safety" parsed)) :to-equal "safe")
        (expect (%machine-form-summaries parsed) :to-equal '(("git status" "command" t))))))

  (it "exits 2 with E_PARSE for unreadable input"
    (destructuring-bind (status output) (%machine-cli-run '("--json" "explain" "(ls"))
      (expect status :to-equal 2)
      (expect (gethash "code" (gethash "error" (json-kit:parse output)))
              :to-equal "E_PARSE")))

  (it "prints the same envelope without --json"
    ;; language/L2 2.5 and the ux chapters define only the JSON form, so the
    ;; plain form prints the same envelope.
    (expect (%machine-cli-run-untimed '("explain" "ls; rm -r build"))
            :to-equal (%machine-cli-run-untimed
                       '("--json" "explain" "ls; rm -r build"))))

  (it "takes exactly one input"
    (expect (first (%machine-cli-run '("explain"))) :to-equal 1)
    (expect (first (%machine-cli-run '("explain" "ls" "pwd"))) :to-equal 1)
    (expect (first (%machine-cli-run '("--json" "explain"))) :to-equal 1))

  (it "keeps an option before a script name a script, as before"
    (expect (%bug-report-script-call '("--safe" "explain"))
            :to-equal '(31 ("explain" nil))))

  (it "leaves ./explain to the script runner"
    (expect (%bug-report-script-call '("./explain" "a"))
            :to-equal '(31 ("./explain" ("a"))))))
