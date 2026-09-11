(in-package #:nshell/test)

(describe "repl-search-ui-tests"
  (it "render-search-results-prints-header-with-match-count"
    (let* ((theme (nshell.domain.configuration:default-theme))
           (output (capture-standard-output
                     (nshell.presentation::render-search-results
                      "git" '("git status" "git log") 0
                      :terminal-width 80 :theme theme))))
      (expect (search "history: git  (2 matches)" output) :to-be-truthy)))

  (it "render-search-results-prints-header-for-no-matches"
    (let* ((theme (nshell.domain.configuration:default-theme))
           (output (capture-standard-output
                     (nshell.presentation::render-search-results
                      "zzz" nil 0
                      :terminal-width 80 :theme theme))))
      (expect (search "history: zzz  (no matches)" output) :to-be-truthy)))

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
                                     "history: git  (1 matches)"
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

  (it "render-search-results-truncates-rows-to-terminal-width"
    (let* ((theme (nshell.domain.configuration:default-theme))
           (output (capture-standard-output
                     (nshell.presentation::render-search-results
                      "git" '("git status --long-flag-name-here") 0
                      :terminal-width 10 :theme theme))))
      (expect (search "git status --long-flag-name-here" output) :to-be-falsy)))

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
