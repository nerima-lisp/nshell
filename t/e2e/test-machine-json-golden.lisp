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

(defun %json-golden-run (input directory &key extra-environment binary)
  "Run nshell in JSON command mode and return the decoded envelope, stdout,
exit status, and stderr. BINARY selects the built executable; without it the
legacy e2e helper starts the current source through SBCL."
  (let* ((root (asdf:system-source-directory :nshell))
         (program (if binary
                      (list binary "--json" "--command" input)
                      (append (list (current-sbcl-executable) "--noinform")
                              (%asdf-bootstrap-forms (namestring root))
                              (list "--eval"
                                    (%nshell-main-form
                                     (list "--json" "--command" input))))))
         (overridden (mapcar #'%json-golden-case-environment-name
                             extra-environment))
         (filtered-names (adjoin "NSHELL_AI_COMMAND" overridden
                                 :test #'string=))
         (defaults (unless (member "NSHELL_AI_COMMAND" overridden :test #'string=)
                     (list "NSHELL_AI_COMMAND=/nonexistent")))
         (environment (append defaults
                              extra-environment
                              (remove-if
                               (lambda (entry)
                                 (member
                                  (%json-golden-case-environment-name entry)
                                  filtered-names :test #'string=))
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
  (it "BUG-3 exits JSON CLI normally when an earlier pipeline command is missing"
    (cl-weave:expect-assertions 7)
    (host-kit:with-temporary-directory (work)
      (multiple-value-bind (envelope stdout status stderr)
          (%json-golden-run "gti status | cat" work)
        (expect 0 :to-equal status)
        (expect 1 :to-equal (count #\Newline stdout))
        (expect "" :to-equal stderr)
        (expect nil :to-equal (machine-envelope-failures envelope))
        (expect 0 :to-equal (json-at envelope "status"))
        (expect nil :to-equal (json-at envelope "error"))
        (expect (format nil "nshell: gti: command not found~%")
                :to-equal (json-at envelope "stderr" "text")))))
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

  ;; P2-6 removed the fish function block, so f is a defun. Its body runs no
  ;; external command before exec: a defun stage drops that command's output,
  ;; as v0.7.0 does too (eval '(defun f () (sh -c "echo x"))'; f | cat prints
  ;; nothing).
  (it "keeps a function stage's output from before its exec in order"
    (%json-golden-expect-exec-output
     (format nil "eval '(defun f () (echo a) ~
                  (exec sh -c \"echo $$ > p1; echo b\"))'; ~
                  f | tr a-z A-Z; echo after")
     '("p1") 0 (format nil "A~%B~%after~%"))))

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
     (format nil "eval '(defun f () (echo a) (exec sh -c \"echo $$ > p1; echo b\"))'; ~
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

;;; The t/golden/<id>.json runner (D-84): each case runs NSHELL_BIN in a fresh
;;; work directory and compares the normalized envelope with its expected.

(defun %machine-json-replace-text
    (text old new &key path-prefix-p (path-boundaries '(#\/)))
  (if (zerop (length old))
      text
      (with-output-to-string (out)
        (loop with start = 0
              for position = (search old text :start2 start)
              while position
              do (write-string text out :start start :end position)
                 (let ((end (+ position (length old))))
                   (if (or (not path-prefix-p)
                           (and (or (zerop position)
                                    (%machine-json-path-delimiter-p
                                     (char text (1- position))))
                                (or (= end (length text))
                                    (find (char text end) path-boundaries))))
                       (write-string new out)
                       (write-string text out :start position :end end))
                   (setf start end))
              finally (write-string text out :start start)))))
(defun %machine-json-path-delimiter-p (character)
  (find character
        (list #\Space #\Tab #\Newline #\: #\, #\; #\" #\'
              #\( #\[ #\{ #\= #\) #\] #\})))
(defun %machine-json-normalize-tool-paths (text)
  (labels ((tool-path-p (token)
             (let ((bin (search "/bin/" token)))
               (and bin
                    (> (length token) (+ bin 5))
                    (not (find #\/ token :start (+ bin 5)))
                    (or (nshell.util:string-prefix-p "/nix/store/" token)
                        (nshell.util:string-prefix-p "/usr/bin/" token)
                        (nshell.util:string-prefix-p "/usr/local/bin/" token)
                        (nshell.util:string-prefix-p "/opt/homebrew/bin/" token)
                        (nshell.util:string-prefix-p "/opt/local/bin/" token)
                        (nshell.util:string-prefix-p "/bin/" token)))))
           (absolute-path-start-p (text position)
             (or (zerop position)
                 (%machine-json-path-delimiter-p
                  (char text (1- position)))))
           (path-end (text start)
             (or (position-if #'%machine-json-path-delimiter-p text :start start)
                 (length text))))
    (with-output-to-string (out)
      (loop with start = 0
            with length = (length text)
            for slash = (position #\/ text :start start)
            while slash
            for end = (path-end text slash)
            for token = (subseq text slash end)
            do (write-string text out :start start :end slash)
               (write-string (if (and (absolute-path-start-p text slash)
                                      (tool-path-p token))
                                 "<tool>"
                                 token)
                             out)
               (setf start end)
            finally (write-string text out :start start)))))
(defun %json-golden-case-normalize (value &key work environment)
  (let ((path-prefixes
          (append
           (loop for name in (list "HOME" "XDG_CONFIG_HOME" "XDG_DATA_HOME"
                                   "XDG_STATE_HOME" "XDG_CACHE_HOME")
                 for prefix = (format nil "~A=" name)
                 for entry = (find-if
                              (lambda (candidate)
                                (and (>= (length candidate) (length prefix))
                                     (string= prefix candidate
                                              :end2 (length prefix))))
                              environment)
                 when entry
                   collect (cons (subseq entry (length prefix))
                                 (format nil "$~A" name)))
           (when work (list (cons work "$WORK"))))))
    (labels ((normalize-string (text)
               (let* ((ordered-path-prefixes
                        (sort (copy-list path-prefixes) #'>
                              :key (lambda (entry) (length (car entry)))))
                      (normalized text))
                 (dolist (prefix ordered-path-prefixes)
                   (setf normalized
                         (%machine-json-replace-text normalized
                                                      (car prefix)
                                                      (cdr prefix)
                                                      :path-prefix-p t)))
                 (setf normalized
                       (%machine-json-replace-text normalized
                                                    "/private/tmp"
                                                    "/tmp"
                                                    :path-prefix-p t))
                 (%machine-json-normalize-tool-paths normalized)))
             (normalize-value (item path)
               (cond
                 ((hash-table-p item)
                  (sort (loop for name being the hash-keys of item
                              using (hash-value value)
                              collect
                              (cons name
                                    (cond
                                      ((and (null path)
                                            (string= name "duration_ms"))
                                       0)
                                      ((and (null path)
                                            (string= name "session"))
                                       "s_golden")
                                      ((and (null path)
                                            (string= name "version")
                                            (stringp value))
                                       "<VERSION>")
                                      ((and (string= name "pid")
                                            (equal path '("state" "jobs")))
                                       0)
                                      (t (normalize-value value
                                                          (append path
                                                                  (list name)))))))
                        #'string< :key #'car))
                 ((and (vectorp item) (not (stringp item)))
                  (cons :array
                        (map 'list (lambda (element)
                                     (normalize-value element path))
                             item)))
                 ((json-kit:json-null-p item) :null)
                 ((stringp item) (normalize-string item))
                 (t item))))
      (normalize-value value nil))))

(defun %json-golden-json-value (value)
  (cond
    ((eq value :null) json-kit:+json-null+)
    ((and (consp value) (eq (car value) :array))
     (map 'vector (lambda (item) (%json-golden-json-value item)) (cdr value)))
    ((and (listp value)
          (every (lambda (entry)
                   (and (consp entry) (stringp (car entry))))
                 value))
     (json-kit:alist->json-object
      (mapcar (lambda (entry)
                (cons (car entry) (%json-golden-json-value (cdr entry))))
              (sort (copy-list value) #'string< :key #'car))))
    (t value)))

(defun %json-golden-comparison-value (value &key work environment)
  (let* ((normalized (%json-golden-case-normalize value :work work
                                             :environment environment))
         (error-entry (assoc "error" normalized :test #'string=)))
    (when (and error-entry (listp (cdr error-entry)))
      (setf (cdr error-entry)
            (remove "message" (cdr error-entry) :key #'car :test #'string=)))
    normalized))

(defun %json-golden-case-files ()
  (let* ((root (asdf:system-source-directory :nshell))
         (directory (merge-pathnames "t/golden/" root)))
    (sort (directory (merge-pathnames "*.json" directory))
          #'string< :key #'namestring)))

(defun %json-golden-case-environment-name (entry)
  (let ((separator (position #\= entry)))
    (unless separator
      (error "golden: invalid environment entry ~S" entry))
    (subseq entry 0 separator)))

(defun %json-golden-case-environment-entries (object)
  (unless (hash-table-p object)
    (error "golden: env must be a JSON object"))
  (sort (loop for name being the hash-keys of object using (hash-value value)
              collect
              (progn
                (unless (stringp value)
                  (error "golden: env value for ~A must be a string" name))
                (format nil "~A=~A" name value)))
        #'string< :key #'%json-golden-case-environment-name))

(defun %json-golden-missing-environment (name what)
  "Handle environment variable NAME not naming WHAT as the PTY tests handle a
missing PTY: an error when CI is set, a skip otherwise. checks.default sets
NSHELL_BIN and NSHELL_SPEC_BIN_DIR."
  (let ((reason (format nil "golden: ~A must name ~A" name what)))
    (if (uiop:getenv "CI")
        (error "~A (required in CI)" reason)
        (skip (format nil "~A (skipped outside CI)" reason)))))

(defun %json-golden-binary ()
  (let ((binary (uiop:getenv "NSHELL_BIN")))
    (unless (and binary (plusp (length binary)))
      (%json-golden-missing-environment "NSHELL_BIN" "the built nshell executable"))
    binary))

(defun %json-golden-case-environment (work object)
  (labels ((temporary-directory (name)
             (let* ((directory (merge-pathnames (format nil "~A/" name) work))
                    (placeholder (merge-pathnames ".golden-placeholder" directory)))
               (ensure-directories-exist placeholder)
               (%json-golden-native directory))))
    (let* ((work-path (%json-golden-native work))
           (fixture-entries (%json-golden-case-environment-entries object))
           (fixture-path-entry (find "PATH" fixture-entries
                                     :key #'%json-golden-case-environment-name
                                     :test #'string=))
           (path-value
             (if fixture-path-entry
                 (%machine-json-replace-text
                  (subseq fixture-path-entry
                          (1+ (position #\= fixture-path-entry)))
                  "$WORK" work-path
                  :path-prefix-p t
                  :path-boundaries '(#\/ #\:))
                 (let ((fixed-bin (uiop:getenv "NSHELL_SPEC_BIN_DIR")))
                   (unless (and fixed-bin (uiop:directory-exists-p fixed-bin))
                     (%json-golden-missing-environment
                      "NSHELL_SPEC_BIN_DIR" "the t/spec fixed bin directory"))
                   (format nil "~A/bin:~A" work-path fixed-bin))))
           (path-entry (format nil "PATH=~A" path-value))
           (defaults (list (format nil "HOME=~A" (temporary-directory "home"))
                           (format nil "XDG_CONFIG_HOME=~A"
                                   (temporary-directory "config"))
                           (format nil "XDG_DATA_HOME=~A"
                                   (temporary-directory "data"))
                           (format nil "XDG_STATE_HOME=~A"
                                   (temporary-directory "state"))
                           (format nil "XDG_CACHE_HOME=~A"
                                   (temporary-directory "cache"))))
           (fixture-overrides
             (remove-if (lambda (entry)
                          (string= "PATH"
                                   (%json-golden-case-environment-name entry)))
                        fixture-entries))
           (fixture-names (mapcar #'%json-golden-case-environment-name
                                  fixture-overrides)))
      (ensure-directories-exist
       (merge-pathnames "bin/.golden-placeholder" work))
      (append (remove-if (lambda (entry)
                           (member (%json-golden-case-environment-name entry)
                                   fixture-names :test #'string=))
                         defaults)
              fixture-overrides
              (list path-entry)))))

(defun %json-golden-safe-relative-file-p (path)
  (labels ((safe-components-p (start)
             (let* ((separator (position #\/ path :start start))
                    (end (or separator (length path)))
                    (component (subseq path start end)))
               (and (plusp (length component))
                    (not (string= component "."))
                    (not (string= component ".."))
                    (or (null separator)
                        (safe-components-p (1+ end)))))))
    (and (stringp path)
         (plusp (length path))
         (not (char= #\/ (char path 0)))
         (safe-components-p 0))))

(defun %json-golden-materialize-files (directory files)
  (unless (hash-table-p files)
    (error "golden: files must be a JSON object"))
  (maphash
   (lambda (name contents)
     (unless (and (stringp name)
                  (stringp contents)
                  (%json-golden-safe-relative-file-p name))
       (error "golden: invalid fixture file ~S" name))
     (let ((target (merge-pathnames name directory)))
       (ensure-directories-exist target)
       (with-open-file (out target :direction :output :if-exists :supersede
                            :if-does-not-exist :create :external-format :utf-8)
         (write-string contents out))
       (when (and (>= (length name) 4)
                  (string= "bin/" name :end2 4))
         (sb-posix:chmod (namestring target) #o755))))
   files))

(defun %json-golden-read-case (path)
  (json-kit:parse (uiop:read-file-string path :external-format :utf-8)))

(defun %json-golden-write-case (path case expected)
  (setf (gethash "expected" case) (%json-golden-json-value expected))
  (with-open-file (out path :direction :output :if-exists :supersede
                       :if-does-not-exist :create :external-format :utf-8)
    (json-kit:write-json case out :pretty t :indent 2 :sort-keys t)
    (terpri out)))

(defun %json-golden-update-mode-p (ci update)
  (let ((update-p (string= (or update "") "1")))
    (when (and ci update-p)
      (error "golden: expectation updates are disabled when CI is set"))
    update-p))

(defun %json-golden-update-case (case-path case expected)
  (%json-golden-write-case case-path case expected)
  t)

(defun %json-golden-run-case (case-path binary update-p &optional (ci (uiop:getenv "CI")))
  (let* ((update-p (%json-golden-update-mode-p
                    ci
                    (if update-p "1" "")))
         (case (%json-golden-read-case case-path))
         (input (gethash "input" case))
         (env (gethash "env" case))
         (files (gethash "files" case))
         (expected (gethash "expected" case))
         (keys (sort (loop for key being the hash-keys of case collect key)
                     #'string<))
         (envelope nil)
         (work-path nil)
         (environment nil)
         (status nil))
    (expect keys :to-equal (list "env" "expected" "files" "input"))
    (expect (stringp input) :to-be-truthy)
    (expect (hash-table-p env) :to-be-truthy)
    (expect (hash-table-p files) :to-be-truthy)
    (expect (hash-table-p expected) :to-be-truthy)
    (host-kit:with-temporary-directory (work)
      (setf work-path (%json-golden-native work)
            environment (%json-golden-case-environment work env))
      (%json-golden-materialize-files work files)
      (multiple-value-bind (result stdout exit-status stderr)
          (%json-golden-run input work :extra-environment environment
                                         :binary binary)
        (declare (ignore stdout stderr))
        (setf envelope result
              status exit-status)))
    (expect status :to-equal (gethash "status" envelope))
    (if update-p
        (progn
          (%json-golden-update-case
           case-path case
           (%json-golden-case-normalize envelope :work work-path
                                  :environment environment))
          (fail "期待値を更新した。比べるモードでもう一度流す"))
        (expect (%json-golden-comparison-value
                 envelope :work work-path :environment environment)
                :to-equal
                (%json-golden-comparison-value
                 expected :work work-path :environment environment)))))

(defun %json-golden-case-test-name (case-path)
  (format nil "case ~A" (pathname-name case-path)))

(defun %json-golden-register-cases ()
  (let ((update-p (string= (or (uiop:getenv "NSHELL_GOLDEN_UPDATE") "") "1")))
    (dolist (case-path (%json-golden-case-files))
      (eval (list 'it
                  (%json-golden-case-test-name case-path)
                  (list '%json-golden-run-case
                        (namestring case-path) '(%json-golden-binary) update-p))))))

(defun %json-golden-planned-test-paths ()
  "Return the path, a list of suite and test names, of every planned test."
  (let ((plan (let ((*read-eval* nil))
                (read-from-string
                 (with-output-to-string (stream)
                   (cl-weave:list-tests :reporter :sexp :stream stream))))))
    (mapcar (lambda (entry) (getf entry :path))
            (getf (rest plan) :tests))))

(describe "golden runner"
  (%json-golden-register-cases)

  (it "registers every case id as a separate test"
    (let ((case-test-names
            (loop for path in (%json-golden-planned-test-paths)
                  when (equal (car (last path 2)) "golden runner")
                    collect (car (last path)))))
      (expect (%json-golden-case-files) :to-be-truthy)
      (dolist (case-path (%json-golden-case-files))
        (expect (count (%json-golden-case-test-name case-path) case-test-names
                       :test #'equal)
                :to-equal 1))))

  (it "normalizes short tool paths and preserves unrelated absolute paths"
    (expect (%json-golden-case-normalize
             (json-kit:parse "{\"stderr\":{\"text\":\"/bin/sh: x: not found\"}}"))
            :to-equal
            (list (cons "stderr"
                        (list (cons "text" "<tool>: x: not found")))))
    (expect (%json-golden-case-normalize
             (json-kit:parse "{\"path\":\"/usr/share/doc/bin/README\"}"))
            :to-equal
            (list (cons "path" "/usr/share/doc/bin/README"))))

  (it "keeps WORK paths and unrelated prefixes intact"
    (expect (%json-golden-case-normalize
             (json-kit:parse "{\"state\":{\"cwd\":\"/tmp/golden-work\",\"embedded\":\"prefix/tmp/golden-work/file\",\"lookalike\":\"/tmp/golden-workshop/file\",\"private\":\"/private/tmp/external\",\"private-embedded\":\"prefix/private/tmp/file\",\"tool\":\"/tmp/golden-work/bin/longtoolname\"}}")
             :work "/tmp/golden-work")
            :to-equal
            (list (cons "state"
                        (list (cons "cwd" "$WORK")
                              (cons "embedded" "prefix/tmp/golden-work/file")
                              (cons "lookalike" "/tmp/golden-workshop/file")
                              (cons "private" "/tmp/external")
                              (cons "private-embedded" "prefix/private/tmp/file")
                              (cons "tool" "$WORK/bin/longtoolname"))))))

  (it "normalizes volatile values only at envelope positions"
    (expect (%json-golden-case-normalize
             (json-kit:parse
              "{\"duration_ms\":91,\"session\":\"s_actual\",\"version\":\"0.8.0\",\"state\":{\"duration_ms\":5,\"jobs\":[{\"pid\":8123}],\"pid\":41,\"session\":\"state-user\",\"version\":\"state-user\"},\"stdout\":{\"duration_ms\":7,\"pid\":1001,\"session\":\"stdout-user\",\"version\":\"user-data\"}}"))
            :to-equal
            (list (cons "duration_ms" 0)
                  (cons "session" "s_golden")
                  (cons "state"
                        (list (cons "duration_ms" 5)
                              (cons "jobs" (list :array (list (cons "pid" 0))))
                              (cons "pid" 41)
                              (cons "session" "state-user")
                              (cons "version" "state-user")))
                  (cons "stdout"
                        (list (cons "duration_ms" 7)
                              (cons "pid" 1001)
                              (cons "session" "stdout-user")
                              (cons "version" "user-data")))
                  (cons "version" "<VERSION>"))))

  (it "rejects expectation updates when CI is set"
    (let ((condition
            (handler-case
                (progn (%json-golden-update-mode-p "" "1") nil)
              (error (condition) condition))))
      (expect (and condition
                   (search "CI" (princ-to-string condition)))
              :to-be-truthy)
      (expect (%json-golden-update-mode-p nil "1") :to-be-truthy)))

  (it "fails after writing updated expectations"
    (let ((binary (%json-golden-binary))
          (failure nil)
          (written-p nil))
      (host-kit:with-temporary-directory (work)
        (let* ((case-path (merge-pathnames "case.json" work))
               (case (json-kit:parse "{\"env\":{},\"expected\":{},\"files\":{},\"input\":\"echo hi\"}")))
          (%json-golden-write-case case-path case nil)
          (setf failure
                (handler-case
                    (progn
                      (%json-golden-run-case case-path binary t nil)
                      nil)
                  (cl-weave:test-failure (condition) condition)))
          (setf written-p
                (eql 0 (gethash "status"
                                (gethash "expected"
                                         (%json-golden-read-case case-path)))))))
      (expect (typep failure 'cl-weave:test-failure) :to-be-truthy)
      (expect written-p :to-be-truthy)))

  (it "normalizes the D-84 fields and path values"
    (let ((actual
            (json-kit:parse
             "{\"duration_ms\":91,\"outside\":\"/private/tmp/external\",\"session\":\"s_actual\",\"state\":{\"cwd\":\"/tmp/golden-work/home\",\"jobs\":[{\"pid\":8123}],\"tool\":\"/nix/store/hash-coreutils/bin/echo\"},\"version\":\"0.7.0\",\"work\":\"/tmp/golden-work/cache\"}")))
      (expect (%json-golden-case-normalize
               actual
               :work "/tmp/golden-work"
               :environment (list "HOME=/tmp/golden-work/home"))
              :to-equal
              (list (cons "duration_ms" 0)
                    (cons "outside" "/tmp/external")
                    (cons "session" "s_golden")
                    (cons "state"
                          (list (cons "cwd" "$HOME")
                                (cons "jobs" (list :array (list (cons "pid" 0))))
                                (cons "tool" "<tool>")))
                    (cons "version" "<VERSION>")
                    (cons "work" "$WORK/cache")))))

  (it "stores error.message but excludes it from comparisons"
    (let* ((first (json-kit:parse
                   "{\"error\":{\"code\":\"E_TEST\",\"message\":\"first\"}}"))
           (second (json-kit:parse
                    "{\"error\":{\"code\":\"E_TEST\",\"message\":\"second\"}}"))
           (normalized (%json-golden-case-normalize first))
           (error-object (cdr (assoc "error" normalized :test #'string=))))
      (expect (%json-golden-comparison-value first)
              :to-equal (%json-golden-comparison-value second))
      (expect (cdr (assoc "message" error-object :test #'string=))
              :to-equal "first"))))

(describe "golden PATH"
  (it "uses only WORK/bin and the t/spec fixed bin by default"
    (host-kit:with-temporary-directory (work)
      (let* ((work-path (%json-golden-native work))
             (fixed-bin (uiop:getenv "NSHELL_SPEC_BIN_DIR"))
             (environment (%json-golden-case-environment
                           work (make-hash-table :test #'equal)))
             (path-entry
               (find-if (lambda (entry)
                          (and (>= (length entry) 5)
                               (string= "PATH=" entry :end2 5)))
                        environment)))
        (expect path-entry
                :to-equal (format nil "PATH=~A/bin:~A" work-path fixed-bin)))))

  (it "expands only complete WORK tokens in an explicit PATH"
    (host-kit:with-temporary-directory (work)
      (let ((fixture (make-hash-table :test #'equal)))
        (setf (gethash "PATH" fixture)
              "$WORKSHOP/bin:$WORK/bin:$WORK:/fixture/bin")
        (let* ((work-path (%json-golden-native work))
               (environment (%json-golden-case-environment work fixture))
               (path-entry
                 (find-if (lambda (entry)
                            (and (>= (length entry) 5)
                                 (string= "PATH=" entry :end2 5)))
                          environment)))
          (expect path-entry
                  :to-equal
                  (format nil "PATH=$WORKSHOP/bin:~A/bin:~A:/fixture/bin"
                          work-path work-path)))))))
