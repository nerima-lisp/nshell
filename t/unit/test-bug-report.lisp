;;; Tests for reserved-word subcommands and `nshell bug-report` (task P0-6,
;;; design decisions D-53 and D-54).
(in-package #:nshell/test)

(defparameter +bug-report-secret-values+
  '("sk-test-SECRET-0000" "sk-test-SECRET-0001" "termx-secret-value"
    "language-secret-value" "lowercase-secret-value" "p06-fake-user"
    "init-secret-content" "conf-secret-content" "function-secret-content")
  "Values the fixture puts where the draft must not show them.")

(defun %bug-report-main (arguments)
  "Run NSHELL::MAIN with ARGUMENTS as argv and return its exit status. Safe
mode is bound here so a --safe argument does not leak into later tests."
  (let* ((exit-status nil)
         (nshell.application:*safe-mode-p* nil)
         (nshell::*main-exit-function*
           (lambda (&key unix-status &allow-other-keys)
             (setf exit-status unix-status))))
    (with-temporary-functions
        (('nshell::%current-process-arguments (lambda () arguments)))
      (nshell::main))
    exit-status))

(defun %bug-report-script-call (arguments)
  "Run MAIN with ARGUMENTS and a stub script runner; return (EXIT-STATUS
SCRIPT-CALL), SCRIPT-CALL being (PATH ARGS) or :UNCALLED."
  (let ((script-call :uncalled))
    (with-temporary-functions
        (('nshell.presentation:run-repl-script
          (lambda (path arguments)
            (setf script-call (list path arguments))
            31))
         ('nshell::%run-bug-report
          (lambda (arguments)
            (setf script-call (list :bug-report arguments))
            37)))
      (list (%bug-report-main arguments) script-call))))

(defun %bug-report-write-file (path text)
  (ensure-directories-exist path)
  (with-open-file (stream path :direction :output :if-exists :supersede
                               :external-format :utf-8)
    (write-string text stream)))

(defmacro with-bug-report-fixture ((root environment) &body body)
  "Bind ROOT to a temporary directory holding home/, config/, and state/
fixtures and ENVIRONMENT to \"NAME=VALUE\" strings pointing at them, with
secret-looking values in variables the draft must not print."
  `(host-kit:with-temporary-directory (root-pathname)
     (let* ((,root (namestring (uiop:ensure-directory-pathname root-pathname)))
            (home (concatenate 'string ,root "home"))
            (config (concatenate 'string ,root "config/"))
            (state (concatenate 'string ,root "state"))
            (,environment
              (list (concatenate 'string "HOME=" home)
                    (concatenate 'string "XDG_CONFIG_HOME=" config)
                    (concatenate 'string "XDG_STATE_HOME=" state)
                    "TERM=xterm-256color"
                    "LANG=ja_JP.UTF-8"
                    "LC_CTYPE=UTF-8"
                    (concatenate 'string "LC_ALL=" home "/locale")
                    "TERMX=termx-secret-value"
                    "LANGUAGE=language-secret-value"
                    "lc_all=lowercase-secret-value"
                    "AWS_SECRET_ACCESS_KEY=sk-test-SECRET-0000"
                    "NSHELL_API_TOKEN=sk-test-SECRET-0001"
                    "NSHELL_SAFE=1"
                    "NSHELL_odd=lowercase-secret-value"
                    "USER=p06-fake-user"
                    "LOGNAME=p06-fake-user"
                    "NO_EQUALS_SIGN")))
       (declare (ignorable ,root ,environment))
       (ensure-directories-exist (concatenate 'string home "/"))
       (%bug-report-write-file
        (concatenate 'string config "nshell/init.lisp")
        "(set NSHELL_API_TOKEN \"sk-test-SECRET-0000\") ; init-secret-content
")
       (%bug-report-write-file
        (concatenate 'string config "nshell/conf.d/10-client-name.lisp")
        "(echo conf-secret-content)
")
       (%bug-report-write-file
        (concatenate 'string config "nshell/conf.d/notes.txt")
        "not loaded, not listed")
       (ensure-directories-exist
        (concatenate 'string config "nshell/conf.d/subdirectory.lisp/"))
       (%bug-report-write-file
        (concatenate 'string config "nshell/functions/greet.nsh")
        "(defun greet () (echo function-secret-content))
")
       (dolist (name '("20261115T235959.000001Z.log"
                       "20261116T010203.000004Z.log"
                       "20261116T010203.000004Z-1.log"
                       "sk-test-SECRET-0000.log"
                       "notes.txt"))
         (%bug-report-write-file
          (concatenate 'string state "/nshell/crash/" name)
          "crash log content is never read"))
       ,@body)))

(defun %bug-report-normalize (text)
  "Replace the fields that depend on the build and the host with placeholders,
so the golden file stays stable. In the dependency list only the versions are
replaced: the names come from the :depends-on list of nshell.asd, which every
build reads the same way."
  (with-output-to-string (output)
    (with-input-from-string (input text)
      (loop with in-dependencies = nil
            for line = (read-line input nil nil)
            while line
            do (let ((prefix (find-if (lambda (prefix)
                                        (and (>= (length line) (length prefix))
                                             (string= prefix line
                                                      :end2 (length prefix))))
                                      '("- nshell: " "- Lisp: " "- OS: "
                                        "- Architecture: " "- Terminal width: ")))
                     (separator (search ": " line)))
                 (cond
                   ((string= line "### Dependencies")
                    (setf in-dependencies t)
                    (format output "~a~%" line))
                   ((and in-dependencies separator
                         (>= (length line) 2) (string= "- " line :end2 2))
                    (format output "~a<normalized>~%"
                            (subseq line 0 (+ separator 2))))
                   (prefix
                    (format output "~a<normalized>~%" prefix))
                   (t
                    (format output "~a~%" line))))))))

(defun %bug-report-golden-path ()
  (asdf:system-relative-pathname "nshell" "t/golden/bug-report.txt"))

(describe "bug-report-subcommand-dispatch"
  (it "a-reserved-word-runs-the-subcommand-instead-of-a-script"
    (expect (list 37 (list :bug-report nil)) :to-equal
            (%bug-report-script-call (list "bug-report"))))

  (it "a-path-or-double-dash-runs-the-script-of-the-same-name"
    (expect (list 31 (list "./bug-report" (list "a"))) :to-equal
            (%bug-report-script-call (list "./bug-report" "a")))
    (expect (list 31 (list "bug-report" (list "a"))) :to-equal
            (%bug-report-script-call (list "--" "bug-report" "a")))
    ;; Only the first argument is a reserved word: after an option the name is
    ;; a script, as it was before subcommands existed.
    (expect (list 31 (list "bug-report" nil)) :to-equal
            (%bug-report-script-call (list "--safe" "bug-report"))))

  (it "an-unregistered-word-still-runs-a-script"
    (expect (list 31 (list "doctor" (list "--x"))) :to-equal
            (%bug-report-script-call (list "doctor" "--x")))
    (expect (list 31 (list "Bug-Report" nil)) :to-equal
            (%bug-report-script-call (list "Bug-Report"))))

  (it "a-script-named-like-a-subcommand-runs-through-double-dash"
    (host-kit:with-temporary-directory (root)
      (let ((script (namestring (merge-pathnames "bug-report" root))))
        (%bug-report-write-file script "(echo script-ran $argv[1])
")
        (let* ((status nil)
               (output (capture-standard-output
                         (setf status (%bug-report-main
                                       (list "--" script "p06"))))))
          (expect 0 :to-equal status)
          (expect (search "script-ran p06" output) :to-be-truthy)
          (expect (search "## nshell bug report" output) :to-be-null)))))

  (it "bug-report-rejects-extra-arguments-on-stderr"
    (let* ((status nil)
           (error-output nil)
           (output (capture-standard-output
                     (setf error-output
                           (with-output-to-string (*error-output*)
                             (setf status
                                   (%bug-report-main
                                    (list "bug-report" "extra"))))))))
      (expect 1 :to-equal status)
      (expect "" :to-equal output)
      (expect (search "bug-report takes no arguments" error-output)
              :to-be-truthy)))

  (it "the-registry-is-the-only-source-for-dispatch-and-help"
    (let ((nshell.feature.command-line::*subcommands*
            (copy-tree nshell.feature.command-line::*subcommands*))
          (received :uncalled))
      (nshell.feature.command-line:register-subcommand
       "p06-probe" "Probe subcommand for the registry test."
       (lambda (arguments) (setf received arguments) 41))
      (let ((help (with-output-to-string (stream)
                    (nshell::%print-usage stream))))
        (expect (search "nshell SUBCOMMAND [ARGS...]" help) :to-be-truthy)
        (dolist (entry (nshell.feature.command-line:subcommand-summaries))
          (expect (search (first entry) help) :to-be-truthy)
          (expect (search (second entry) help) :to-be-truthy))
        (expect (search "p06-probe" help) :to-be-truthy)
        (expect (search "bug-report" help) :to-be-truthy)
        (expect (search "nshell -- NAME" help) :to-be-truthy))
      (expect 41 :to-equal (%bug-report-main (list "p06-probe" "x" "--y")))
      (expect (list "x" "--y") :to-equal received)
      (expect (list "bug-report" "explain" "p06-probe") :to-equal
              (mapcar #'first (nshell.feature.command-line:subcommand-summaries))))
    (expect (find "p06-probe" (nshell.feature.command-line:subcommand-summaries)
                  :key #'first :test #'string=)
            :to-be-null))

  (it "a-subcommand-name-must-not-look-like-a-flag-or-a-path"
    (let ((nshell.feature.command-line::*subcommands* '()))
      (dolist (name '("" "-x" "./x" "a/b"))
        (expect (handler-case
                    (progn
                      (nshell.feature.command-line:register-subcommand
                       name "bad" 'identity)
                      :registered)
                  (error () :rejected))
                :to-equal :rejected)))))

(describe "bug-report-domain"
  (it "sha256-matches-the-fips-180-4-examples"
    (flet ((digest (text)
             (nshell.domain.bug-report:sha256-hex
              (sb-ext:string-to-octets text :external-format :utf-8))))
      (expect "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
              :to-equal (digest ""))
      (expect "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
              :to-equal (digest "abc"))
      (expect "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"
              :to-equal
              (digest "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"))))

  (it "only-term-colorterm-lang-and-lc-names-may-show-a-value"
    (dolist (name '("TERM" "COLORTERM" "LANG" "LC_ALL" "LC_CTYPE" "LC_X_9"))
      (expect (nshell.domain.bug-report:environment-value-printable-p name)
              :to-be-truthy))
    (dolist (name '("TERMX" "TERM_PROGRAM" "COLORTERM2" "LANGUAGE" "LANG_"
                    "LC_" "lc_all" "LC_all" "LC-ALL" "HOME" "USER"
                    "NSHELL_SAFE" "AWS_SECRET_ACCESS_KEY" "" nil))
      (expect (nshell.domain.bug-report:environment-value-printable-p name)
              :to-be-falsy)))

  (it "only-well-formed-nshell-names-are-listed"
    (expect (nshell.domain.bug-report:nshell-variable-name-p "NSHELL_SAFE")
            :to-be-truthy)
    (dolist (name '("NSHELL_" "NSHELL_odd" "NSHELLX" "XNSHELL_A" nil))
      (expect (nshell.domain.bug-report:nshell-variable-name-p name)
              :to-be-falsy)))

  (it "crash-log-names-follow-the-crash-log-writer"
    (dolist (attempt '(0 1 12))
      (expect (nshell.domain.bug-report:crash-log-file-name-p
               (nshell.domain.crash:crash-log-file-name 1763254923 4 attempt))
              :to-be-truthy))
    (dolist (name '("notes.txt" "sk-test-SECRET-0000.log"
                    "20261116T010203.000004Z-.log" "20261116T010203.000004Z-x.log"
                    "20261116T010203.000004Zlog"))
      (expect (nshell.domain.bug-report:crash-log-file-name-p name)
              :to-be-falsy))))

(describe "bug-report-rendering"
  (it "names-the-newest-crash-log-including-retry-suffixes"
    (let ((text (nshell.domain.bug-report:render-bug-report
                 :crash-log-names (list "20261116T010203.000004Z-2.log"
                                        "20261116T010203.000004Z.log"
                                        "20261116T010203.000004Z-12.log"
                                        "20261115T235959.999999Z-99.log"
                                        "notes.txt")
                 :init-file (nshell.domain.bug-report:make-config-file-fact
                             :absent))))
      (expect (search "- Logs: 4" text) :to-be-truthy)
      (expect (search "- Most recent: 20261116T010203.000004Z-12.log" text)
              :to-be-truthy)
      (expect (search "notes.txt" text) :to-be-null)))

  (it "replaces-home-anywhere-in-an-allowed-value"
    (flet ((render (home value)
             (nshell.domain.bug-report:render-bug-report
              :environment (list (cons "LC_ALL" value))
              :home home
              :init-file (nshell.domain.bug-report:make-config-file-fact
                          :absent))))
      (expect (search "- LC_ALL: prefix~/locale"
                      (render "/home/p06/" "prefix/home/p06/locale"))
              :to-be-truthy)
      (expect (search "- LC_ALL: /home/p06/locale"
                      (render "/" "/home/p06/locale"))
              :to-be-truthy)
      (expect (search "- LC_ALL: /home/p06/locale"
                      (render "" "/home/p06/locale"))
              :to-be-truthy)))

  (it "shows-allowed-values-on-one-line-with-tokens-redacted"
    (let ((text (nshell.domain.bug-report:render-bug-report
                 :environment
                 (list (cons "LC_MESSAGES"
                             (format nil "C~%- injected: line sk-test-SECRET-0000-0000-0000"))
                       (cons "TERM" "/home/p06/term")
                       (cons "LANGUAGE" "language-secret-value"))
                 :home "/home/p06"
                 :init-file (nshell.domain.bug-report:make-config-file-fact
                             :absent))))
      (expect (search "- TERM: ~/term" text) :to-be-truthy)
      (expect (search "/home/p06" text) :to-be-null)
      ;; The assistant redaction replaces sk- followed by 20 or more token
      ;; characters.
      (expect (search "sk-test-SECRET" text) :to-be-null)
      (expect (search "[REDACTED]" text) :to-be-truthy)
      (expect (search (format nil "~%- injected") text) :to-be-null)
      (expect (search "language-secret-value" text) :to-be-null)
      (expect (search "LANGUAGE" text) :to-be-null))))

(describe "bug-report-output"
  (it "matches-the-golden-draft"
    (with-bug-report-fixture (root environment)
      (let ((text (nshell.infrastructure.persistence:bug-report-text
                   :environment environment)))
        (expect (uiop:read-file-string (%bug-report-golden-path)
                                       :external-format :utf-8)
                :to-equal (%bug-report-normalize text))
        (expect (search "- cl-cli: " text) :to-be-truthy))))

  (it "prints-no-secret-home-path-or-user-name"
    (with-bug-report-fixture (root environment)
      (let ((text (nshell.infrastructure.persistence:bug-report-text
                   :environment environment))
            (real-home (host-kit:getenv "HOME")))
        (dolist (secret +bug-report-secret-values+)
          (expect (search secret text) :to-be-null))
        (expect (search root text) :to-be-null)
        (expect (search (namestring (truename root)) text) :to-be-null)
        (expect (search "10-client-name" text) :to-be-null)
        (expect (search "greet" text) :to-be-null)
        (when (and real-home (> (length real-home) 1))
          (expect (search real-home text) :to-be-null))
        (expect (search "NSHELL_API_TOKEN" text) :to-be-truthy)
        (expect (search "NSHELL_SAFE" text) :to-be-truthy)
        (expect (search "- LC_ALL: ~/locale" text) :to-be-truthy))))

  (it "reports-missing-unreadable-and-special-configuration-files"
    (host-kit:with-temporary-directory (root-pathname)
      (let* ((root (namestring (uiop:ensure-directory-pathname root-pathname)))
             (config (concatenate 'string root "config/nshell/"))
             (environment (list (concatenate 'string "HOME=" root "home")
                                (concatenate 'string "XDG_CONFIG_HOME=" root "config"))))
        (expect (search "- init.lisp: absent"
                        (nshell.infrastructure.persistence:bug-report-text
                         :environment environment))
                :to-be-truthy)
        (%bug-report-write-file (concatenate 'string config "init.lisp") "x")
        (sb-posix:chmod (concatenate 'string config "init.lisp") 0)
        (ensure-directories-exist (concatenate 'string config "conf.d/"))
        (sb-posix:mkfifo (concatenate 'string config "conf.d/pipe.lisp") #o600)
        (let ((text (nshell.infrastructure.persistence:bug-report-text
                     :environment environment)))
          (unless (zerop (sb-posix:geteuid))
            (expect (search "- init.lisp: 1 bytes, unreadable" text)
                    :to-be-truthy))
          (expect (search "  - conf.d #1: not a regular file" text)
                  :to-be-truthy)
          (expect (search "Directory: $XDG_CONFIG_HOME/nshell/" text)
                  :to-be-truthy)
          (expect (search "Directory: ~/.local/state/nshell/crash/" text)
                  :to-be-truthy)
          (expect (search root text) :to-be-null)))))

  (it "uses-the-account-home-when-home-is-unset-without-printing-it"
    (let ((text (nshell.infrastructure.persistence:bug-report-text
                 :environment (list "TERM=dumb")))
          (account-home (string-right-trim
                         "/" (namestring (user-homedir-pathname)))))
      (expect (search "Directory: ~/.config/nshell/" text) :to-be-truthy)
      (expect (search "Directory: ~/.local/state/nshell/crash/" text)
              :to-be-truthy)
      (when (> (length account-home) 1)
        (expect (search account-home text) :to-be-null)))))
