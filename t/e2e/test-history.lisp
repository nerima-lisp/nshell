(in-package #:nshell/test)
(describe "e2e-history-tests"
  (it "e2e-history-persists-across-sessions"
    #-(or darwin linux)
    (skip "PTY tests are only supported on Darwin and Linux")
    #+(or darwin linux)
    (skip-when-pty-unavailable "persists history between real nshell processes"
      (with-temporary-output-file (history-path :prefix "nshell-e2e-session-history")
        (let* ((program (%absolute-sbcl-executable))
               (older "printf 'history-older:<%s>\\n' first")
               (newer "printf 'history-newest:<%s>\\n' second")
               (arguments
                 (append
                  (list "--noinform" "--disable-debugger")
                  (%asdf-bootstrap-forms
                   (namestring (asdf:system-source-directory :nshell)))
                  (list "--eval" "(asdf:load-system :nshell)"
                        "--eval"
                        (format nil
                                "(set (find-symbol ~S ~S) ~S)"
                                "*HISTORY-FILE-PATH-OVERRIDE*"
                                "NSHELL.INFRASTRUCTURE.PERSISTENCE" history-path)
                        "--eval" (%nshell-main-form '("--no-config")))))
               (first-pid nil))
          (unless program
            (skip "requires an absolute SBCL runtime path"))
          (expect (probe-file history-path) :to-be-falsy)
          (labels ((await-command (fd marker)
                     (expect (search marker (%e2e-pty-read-until fd marker))
                             :to-be-truthy))
                   (run-session (action)
                     (let ((pty nil))
                       (unwind-protect
                            (progn
                              (setf pty (nshell.infrastructure.acl:pty-spawn
                                         program arguments :rows 24 :cols 100))
                              (let* ((fd (nshell.infrastructure.acl:pty-process-master-fd pty))
                                     (ready (format nil "~c[?2004h" #\Escape)))
                                (expect (search ready (%e2e-pty-read-until fd ready))
                                        :to-be-truthy)
                                (funcall action pty fd)
                                (nshell.infrastructure.acl:pty-write fd (string (code-char 4)))
                                (%assert-pty-child-exit pty)))
                         (%terminate-pty-process pty)))))
            (run-session
             (lambda (pty fd)
               (setf first-pid (nshell.infrastructure.acl:pty-process-pid pty))
               (%e2e-pty-write-line fd older)
               (await-command fd "history-older:<first>")
               (%e2e-pty-write-line fd newer)
               (await-command fd "history-newest:<second>")))
            (let ((nshell.infrastructure.persistence::*history-file-path-override*
                    history-path))
              (expect (list older newer) :to-equal
                      (nshell.infrastructure.persistence:load-history-file)))
            (run-session
             (lambda (pty fd)
               (expect (= first-pid (nshell.infrastructure.acl:pty-process-pid pty))
                       :to-be-falsy)
               (nshell.infrastructure.acl:pty-write fd (format nil "~c[A~c" #\Escape #\Return))
               (await-command fd "history-newest:<second>"))))))))

  (it "e2e-history-reverse-search-selects-and-executes-match"
    (let ((history (history-kit:make-history :capacity 10))
          (state (input-state)))
      (history-kit:history-add history "docker ps")
      (history-kit:history-add history "git status --short")
      (multiple-value-bind (search-state start-output)
          (nshell.presentation:reduce-input-state
           state
           (input-key-event :ctrl-r))
        (expect :search-start :to-be start-output)
        (setf state search-state))
      (dolist (ch (coerce "status" 'list))
        (setf state (reduce-once state :char ch)))
      (let* ((entries (nshell.application:search-history-use-case
                       history
                       (nshell.presentation:input-state-search-query state)
                       :contains))
             (texts (history-kit:history-entry-texts entries)))
        (setf state
              (nshell.presentation:apply-history-search-results-to-input-state
               state texts)))
      (expect "git status --short" :to-equal (nshell.presentation:input-state-buffer state))
      (multiple-value-bind (finished output)
          (nshell.presentation:reduce-input-state
           state
           (input-key-event :enter))
        (expect :execute :to-be output)
        (expect :insert :to-be (nshell.presentation:input-state-mode finished))
        (expect "git status --short" :to-equal (nshell.presentation:input-state-buffer finished)))))

  (it "e2e-history-reverse-search-start-does-not-preselect-history-before-query"
    (with-repl-history-lines ("docker ps" "git status --short")
      (with-repl-input-state (:buffer "git" :cursor-pos 3)
        (multiple-value-bind (searching start-output)
            (nshell.presentation:reduce-input-state
             nshell.presentation::*input-state*
             (input-key-event :ctrl-r))
          (expect :search-start :to-be start-output)
          (setf nshell.presentation::*input-state* searching)
          (capture-process-output-event start-output))
        (expect :search :to-be (nshell.presentation:input-state-mode
                         nshell.presentation::*input-state*))
        (expect "git" :to-equal (nshell.presentation:input-state-buffer
                      nshell.presentation::*input-state*))
        (expect 3 :to-equal (nshell.presentation:input-state-cursor-pos
                nshell.presentation::*input-state*))
        (expect "" :to-equal (nshell.presentation:input-state-search-query
                      nshell.presentation::*input-state*)))))

  (it "e2e-history-reverse-search-accepts-match-for-editing"
    (let ((history (history-kit:make-history :capacity 10))
          (state (input-state :buffer "git" :cursor-pos 3)))
      (history-kit:history-add history "docker ps")
      (history-kit:history-add history "git status --short")
      (multiple-value-bind (search-state start-output)
          (nshell.presentation:reduce-input-state
           state
           (input-key-event :ctrl-r))
        (expect :search-start :to-be start-output)
        (setf state search-state))
      (dolist (ch (coerce "status" 'list))
        (setf state (reduce-once state :char ch)))
      (let* ((entries (nshell.application:search-history-use-case
                       history
                       (nshell.presentation:input-state-search-query state)
                       :contains))
             (texts (history-kit:history-entry-texts entries)))
        (setf state
              (nshell.presentation:apply-history-search-results-to-input-state
               state texts)))
      (multiple-value-bind (accepted output)
          (nshell.presentation:reduce-input-state
           state
           (input-key-event :right))
        (expect :suggest-update :to-be output)
        (expect :insert :to-be (nshell.presentation:input-state-mode accepted))
        (expect "git status --short" :to-equal (nshell.presentation:input-state-buffer accepted))
        (multiple-value-bind (edited edit-output)
            (nshell.presentation:reduce-input-state
             accepted
             (input-key-event :char #\!))
          (expect :suggest-update :to-be edit-output)
          (expect "git status --short!" :to-equal (nshell.presentation:input-state-buffer edited))))))

  (it "e2e-history-reverse-search-accepts-bracketed-paste-query"
    (with-repl-history-lines ("docker ps" "git status --short")
      (with-repl-input-state (:buffer "git" :cursor-pos 3)
        (multiple-value-bind (searching start-output)
            (nshell.presentation:reduce-input-state
             nshell.presentation::*input-state*
             (input-key-event :ctrl-r))
          (expect :search-start :to-be start-output)
          (setf nshell.presentation::*input-state* searching)
          (capture-process-output-event start-output))
        (multiple-value-bind (updated output)
            (nshell.presentation:reduce-input-state
             nshell.presentation::*input-state*
             (input-key-event :paste nil nil
                              '(:protocol :bracketed :text "status --short")))
          (expect :search-update :to-be output)
          (setf nshell.presentation::*input-state* updated)
          (capture-process-output-event output))
        (expect "status --short" :to-equal (nshell.presentation:input-state-search-query
                      nshell.presentation::*input-state*))
        (is-input-state nshell.presentation::*input-state*
                        :buffer "git status --short"
                        :cursor-pos 18))))

  (it "e2e-history-reverse-search-prefers-continuation-line-prefix"
    (with-repl-history-lines ("echo setup
git status" "printf 'not a prefix git'")
      (let ((multiline "echo setup
git status"))
        (with-repl-input-state ()
          (multiple-value-bind (searching output)
              (nshell.presentation:reduce-input-state
               nshell.presentation::*input-state*
               (input-key-event :ctrl-r))
            (expect :search-start :to-be output)
            (setf nshell.presentation::*input-state* searching)
            (capture-process-output-event output))
          (dolist (ch (coerce "git" 'list))
            (multiple-value-bind (updated output)
                (nshell.presentation:reduce-input-state
                 nshell.presentation::*input-state*
                 (input-key-event :char ch))
              (expect :search-update :to-be output)
              (setf nshell.presentation::*input-state* updated)
              (capture-process-output-event output)))
          (is-input-state nshell.presentation::*input-state*
                          :buffer multiline
                          :cursor-pos (length multiline))))))

  (it "e2e-history-up-prefers-continuation-line-prefix"
    (with-repl-history-lines ("echo setup
git status" "printf 'not a prefix git'")
      (let ((multiline "echo setup
git status"))
        (with-repl-input-state (:buffer "git" :cursor-pos 3)
          (multiple-value-bind (requested output)
              (nshell.presentation:reduce-input-state
               nshell.presentation::*input-state*
               (input-key-event :up))
            (expect :history-prev :to-be output)
            (setf nshell.presentation::*input-state* requested)
            (capture-process-output-event output))
          (is-input-state nshell.presentation::*input-state*
                          :buffer multiline
                          :cursor-pos (length multiline))))))

  (it "e2e-history-autosuggests-continuation-line-prefix"
    (with-repl-history-lines ("echo setup
git status --short")
      (with-repl-input-state (:buffer "git st" :cursor-pos 6)
        (let ((suggestion (nshell.presentation:compute-suggestion
                           nshell.presentation::*history*
                           (nshell.presentation:input-state-buffer
                            nshell.presentation::*input-state*))))
          (expect "atus --short" :to-equal suggestion))
        (let ((with-suggestion
                (nshell.presentation::copy-input-state-with
                 nshell.presentation::*input-state*
                 :suggestion "atus --short")))
          (multiple-value-bind (accepted output)
              (nshell.presentation:reduce-input-state
               with-suggestion
               (input-key-event :right))
            (expect :suggest-update :to-be output)
            (is-input-state accepted
                            :buffer "git status --short"
                            :cursor-pos 18))))))

  (it "e2e-history-alt-dot-inserts-last-argument-for-editing"
    (with-repl-history-lines ("git status --short")
      (with-repl-input-state (:buffer "echo " :cursor-pos 5)
        (multiple-value-bind (requested output)
            (nshell.presentation:reduce-input-state
             nshell.presentation::*input-state*
             (input-key-event :alt-dot))
          (expect :insert-last-argument :to-be output)
          (is-input-state requested :buffer "echo " :cursor-pos 5)
          (setf nshell.presentation::*input-state* requested)
          (capture-process-output-event output)
          (is-input-state nshell.presentation::*input-state*
                          :buffer "echo --short"
                          :cursor-pos 12)))))

  (it "e2e-history-alt-dot-cycles-older-last-arguments"
    (with-repl-history-lines ("docker compose up api" "git status --short")
      (with-repl-input-state (:buffer "echo " :cursor-pos 5)
        (multiple-value-bind (requested output)
            (nshell.presentation:reduce-input-state
             nshell.presentation::*input-state*
             (input-key-event :alt-dot))
          (expect :insert-last-argument :to-be output)
          (setf nshell.presentation::*input-state* requested)
          (capture-process-output-event output))
        (is-input-state nshell.presentation::*input-state*
                        :buffer "echo --short"
                        :cursor-pos 12)
        (multiple-value-bind (requested output)
            (nshell.presentation:reduce-input-state
             nshell.presentation::*input-state*
             (input-key-event :alt-dot))
          (expect :insert-last-argument :to-be output)
          (setf nshell.presentation::*input-state* requested)
          (capture-process-output-event output))
        (is-input-state nshell.presentation::*input-state*
                        :buffer "echo api"
                        :cursor-pos 8))))

  (it "e2e-history-edit-after-up-starts-a-new-prefix-navigation"
    (with-repl-history-lines ("git commit" "grep needle" "git status")
      (with-repl-input-state (:buffer "git" :cursor-pos 3)
        (multiple-value-bind (requested output)
            (nshell.presentation:reduce-input-state
             nshell.presentation::*input-state*
             (input-key-event :up))
          (expect :history-prev :to-be output)
          (setf nshell.presentation::*input-state* requested)
          (capture-process-output-event output))
        (is-input-state nshell.presentation::*input-state*
                        :buffer "git status"
                        :cursor-pos 10)
        (multiple-value-bind (edited edit-output)
            (nshell.presentation:reduce-input-state
             nshell.presentation::*input-state*
             (input-key-event :char #\!))
          (expect :suggest-update :to-be edit-output)
          (setf nshell.presentation::*input-state* edited)
          (capture-process-output-event edit-output))
        (is-input-state nshell.presentation::*input-state*
                        :buffer "git status!"
                        :cursor-pos 11)
        (multiple-value-bind (requested-again output-again)
            (nshell.presentation:reduce-input-state
             nshell.presentation::*input-state*
             (input-key-event :up))
          (expect :history-prev :to-be output-again)
          (setf nshell.presentation::*input-state* requested-again)
          (capture-process-output-event output-again))
        (is-input-state nshell.presentation::*input-state*
                        :buffer "git status!"
                        :cursor-pos 11)))))
