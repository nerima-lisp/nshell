(in-package #:nshell/test)

(describe "prompt-left-layout-tests"
  (it "default-left-prompt-has-no-host-or-git-segment"
    "A local session with a clean, un-versioned directory renders only path and exit-character segments."
    (let ((nshell.domain.prompting:*git-status-resolver*
            (lambda (directory)
              (declare (ignore directory))
              (values nil nil))))
      (let* ((pm (nshell.domain.prompting:make-prompt-model
                  :hostname "host1" :cwd "~/project" :exit-code 0))
             (result (nshell.domain.prompting:render-prompt-model pm)))
        (expect (list :path :literal :exit :literal)
                :to-equal (mapcar #'nshell.domain.prompting:prompt-segment-kind result))
        (expect "~/project" :to-equal (nshell.domain.prompting:prompt-segment-text (first result)))
        (expect "❯" :to-equal (nshell.domain.prompting:prompt-segment-text (third result))))))

  (it "remote-session-shows-user-at-host-before-the-path"
    "A remote session with a known user renders a host segment ahead of the path."
    (let ((nshell.domain.prompting:*git-status-resolver*
            (lambda (directory) (declare (ignore directory)) (values nil nil))))
      (let* ((pm (nshell.domain.prompting:make-prompt-model
                  :hostname "host1" :cwd "~/project" :exit-code 0
                  :remote-session-p t :user "alice"))
             (result (nshell.domain.prompting:render-prompt-model pm)))
        (expect :host :to-be (nshell.domain.prompting:prompt-segment-kind (first result)))
        (expect "alice@host1 " :to-equal (nshell.domain.prompting:prompt-segment-text (first result)))
        (expect :path :to-be (nshell.domain.prompting:prompt-segment-kind (second result))))))

  (it "remote-session-without-a-known-user-omits-the-at-sign"
    "A remote session with no resolvable username shows the bare host, not a dangling @."
    (let ((nshell.domain.prompting:*git-status-resolver*
            (lambda (directory) (declare (ignore directory)) (values nil nil))))
      (let* ((pm (nshell.domain.prompting:make-prompt-model
                  :hostname "host1" :cwd "~/project" :exit-code 0
                  :remote-session-p t))
             (result (nshell.domain.prompting:render-prompt-model pm)))
        (expect "host1 " :to-equal (nshell.domain.prompting:prompt-segment-text (first result))))))

  (it "local-session-never-shows-a-host-segment-even-with-a-user"
    "REMOTE-SESSION-P, not the presence of a user, gates the host segment."
    (let ((nshell.domain.prompting:*git-status-resolver*
            (lambda (directory) (declare (ignore directory)) (values nil nil))))
      (let* ((pm (nshell.domain.prompting:make-prompt-model
                  :hostname "host1" :cwd "~/project" :exit-code 0 :user "alice"))
             (result (nshell.domain.prompting:render-prompt-model pm)))
        (expect :path :to-be (nshell.domain.prompting:prompt-segment-kind (first result))))))

  (it "clean-repository-renders-a-git-segment-after-the-path"
    (let ((nshell.domain.prompting:*git-status-resolver*
            (lambda (directory)
              (expect "/repo/" :to-equal directory)
              (values "main" nil))))
      (let* ((pm (nshell.domain.prompting:make-prompt-model
                  :hostname "h" :cwd "/repo" :directory "/repo/" :exit-code 0))
             (result (nshell.domain.prompting:render-prompt-model pm))
             (git (third result)))
        (expect :git :to-be (nshell.domain.prompting:prompt-segment-kind git))
        (expect "main" :to-equal (nshell.domain.prompting:prompt-segment-text git)))))

  (it "dirty-repository-renders-a-git-dirty-segment-with-a-trailing-asterisk"
    (let ((nshell.domain.prompting:*git-status-resolver*
            (lambda (directory) (declare (ignore directory)) (values "main" t))))
      (let* ((pm (nshell.domain.prompting:make-prompt-model
                  :hostname "h" :cwd "/repo" :directory "/repo/" :exit-code 0))
             (result (nshell.domain.prompting:render-prompt-model pm))
             (git (third result)))
        (expect :git-dirty :to-be (nshell.domain.prompting:prompt-segment-kind git))
        (expect "main*" :to-equal (nshell.domain.prompting:prompt-segment-text git)))))

  (it "no-branch-omits-the-git-segment-entirely"
    (let ((nshell.domain.prompting:*git-status-resolver*
            (lambda (directory) (declare (ignore directory)) (values nil nil))))
      (let* ((pm (nshell.domain.prompting:make-prompt-model
                  :hostname "h" :cwd "/repo" :directory "/repo/" :exit-code 0))
             (result (nshell.domain.prompting:render-prompt-model pm)))
        (expect nil :to-be (find :git result :key #'nshell.domain.prompting:prompt-segment-kind))
        (expect nil :to-be (find :git-dirty result :key #'nshell.domain.prompting:prompt-segment-kind)))))

  (it "successful-and-unset-exit-codes-render-the-ok-prompt-character"
    (let ((nshell.domain.prompting:*git-status-resolver*
            (lambda (directory) (declare (ignore directory)) (values nil nil))))
      (dolist (exit-code (list 0 nil))
        (let* ((pm (nshell.domain.prompting:make-prompt-model
                    :hostname "h" :cwd "/repo" :exit-code exit-code))
               (result (nshell.domain.prompting:render-prompt-model pm))
               (prompt-char (find-if (lambda (seg)
                                       (member (nshell.domain.prompting:prompt-segment-kind seg)
                                               '(:exit :exit-error)))
                                     result)))
          (expect :exit :to-be (nshell.domain.prompting:prompt-segment-kind prompt-char))
          (expect "❯" :to-equal (nshell.domain.prompting:prompt-segment-text prompt-char))))))

  (it "a-failing-exit-code-renders-the-error-prompt-character-with-the-same-glyph"
    (let ((nshell.domain.prompting:*git-status-resolver*
            (lambda (directory) (declare (ignore directory)) (values nil nil))))
      (let* ((pm (nshell.domain.prompting:make-prompt-model
                  :hostname "h" :cwd "/repo" :exit-code 7))
             (result (nshell.domain.prompting:render-prompt-model pm))
             (prompt-char (find-if (lambda (seg)
                                     (member (nshell.domain.prompting:prompt-segment-kind seg)
                                             '(:exit :exit-error)))
                                   result)))
        (expect :exit-error :to-be (nshell.domain.prompting:prompt-segment-kind prompt-char))
        (expect "❯" :to-equal (nshell.domain.prompting:prompt-segment-text prompt-char)))))

  (it "remote-session-p-must-be-a-generalized-boolean"
    (expect (lambda () (nshell.domain.prompting:make-prompt-model :remote-session-p :not-a-boolean))
            :to-throw 'error)
    (expect (lambda () (nshell.domain.prompting:make-prompt-model :user 42))
            :to-throw 'error)))

(describe "prompt-duration-format-tests"
  (it "hides-sub-second-durations"
    (let* ((pm (nshell.domain.prompting:make-prompt-model :duration-ms 999))
           (result (nshell.domain.prompting:render-right-prompt-model pm)))
      (expect nil :to-be (find :duration result :key #'nshell.domain.prompting:prompt-segment-kind))))

  (it "formats-a-multi-second-duration-with-one-decimal"
    (let* ((pm (nshell.domain.prompting:make-prompt-model :duration-ms 1234))
           (result (nshell.domain.prompting:render-right-prompt-model pm))
           (duration (find :duration result :key #'nshell.domain.prompting:prompt-segment-kind)))
      (expect "1.2s" :to-equal (nshell.domain.prompting:prompt-segment-text duration))))

  (it "formats-a-minute-scale-duration-as-minutes-and-seconds"
    (let* ((pm (nshell.domain.prompting:make-prompt-model :duration-ms 123000))
           (result (nshell.domain.prompting:render-right-prompt-model pm))
           (duration (find :duration result :key #'nshell.domain.prompting:prompt-segment-kind)))
      (expect "2m 3s" :to-equal (nshell.domain.prompting:prompt-segment-text duration))))

  (it "formats-an-hour-scale-duration-as-hours-and-minutes"
    (let* ((pm (nshell.domain.prompting:make-prompt-model :duration-ms 3720000))
           (result (nshell.domain.prompting:render-right-prompt-model pm))
           (duration (find :duration result :key #'nshell.domain.prompting:prompt-segment-kind)))
      (expect "1h 2m" :to-equal (nshell.domain.prompting:prompt-segment-text duration)))))
