(in-package #:nshell/test)

;;; `nshell --json --command INPUT`: RUN-JSON-COMMAND in process, and the
;;; --json and --timeout options of MAIN. Every envelope a test gets is parsed
;;; back and checked against docs/design/conformance/envelope.schema.json with
;;; the helpers of test-machine-envelope.lisp.

(defmacro with-json-cache-home ((root) &body body)
  "Run BODY with XDG_CACHE_HOME set to a fresh temporary directory and ROOT
bound to the output store root under it."
  (let ((directory (gensym "DIRECTORY"))
        (saved (gensym "SAVED")))
    `(host-kit:with-temporary-directory (,directory)
       (let ((,saved (host-kit:getenv "XDG_CACHE_HOME")))
         (unwind-protect
              (progn
                (sb-posix:setenv "XDG_CACHE_HOME"
                                 (string-right-trim
                                  "/" (sb-ext:native-namestring ,directory))
                                 1)
                (let ((,root (nshell.feature.machine:output-store-root)))
                  ,@body))
           (if ,saved
               (sb-posix:setenv "XDG_CACHE_HOME" ,saved 1)
               (sb-posix:unsetenv "XDG_CACHE_HOME")))))))

(defun json-command (input &rest keys)
  "Run INPUT through RUN-JSON-COMMAND and return the decoded envelope, the
exit status and the seconds it took. Fails the test when the JSON does not
match the schema or its status differs from the exit status."
  (let ((start (get-internal-real-time)))
    (multiple-value-bind (json status) (apply #'nshell.feature.machine:run-json-command
                                              input keys)
      (let ((decoded (json-kit:parse json)))
        (expect (find #\Newline json) :to-be-null)
        (expect (machine-envelope-failures decoded) :to-be-null)
        (expect (gethash "status" decoded) :to-equal status)
        (values decoded
                status
                (/ (- (get-internal-real-time) start)
                   internal-time-units-per-second))))))

(defun json-at (object &rest keys)
  "Follow KEYS (strings for members, integers for elements) into decoded
JSON OBJECT; NIL when a member is missing."
  (dolist (key keys object)
    (setf object (cond ((null object) nil)
                       ((integerp key) (aref object key))
                       (t (gethash key object))))))

(defun json-pid-alive-p (pid)
  (handler-case (progn (sb-posix:kill pid 0) t)
    (sb-posix:syscall-error () nil)))

(defun json-wait-until-dead (pids seconds)
  "Return the PIDS still alive after waiting up to SECONDS for them to exit;
an orphan needs its new parent to reap it before kill 0 fails."
  (let ((deadline (+ (get-internal-real-time)
                     (* seconds internal-time-units-per-second))))
    (loop for alive = (remove-if-not #'json-pid-alive-p pids)
          while (and alive (< (get-internal-real-time) deadline))
          do (sleep 0.05)
          finally (return alive))))

(defun json-file-mode (path)
  (logand (sb-posix:stat-mode (sb-posix:lstat (string-right-trim "/" path))) #o7777))

(describe "machine json command"
  (it "reports a successful command as an ok envelope"
    (let ((envelope (json-command "echo hi")))
      (expect (json-at envelope "ok") :to-equal t)
      (expect (json-at envelope "status") :to-equal 0)
      (expect (json-at envelope "stdout" "text") :to-equal (format nil "hi~%"))
      (expect (json-at envelope "stdout" "bytes") :to-equal 3)
      (expect (json-at envelope "stdout" "lines") :to-equal 1)
      (expect (json-at envelope "stderr" "text") :to-equal "")
      (expect (json-at envelope "error") :to-be-null)
      (expect (json-at envelope "safety" "level") :to-equal "safe")
      (expect (length (json-at envelope "safety" "reasons")) :to-equal 0)
      (expect (length (json-at envelope "effects")) :to-equal 0)
      (expect (json-at envelope "state" "cwd") :to-equal
              (string-right-trim
               "/" (namestring (nshell.infrastructure.acl:current-working-directory))))
      (expect (json-at envelope "session") :to-be-null)
      (expect (json-at envelope "value") :to-be-null))
    (let ((envelope (json-command "true")))
      (expect (json-at envelope "ok") :to-equal t)
      (expect (json-at envelope "stdout" "text") :to-equal "")
      ;; No safe command spec covers true: an unknown command is confirm.
      (expect (json-at envelope "safety" "level") :to-equal "confirm")
      (expect (json-at envelope "safety" "reasons" 0 "rule")
              :to-equal "classify/unknown-command")))

  (it "reports the working directory the run leaves behind"
    (host-kit:with-temporary-directory (directory)
      (let ((saved (nshell.infrastructure.acl:current-working-directory))
            (target (string-right-trim "/" (sb-ext:native-namestring
                                            (truename directory)))))
        (unwind-protect
             (let ((envelope (json-command (format nil "cd ~A" target))))
               (expect (json-at envelope "ok") :to-equal t)
               (expect (json-at envelope "state" "cwd") :to-equal target))
          (uiop:chdir saved)))))

  (it "reports a failing command as E_COMMAND_FAILED with the child's status"
    (let ((envelope (json-command "false")))
      (expect (json-at envelope "ok") :to-equal json-kit:+json-false+)
      (expect (json-at envelope "status") :to-equal 1)
      (expect (json-at envelope "error" "code") :to-equal "E_COMMAND_FAILED"))
    (let ((envelope (json-command "sh -c 'echo broken >&2; exit 3'")))
      (expect (json-at envelope "status") :to-equal 3)
      (expect (json-at envelope "error" "code") :to-equal "E_COMMAND_FAILED")
      (expect (json-at envelope "error" "message") :to-equal "broken")
      (expect (json-at envelope "stderr" "text") :to-equal (format nil "broken~%"))
      (expect (json-at envelope "stdout" "text") :to-equal "")))

  (it "keeps every pipeline stage's stderr out of stdout"
    (dolist (input '("sh -c 'echo out; echo first >&2' | sh -c 'cat; echo last >&2'"
                     "(| (sh -c \"echo out; echo first >&2\") (sh -c \"cat; echo last >&2\"))"))
      (let ((envelope (json-command input)))
        (expect (json-at envelope "stdout" "text") :to-equal (format nil "out~%"))
        ;; Each stage's stderr has its own copier thread, so the order may vary.
        (expect (sort (uiop:split-string (string-right-trim '(#\Newline)
                                                            (json-at envelope "stderr" "text"))
                                         :separator '(#\Newline))
                      #'string<)
                :to-equal '("first" "last")))))

  (it "reports an unknown command as E_COMMAND_NOT_FOUND with its span"
    (let ((envelope (json-command "gti status")))
      (expect (json-at envelope "status") :to-equal 127)
      (expect (json-at envelope "error" "code") :to-equal "E_COMMAND_NOT_FOUND")
      (expect (json-at envelope "error" "message")
              :to-equal "gti: command not found")
      (expect (list (json-at envelope "error" "span" "line")
                    (json-at envelope "error" "span" "column")
                    (json-at envelope "error" "span" "end"))
              :to-equal '(1 1 4)))
    (let ((envelope (json-command "(gti status)")))
      (expect (json-at envelope "error" "code") :to-equal "E_COMMAND_NOT_FOUND")
      (expect (list (json-at envelope "error" "span" "column")
                    (json-at envelope "error" "span" "end"))
              :to-equal '(2 5))))

  (it "points the span of E_COMMAND_NOT_FOUND at the command, not an earlier word"
    (loop for (input span) in (list '("echo gti; gti status" (1 11 14))
                                    (list (format nil "echo gti~%X=gti gti status") '(2 7 10))
                                    '("g\"ti\" gti status" (1 1 6)))
          do (let ((envelope (json-command input)))
               (expect (json-at envelope "error" "code") :to-equal "E_COMMAND_NOT_FOUND")
               (expect (list (json-at envelope "error" "span" "line")
                             (json-at envelope "error" "span" "column")
                             (json-at envelope "error" "span" "end"))
                       :to-equal span))))

  (it "reports unreadable input as E_PARSE and a Lisp error as E_LISP_ERROR"
    (let ((envelope (json-command "(echo")))
      (expect (json-at envelope "status") :to-equal 2)
      (expect (json-at envelope "error" "code") :to-equal "E_PARSE")
      (expect (json-at envelope "error" "message")
              :to-equal "the input could not be parsed")
      ;; Unreadable input is block, as at Enter on an AI proposal.
      (expect (json-at envelope "safety" "level") :to-equal "block")
      (expect (json-at envelope "safety" "reasons" 0 "rule")
              :to-equal "classify/unparsable"))
    (let ((envelope (json-command "(car 1)")))
      (expect (json-at envelope "status") :to-equal 1)
      (expect (json-at envelope "error" "code") :to-equal "E_LISP_ERROR")
      (expect (json-at envelope "error" "message")
              :to-equal "The value 1 is not of type LIST when binding LIST")))

  (it "removes ANSI sequences and keeps only the last carriage-return segment"
    (let ((envelope (json-command
                     "printf '\\033[1mbold\\033[0m\\n50%%\\r100%%\\n'")))
      (expect (json-at envelope "stdout" "text")
              :to-equal (format nil "bold~%100%~%"))
      (expect (json-at envelope "stdout" "truncated") :to-equal json-kit:+json-false+)))

  (it "cuts long output and saves the full text in a private session directory"
    (with-json-cache-home (root)
      (let* ((envelope (json-command "seq 1 10000"))
             (full (with-output-to-string (out)
                     (loop for n from 1 to 10000 do (format out "~D~%" n))))
             (path (json-at envelope "stdout" "path"))
             (session (json-at envelope "session")))
        (expect (json-at envelope "ok") :to-equal t)
        (expect (json-at envelope "stdout" "truncated") :to-equal t)
        (expect (json-at envelope "stdout" "lines") :to-equal 10000)
        (expect (json-at envelope "stdout" "bytes") :to-equal (length full))
        (expect (search (format nil "~%… 9,980 lines omitted …~%")
                        (json-at envelope "stdout" "text"))
                :to-be-truthy)
        (expect (json-at envelope "seq") :to-equal 1)
        (expect (and (stringp session) (= 8 (length session))
                     (string= "s_" session :end2 2))
                :to-be-truthy)
        (expect path :to-equal (format nil "~A~A/1.txt" root session))
        (expect (json-file-mode (format nil "~A~A" root session)) :to-equal #o700)
        (expect (json-file-mode path) :to-equal #o600)
        (expect (uiop:read-file-string path :external-format :utf-8)
                :to-equal full)
        ;; stderr was not cut, so it gets no file.
        (expect (json-at envelope "stderr" "path") :to-be-null)
        (expect (probe-file (format nil "~A~A/1.stderr.txt" root session))
                :to-be-null))))

  (it "saves nothing with :private"
    (with-json-cache-home (root)
      (let ((envelope (json-command "seq 1 10000" :private t)))
        (expect (json-at envelope "stdout" "truncated") :to-equal t)
        (expect (json-at envelope "stdout" "path") :to-be-null)
        (expect (json-at envelope "session") :to-be-null)
        (expect (json-at envelope "seq") :to-be-null)
        (expect (probe-file root) :to-be-null))))

  (it "gives each run its own session and keeps the newest fifty"
    (with-json-cache-home (root)
      (let ((first (json-at (json-command "seq 1 10000") "session"))
            (second (json-at (json-command "seq 1 10000") "session")))
        (expect (string= first second) :to-be-falsy)
        (dotimes (index 55)
          (let ((path (format nil "~As_old~3,'0D" root index)))
            (sb-posix:mkdir path #o700)
            (sb-posix:utimes path (+ 1000 index) (+ 1000 index))))
        (let ((third (json-at (json-command "seq 1 10000") "session")))
          (expect (length (uiop:subdirectories root)) :to-equal 50)
          (dolist (kept (list first second third))
            (expect (probe-file (format nil "~A~A/" root kept)) :to-be-truthy))))))

  (it "stops the whole process group at the deadline and keeps the output so far"
    (host-kit:with-temporary-directory (directory)
      (let* ((pid-file (format nil "~Apids"
                               (sb-ext:native-namestring directory)))
             (input (format nil "sh -c 'echo before; sleep 60 & echo $! > ~A; ~
                                 echo $$ >> ~A; sleep 60'"
                            pid-file pid-file)))
        (multiple-value-bind (envelope status seconds)
            (json-command input :timeout 1)
          (expect status :to-equal 124)
          (expect (json-at envelope "error" "code") :to-equal "E_TIMEOUT")
          (expect seconds :to-be-less-than 3)
          (expect (json-at envelope "stdout" "text") :to-equal (format nil "before~%"))
          (let ((pids (with-open-file (in pid-file)
                        (loop for line = (read-line in nil)
                              while line
                              collect (parse-integer line)))))
            (expect (length pids) :to-equal 2)
            (expect (json-wait-until-dead pids 2) :to-be-null)))))
    (let ((envelope (json-command "(progn (echo a) (sh -c \"sleep 30\") (echo after))"
                                  :timeout 1)))
      (expect (json-at envelope "error" "code") :to-equal "E_TIMEOUT")
      ;; The run stops at the deadline: the command after it never runs.
      (expect (json-at envelope "stdout" "text") :to-equal (format nil "a~%"))))

  (it "stops a grandchild whose parent exited before the deadline"
    ;; sh is reaped long before the deadline, so only the record of the
    ;; process groups the run created leads to the sleep it left behind.
    (host-kit:with-temporary-directory (directory)
      (let* ((pid-file (format nil "~Apid" (sb-ext:native-namestring directory)))
             (input (format nil "sh -c 'sleep 60 >/dev/null 2>&1 & echo $! > ~A; ~
                                 exit 0'; sleep 30"
                            pid-file)))
        (multiple-value-bind (envelope status seconds) (json-command input :timeout 1)
          (expect status :to-equal 124)
          (expect (json-at envelope "error" "code") :to-equal "E_TIMEOUT")
          (expect seconds :to-be-less-than 3)
          (let ((pid (parse-integer (uiop:read-file-string pid-file) :junk-allowed t)))
            (expect (integerp pid) :to-be-truthy)
            (expect (json-wait-until-dead (list pid) 2) :to-be-null))))))

  (it "leaves a background grandchild running when the run ends normally"
    (host-kit:with-temporary-directory (directory)
      (let* ((pid-file (format nil "~Apid" (sb-ext:native-namestring directory)))
             (input (format nil "sh -c 'sleep 60 >/dev/null 2>&1 & echo $! > ~A; exit 0'"
                            pid-file))
             (pid nil))
        (unwind-protect
             (let ((envelope (json-command input :timeout 5)))
               (expect (json-at envelope "ok") :to-equal t)
               (setf pid (parse-integer (uiop:read-file-string pid-file) :junk-allowed t))
               (expect (json-pid-alive-p pid) :to-be-truthy))
          (when pid
            (ignore-errors (sb-posix:kill pid sb-unix:sigkill)))))))

  (it "rejects a deadline that is not a positive number of seconds"
    (dolist (timeout (list 0 -1 "5" nil))
      (expect (handler-case
                  (progn (nshell.feature.machine:run-json-command "true" :timeout timeout)
                         nil)
                (error () t))
              :to-be-truthy)))

  (it "refuses confirm and block forms under NSHELL_AGENT=1 without running them"
    (host-kit:with-temporary-directory (directory)
      (let* ((victim (format nil "~Avictim" (sb-ext:native-namestring directory)))
             (marker (format nil "~A/keep" victim)))
        (ensure-directories-exist marker)
        (with-open-file (out marker :direction :output) (write-string "x" out))
        (let ((envelope (json-command (format nil "rm -r ~A" victim)
                                      :environment-agent-p t)))
          (expect (json-at envelope "status") :to-equal 3)
          (expect (json-at envelope "error" "code") :to-equal "E_NEEDS_APPROVAL")
          (expect (json-at envelope "safety" "level") :to-equal "confirm")
          (expect (json-at envelope "safety" "reasons" 0 "rule")
                  :to-equal "classify/delete-dir")
          (expect (probe-file marker) :to-be-truthy))
        ;; rm refuses to remove ".", so this stays harmless even if it ran.
        (let ((envelope (json-command "rm -r ." :environment-agent-p t)))
          (expect (json-at envelope "status") :to-equal 4)
          (expect (json-at envelope "error" "code") :to-equal "E_BLOCKED_BY_POLICY")
          (expect (json-at envelope "safety" "level") :to-equal "block")
          (expect (json-at envelope "stderr" "text") :to-equal ""))
        (let ((envelope (json-command "echo allowed" :environment-agent-p t)))
          (expect (json-at envelope "ok") :to-equal t)
          (expect (json-at envelope "stdout" "text") :to-equal (format nil "allowed~%")))
        ;; Without NSHELL_AGENT, --json only reports the level and runs.
        (let ((envelope (json-command (format nil "rm -r ~A" victim))))
          (expect (json-at envelope "ok") :to-equal t)
          (expect (json-at envelope "safety" "level") :to-equal "confirm")
          (expect (probe-file marker) :to-be-null)))))

  (it "maps the execution gate's own refusals to approval and policy errors"
    ;; The Enter step is made to pass everything, so the gate alone decides,
    ;; as for a line whose alias or function expands to more than it shows.
    (host-kit:with-temporary-directory (directory)
      (let* ((victim (format nil "~Avictim" (sb-ext:native-namestring directory)))
             (marker (format nil "~A/keep" victim)))
        (ensure-directories-exist marker)
        (with-open-file (out marker :direction :output) (write-string "x" out))
        (with-temporary-function
            ((quote nshell.feature.machine::%classify-input)
             (lambda (input) (declare (ignore input)) (values (list :safe) t)))
          (dolist (case (list (list (format nil "rm -r ~A" victim) 3 "E_NEEDS_APPROVAL")
                              (list (format nil "echo before; rm -r ~A; echo after" victim)
                                    3 "E_NEEDS_APPROVAL")
                              (list (format nil "echo hi | rm -r ~A" victim)
                                    3 "E_NEEDS_APPROVAL")
                              (list "rm -r ." 4 "E_BLOCKED_BY_POLICY")))
            (destructuring-bind (input status code) case
              (let ((envelope (json-command input :environment-agent-p t)))
                (expect (list input (json-at envelope "status")
                              (json-at envelope "error" "code"))
                        :to-equal (list input status code))
                (expect (search "nshell: AI proposal"
                                (json-at envelope "error" "message"))
                        :to-be-truthy))))
          (expect (probe-file marker) :to-be-truthy)))))

  (it "answers exec with an envelope carrying the exec'd program's status"
    (let ((envelope (json-command "exec sh -c 'echo viaexec; exit 5'")))
      (expect (json-at envelope "status") :to-equal 5)
      (expect (json-at envelope "error" "code") :to-equal "E_COMMAND_FAILED")
      (expect (json-at envelope "stdout" "text") :to-equal (format nil "viaexec~%")))
    (let ((envelope (json-command "exec true")))
      (expect (json-at envelope "ok") :to-equal t)))

  (it "stops at the first failure with :errexit-p"
    (let ((envelope (json-command "false; echo x" :errexit-p t)))
      (expect (json-at envelope "status") :to-equal 1)
      (expect (json-at envelope "stdout" "text") :to-equal ""))
    (let ((envelope (json-command "false; echo x")))
      (expect (json-at envelope "stdout" "text") :to-equal (format nil "x~%"))))

  (it "states a fractional deadline as a decimal"
    (let ((envelope (json-command "sh -c 'sleep 5'" :timeout 1/2)))
      (expect (json-at envelope "error" "message")
              :to-equal "the run exceeded its 0.5 s deadline")))

  (it "reports captured output only when the deadline stops the run"
    ;; A capture abandoned by an error, not the deadline, never reaches stdout.
    (with-temporary-function
        ((quote nshell.infrastructure.acl:spawn-pipeline)
         (lambda (&rest arguments)
           (declare (ignore arguments))
           (write-string "partial" *standard-output*)
           (error "spawn failed")))
      (let ((envelope (json-command "sh -c true")))
        (expect (json-at envelope "stdout" "text") :to-equal "")))
    ;; Text a command substitution captured is not the run's stdout.
    (let ((envelope (json-command "echo $(sh -c 'echo inner; sleep 30')" :timeout 1)))
      (expect (json-at envelope "error" "code") :to-equal "E_TIMEOUT")
      (expect (json-at envelope "stdout" "text") :to-equal ""))
    ;; Output earlier commands wrote comes before the stopped command's.
    (let ((envelope (json-command "(progn (echo a) (sh -c \"echo b; sleep 30\"))"
                                  :timeout 1)))
      (expect (json-at envelope "stdout" "text") :to-equal (format nil "a~%b~%"))))

  (it "returns E_TIMEOUT without the worker's streams when the worker survives"
    (with-temporary-function
        ((quote nshell.feature.machine::%finish-worker)
         (lambda (worker)
           (sb-thread:join-thread worker :default nil :timeout 5)
           nil))
      (let ((envelope (json-command "sh -c 'echo early; sleep 30'" :timeout 1/2)))
        (expect (json-at envelope "error" "code") :to-equal "E_TIMEOUT")
        (expect (json-at envelope "stdout" "text") :to-equal "")
        (expect (json-at envelope "stderr" "text") :to-equal ""))))

  (it "produces schema-valid envelopes for every outcome"
    (with-json-cache-home (root)
      (declare (ignorable root))
      (dolist (case '(("true") ("false") ("gti status") ("(echo") ("(car 1)")
                      ("") ("echo a; echo b") ("seq 1 10000") ("seq 1 10000" :private t)
                      ("(| (echo x) (cat))") ("rm -r ." :environment-agent-p t)
                      ("sh -c 'sleep 5'" :timeout 0.2)))
        (apply #'json-command case)))))

(describe "machine json command line"
  (it "parses --json and --timeout before --command"
    (let ((invocation (nth-value 0 (nshell::%parse-cli-arguments
                                    (list "--json" "--timeout" "2.5" "--command"
                                          "echo hi" "arg")))))
      (expect (cl-cli:option-value invocation :json) :to-be-truthy)
      (expect (cl-cli:option-value invocation :timeout) :to-equal "2.5")
      (expect (cl-cli:option-value invocation :command) :to-equal "echo hi")
      (expect (cl-cli:positional-value invocation :command-args) :to-equal '("arg")))
    (expect (nshell::%parse-timeout-seconds "2.5") :to-equal 5/2)
    (expect (nshell::%parse-timeout-seconds "120") :to-equal 120)
    (dolist (text (list "0" "0.0" "-1" "abc" "1e3" "" "." "1." ".5"))
      (expect (nshell::%parse-timeout-seconds text) :to-be-null)))

  (it "reports misused --json and --timeout as startup option errors"
    (dolist (case '((("--json") "--json requires --command")
                    (("--timeout" "5" "--command" "true") "--timeout requires --json")
                    (("--json" "--mcp") "--json cannot be combined with --mcp")
                    (("--json" "-c" "true") "--json cannot be combined with -c")
                    (("--json" "-i" "--command" "true")
                     "--json cannot be combined with --interactive")
                    (("--json" "--timeout" "0" "--command" "true")
                     "--timeout must be a positive number")
                    (("--json" "--timeout" "soon" "--command" "true")
                     "--timeout must be a positive number")))
      (destructuring-bind (arguments message) case
        (let* ((status nil)
               (stdout nil)
               (stderr (with-output-to-string (*error-output*)
                         (setf stdout
                               (with-output-to-string (*standard-output*)
                                 (setf status
                                       (nshell::%run-parsed-invocation
                                        (nth-value 0 (nshell::%parse-cli-arguments
                                                      arguments)))))))))
          (expect status :to-equal 1)
          (expect stdout :to-equal "")
          (expect (search message stderr) :to-be-truthy)
          (expect (search "Usage: nshell" stderr) :to-be-truthy)))))

  (it "prints one envelope line and exits with its status"
    (labels ((invoke (arguments)
               (let* ((exit-status nil)
                      (nshell::*main-exit-function*
                        (lambda (&key unix-status &allow-other-keys)
                          (setf exit-status unix-status)))
                      (stdout (with-output-to-string (*standard-output*)
                                (with-temporary-functions
                                    (('nshell::%current-process-arguments
                                      (lambda () arguments)))
                                  (nshell::main)))))
                 (values stdout exit-status))))
      (dolist (case '(("echo hi" 0 nil) ("false" 1 "E_COMMAND_FAILED")
                      ("gti status" 127 "E_COMMAND_NOT_FOUND")))
        (destructuring-bind (input expected-status code) case
          (multiple-value-bind (stdout exit-status)
              (invoke (list "--json" "--private" "--command" input))
            (let ((decoded (json-kit:parse stdout)))
              (expect (count #\Newline stdout) :to-equal 1)
              (expect (machine-envelope-failures decoded) :to-be-null)
              (expect exit-status :to-equal expected-status)
              (expect (json-at decoded "status") :to-equal expected-status)
              (expect (json-at decoded "error" "code") :to-equal code)))))
      (multiple-value-bind (stdout exit-status)
          (invoke (list "-e" "--json" "--private" "--command" "false; echo x"))
        (expect exit-status :to-equal 1)
        (expect (json-at (json-kit:parse stdout) "stdout" "text") :to-equal ""))
      (multiple-value-bind (stdout exit-status)
          (invoke (list "--json" "--timeout" "0.5" "--command" "sh -c 'sleep 5'"))
        (expect exit-status :to-equal 124)
        (expect (json-at (json-kit:parse stdout) "error" "code") :to-equal "E_TIMEOUT"))))

  (it "asks for approval under NSHELL_AGENT=1"
    (let ((saved (host-kit:getenv "NSHELL_AGENT"))
          (seen nil))
      (unwind-protect
           (with-temporary-function
               ((quote nshell.feature.machine:run-json-command)
                (lambda (input &key environment-agent-p &allow-other-keys)
                  (setf seen environment-agent-p)
                  (values (format nil "{~S:1}" input) 3)))
             (dolist (case '(("1" t) ("yes" t) ("0" nil) ("false" nil) ("" nil)))
               (sb-posix:setenv "NSHELL_AGENT" (first case) 1)
               (with-output-to-string (*standard-output*)
                 (expect (nshell::%run-parsed-invocation
                          (nth-value 0 (nshell::%parse-cli-arguments
                                        (list "--json" "--command" "x"))))
                         :to-equal 3))
               (expect seen :to-equal (second case))))
        (if saved
            (sb-posix:setenv "NSHELL_AGENT" saved 1)
            (sb-posix:unsetenv "NSHELL_AGENT"))))))

(describe "machine json process stopping"
  (it "copies the process registry while another thread holds its lock"
    (let* ((held (sb-thread:make-semaphore))
           (done (sb-thread:make-semaphore))
           (holder (sb-thread:make-thread
                    (lambda ()
                      (sb-thread:with-mutex
                          (nshell.infrastructure.acl::*native-process-registry-lock*)
                        (sb-thread:signal-semaphore held)
                        (sb-thread:wait-on-semaphore done :timeout 10))))))
      (unwind-protect
           (progn
             (sb-thread:wait-on-semaphore held :timeout 5)
             (let ((start (get-internal-real-time)))
               (expect (listp (nshell.infrastructure.acl:registered-processes))
                       :to-be-truthy)
               (expect (/ (- (get-internal-real-time) start)
                          internal-time-units-per-second)
                       :to-be-less-than 1/10)))
        (sb-thread:signal-semaphore done)
        (sb-thread:join-thread holder :default nil :timeout 5))))

  (it "signals only processes still running in their recorded group"
    (let ((process (nshell.infrastructure.acl:spawn-async "sleep" (list "30"))))
      (expect process :to-be-truthy)
      (unwind-protect
           (let ((pid (nshell.infrastructure.acl:process-pid process))
                 (pgid (nshell.infrastructure.acl::native-process-pgid process)))
             (expect pgid :to-equal pid)
             ;; Reaped but not yet recorded as such: left alone.
             (setf (nshell.infrastructure.acl::native-process-%status process) :exited)
             (nshell.infrastructure.acl:stop-process-groups (list process)
                                                            :grace-seconds 0.05)
             (expect (json-pid-alive-p pid) :to-be-truthy)
             ;; Recorded group no longer the process's group: left alone.
             (setf (nshell.infrastructure.acl::native-process-%status process) :running
                   (nshell.infrastructure.acl::native-process-pgid process) (1+ pgid))
             (nshell.infrastructure.acl:stop-process-groups (list process)
                                                            :grace-seconds 0.05)
             (expect (json-pid-alive-p pid) :to-be-truthy)
             (setf (nshell.infrastructure.acl::native-process-pgid process) pgid)
             (nshell.infrastructure.acl:stop-process-groups (list process)
                                                            :grace-seconds 0.05)
             (nshell.infrastructure.acl:process-wait process)
             (expect (json-pid-alive-p pid) :to-be-falsy))
        (ignore-errors
          (nshell.infrastructure.acl:kill-process
           (nshell.infrastructure.acl:process-pid process) :sigkill))
        (ignore-errors (nshell.infrastructure.acl:process-wait process))))))
