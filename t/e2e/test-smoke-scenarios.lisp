(in-package #:nshell/test)

;;; Entry-point tests ported from the batch and script scenarios of
;;; t/scenarios/ (docs/design/tasks/P1-7c-scenario-corpus.md).  Each test runs
;;; the public MAIN in a fresh SBCL child through the same entry point as its
;;; scenario: argv (-c / -l -c), --command TEXT, stdin, or a script file.  The
;;; scenario ID is part of every test name.

(defun %scenario-environment (home &rest overrides)
  "Return the E2E child environment of a scenario: HOME, PATH=/usr/bin:/bin,
TERM=dumb, and OVERRIDES (NAME=VALUE strings) replacing same-named entries."
  (let* ((entries (append (list (format nil "HOME=~A" (namestring home))
                                "PATH=/usr/bin:/bin"
                                "TERM=dumb")
                          overrides))
         (names (mapcar (lambda (entry) (subseq entry 0 (position #\= entry)))
                        entries)))
    (append (remove-if (lambda (entry)
                         (let ((separator (position #\= entry)))
                           (and separator
                                (member (subseq entry 0 separator) names
                                        :test #'string=))))
                       (%e2e-child-environment))
            (remove-duplicates entries
                               :test #'string=
                               :key (lambda (entry)
                                      (subseq entry 0 (position #\= entry)))
                               :from-end nil))))

(defun %make-scenario-root ()
  (let ((state (make-random-state t)))
    (loop
      (let ((root (merge-pathnames
                   (format nil "nshell-scenario-~36R/"
                           (random most-positive-fixnum state))
                   (host-kit:temporary-directory))))
        (when (nth-value 1 (ensure-directories-exist root))
          (return root))))))

;; Not host-kit:with-temporary-directory: it wraps every condition raised in
;; its body in a host-kit error, which turns a failed EXPECT into an errored
;; test and keeps IT-FAILS from recognising the expected failure.
(defmacro with-scenario-directories ((root home work) &body body)
  "Bind ROOT to a fresh temporary directory holding the scenario's home/ and
work/ directories, bound to HOME and WORK, and delete it afterwards."
  `(let* ((,root (%make-scenario-root))
          (,home (merge-pathnames "home/" ,root))
          (,work (merge-pathnames "work/" ,root)))
     (unwind-protect
          (progn
            (ensure-directories-exist ,home)
            (ensure-directories-exist ,work)
            ,@body)
       (ignore-errors (host-kit:delete-directory-tree ,root :validate t)))))

(defun %scenario-text (&rest lines)
  "Join LINES with newlines.  End with \"\" to get a final newline."
  (format nil "~{~A~^~%~}" lines))

(defun %write-scenario-file (path content)
  (ensure-directories-exist path)
  (with-open-file (out path :direction :output :if-exists :supersede
                            :if-does-not-exist :create)
    (write-string content out))
  path)

(defun %run-scenario-script (work text &key environment arguments)
  "Write TEXT to WORK/scenario.nsh and run it as a script from WORK."
  (let ((path (%write-scenario-file (merge-pathnames "scenario.nsh" work) text)))
    (%run-nshell-main (cons (namestring path) arguments)
                      :directory work
                      :environment environment)))

(defun %read-file-octets (path)
  (with-open-file (in path :element-type '(unsigned-byte 8))
    (let ((octets (make-array (file-length in) :element-type '(unsigned-byte 8))))
      (read-sequence octets in)
      octets)))

(defun %run-nshell-main-to-files (arguments stdout-path stderr-path
                                  &key environment directory)
  "Run MAIN like %RUN-NSHELL-MAIN, but send stdout and stderr to files so the
exact bytes can be compared.  Return the exit code."
  (let* ((root (asdf:system-source-directory :nshell))
         (program (append (list (current-sbcl-executable) "--noinform")
                          (%asdf-bootstrap-forms (namestring root))
                          (list "--eval" (%nshell-main-form arguments)))))
    (sb-ext:process-exit-code
     (sb-ext:run-program (first program) (rest program)
                         :input nil
                         :output (namestring stdout-path)
                         :if-output-exists :supersede
                         :error (namestring stderr-path)
                         :if-error-exists :supersede
                         :directory (namestring (or directory root))
                         :environment environment
                         :wait t))))

(defun %c17-large-block ()
  "The 10000 lines of \"C17_LARGE\" that yes | head -n 10000 writes."
  (let* ((line (map '(vector (unsigned-byte 8)) #'char-code
                    (format nil "C17_LARGE~%")))
         (block (make-array (* 10000 (length line))
                            :element-type '(unsigned-byte 8))))
    (dotimes (i 10000 block)
      (replace block line :start1 (* i (length line))))))

(defparameter +c17-binary-tail+
  (coerce '(0 67 49 55 95 66 73 78 65 82 89 255) '(vector (unsigned-byte 8)))
  "NUL, \"C17_BINARY\" and 0xFF, as printf '\\000C17_BINARY\\377' writes them.")

(defun %stdout-lines (stdout)
  (with-input-from-string (in stdout)
    (loop for line = (read-line in nil)
          while line collect line)))

(describe "e2e-scenario-ports"
  ;; -l -c and -c delegate to /bin/sh (A03, A06, A07, B06, B09).
  (it "e2e-scenario-A03-login-shell-command"
    "-l -c COMMAND is delegated to /bin/sh and prints only the command's stdout."
    (with-scenario-directories (root home work)
      (multiple-value-bind (stdout stderr exit-code)
          (%run-nshell-main (list "-l" "-c" "printf 'A03_LOGIN_OK\\n'")
                            :directory work
                            :environment (%scenario-environment home))
        (expect (format nil "A03_LOGIN_OK~%") :to-equal stdout)
        (expect "" :to-equal stderr)
        (expect 0 :to-equal exit-code))))

  (it "e2e-scenario-A06-login-environment"
    "-l -c passes the caller's USER, SHELL and SHLVL to /bin/sh unchanged."
    ;; /bin/sh, not nshell, raises SHLVL: bash makes 40 into 41, dash keeps 40.
    ;; The scenario's fixed 41 is replaced by what this host's /bin/sh prints
    ;; when it is started directly with the same environment.
    (with-scenario-directories (root home work)
      (let* ((environment (%scenario-environment home
                                                 "USER=r04-user"
                                                 "SHELL=/r04-login-shell"
                                                 "SHLVL=40"))
             (shlvl (host-kit:process-result-stdout
                     (host-kit:run-program "/bin/sh"
                                           (list "-c" "printf '%s' \"$SHLVL\"")
                                           :environment environment
                                           :timeout 30)))
             (command
               (format nil "if [ \"$SHLVL\" -eq ~A ] && [ \"$USER\" = \"r04-user\" ] && [ \"$SHELL\" = \"/r04-login-shell\" ]; then printf 'A06_OK|%s|%s|%s\\n' \"$USER\" \"$SHELL\" \"$SHLVL\"; else exit 91; fi"
                       shlvl)))
        (expect (member shlvl '("40" "41") :test #'string=) :to-be-truthy)
        (multiple-value-bind (stdout stderr exit-code)
            (%run-nshell-main (list "--no-config" "-l" "-c" command)
                              :directory work
                              :environment environment)
          (expect (format nil "A06_OK|r04-user|/r04-login-shell|~A~%" shlvl)
                  :to-equal stdout)
          (expect "" :to-equal stderr)
          (expect 0 :to-equal exit-code)))))

  (it "e2e-scenario-A07-quiet-login-command"
    "-l -c true prints nothing and exits 0."
    (with-scenario-directories (root home work)
      (multiple-value-bind (stdout stderr exit-code)
          (%run-nshell-main (list "-l" "-c" "true")
                            :directory work
                            :environment (%scenario-environment home))
        (expect "" :to-equal stdout)
        (expect "" :to-equal stderr)
        (expect 0 :to-equal exit-code))))

  (it "e2e-scenario-B06-approx-shell-c-command-contract"
    "-c keeps /bin/sh's stdout and stderr separate for the caller."
    (with-scenario-directories (root home work)
      (multiple-value-bind (stdout stderr exit-code)
          (%run-nshell-main
           (list "-c" "printf \"B06_SHELL_C\\n\"; printf \"B06_STDERR\\n\" >&2")
           :directory work
           :environment (%scenario-environment home))
        (expect (format nil "B06_SHELL_C~%") :to-equal stdout)
        (expect (format nil "B06_STDERR~%") :to-equal stderr)
        (expect 0 :to-equal exit-code))))

  (it "e2e-scenario-B09-command-stdio-and-status"
    "-c returns /bin/sh's stdout, stderr and exit status 23 unchanged."
    (with-scenario-directories (root home work)
      (multiple-value-bind (stdout stderr exit-code)
          (%run-nshell-main
           (list "-c"
                 "printf \"B09_STDOUT\\n\"; printf \"B09_STDERR\\n\" >&2; exit 23")
           :directory work
           :environment (%scenario-environment home))
        (expect (format nil "B09_STDOUT~%") :to-equal stdout)
        (expect (format nil "B09_STDERR~%") :to-equal stderr)
        (expect 23 :to-equal exit-code))))

  (it "e2e-scenario-B09-empty-shell-command"
    "-c \"\" accepts trailing arguments, including -- and -leading, and prints nothing."
    (with-scenario-directories (root home work)
      (multiple-value-bind (stdout stderr exit-code)
          (%run-nshell-main (list "-c" "" "r04-zero" "--" "-leading")
                            :directory work
                            :environment (%scenario-environment home))
        (expect "" :to-equal stdout)
        (expect "" :to-equal stderr)
        (expect 0 :to-equal exit-code))))

  (it "e2e-scenario-B09-shell-command-argv"
    "-c passes $0 and later arguments verbatim and forwards stdin to /bin/sh."
    (with-scenario-directories (root home work)
      (multiple-value-bind (stdout stderr exit-code)
          (%run-nshell-main
           (list "-c"
                 "printf '%s\\n' \"$0\" \"$1\" \"$2\" \"$3\" \"$4\" \"$5\"; while IFS= read -r line; do printf '%s\\n' \"$line\"; done"
                 "r04-zero" "space arg" "single' quote"
                 (format nil "line one~%line two") "--" "-leading")
           :input (format nil "R04_STDIN_OK~%")
           :directory work
           :environment (%scenario-environment home))
        (expect (%scenario-text "r04-zero" "space arg" "single' quote"
                                "line one" "line two" "--" "-leading"
                                "R04_STDIN_OK" "")
                :to-equal stdout)
        (expect "" :to-equal stderr)
        (expect 0 :to-equal exit-code))))

  ;; --command TEXT.
  (it "e2e-scenario-A10-exec-replaces-shell"
    "exec in --command replaces the shell and leaves only the new program's output."
    (with-scenario-directories (root home work)
      (multiple-value-bind (stdout stderr exit-code)
          (%run-nshell-main (list "--command" "exec echo A10_EXEC_REPLACED")
                            :directory work
                            :environment (%scenario-environment home))
        (expect (format nil "A10_EXEC_REPLACED~%") :to-equal stdout)
        (expect "" :to-equal stderr)
        (expect 0 :to-equal exit-code))))

  (it "e2e-scenario-B09-batch-command-uses-nshell-builtins"
    "--command runs nshell's string upper builtin, not /bin/sh."
    (with-scenario-directories (root home work)
      (multiple-value-bind (stdout stderr exit-code)
          (%run-nshell-main (list "--command" "string upper r04_nshell_builtin_guard")
                            :directory work
                            :environment (%scenario-environment home))
        (expect (format nil "R04_NSHELL_BUILTIN_GUARD~%") :to-equal stdout)
        (expect "" :to-equal stderr)
        (expect 0 :to-equal exit-code))))

  (it "e2e-scenario-C01-batch-command"
    "--command writes a builtin's redirected output to a file and prints only the next command."
    (with-scenario-directories (root home work)
      (multiple-value-bind (stdout stderr exit-code)
          (%run-nshell-main
           (list "--command"
                 "echo SCENARIO_BATCH_OK > result.txt; echo SCENARIO_BATCH_COMMAND_OK")
           :directory work
           :environment (%scenario-environment home))
        (expect (%stdout-lines stdout) :to-equal '("SCENARIO_BATCH_COMMAND_OK"))
        (expect (search "SCENARIO_BATCH_OK" stdout) :to-be-falsy)
        (expect "" :to-equal stderr)
        (expect 0 :to-equal exit-code)
        (let ((result (merge-pathnames "result.txt" work)))
          (expect (probe-file result) :to-be-truthy)
          (expect (search "SCENARIO_BATCH_OK" (host-kit:read-file-string result))
                  :to-be-truthy)))))

  (it "e2e-scenario-C03-path-search-and-absolute-path"
    "--command finds a command in a relative PATH entry and runs one by absolute path."
    (with-scenario-directories (root home work)
      (%write-scenario-file (merge-pathnames "bin/scenario-tool" work)
                            (%scenario-text "#!/bin/sh"
                                            "printf \"C03_PATH_FOUND\\n\"" ""))
      (%write-scenario-file (merge-pathnames "bin/absolute-tool" work)
                            (%scenario-text "#!/bin/sh"
                                            "printf \"C03_ABSOLUTE\\n\"" ""))
      (multiple-value-bind (stdout stderr exit-code)
          (%run-nshell-main
           (list "--command"
                 "chmod +x bin/scenario-tool bin/absolute-tool; scenario-tool; \"$HOME/../work/bin/absolute-tool\"")
           :directory work
           :environment (%scenario-environment home "PATH=bin:/usr/bin:/bin"))
        (expect (search "C03_PATH_FOUND" stdout) :to-be-truthy)
        (expect (search "C03_ABSOLUTE" stdout) :to-be-truthy)
        (expect "" :to-equal stderr)
        (expect 0 :to-equal exit-code))))

  (it "e2e-scenario-C04-missing-command-suggestion-and-status"
    "--command reports a missing command with a suggestion and exits 127."
    (with-scenario-directories (root home work)
      (multiple-value-bind (stdout stderr exit-code)
          (%run-nshell-main (list "--command" "echp C04")
                            :directory work
                            :environment (%scenario-environment home))
        (expect "" :to-equal stdout)
        (expect (search "command not found" stderr) :to-be-truthy)
        (expect (search "echo" stderr) :to-be-truthy)
        (expect 127 :to-equal exit-code))))

  (it "e2e-scenario-C05-last-exit-status-is-visible"
    "$? after false is 1 in a --command sequence."
    (with-scenario-directories (root home work)
      (multiple-value-bind (stdout stderr exit-code)
          (%run-nshell-main (list "--command" "false; printf \"C05_STATUS:%s\\n\" \"$?\"")
                            :directory work
                            :environment (%scenario-environment home))
        (declare (ignore stderr))
        (expect (search "C05_STATUS:1" stdout) :to-be-truthy)
        (expect 0 :to-equal exit-code))))

  (it "e2e-scenario-C06-pipeline-streams-all-stages"
    "A three-stage external bare-line pipeline delivers its output to stdout."
    (with-scenario-directories (root home work)
      (multiple-value-bind (stdout stderr exit-code)
          (%run-nshell-main (list "--command" "printf \"C06_PIPELINE\\n\" | cat | cat")
                            :directory work
                            :environment (%scenario-environment home))
        (expect (format nil "C06_PIPELINE~%") :to-equal stdout)
        (expect "" :to-equal stderr)
        (expect 0 :to-equal exit-code))))

  (it "e2e-scenario-C11-temporary-command-environment"
    "VAR=value cmd exports VAR to that command only."
    (with-scenario-directories (root home work)
      (multiple-value-bind (stdout stderr exit-code)
          (%run-nshell-main
           (list "--command"
                 "C11_VALUE=inside env; printf \"C11_AFTER:%s\\n\" \"$C11_VALUE\"")
           :directory work
           :environment (%scenario-environment home))
        (declare (ignore stderr))
        (expect (search "C11_VALUE=inside" stdout) :to-be-truthy)
        (expect (search "C11_AFTER:" stdout) :to-be-truthy)
        (expect (search "C11_AFTER:inside" stdout) :to-be-falsy)
        (expect 0 :to-equal exit-code))))

  (it "e2e-scenario-C14-tilde-expansion"
    "A bare-line ~/ argument of an external command expands to HOME."
    (with-scenario-directories (root home work)
      (%write-scenario-file (merge-pathnames "home-marker.txt" home)
                            (format nil "C14_HOME_VALUE~%"))
      (multiple-value-bind (stdout stderr exit-code)
          (%run-nshell-main (list "--command" "cat ~/home-marker.txt")
                            :directory work
                            :environment (%scenario-environment home))
        (expect (format nil "C14_HOME_VALUE~%") :to-equal stdout)
        (expect "" :to-equal stderr)
        (expect 0 :to-equal exit-code))))

  (it "e2e-scenario-C17-large-and-binary-output-reach-stdout"
    "--command passes 10000 lines of external output and printf's NUL-prefixed output to stdout."
    (with-scenario-directories (root home work)
      (let ((stdout-path (merge-pathnames "stdout.bin" root))
            (stderr-path (merge-pathnames "stderr.bin" root)))
        (let ((exit-code
                (%run-nshell-main-to-files
                 (list "--command"
                       "yes C17_LARGE | head -n 10000; printf '\\000C17_BINARY\\377'")
                 stdout-path stderr-path
                 :directory work
                 :environment (%scenario-environment home)))
              (stdout (%read-file-octets stdout-path)))
          (expect 0 :to-equal exit-code)
          (expect 0 :to-equal (length (%read-file-octets stderr-path)))
          (expect (search (%c17-large-block) stdout) :to-be-truthy)
          (expect (search (subseq +c17-binary-tail+ 0 11) stdout) :to-be-truthy)))))

  ;; The scenario only checked that C17_LARGE and C17_BINARY appear.  The exact
  ;; bytes differ today: the printf builtin's output comes before the pipeline's
  ;; output, and \377 is written as the three characters "377" instead of 0xFF.
  (it-fails "e2e-scenario-C17-binary-output-bytes-are-exact"
    "--command writes the pipeline output, then NUL, C17_BINARY and 0xFF, byte for byte."
    (with-scenario-directories (root home work)
      (let ((stdout-path (merge-pathnames "stdout.bin" root))
            (stderr-path (merge-pathnames "stderr.bin" root)))
        (let ((exit-code
                (%run-nshell-main-to-files
                 (list "--command"
                       "yes C17_LARGE | head -n 10000; printf '\\000C17_BINARY\\377'")
                 stdout-path stderr-path
                 :directory work
                 :environment (%scenario-environment home)))
              (stdout (%read-file-octets stdout-path)))
          (expect 0 :to-equal exit-code)
          (expect 100012 :to-equal (length stdout))
          (expect (equalp (%c17-large-block) (subseq stdout 0 (min 100000 (length stdout))))
                  :to-be-truthy)
          (expect (equalp +c17-binary-tail+
                          (subseq stdout (max 0 (- (length stdout) 12))))
                  :to-be-truthy)))))

  (it "e2e-scenario-L07-theme-can-be-selected"
    "theme use nshell followed by theme show prints the theme name and its roles."
    (with-scenario-directories (root home work)
      (multiple-value-bind (stdout stderr exit-code)
          (%run-nshell-main (list "--command" "theme use nshell; theme show")
                            :directory work
                            :environment (%scenario-environment home "TERM=xterm-256color"))
        (expect (search "nshell" stdout) :to-be-truthy)
        (expect (search "prompt-path" stdout) :to-be-truthy)
        (expect "" :to-equal stderr)
        (expect 0 :to-equal exit-code))))

  (it "e2e-scenario-M01-cd-dash"
    "cd - returns to the previous directory, where a later external command runs."
    (with-scenario-directories (root home work)
      (multiple-value-bind (stdout stderr exit-code)
          (%run-nshell-main
           (list "--command"
                 "mkdir first second; cd first; cd ../second; cd -; touch returned.txt")
           :directory work
           :environment (%scenario-environment home "TERM=xterm-256color"))
        (declare (ignore stdout stderr))
        (expect 0 :to-equal exit-code)
        (expect (probe-file (merge-pathnames "first/returned.txt" work)) :to-be-truthy)
        (expect (probe-file (merge-pathnames "second/returned.txt" work)) :to-be-falsy))))

  (it "e2e-scenario-M02-logical-pwd-and-pwd-variable"
    "cd through a symlink and .. resolves logically; $PWD and pwd have no trailing slash."
    (with-scenario-directories (root home work)
      (%write-scenario-file (merge-pathnames "other/marker.txt" root) "outside")
      (multiple-value-bind (stdout stderr exit-code)
          (%run-nshell-main
           (list "--command"
                 "ln -s ../other logical-link; cd logical-link/..; printf '<%s>\\n' \"$PWD\" > logical.txt; pwd >> logical.txt")
           :directory work
           :environment (%scenario-environment home "TERM=xterm-256color"))
        (declare (ignore stdout stderr))
        (expect 0 :to-equal exit-code)
        (let ((logical (merge-pathnames "logical.txt" work)))
          (expect (probe-file logical) :to-be-truthy)
          (let ((content (host-kit:read-file-string logical)))
            (expect (search "work" content) :to-be-truthy)
            (expect (search "work/>" content) :to-be-falsy))))))

  (it "e2e-scenario-M05-pushd-popd-stack-round-trip"
    "pushd twice and popd once with relative paths leave the shell in a."
    (with-scenario-directories (root home work)
      (multiple-value-bind (stdout stderr exit-code)
          (%run-nshell-main
           (list "--command" "mkdir a b; pushd a; pushd ../b; popd; pwd > ../stack.txt")
           :directory work
           :environment (%scenario-environment home "TERM=xterm-256color"))
        (declare (ignore stdout stderr))
        (expect 0 :to-equal exit-code)
        (let ((stack (merge-pathnames "stack.txt" work)))
          (expect (probe-file stack) :to-be-truthy)
          (let ((content (string-right-trim '(#\Newline)
                                            (host-kit:read-file-string stack))))
            (expect (search "a" content) :to-be-truthy)
            (expect (and (>= (length content) 2)
                         (string= "/a" (subseq content (- (length content) 2))))
                    :to-be-truthy))))))

  (it "e2e-scenario-N01-session-variable"
    "A top-level bare-line set defines a variable that $NAME reads in the same --command."
    (with-scenario-directories (root home work)
      (%assert-nshell-main-result
       (list "--no-config" "--command"
             "set SCENARIO_SESSION_VALUE hello; echo $SCENARIO_SESSION_VALUE")
       "hello"
       0
       :directory work
       :environment (%scenario-environment home "TERM=xterm-256color"))))

  (it "e2e-scenario-N02-export-reaches-child-process"
    "export NAME=value puts the variable in a child process's environment."
    (with-scenario-directories (root home work)
      (multiple-value-bind (stdout stderr exit-code)
          (%run-nshell-main (list "--command" "export SCENARIO_EXPORTED_VALUE=exported; env")
                            :directory work
                            :environment (%scenario-environment home "TERM=xterm-256color"))
        (declare (ignore stderr))
        (expect (search "SCENARIO_EXPORTED_VALUE=exported" stdout) :to-be-truthy)
        (expect 0 :to-equal exit-code))))

  (it "e2e-scenario-N03-colon-separated-path-list"
    "set -x PATH a $PATH exports the list joined with colons."
    (with-scenario-directories (root home work)
      (multiple-value-bind (stdout stderr exit-code)
          (%run-nshell-main (list "--command" "set -x PATH a $PATH; env")
                            :directory work
                            :environment (%scenario-environment home "TERM=xterm-256color"))
        (declare (ignore stderr))
        (expect (search "PATH=a:" stdout) :to-be-truthy)
        (expect (search ":/usr/bin:/bin" stdout) :to-be-truthy)
        (expect 0 :to-equal exit-code))))

  (it "e2e-scenario-N04-unset-removes-variable"
    "set -q after unset sets $status to 1."
    (with-scenario-directories (root home work)
      (multiple-value-bind (stdout stderr exit-code)
          (%run-nshell-main
           (list "--command"
                 "set SCENARIO_REMOVE_VALUE present; unset SCENARIO_REMOVE_VALUE; set -q SCENARIO_REMOVE_VALUE; echo $status")
           :directory work
           :environment (%scenario-environment home "TERM=xterm-256color"))
        (expect (format nil "1~%") :to-equal stdout)
        (expect "" :to-equal stderr)
        (expect 0 :to-equal exit-code))))

  ;; stdin batch (no arguments).
  (it "e2e-scenario-C01-batch-stdin"
    "Without arguments, a non-interactive nshell runs bare-line commands from stdin."
    (with-scenario-directories (root home work)
      (%assert-nshell-main-result nil "SCENARIO_STDIN_OK" 0
                                  :input (format nil "echo SCENARIO_STDIN_OK~%")
                                  :directory work
                                  :environment (%scenario-environment home))))

  ;; Script files.
  (it "e2e-scenario-C07-redirection-family"
    "A script applies > >> < 3>&1 >| &> 2> >&2 2>&1 and |& to builtins and externals."
    (with-scenario-directories (root home work)
      (multiple-value-bind (stdout stderr exit-code)
          (%run-scenario-script
           work
           "printf 'C07_OVERWRITE\\n' > redirected.txt; printf 'C07_APPEND\\n' >> redirected.txt; cat < redirected.txt; printf 'C07_DUP\\n' 3>dup.txt 1>&3; printf 'C07_FORCE\\n' >| force.txt; printf 'C07_BOTH\\n' &> both.txt; printf 'C07_ERR\\n' 2>err.txt; printf 'C07_MERGED\\n' >&2 2>&1; /bin/sh -c 'printf \"C07_PIPE_ERR\\n\" >&2' |& cat"
           :environment (%scenario-environment home))
        (expect (search "C07_OVERWRITE" stdout) :to-be-truthy)
        (expect (search "C07_APPEND" stdout) :to-be-truthy)
        (expect (search "C07_PIPE_ERR" stdout) :to-be-truthy)
        (expect (format nil "C07_MERGED~%") :to-equal stderr)
        (expect 0 :to-equal exit-code)
        (flet ((content (name)
                 (let ((path (merge-pathnames name work)))
                   (and (probe-file path) (host-kit:read-file-string path)))))
          (expect (search "C07_OVERWRITE" (or (content "redirected.txt") "")) :to-be-truthy)
          (expect (search "C07_APPEND" (or (content "redirected.txt") "")) :to-be-truthy)
          (expect (search "C07_DUP" (or (content "dup.txt") "")) :to-be-truthy)
          (expect (search "C07_FORCE" (or (content "force.txt") "")) :to-be-truthy)
          (expect (search "C07_BOTH" (or (content "both.txt") "")) :to-be-truthy)
          (expect (probe-file (merge-pathnames "err.txt" work)) :to-be-truthy)))))

  ;; v0.7 behaviour: L5 5.3 makes a bare-line here-document E_UNSUPPORTED_SYNTAX
  ;; in v0.8 (L7 bare-heredoc row, S3).  Rewrite this test when P2-4 rejects it.
  (it "e2e-scenario-C08-here-doc-and-here-string"
    "A script feeds a quoted-delimiter here-document and a here-string to cat."
    (with-scenario-directories (root home work)
      (multiple-value-bind (stdout stderr exit-code)
          (%run-scenario-script
           work
           (%scenario-text "cat <<'C08_END'" "C08_HEREDOC" "C08_END"
                           "cat <<< C08_HERESTRING")
           :environment (%scenario-environment home))
        (declare (ignore stderr))
        (expect (search "C08_HEREDOC" stdout) :to-be-truthy)
        (expect (search "C08_HERESTRING" stdout) :to-be-truthy)
        (expect 0 :to-equal exit-code))))

  (it "e2e-scenario-C09-background-command-returns"
    "A script line with sleep &; wait; printf runs the command after wait."
    (with-scenario-directories (root home work)
      (multiple-value-bind (stdout stderr exit-code)
          (%run-scenario-script
           work "sleep 0.1 &; wait; printf \"C09_BACKGROUND_DONE\\n\""
           :environment (%scenario-environment home))
        (declare (ignore stderr))
        (expect (search "C09_BACKGROUND_DONE" stdout) :to-be-truthy)
        (expect 0 :to-equal exit-code))))

  (it "e2e-scenario-C10-short-circuit-followed-by-sequence"
    "After false && echo a, the command after ; still runs."
    (with-scenario-directories (root home work)
      (multiple-value-bind (stdout stderr exit-code)
          (%run-scenario-script work "false && echo a; echo next"
                                :environment (%scenario-environment home))
        (declare (ignore stderr))
        (expect (member "next" (%stdout-lines stdout) :test #'string=) :to-be-truthy)
        (expect (member "a" (%stdout-lines stdout) :test #'string=) :to-be-falsy)
        (expect 0 :to-equal exit-code))))

  (it "e2e-scenario-C16-approx-process-substitution-input"
    "A script's cat reads the output of <(printf ...)."
    (with-scenario-directories (root home work)
      (multiple-value-bind (stdout stderr exit-code)
          (%run-scenario-script work "cat <(printf 'C16_PROCESS_VALUE')"
                                :environment (%scenario-environment home))
        (declare (ignore stderr))
        (expect "C16_PROCESS_VALUE" :to-equal stdout)
        (expect 0 :to-equal exit-code))))

  (it "e2e-scenario-K06-sexp-and-command-island-evaluation"
    "A script's progn runs the echo command island and prints the last value 42."
    (with-scenario-directories (root home work)
      (multiple-value-bind (stdout stderr exit-code)
          (%run-scenario-script
           work "(progn (echo K06_COMMAND_ISLAND) (+ 20 22))"
           :environment (%scenario-environment home "TERM=xterm-256color"))
        (declare (ignore stderr))
        (expect (search "K06_COMMAND_ISLAND" stdout) :to-be-truthy)
        (expect (search "42" stdout) :to-be-truthy)
        (expect 0 :to-equal exit-code))))

  (it "e2e-scenario-K07-one-line-source-diagnostic"
    "A script syntax error names the script file and runs nothing after it."
    (with-scenario-directories (root home work)
      (multiple-value-bind (stdout stderr exit-code)
          (%run-scenario-script work (%scenario-text "(" "echo K07_AFTER_ERROR")
                                :environment (%scenario-environment
                                              home "TERM=xterm-256color"))
        (declare (ignore exit-code))
        (expect (search "scenario.nsh:" stderr) :to-be-truthy)
        (expect (search "syntax error" stderr) :to-be-truthy)
        (expect (search "K07_AFTER_ERROR" stdout) :to-be-falsy))))

  ;; L6 6.1 and 6.5: a syntax error exits 2 (E_PARSE).  v0.7 exits 1.
  (it-fails "e2e-scenario-K07-syntax-error-exits-2"
    "A script syntax error exits with E_PARSE's status 2."
    (with-scenario-directories (root home work)
      (multiple-value-bind (stdout stderr exit-code)
          (%run-scenario-script work (%scenario-text "(" "echo K07_AFTER_ERROR")
                                :environment (%scenario-environment
                                              home "TERM=xterm-256color"))
        (declare (ignore stdout stderr))
        (expect 2 :to-equal exit-code))))

  (it "e2e-scenario-K08-macro-expansion-error-location"
    "A macro expansion error is reported at the call site scenario.nsh:2:1."
    (with-scenario-directories (root home work)
      (multiple-value-bind (stdout stderr exit-code)
          (%run-scenario-script
           work (%scenario-text "(defmacro bad-form () (error \"K08_EXPANSION_ERROR\"))"
                                "(bad-form)")
           :environment (%scenario-environment home "TERM=xterm-256color"))
        (declare (ignore stdout exit-code))
        (expect (search "scenario.nsh:2:1" stderr) :to-be-truthy)
        (expect (search "K08_EXPANSION_ERROR" stderr) :to-be-truthy))))

  ;; P1-7c 補足 treats this as a syntax error, which L6 6.5 maps to 2.  v0.7
  ;; reports it as a syntax error and exits 1.
  (it-fails "e2e-scenario-K08-macro-expansion-error-exits-2"
    "A script stopped by a macro expansion error exits 2."
    (with-scenario-directories (root home work)
      (multiple-value-bind (stdout stderr exit-code)
          (%run-scenario-script
           work (%scenario-text "(defmacro bad-form () (error \"K08_EXPANSION_ERROR\"))"
                                "(bad-form)")
           :environment (%scenario-environment home "TERM=xterm-256color"))
        (declare (ignore stdout stderr))
        (expect 2 :to-equal exit-code))))

  (it "e2e-scenario-N05-approx-lexical-let-scope"
    "A let inside a defun shadows a shell variable for $ references only inside it."
    (with-scenario-directories (root home work)
      (multiple-value-bind (stdout stderr exit-code)
          (%run-scenario-script
           work (%scenario-text
                 "(set lexical_scope \"outer\")"
                 "(defun scope_probe () (let ((lexical_scope \"inner\")) (echo $lexical_scope)))"
                 "(scope_probe)"
                 "(echo $lexical_scope)"
                 "")
           :environment (%scenario-environment home "TERM=xterm-256color"))
        (declare (ignore stderr))
        (let ((inner (search "inner" stdout))
              (outer (search "outer" stdout :from-end t)))
          (expect inner :to-be-truthy)
          (expect outer :to-be-truthy)
          (expect (and inner outer (< inner outer)) :to-be-truthy))
        (expect 0 :to-equal exit-code))))

  (it "e2e-scenario-N07-status-and-pipeline-status"
    "After false | true, $status is 0 and $pipestatus is 1 0."
    (with-scenario-directories (root home work)
      (multiple-value-bind (stdout stderr exit-code)
          (%run-scenario-script
           work "false | true && printf \"<%s,%s>\\n\" $status $pipestatus"
           :environment (%scenario-environment home "TERM=xterm-256color"))
        (declare (ignore stderr))
        (expect (format nil "<0,1 0>~%") :to-equal stdout)
        (expect 0 :to-equal exit-code))))

  (it "e2e-scenario-O02-command-island-evaluation"
    "$var and ,(expr) inside a command form become arguments."
    (with-scenario-directories (root home work)
      (%assert-nshell-main-result
       (list (namestring
              (%write-scenario-file (merge-pathnames "scenario.nsh" work)
                                    (%scenario-text "(set o02_value \"preserved\")"
                                                    "(echo $o02_value ,(+ 2 3))"
                                                    ""))))
       '("preserved" "5")
       0
       :directory work
       :environment (%scenario-environment home))))

  (it "e2e-scenario-O03-let-and-set"
    "A let-bound string is visible through $, and a top-level set survives the let."
    (with-scenario-directories (root home work)
      (%assert-nshell-main-result
       (list (namestring
              (%write-scenario-file (merge-pathnames "scenario.nsh" work)
                                    (%scenario-text "(set o03_shared \"outer\")"
                                                    "(let ((o03_local \"inner\")) (echo $o03_local))"
                                                    "(echo $o03_shared)"
                                                    ""))))
       '("inner" "outer")
       0
       :directory work
       :environment (%scenario-environment home))))

  (it "e2e-scenario-O04-control-forms"
    "if, when, unless, cond, case and dotimes run commands in the right branch."
    (with-scenario-directories (root home work)
      (multiple-value-bind (stdout stderr exit-code)
          (%run-scenario-script
           work (%scenario-text
                 "(if (= 1 1) (echo O04_IF_OK) (echo O04_IF_WRONG))"
                 "(when (= 1 1) (echo O04_WHEN_OK))"
                 "(unless (= 1 2) (echo O04_UNLESS_OK))"
                 "(cond ((= 1 2) (echo O04_COND_WRONG)) ((= 2 2) (echo O04_COND_OK)))"
                 "(case 2 ((1) (echo O04_CASE_WRONG)) ((2) (echo O04_CASE_OK)))"
                 "(dotimes (o04_i 2) (echo O04_LOOP_OK))"
                 "")
           :environment (%scenario-environment home))
        (declare (ignore stderr))
        (dolist (marker '("O04_IF_OK" "O04_WHEN_OK" "O04_UNLESS_OK" "O04_COND_OK"
                          "O04_CASE_OK" "O04_LOOP_OK"))
          (expect (search marker stdout) :to-be-truthy))
        (dolist (marker '("O04_IF_WRONG" "O04_COND_WRONG" "O04_CASE_WRONG"))
          (expect (search marker stdout) :to-be-falsy))
        (expect 0 :to-equal exit-code))))

  (it "e2e-scenario-O05-nested-command-definitions"
    "Functions defined at top level and inside when are both callable as commands."
    (with-scenario-directories (root home work)
      (%assert-nshell-main-result
       (list (namestring
              (%write-scenario-file (merge-pathnames "scenario.nsh" work)
                                    (%scenario-text
                                     "(defun o05_greet (name) (echo $name))"
                                     "(o05_greet \"O05_TOPLEVEL_OK\")"
                                     "(when t (defun o05_nested (name) (echo $name)))"
                                     "(o05_nested \"O05_NESTED_OK\")"
                                     ""))))
       '("O05_TOPLEVEL_OK" "O05_NESTED_OK")
       0
       :directory work
       :environment (%scenario-environment home))))

  (it "e2e-scenario-O06-macro-expansion"
    "A defmacro that expands a command form twice runs it twice."
    (with-scenario-directories (root home work)
      (multiple-value-bind (stdout stderr exit-code)
          (%run-scenario-script
           work (%scenario-text "(defmacro o06_twice (form) `(progn ,form ,form))"
                                "(o06_twice (echo O06_MACRO_OK))"
                                "")
           :environment (%scenario-environment home))
        (declare (ignore stderr))
        (expect (count "O06_MACRO_OK" (%stdout-lines stdout) :test #'string=)
                :to-equal 2)
        (expect 0 :to-equal exit-code))))

  (it "e2e-scenario-O07-false-command-is-a-false-test"
    "(false) in a when test is false, so the body does not run."
    (with-scenario-directories (root home work)
      (multiple-value-bind (stdout stderr exit-code)
          (%run-scenario-script
           work (%scenario-text
                 "(when (false) (echo O07_FALSE_BRANCH_WRONG))"
                 "(handler-case (^o07-command-that-does-not-exist) (COMMAND-FAILED () (echo O07_HANDLER_OK)))"
                 "")
           :environment (%scenario-environment home))
        (declare (ignore stderr exit-code))
        (expect (search "O07_FALSE_BRANCH_WRONG" stdout) :to-be-falsy))))

  ;; L6 6.3: a failure at top level is not signalled as command-failed; a
  ;; missing command continues with 127, which is the script's last status
  ;; (L6 6.1).  v0.7 runs the COMMAND-FAILED clause and exits 0.
  (it-fails "e2e-scenario-O07-top-level-failure-is-not-signalled"
    "A top-level missing command does not run a COMMAND-FAILED clause and exits 127."
    (with-scenario-directories (root home work)
      (multiple-value-bind (stdout stderr exit-code)
          (%run-scenario-script
           work (%scenario-text
                 "(when (false) (echo O07_FALSE_BRANCH_WRONG))"
                 "(handler-case (^o07-command-that-does-not-exist) (COMMAND-FAILED () (echo O07_HANDLER_OK)))"
                 "")
           :environment (%scenario-environment home))
        (declare (ignore stderr))
        (expect (search "O07_FALSE_BRANCH_WRONG" stdout) :to-be-falsy)
        (expect (search "O07_HANDLER_OK" stdout) :to-be-falsy)
        (expect 127 :to-equal exit-code))))

  (it "e2e-scenario-O08-structured-pipeline"
    "A -> pipeline with where and select yields one record."
    (with-scenario-directories (root home work)
      (%assert-nshell-main-result
       (list (namestring
              (%write-scenario-file
               (merge-pathnames "scenario.nsh" work)
               (%scenario-text
                "(echo ,(length (-> '((:state \"stopped\" :id 7 :command \"demo\") (:state \"running\" :id 8 :command \"other\")) (where (= :state \"stopped\")) (select :id :command))))"
                ""))))
       "1"
       0
       :directory work
       :environment (%scenario-environment home))))

  (it "e2e-scenario-O09-json-tsv-lines-conversion"
    "JSON, TSV and line conversions round-trip in a script."
    (with-scenario-directories (root home work)
      (%assert-nshell-main-result
       (list (namestring
              (%write-scenario-file
               (merge-pathnames "scenario.nsh" work)
               (%scenario-text
                "(echo ,(to-json (from-json \"{\\\"name\\\":\\\"Ada\\\"}\")))"
                "(echo ,(to-tsv (from-tsv (concatenate (quote string) \"name\" (string #\\Tab) \"Ada\" (string #\\Newline)))))"
                "(echo ,(from-lines (to-lines (concatenate (quote string) \"first\" (string #\\Newline) \"second\" (string #\\Newline)))))"
                ""))))
       '("Ada" "name" "first" "second")
       0
       :directory work
       :environment (%scenario-environment home))))

  (it "e2e-scenario-O10-regex-and-string-library"
    "string match -r with a quoted regular expression prints the matching argument."
    (with-scenario-directories (root home work)
      (%assert-nshell-main-result
       (list (namestring
              (%write-scenario-file (merge-pathnames "scenario.nsh" work)
                                    (%scenario-text "string match -r \"^[a-z]+$\" nshell" ""))))
       "nshell"
       0
       :directory work
       :environment (%scenario-environment home))))

  (it "e2e-scenario-O11-native-arithmetic"
    ",(* 3 (+ 2 4)) becomes the command argument 18."
    (with-scenario-directories (root home work)
      (multiple-value-bind (stdout stderr exit-code)
          (%run-scenario-script work (%scenario-text "(echo ,(* 3 (+ 2 4)))" "")
                                :environment (%scenario-environment home))
        (declare (ignore stderr))
        (expect (search "18" stdout) :to-be-truthy)
        (expect 0 :to-equal exit-code))))

  (it "e2e-scenario-O12-comments"
    "Trailing and full-line ; comments are ignored and the forms around them run."
    (with-scenario-directories (root home work)
      (multiple-value-bind (stdout stderr exit-code)
          (%run-scenario-script
           work (%scenario-text "(echo O12_FORM_OK) ; trailing comment"
                                "; full-line comment"
                                "(echo O12_AFTER_COMMENT_OK)"
                                "")
           :environment (%scenario-environment home))
        (declare (ignore stderr))
        (expect (search "O12_FORM_OK" stdout) :to-be-truthy)
        (expect (search "O12_AFTER_COMMENT_OK" stdout) :to-be-truthy)
        (expect (search "trailing comment" stdout) :to-be-falsy)
        (expect (search "full-line comment" stdout) :to-be-falsy)
        (expect 0 :to-equal exit-code))))

  (it "e2e-scenario-O13-script-shebang-and-source"
    "A script with a #! line runs (source \"relative.nsh\") from its working directory."
    (with-scenario-directories (root home work)
      (%write-scenario-file (merge-pathnames "source-child.nsh" work)
                            (%scenario-text "(echo O13_SOURCE_OK)" ""))
      (multiple-value-bind (stdout stderr exit-code)
          (%run-scenario-script
           work (%scenario-text "#!/usr/bin/env nshell"
                                "(source \"source-child.nsh\")"
                                "")
           :environment (%scenario-environment home))
        (declare (ignore stderr))
        (expect (search "O13_SOURCE_OK" stdout) :to-be-truthy)
        (expect 0 :to-equal exit-code))))

  (it "e2e-scenario-O14-function-directory-autoload"
    "A non-interactive script autoloads HOME/.config/nshell/functions/NAME.nsh."
    (with-scenario-directories (root home work)
      (%write-scenario-file
       (merge-pathnames ".config/nshell/functions/o14_greet.nsh" home)
       (%scenario-text "(defun o14_greet () (echo O14_AUTOLOAD_OK))" ""))
      (let ((environment (%scenario-environment home)))
        (expect (find-if (lambda (entry) (eql 0 (search "XDG_CONFIG_HOME=" entry)))
                         environment)
                :to-be-falsy)
        (multiple-value-bind (stdout stderr exit-code)
            (%run-scenario-script work (%scenario-text "o14_greet" "")
                                  :environment environment)
          (declare (ignore stderr))
          (expect (search "O14_AUTOLOAD_OK" stdout) :to-be-truthy)
          (expect 0 :to-equal exit-code)))))

  (it "e2e-scenario-O15-asdf-library-load"
    "A script adds its directory to the ASDF registry, loads a system and calls it."
    (with-scenario-directories (root home work)
      (%write-scenario-file
       (merge-pathnames "scenario-helper.asd" work)
       (%scenario-text
        "(asdf:defsystem \"scenario-helper\" :serial t :components ((:file \"scenario-helper\")))"
        ""))
      (%write-scenario-file
       (merge-pathnames "scenario-helper.lisp" work)
       (%scenario-text "(defpackage #:scenario-helper (:use #:cl))"
                       "(in-package #:scenario-helper)"
                       "(defun greeting () \"O15_ASDF_OK\")"
                       ""))
      (multiple-value-bind (stdout stderr exit-code)
          (%run-scenario-script
           work (%scenario-text
                 "(eval-when (:EXECUTE) (pushnew (truename \".\") asdf:*central-registry* :TEST #'equal))"
                 "(asdf:load-system \"scenario-helper\")"
                 "(format t \"~a~%\" (scenario-helper:greeting))"
                 "")
           :environment (%scenario-environment
                         home (format nil "XDG_CACHE_HOME=~A"
                                      (namestring (merge-pathnames "cache/" root)))))
        ;; The compiler may write notes to stderr, so stderr is not compared.
        (declare (ignore stderr))
        (expect (search "O15_ASDF_OK" stdout) :to-be-truthy)
        (expect 0 :to-equal exit-code))))

  (it "e2e-scenario-O16-preserve-case"
    "A script keeps -KeepCase as written and expands the upper-case glob *.NSH."
    (with-scenario-directories (root home work)
      (%write-scenario-file (merge-pathnames "CaseSensitive.NSH" work)
                            (format nil "fixture~%"))
      (multiple-value-bind (stdout stderr exit-code)
          (%run-scenario-script work (%scenario-text "(echo -KeepCase *.NSH)" "")
                                :environment (%scenario-environment home))
        (declare (ignore stderr))
        (expect (search "-KeepCase" stdout) :to-be-truthy)
        (expect (search "CaseSensitive.NSH" stdout) :to-be-truthy)
        (expect 0 :to-equal exit-code))))

  (it "e2e-scenario-O18-alias-eval-and-string-execution"
    "An alias whose body has double quotes runs, and (eval \"...\") runs a string."
    (with-scenario-directories (root home work)
      (%assert-nshell-main-result
       (list (namestring
              (%write-scenario-file (merge-pathnames "scenario.nsh" work)
                                    (%scenario-text
                                     "alias o18_alias 'echo \"O18_ALIAS_OK\"'"
                                     "o18_alias"
                                     "(eval \"echo O18_EVAL_OK\")"
                                     ""))))
       '("O18_ALIAS_OK" "O18_EVAL_OK")
       0
       :directory work
       :environment (%scenario-environment home))))

  (it "e2e-scenario-P07-theme-selection"
    "In a script, theme show after theme use nord shows nord."
    (with-scenario-directories (root home work)
      (multiple-value-bind (stdout stderr exit-code)
          (%run-scenario-script work (%scenario-text "theme use nord" "theme show" "")
                                :environment (%scenario-environment home))
        (declare (ignore stderr))
        (expect (search "nord" stdout) :to-be-truthy)
        (expect 0 :to-equal exit-code))))

  (it "e2e-scenario-P10-completion-definition"
    "In a script, an option registered with complete -c is a complete -C candidate."
    (with-scenario-directories (root home work)
      (multiple-value-bind (stdout stderr exit-code)
          (%run-scenario-script
           work (%scenario-text "complete -c p10_command -f --p10-option"
                                "complete -C \"p10_command --p10\""
                                "")
           :environment (%scenario-environment home))
        (declare (ignore stderr))
        (expect (search "--p10-option" stdout) :to-be-truthy)
        (expect 0 :to-equal exit-code))))

  (it "e2e-scenario-Q01-no-debug-dump"
    "A script holding only ) exits 2 without printing a structure or a backtrace."
    (with-scenario-directories (root home work)
      (multiple-value-bind (stdout stderr exit-code)
          (%run-scenario-script work (%scenario-text ")" "")
                                :environment (%scenario-environment home))
        (expect 2 :to-equal exit-code)
        (dolist (marker '("#S(" "Backtrace" "SB-DEBUG"))
          (expect (search marker stdout) :to-be-falsy)
          (expect (search marker stderr) :to-be-falsy)))))

  (it "e2e-scenario-T03-help-output"
    "help echo in a script prints echo's description."
    (with-scenario-directories (root home work)
      (%assert-nshell-main-result
       (list (namestring
              (%write-scenario-file (merge-pathnames "scenario.nsh" work)
                                    (%scenario-text "help echo" ""))))
       "echo"
       0
       :directory work
       :environment (%scenario-environment home)))))
