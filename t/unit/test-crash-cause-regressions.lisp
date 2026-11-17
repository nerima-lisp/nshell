;;; Regression tests for inputs that ended in a crash log although they are
;;; ordinary failures: language-spec probes run as scripts, and pipefail set
;;; earlier on the same command line.
(in-package #:nshell/test)

(defun %crash-cause-run-script (source &key path-directory config-home)
  "Run SOURCE as a script file under a fresh XDG_STATE_HOME. Return the exit
status, the standard output, the error output, and the crash log count. When
PATH-DIRECTORY is given, PATH holds only that directory while the script runs;
CONFIG-HOME likewise replaces XDG_CONFIG_HOME."
  (with-crash-state-home (state-home)
    (with-repl-test-state
      (host-kit:with-temporary-directory (root)
        (let ((script (namestring (merge-pathnames "case.nsh" root)))
              (status nil)
              (output nil))
          (with-open-file (stream script :direction :output)
            (write-string source stream))
          (let ((error-output
                  (with-output-to-string (*error-output*)
                    (setf output
                          (with-output-to-string (*standard-output*)
                            (with-crash-test-environment
                                (("PATH" (if path-directory
                                             (namestring path-directory)
                                             (host-kit:getenv "PATH")))
                                 ("XDG_CONFIG_HOME"
                                  (if config-home
                                      (namestring config-home)
                                      (host-kit:getenv "XDG_CONFIG_HOME"))))
                              (setf status
                                    (nshell.presentation::run-repl-script
                                     script))))))))
            (values status output error-output
                    (length (%crash-log-files state-home)))))))))

(defun %crash-cause-run-batch (line)
  "Run LINE through the --command batch path under a fresh XDG_STATE_HOME.
Return the exit status, the error output, and the crash log count."
  (with-crash-state-home (state-home)
    (with-repl-test-state
      (let* ((status nil)
             (error-output
               (with-output-to-string (*error-output*)
                 (let ((*standard-output* (make-broadcast-stream)))
                   (setf status
                         (nshell.presentation::run-repl-batch :line line))))))
        (values status error-output
                (length (%crash-log-files state-home)))))))

(describe "crash-cause-regressions"
  (it "scanner-rejected-script-forms-are-e-parse-diagnostics-without-a-crash-log"
    ;; Probes redir-value-target and pipe-mixed-2: the reader accepts each
    ;; form but the scanner reports it invalid or incomplete.
    (dolist (case '(("(echo hi > ,(concatenate (quote string) \"o\" \"3.txt\"))
(^cat o3.txt)
" 2 "case.nsh:1:13: syntax error [12,13)")
                    ;; An empty span at the end of the input exits 1, as
                    ;; %REPORT-REPL-SCRIPT-SOURCE-DIAGNOSTIC does for an
                    ;; unclosed parenthesis.
                    ("(echo hi) | tr a-z A-Z
" 1 "case.nsh:1:23: syntax error [22,22)")))
      (destructuring-bind (source expected-status expected-diagnostic) case
        (multiple-value-bind (status output error-output crash-logs)
            (%crash-cause-run-script source)
          (expect 0 :to-equal crash-logs)
          (expect expected-status :to-equal status)
          (expect "" :to-equal output)
          (expect (search expected-diagnostic error-output) :to-be-truthy)
          (expect (search "crash log" error-output) :to-be-null)))))

  (it "a-function-form-in-a-value-is-lisp-without-a-crash-log"
    ;; Probe sort-in-value: with the function builtin gone (P2-6), (function <)
    ;; is the CL special form, so the sorted list reaches ECHO as an argument.
    (multiple-value-bind (status output error-output crash-logs)
        (%crash-cause-run-script "(echo ,(sort (list 3 1 2) (function <)))
")
      (expect 0 :to-equal crash-logs)
      (expect 1 :to-equal status)
      (expect (search "Command argument (1 2 3) is not a string" output) :to-be-truthy)
      (expect (search "crash log" error-output) :to-be-null)))

  (it "a-non-scalar-command-argument-is-e-arg-type-without-a-crash-log"
    ;; Probe defun-sym-args: ,(+ 1 1) reaches ECHO as an unevaluated comma
    ;; object, which is neither a scalar nor a list.
    (multiple-value-bind (status output error-output crash-logs)
        (%crash-cause-run-script
         "(defun g2 (a) (echo got=$a))
(g2 sym)
(g2 \"str\")
(g2 ,(+ 1 1))
")
      (expect 0 :to-equal crash-logs)
      (expect 1 :to-equal status)
      (expect (search (format nil "got=~%got=str~%") output) :to-equal 0)
      (expect (search "is not a string, number, character, or non-nil symbol"
                      output)
              :to-be-truthy)
      (expect (search "crash log" error-output) :to-be-null)))

  (it "a-function-object-as-a-command-argument-is-e-arg-type-without-a-crash-log"
    ;; Probe time-head: with no time program on PATH, (time …) is the CL macro,
    ;; whose expansion passes a function object to a head resolved as a command.
    (host-kit:with-temporary-directory (empty-bin)
      (multiple-value-bind (status output error-output crash-logs)
          (%crash-cause-run-script (format nil "(time (+ 1 2))~%")
                                   :path-directory empty-bin)
        (expect 0 :to-equal crash-logs)
        (expect 1 :to-equal status)
        (expect (search "#<FUNCTION" output) :to-be-truthy)
        (expect (search "crash log" error-output) :to-be-null))))

  (it "argv-scalar-string-rejects-every-non-scalar-value-with-e-arg-type"
    (dolist (value (list (function car) (vector 1 2) (make-hash-table)
                         (make-condition 'simple-error)))
      (let ((caught nil))
        (handler-case (nshell.application:argv-scalar-string
                       value :source-span '(1 4))
          (nshell.application:command-argument-type-error (condition)
            (setf caught condition)))
        (expect caught :to-be-truthy)
        (expect "E_ARG_TYPE" :to-equal
                (nshell.domain.error-codes:condition-error-code caught))
        (expect value :to-be
                (nshell.application:command-argument-type-error-value caught))
        (expect '(1 4) :to-equal
                (nshell.application:command-argument-type-error-source-span
                 caught)))))

  (it "pipefail-set-earlier-on-the-same-line-sets-the-pipeline-status"
    (multiple-value-bind (status error-output crash-logs)
        (%crash-cause-run-batch "set -o pipefail; sh -c 'exit 7' | cat")
      (expect 0 :to-equal crash-logs)
      (expect 7 :to-equal status)
      (expect (search "Inconsistent command status" error-output) :to-be-null))
    ;; The opposite direction: pipefail is on when the line starts and is
    ;; turned off before the pipeline runs.
    (multiple-value-bind (status output error-output crash-logs)
        (%crash-cause-run-script
         (format nil "set -o pipefail~%set +o pipefail; sh -c 'exit 7' | cat~%"))
      (expect 0 :to-equal crash-logs)
      (expect 0 :to-equal status)
      (expect "" :to-equal output)
      (expect (search "Inconsistent command status" error-output) :to-be-null)
      (expect (search "Inconsistent command status" output) :to-be-null)))

  (it "an-incomplete-autoloaded-function-file-is-located-in-that-file"
    ;; The script has one line; the location must come from the function
    ;; file's own text. Its lines are joined without the final newline, so
    ;; the end of the input is the end of line 2, column 12.
    (host-kit:with-temporary-directory (config-home)
      (let ((function-file
              (merge-pathnames "nshell/functions/bug1_incomplete_fn.nsh"
                               (uiop:ensure-directory-pathname config-home))))
        (ensure-directories-exist function-file)
        (with-open-file (stream function-file :direction :output)
          (format stream "(defun bug1_incomplete_fn ()~%  (echo hi)~%"))
        (multiple-value-bind (status output error-output crash-logs)
            (%crash-cause-run-script (format nil "(bug1_incomplete_fn)~%")
                                     :config-home config-home)
          (expect 0 :to-equal crash-logs)
          (expect 1 :to-equal status)
          (expect "" :to-equal output)
          (expect (search (format nil "~a:2:12: syntax error [41,41): Incomplete form at the end of the input."
                                  (namestring function-file))
                          error-output)
                  :to-be-truthy)
          (expect (search "crash log" error-output) :to-be-null)))))

  (it "a-reader-error-in-batch-mode-reports-its-message-and-location"
    (dolist (case '(("(echo hi" "<input>: syntax error [8,8): Expected a datum.")
                    ("(echo hi > ,(concatenate (quote string) \"o\" \"3.txt\"))"
                     "<input>: syntax error [12,13): Invalid syntax in this form.")))
      (destructuring-bind (line expected) case
        (multiple-value-bind (status error-output crash-logs)
            (%crash-cause-run-batch line)
          (expect 0 :to-equal crash-logs)
          (expect 1 :to-equal status)
          (expect (search (format nil "nshell error: ~a" expected) error-output)
                  :to-be-truthy)
          (expect (search "was signalled" error-output) :to-be-null))))))
