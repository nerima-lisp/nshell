(in-package #:nshell/test)

(defun %strip-sgr-sequences (text)
  (with-output-to-string (output)
    (loop with in-control-sequence-p = nil
          for char across text
          do (cond
               (in-control-sequence-p
                (when (char= char #\m)
                  (setf in-control-sequence-p nil)))
               ((char= char #\Esc)
                (setf in-control-sequence-p t))
               (t
                (write-char char output))))))

(describe "repl-search-ui-tests"
  (it "render-search-results-prints-header-with-match-count"
    (let* ((theme (nshell.domain.configuration:default-theme))
           (output (capture-standard-output
                     (nshell.presentation::render-search-results
                      "git" '("git status" "git log") 0
                      :terminal-width 80 :theme theme))))
      (expect (search "履歴: git  (2 件)" output) :to-be-truthy)))

  (it "render-search-results-prints-header-for-no-matches"
    (let* ((theme (nshell.domain.configuration:default-theme))
           (output (capture-standard-output
                     (nshell.presentation::render-search-results
                      "zzz" nil 0
                      :terminal-width 80 :theme theme))))
      (expect (search "履歴: zzz  (該当なし)" output) :to-be-truthy)))

  (it "render-search-results-header-uses-comment-role"
    (let ((nshell.infrastructure.terminal:*terminal-color-depth* :truecolor))
      (let* ((theme (nshell.domain.configuration:default-theme))
             (prefix (nshell.presentation::theme-color->ansi theme :comment))
             (output (capture-standard-output
                       (nshell.presentation::render-search-results
                        "git" '("git status") 0
                        :terminal-width 80 :theme theme))))
        (expect (search (concatenate 'string
                                     prefix
                                     (nshell.presentation::%truncate-string-to-width
                                      (nshell.presentation::%search-header-text
                                       "git" 1)
                                      80)
                                     (esc-sequence "[0m"))
                        output)
                :to-be-truthy))))

  (it "render-search-results-highlights-matched-substring-with-search-match-role"
    (let ((nshell.infrastructure.terminal:*terminal-color-depth* :truecolor))
      (let* ((theme (nshell.domain.configuration:default-theme))
             (match-prefix (nshell.presentation::theme-color->ansi theme :search-match))
             (output (capture-standard-output
                       (nshell.presentation::render-search-results
                        "log" '("git status" "git log") 0
                        :terminal-width 80 :theme theme))))
        (expect (search (concatenate 'string
                                     "  git "
                                     match-prefix
                                     "log"
                                     (esc-sequence "[0m"))
                        output)
                :to-be-truthy))))

  (it "render-search-results-highlights-matched-substring-case-insensitively-for-lowercase-query"
    (let ((nshell.infrastructure.terminal:*terminal-color-depth* :truecolor))
      (let* ((theme (nshell.domain.configuration:default-theme))
             (match-prefix (nshell.presentation::theme-color->ansi theme :search-match))
             (output (capture-standard-output
                       (nshell.presentation::render-search-results
                        "log" '("git LOG") 1
                        :terminal-width 80 :theme theme))))
        (expect (search (concatenate 'string
                                     "  git "
                                     match-prefix
                                     "LOG"
                                     (esc-sequence "[0m"))
                        output)
                :to-be-truthy))))

  (it "render-search-results-wraps-selected-row-in-completion-selected-role"
    (let ((nshell.infrastructure.terminal:*terminal-color-depth* :truecolor))
      (let* ((theme (nshell.domain.configuration:default-theme))
             (selected-prefix
               (nshell.presentation::theme-color->ansi theme :completion-selected))
             (output (capture-standard-output
                       (nshell.presentation::render-search-results
                        "git" '("git status" "git log") 0
                        :terminal-width 80 :theme theme))))
        (expect (search (concatenate 'string
                                     selected-prefix
                                     "▸ git status"
                                     (esc-sequence "[0m"))
                        output)
                :to-be-truthy))))

  (it "render-search-results-marks-unselected-rows-with-two-space-indent"
    (let* ((theme (nshell.domain.configuration:default-theme))
           (output (capture-standard-output
                     (nshell.presentation::render-search-results
                      "zzz" '("alpha" "beta") 0
                      :terminal-width 80 :theme theme))))
      (expect (search (format nil "~%  beta~%") output) :to-be-truthy)))

  (it "render-search-results-shows-origin-and-failure-badges-with-theme-roles"
    (let ((nshell.infrastructure.terminal:*terminal-color-depth* :truecolor))
      (let* ((theme (nshell.domain.configuration:default-theme))
             (assistant-prefix
               (nshell.presentation::theme-color->ansi theme :prompt-assistant))
             (error-prefix
               (nshell.presentation::theme-color->ansi theme :prompt-error))
             (output (capture-standard-output
                       (nshell.presentation::render-search-results
                        "deploy"
                        '((:text "deploy production" :origin :proposal :exit-code 7))
                        0 :terminal-width 80 :theme theme))))
        (expect (search "[提案]" output) :to-be-truthy)
        (expect (search "[終了 7]" output) :to-be-truthy)
        (expect (search assistant-prefix output) :to-be-truthy)
        (expect (search error-prefix output) :to-be-truthy))))

  (it "render-search-results-makes-history-filters-discoverable"
    (let ((output (capture-standard-output
                    (nshell.presentation::render-search-results
                     "" nil 0 :terminal-width 120
                     :theme (nshell.domain.configuration:default-theme)))))
      (expect (search "status:failed" output) :to-be-truthy)
      (expect (search "origin:typed|proposal|agent" output) :to-be-truthy)))

  (it "render-search-results-truncates-rows-to-terminal-width"
    (let* ((theme (nshell.domain.configuration:default-theme))
           (output (capture-standard-output
                     (nshell.presentation::render-search-results
                      "git" '("git status --long-flag-name-here") 0
                      :terminal-width 10 :theme theme))))
      (expect (search "git status --long-flag-name-here" output) :to-be-falsy)))

  (it "render-search-result-row-fits-badges-within-terminal-width"
    (let ((nshell.infrastructure.terminal:*terminal-color-depth* :none)
          (theme (nshell.domain.configuration:make-theme)))
      (dolist (width '(10 3))
        (let ((output (capture-standard-output
                        (nshell.presentation::%search-result-row
                         '(:text "deploy production"
                           :origin :agent
                           :exit-code 7)
                         "deploy" t width theme))))
          (expect
           (<= (nshell.presentation::%string-visible-width
                (%strip-sgr-sequences output))
               width)
           :to-be-truthy)))))

  (it "render-search-results-truncates-the-header-at-width-40-and-80"
    (dolist (width '(40 80))
      (let* ((theme (nshell.domain.configuration:default-theme))
             (header (nshell.presentation::%search-header-text
                      "git" 1))
             (output (capture-standard-output
                       (nshell.presentation::render-search-results
                        "git" '("git status") 0
                        :terminal-width width :theme theme))))
        (expect (search (nshell.presentation::%truncate-string-to-width
                         header width)
                        output)
                :to-be-truthy)
        (expect 3 :to-equal
                (count #\Newline output)))))

  (it "render-search-results-limits-to-eight-visible-matches"
    (let* ((theme (nshell.domain.configuration:default-theme))
           (matches (loop for i from 1 to 12 collect (format nil "git cmd~d" i))))
      (expect 9 :to-equal (nshell.presentation::render-search-results
                            "git" matches 0
                            :terminal-width 80 :theme theme))
      (let ((output (capture-standard-output
                      (nshell.presentation::render-search-results
                       "git" matches 0
                       :terminal-width 80 :theme theme))))
        (expect (search "cmd8" output) :to-be-truthy)
        (expect (search "cmd9" output) :to-be-falsy))))

  (it "render-search-results-returns-line-count-for-no-matches"
    (let ((*standard-output* (make-string-output-stream)))
      (expect 1 :to-equal (nshell.presentation::render-search-results
                            "zzz" nil 0
                            :terminal-width 80))))

  (it "render-search-results-returns-line-count-for-visible-matches"
    (let ((*standard-output* (make-string-output-stream)))
      (expect 3 :to-equal (nshell.presentation::render-search-results
                            "git" '("git status" "git log") 0
                            :terminal-width 80))))

  (it "history-search-match-start-is-case-insensitive-for-lowercase-query"
    (expect 4 :to-equal (nshell.presentation::history-search-match-start
                          "git STATUS" "status")))

  (it "history-search-match-start-is-case-sensitive-for-uppercase-query"
    (expect (nshell.presentation::history-search-match-start "git status" "STATUS")
            :to-be-null)
    (expect 4 :to-equal (nshell.presentation::history-search-match-start
                          "git STATUS" "STATUS")))

  (it "history-search-match-start-returns-nil-when-query-does-not-occur"
    (expect (nshell.presentation::history-search-match-start "git status" "nope")
            :to-be-null)))
