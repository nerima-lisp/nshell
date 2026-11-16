(in-package #:nshell/test)

;;; The --json examples of proposal/02 and ux/U6 as golden tests against a
;;; real `nshell --json --command` process. Each example is read from the
;;; design document itself, so the test fails when either side drifts.
;;;
;;; The envelope writer always emits stdout/stderr "lines" and "truncated" and
;;; state "env_changed" and "jobs"; the examples omit some of them. The
;;; comparisons add exactly those members, with their empty values, to the
;;; example and then require equality.

(defparameter +json-golden-writer-members+
  '((("stderr") "lines" 0)
    (("stderr") "truncated" :false)
    (("state") "env_changed" :empty-array)
    (("state") "jobs" :empty-array))
  "Members the envelope writer always emits that an example may omit, as
(PATH NAME VALUE) with :FALSE and :EMPTY-ARRAY standing for JSON false and [].")

(defun %json-golden-document (relative-path)
  (uiop:read-file-lines
   (merge-pathnames relative-path (asdf:system-source-directory :nshell))
   :external-format :utf-8))

(defun %json-golden-example (relative-path first-line &key whole-line-p)
  "Return the example JSON in RELATIVE-PATH that starts on the line starting
with FIRST-LINE (equal to it when WHOLE-LINE-P), or on the line after it when
that line is a shell command, and ends before the closing fence."
  (let* ((lines (%json-golden-document relative-path))
         (start (position-if (lambda (line)
                               (if whole-line-p
                                   (string= first-line line)
                                   (and (>= (length line) (length first-line))
                                        (string= first-line line
                                                 :end2 (length first-line)))))
                             lines)))
    (unless start
      (error "golden: ~A has no example line ~S" relative-path first-line))
    (let* ((from (if (char= #\{ (char (nth start lines) 0)) start (1+ start)))
           (end (position "```" lines :start from :test #'string=)))
      (format nil "~{~A~^~%~}" (subseq lines from end)))))

(defun %json-golden-normalize (value)
  "Return decoded JSON VALUE with objects as alists sorted by key, so EQUAL
compares two documents regardless of member order."
  (cond
    ((hash-table-p value)
     (sort (loop for key being the hash-keys of value using (hash-value item)
                 collect (cons key (%json-golden-normalize item)))
           #'string< :key #'car))
    ((and (vectorp value) (not (stringp value)))
     (cons :array (map 'list #'%json-golden-normalize value)))
    (t value)))

(defun %json-golden-set (object path name value)
  "Set member NAME of the object at PATH under decoded OBJECT to VALUE."
  (let ((target object))
    (dolist (key path) (setf target (gethash key target)))
    (setf (gethash name target) value)
    object))

(defun %json-golden-with-writer-members (object)
  (loop for (path name value) in +json-golden-writer-members+
        do (%json-golden-set object path name
                             (case value
                               (:false json-kit:+json-false+)
                               (:empty-array (vector))
                               (t value))))
  object)

(defun %json-golden-run (input directory &key extra-environment)
  "Run `nshell --json --command INPUT` with DIRECTORY as its working
directory and return the decoded envelope, its stdout text and exit status."
  (let* ((root (asdf:system-source-directory :nshell))
         (program (append (list (current-sbcl-executable) "--noinform")
                          (%asdf-bootstrap-forms (namestring root))
                          (list "--eval"
                                (%nshell-main-form (list "--json" "--command" input)))))
         (overridden (mapcar (lambda (entry) (subseq entry 0 (position #\= entry)))
                             extra-environment))
         (environment (append extra-environment
                              (list "NSHELL_AI_COMMAND=/nonexistent")
                              (remove-if (lambda (entry)
                                           (member (subseq entry 0 (position #\= entry))
                                                   overridden :test #'string=))
                                         (%e2e-child-environment))))
         (result (host-kit:run-program (first program) (rest program)
                                       :directory directory
                                       :environment environment
                                       :timeout 120))
         (stdout (host-kit:process-result-stdout result)))
    (values (json-kit:parse stdout)
            stdout
            (host-kit:process-result-exit-code result)
            (host-kit:process-result-stderr result))))

(defun %json-golden-bin-file (work name content)
  "Create bin/NAME under WORK with CONTENT and make it executable, as the
golden convention creates every file under bin/; return the bin directory."
  (let ((bin (merge-pathnames "bin/" work)))
    (ensure-directories-exist bin)
    (with-open-file (out (merge-pathnames name bin) :direction :output)
      (write-string content out))
    (sb-posix:chmod (sb-ext:native-namestring (merge-pathnames name bin)) #o755)
    bin))

(defun %json-golden-native (directory)
  (string-right-trim "/" (sb-ext:native-namestring (truename directory))))

(defun %json-golden-run-pipeline-example ()
  "Run proposal/02's --json example in a fresh directory and return the
envelope with duration_ms set to 0 and state.cwd to $WORK."
  (host-kit:with-temporary-directory (work)
    ;; As the golden convention has it: no repository, but a git on
    ;; $WORK/bin, put before the host's PATH, that prints three changed
    ;; files.  wc comes from the host.
    (let ((bin (%json-golden-bin-file
                work "git"
                (format nil "#!/bin/sh~%printf '?? a.txt\\n?? b.txt\\n?? c.txt\\n'~%"))))
      (multiple-value-bind (envelope stdout status stderr)
          (%json-golden-run "(| (git status --short) (wc -l))" work
                            :extra-environment
                            (list (format nil "PATH=~A:~A" (%json-golden-native bin)
                                          (uiop:getenv "PATH"))))
        (declare (ignore stdout))
        (unless (eql status 0)
          (format *error-output* "~&golden pipeline exited ~A; stderr:~%~A~%"
                  status stderr))
        (expect status :to-equal 0)
        (expect (machine-envelope-failures envelope) :to-be-null)
        (expect (gethash "cwd" (gethash "state" envelope))
                :to-equal (%json-golden-native work))
        (setf (gethash "duration_ms" envelope) 0
              (gethash "cwd" (gethash "state" envelope)) "$WORK")
        envelope))))

(defun %json-golden-pipeline-expected ()
  (let ((example (json-kit:parse
                  (%json-golden-example "docs/design/proposal/02-machine-interface.md"
                                        "$ nshell --json --command '(| (git status --short)"))))
    (setf (gethash "duration_ms" example) 0
          (gethash "cwd" (gethash "state" example)) "$WORK")
    (%json-golden-with-writer-members example)))

(describe "machine json golden examples"
  (it "matches proposal/02's --json pipeline example"
    (expect (%json-golden-normalize (%json-golden-run-pipeline-example))
            :to-equal
            (%json-golden-normalize (%json-golden-pipeline-expected))))

  (it "has the shape of ux/U6's long-output example"
    (host-kit:with-temporary-directory (work)
      (host-kit:with-temporary-directory (cache)
        (let ((log (merge-pathnames "build.log" work)))
          (with-open-file (out log :direction :output)
            (dotimes (index 9120)
              (format out "Compiling module ~5,'0D of nshell~%" index)))
          (multiple-value-bind (envelope stdout status)
              (%json-golden-run "cat build.log" work
                                :extra-environment
                                (list (format nil "XDG_CACHE_HOME=~A"
                                              (%json-golden-native cache))))
            (declare (ignore stdout))
            (let* ((example (%json-golden-with-writer-members
                             (json-kit:parse
                              (%json-golden-example
                               "docs/design/ux/U6-response-envelope.md"
                               "{\"nshell_api\": 1, \"ok\": true"))))
                   (output (gethash "stdout" envelope))
                   (session (gethash "session" envelope))
                   (seq (gethash "seq" envelope)))
              (expect status :to-equal 0)
              (expect (machine-envelope-failures envelope) :to-be-null)
              (flet ((keys (object &rest drop)
                         (sort (loop for key being the hash-keys of object
                                     unless (member key drop :test #'string=)
                                       collect key)
                               #'string<)))
                (expect (keys envelope) :to-equal (keys example))
                (expect (keys output) :to-equal (keys (gethash "stdout" example)))
                (expect (keys (gethash "state" envelope))
                        :to-equal (keys (gethash "state" example))))
              (expect (gethash "truncated" output) :to-equal t)
              (expect (gethash "lines" output) :to-equal 9120)
              (expect (gethash "bytes" output)
                      :to-equal (with-open-file (in log :element-type '(unsigned-byte 8))
                                  (file-length in)))
              (expect (search (format nil "… 9,100 lines omitted …")
                              (gethash "text" output))
                      :to-be-truthy)
              (expect (%json-golden-normalize (gethash "stderr" envelope))
                      :to-equal (%json-golden-normalize (gethash "stderr" example)))
              (expect (%json-golden-normalize (gethash "safety" envelope))
                      :to-equal (%json-golden-normalize (gethash "safety" example)))
              (expect (integerp seq) :to-be-truthy)
              (expect (gethash "path" output)
                      :to-equal (format nil "~A/nshell/out/~A/~D.txt"
                                        (%json-golden-native cache) session seq))
              (expect (probe-file (gethash "path" output)) :to-be-truthy)))))))

  (it "has the shape of ux/U6's long-output example effects"
    (skip (format nil "the example's writes result/ comes from a build, ~
                       not from cat, whose effect is reads build.log")))

  (it "matches proposal/02's structured error example"
    ;; The fixes come from the names the run can resolve, PATH included, so
    ;; PATH holds only a git instead of being put before the host's PATH:
    ;; a name one edit from gti on some host's PATH would be a fix as near
    ;; as git.
    (host-kit:with-temporary-directory (work)
      (let ((example (json-kit:parse
                      (%json-golden-example "docs/design/proposal/02-machine-interface.md"
                                            "{" :whole-line-p t)))
            (bin (%json-golden-bin-file work "git"
                                        (format nil "#!/bin/sh~%exit 0~%"))))
        (multiple-value-bind (envelope stdout status)
            (%json-golden-run "gti status" work
                              :extra-environment
                              (list (format nil "PATH=~A" (%json-golden-native bin))))
          (declare (ignore stdout))
          (expect status :to-equal (gethash "status" example))
          (expect (gethash "status" envelope) :to-equal (gethash "status" example))
          (expect (machine-envelope-failures envelope) :to-be-null)
          (expect (%json-golden-normalize (gethash "error" envelope))
                  :to-equal (%json-golden-normalize (gethash "error" example))))))))

(describe "machine json real entry"
  (it "answers exec in a pipeline stage with one envelope"
    ;; exec in a stage thread once reached sb-ext:quit and printed nothing.
    ;; The run has the pipeline's status, cat's.
    (host-kit:with-temporary-directory (work)
      (multiple-value-bind (envelope stdout status)
          (%json-golden-run "exec sh -c 'exit 7' | cat" work)
        (expect (count #\Newline stdout) :to-equal 1)
        (expect (machine-envelope-failures envelope) :to-be-null)
        (expect status :to-equal 0)
        (expect (gethash "ok" envelope) :to-equal t)))))

(defun %json-golden-recorded-pids (directory &rest names)
  "Return the pids the run wrote to the files NAMES in DIRECTORY."
  (loop for name in names
        collect (parse-integer (uiop:read-file-string (merge-pathnames name directory))
                               :junk-allowed t)))

(defun %json-golden-check-exec-run (input pid-files check)
  "Run INPUT in a fresh directory and expect one schema-valid envelope whose
status is the exit status. Call CHECK with the envelope, the exit status and
the directory right after the process exited, then expect every pid the run
wrote to PID-FILES to be gone."
  (host-kit:with-temporary-directory (work)
    (multiple-value-bind (envelope stdout status)
        (%json-golden-run input work)
      (unwind-protect
           (progn
             (expect (count #\Newline stdout) :to-equal 1)
             (expect (machine-envelope-failures envelope) :to-be-null)
             (expect (gethash "status" envelope) :to-equal status)
             (funcall check envelope status work)
             (expect (json-wait-until-dead
                      (apply #'%json-golden-recorded-pids work pid-files) 0.5)
                     :to-be-null))
        (dolist (name pid-files)
          (ignore-errors
            (sb-posix:kill (first (%json-golden-recorded-pids work name))
                           sb-unix:sigkill)))))))

(defun %json-golden-expect-exec-pipeline (input expected-status)
  "Run INPUT, whose two stages exec a sh that records its pid in p1 and p2,
and expect EXPECTED-STATUS as the exit status."
  (%json-golden-check-exec-run
   input '("p1" "p2")
   (lambda (envelope status work)
     (declare (ignore envelope work))
     (expect status :to-equal expected-status))))

(defun %json-golden-stdout-text (envelope)
  (gethash "text" (gethash "stdout" envelope)))

(defun %json-golden-expect-exec-output (input pid-files expected-status expected-stdout)
  "Run INPUT as %JSON-GOLDEN-CHECK-EXEC-RUN does and expect EXPECTED-STATUS,
EXPECTED-STDOUT and an empty stderr."
  (%json-golden-check-exec-run
   input pid-files
   (lambda (envelope status work)
     (declare (ignore work))
     (expect status :to-equal expected-status)
     (expect (%json-golden-stdout-text envelope) :to-equal expected-stdout)
     (expect (gethash "text" (gethash "stderr" envelope)) :to-equal ""))))

(describe "machine json real entry exec in several stages"
  ;; exec in a stage ends only that stage, with its program's status, and the
  ;; run reports the pipeline's own status: the last stage's.
  (it "reports the last stage's status when the earlier exec'd stage ends first"
    (%json-golden-expect-exec-pipeline
     "exec sh -c 'echo $$ > p1; exit 7' | exec sh -c 'echo $$ > p2; sleep 2; exit 8'"
     8))

  (it "reports the last stage's status when the earlier exec'd stage ends last"
    (%json-golden-expect-exec-pipeline
     "exec sh -c 'echo $$ > p1; sleep 2; exit 7' | exec sh -c 'echo $$ > p2; exit 8'"
     8))

  (it "runs the next command after a pipeline whose stage exec'd"
    (%json-golden-check-exec-run
     "exec true | sh -c 'echo $$ > p1; sleep 1; echo late'; echo after" '("p1")
     (lambda (envelope status work)
       (declare (ignore work))
       (expect status :to-equal 0)
       (expect (%json-golden-stdout-text envelope)
               :to-equal (format nil "late~%after~%")))))

  (it "keeps a function stage's output from before its exec in order"
    (%json-golden-expect-exec-output
     (format nil "function f; echo a; sh -c 'echo x'; ~
                  exec sh -c 'echo $$ > p1; echo b'; end; ~
                  f | tr a-z A-Z; echo after")
     '("p1") 0 (format nil "A~%X~%B~%after~%")))

  (it "keeps a function stage's output from before its exec in a command substitution"
    (%json-golden-expect-exec-output
     (format nil "function f; echo a; exec sh -c 'echo $$ > p1; echo b'; end; ~
                  echo $(f | cat); echo after")
     '("p1") 0 (format nil "a b~%after~%"))))

(describe "machine json real entry exec in substitutions"
  (it "waits for every process substitution when some of them exec"
    (%json-golden-check-exec-run
     (format nil "true <(exec sh -c 'echo $$ > p1; exit 7') ~
                  <(sh -c 'echo $$ > p2; sleep 1; echo late > marker') ~
                  <(exec sh -c 'echo $$ > p3; exit 8'); echo after")
     '("p1" "p2" "p3")
     (lambda (envelope status work)
       (expect (probe-file (merge-pathnames "marker" work)) :to-be-truthy)
       (expect status :to-equal 0)
       (expect (%json-golden-stdout-text envelope) :to-equal (format nil "after~%")))))

  (it "keeps a process substitution's input from before its stage's exec"
    (%json-golden-expect-exec-output
     "cat <(echo a | exec sh -c 'echo $$ > p1; cat; echo b'); echo after" '("p1")
     0 (format nil "a~%b~%after~%")))

  (it "keeps a function's output from before its exec in a command substitution"
    (%json-golden-expect-exec-output
     (format nil "function f; echo a; exec sh -c 'echo $$ > p1; echo b'; end; ~
                  echo $(f); echo after")
     '("p1") 0 (format nil "a b~%after~%")))

  (it "ends only a command substitution whose command execs"
    (%json-golden-check-exec-run
     "echo $(exec sh -c 'echo $$ > p1; echo in; exit 3'); echo after" '("p1")
     (lambda (envelope status work)
       (declare (ignore work))
       (expect status :to-equal 0)
       (expect (%json-golden-stdout-text envelope)
               :to-equal (format nil "in~%after~%")))))

  (it "keeps a command substitution's output from before its exec"
    ;; echo returns its output as a value, which exec once threw away.
    (%json-golden-expect-exec-output
     "echo $(echo a; exec sh -c 'echo $$ > p1; echo b'); echo after" '("p1")
     0 (format nil "a b~%after~%")))

  (it "keeps an external command's output from before exec in order"
    (%json-golden-expect-exec-output
     "echo $(sh -c 'printf x'; exec sh -c 'echo $$ > p1; printf y'); echo after" '("p1")
     0 (format nil "xy~%after~%")))

  (it "keeps the output from before exec in nested command substitutions"
    (%json-golden-expect-exec-output
     "echo $(echo $(echo a; exec echo b) c; exec echo d); echo after" nil
     0 (format nil "a b c d~%after~%")))

  (it "keeps the output from before a top-level exec"
    (%json-golden-expect-exec-output
     "sh -c 'echo x'; exec sh -c 'echo $$ > p1; echo y; exit 4'" '("p1")
     4 (format nil "x~%y~%")))

  (it "waits for a top-level exec's process substitution before ending the run"
    (%json-golden-check-exec-run
     (format nil "exec sh -c 'echo $$ > p1; exit 5' ~
                  <(sh -c 'echo $$ > p2; sleep 1; echo late > marker'); echo after")
     '("p1" "p2")
     (lambda (envelope status work)
       (expect (probe-file (merge-pathnames "marker" work)) :to-be-truthy)
       (expect status :to-equal 5)
       (expect (%json-golden-stdout-text envelope) :to-equal "")))))
