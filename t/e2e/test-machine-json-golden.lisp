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

(defun %json-golden-git-repository (directory)
  "Make DIRECTORY a git repository with exactly three changed (untracked) files."
  (let ((git (%resolve-real-external-executable "git")))
    (host-kit:run-program git (list "init" "-q") :directory directory :timeout 60)
    (dolist (name '("a.txt" "b.txt" "c.txt"))
      (with-open-file (out (merge-pathnames name directory) :direction :output)
        (write-line name out)))))

(defun %json-golden-native (directory)
  (string-right-trim "/" (sb-ext:native-namestring (truename directory))))

(defun %json-golden-run-pipeline-example ()
  "Run proposal/02's --json example in a fresh repository and return the
envelope with duration_ms set to 0 and state.cwd to $WORK."
  (host-kit:with-temporary-directory (work)
    (%json-golden-git-repository work)
    (multiple-value-bind (envelope stdout status stderr)
        (%json-golden-run "(| (git status --short) (wc -l))" work)
      (declare (ignore stdout))
      (unless (eql status 0)
        (format *error-output* "~&golden pipeline exited ~A; stderr:~%~A~%" status stderr))
      (expect status :to-equal 0)
      (expect (machine-envelope-failures envelope) :to-be-null)
      (expect (gethash "cwd" (gethash "state" envelope))
              :to-equal (%json-golden-native work))
      (setf (gethash "duration_ms" envelope) 0
            (gethash "cwd" (gethash "state" envelope)) "$WORK")
      envelope)))

(defun %json-golden-pipeline-expected ()
  (let ((example (json-kit:parse
                  (%json-golden-example "docs/design/proposal/02-machine-interface.md"
                                        "$ nshell --json --command '(| (git status --short)"))))
    (setf (gethash "duration_ms" example) 0
          (gethash "cwd" (gethash "state" example)) "$WORK")
    (%json-golden-with-writer-members example)))

(defun %json-golden-without (object &rest names)
  (let ((copy (make-hash-table :test #'equal)))
    (maphash (lambda (key value)
               (unless (member key names :test #'string=)
                 (setf (gethash key copy) value)))
             object)
    copy))

(describe "machine json golden examples"
  (it "matches proposal/02's --json pipeline example except effects and safety"
    (expect (%json-golden-normalize
             (%json-golden-without (%json-golden-run-pipeline-example) "effects" "safety"))
            :to-equal
            (%json-golden-normalize
             (%json-golden-without (%json-golden-pipeline-expected) "effects" "safety"))))

  (it "matches proposal/02's --json pipeline example effects"
    (skip "effects stay [] until P1-5 adds the effects model (example: reads .)"))

  (it "matches proposal/02's --json pipeline example safety"
    (skip (format nil "the classifier marks git status confirm, the example safe; ~
                       P1-5 rewrites the safety rules")))

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
    (skip "effects stay [] until P1-5 adds the effects model (example: writes result/)"))

  (it "matches proposal/02's structured error example except fixes"
    (host-kit:with-temporary-directory (work)
      (let* ((example (json-kit:parse
                       (%json-golden-example "docs/design/proposal/02-machine-interface.md"
                                             "{" :whole-line-p t)))
             (expected-error (%json-golden-without (gethash "error" example) "fixes")))
        (multiple-value-bind (envelope stdout status)
            (%json-golden-run "gti status" work)
          (declare (ignore stdout))
          (expect status :to-equal (gethash "status" example))
          (expect (gethash "status" envelope) :to-equal (gethash "status" example))
          (expect (machine-envelope-failures envelope) :to-be-null)
          (expect (%json-golden-normalize
                   (%json-golden-without (gethash "error" envelope) "fixes"))
                  :to-equal (%json-golden-normalize expected-error))))))

  (it "matches proposal/02's structured error example fixes"
    (skip "fixes (diagnose/typo) come with P1-5's diagnose rules")))
