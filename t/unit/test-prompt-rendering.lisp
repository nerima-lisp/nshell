(in-package #:nshell/test)

(describe "prompt-rendering-tests"
  (it "render-prompt-truncates-right-prompt-to-current-terminal-width"
    "The presentation prompt uses the supplied terminal width for right prompt alignment."
    (let* ((nshell.domain.prompting:*prompt-time-resolver* (lambda () "abcdef"))
           (terminal-width (+ (current-left-prompt-width) 2 4))
           (output (capture-render-prompt :terminal-width terminal-width)))
      (expect (search "abcd" output) :to-be-truthy)
      (expect (search "abcdef" output) :to-be-falsy)))

  (it "render-prompt-restores-cursor-after-right-prompt"
    "Right prompt rendering should leave the cursor after the left prompt for input text."
    (let ((output (capture-render-prompt :terminal-width (+ (current-left-prompt-width) 10))))
      (expect (search (format nil "~C7" #\Esc) output) :to-be-truthy)
      (expect (search (format nil "~C8" #\Esc) output) :to-be-truthy)))

  (it "render-prompt-renders-time-in-right-prompt"
    "The presentation layer should surface the right-prompt time segment."
    (let ((nshell.domain.prompting:*prompt-time-resolver*
            (lambda ()
              "12:34")))
      (let ((output (capture-render-prompt :terminal-width (+ (current-left-prompt-width) 12))))
        (expect (search "12:34" output) :to-be-truthy))))

  (it "render-prompt-hides-a-sub-second-duration-in-the-right-prompt"
    "A duration under one second is not surfaced in the right prompt."
    (let ((output (capture-render-prompt :terminal-width (+ (current-left-prompt-width) 20)
                                         :duration-ms 123)))
      (expect (search "123ms" output) :to-be-falsy)))

  (it "render-prompt-renders-duration-in-right-prompt"
    "The presentation layer should surface the last-command duration segment from one second up."
    (let ((output (capture-render-prompt :terminal-width (+ (current-left-prompt-width) 20)
                                         :duration-ms 1234)))
      (expect (search "1.2s" output) :to-be-truthy)))

  (it "render-prompt-returns-left-visible-width"
    "The prompt renderer reports the left prompt width for edit-buffer cursor placement."
    (multiple-value-bind (output results)
        (call-render-prompt :terminal-width 80)
      (declare (ignore output))
      (expect (current-left-prompt-width) :to-equal (first results))))

  (it "render-prompt-shows-a-git-dirty-branch-on-the-left-prompt"
    "A dirty branch renders on the left prompt with a trailing asterisk, not on the right."
    (let ((output (capture-render-prompt :terminal-width 80 :branch "main" :dirty t)))
      (expect (search "main*" output) :to-be-truthy)))

  (it "render-prompt-shows-a-remote-session-host-segment"
    "A remote session (per *PROMPT-REMOTE-SESSION-P*) shows user@host ahead of the path."
    (let ((output (capture-render-prompt :terminal-width 80
                                         :remote-session-p t :user "alice")))
      (expect (search "alice@test-host " output) :to-be-truthy)))

  (it "render-prompt-omits-the-host-segment-for-a-local-session"
    "A local session (the default in these tests) never shows a host segment."
    (let ((output (capture-render-prompt :terminal-width 80)))
      (expect (search "test-host" output) :to-be-falsy)))

  (it "render-prompt-omits-the-ai-usage-segment-with-zero-turns"
    "The AI segment is absent until the assistant has recorded a turn."
    (nshell.feature.assistant:reset-assistant-usage)
    (let ((output (capture-render-prompt :terminal-width 80)))
      (expect (search "AI " output) :to-be-falsy)))

  (it "render-prompt-shows-the-ai-usage-segment-after-a-turn"
    "The AI segment appears in the right prompt once ASSISTANT-USAGE-TURNS is positive."
    (unwind-protect
        (progn
          (setf (nshell.feature.assistant:assistant-usage-turns nshell.feature.assistant:*assistant-usage*) 1)
          (let ((output (capture-render-prompt :terminal-width 200)))
            (expect (search "AI " output) :to-be-truthy)))
      (nshell.feature.assistant:reset-assistant-usage)))

  (it "render-prompt-emits-the-window-title-only-when-the-terminal-is-interactive"
    "An OSC window-title sequence is written only when the interactive terminal flag is set."
    (let ((output (capture-render-prompt :terminal-width 80 :window-title-p t)))
      (expect (search (format nil "~C]0;" #\Esc) output) :to-be-truthy))
    (let ((output (capture-render-prompt :terminal-width 80)))
      (expect (search (format nil "~C]0;" #\Esc) output) :to-be-falsy)))

  (it "home-prefix-only-matches-path-boundaries"
    "Home-directory shortening should not trigger on plain string prefixes."
    (expect (nshell.presentation::%home-prefix-p "/Users/take" "/Users/take") :to-be-truthy)
    (expect (nshell.presentation::%home-prefix-p "/Users/take" "/Users/take/projects") :to-be-truthy)
    (expect (nshell.presentation::%home-prefix-p "/Users/take" "/Users/takefoo") :to-be-falsy))

  (it "strip-trailing-slash-keeps-a-lone-separator-or-tilde"
    "Root and home stay as a bare separator or tilde; every other path loses its trailing slash."
    (expect "/" :to-equal (nshell.presentation::%strip-trailing-slash "/"))
    (expect "~" :to-equal (nshell.presentation::%strip-trailing-slash "~"))
    (expect "/a/b" :to-equal (nshell.presentation::%strip-trailing-slash "/a/b/"))
    (expect "/a/b" :to-equal (nshell.presentation::%strip-trailing-slash "/a/b")))

  (it "display-cwd-shortens-fish-style-past-the-absolute-width-threshold"
    "A cwd wider than 40 columns is shortened even at a very wide terminal."
    (let ((wide (nshell.presentation::%display-cwd
                 "/srv/aaaaaaaaaa/bbbbbbbbbb/cccccccccc/dddddddddd/eeeeeeeeee/"
                 1000)))
      (expect "/s/a/b/c/d/eeeeeeeeee" :to-equal wide)))

  (it "display-cwd-shortens-fish-style-when-the-terminal-is-narrow"
    "A short cwd is still shortened when the terminal leaves fewer than 30 columns for input."
    (expect "/s/t/project"
            :to-equal (nshell.presentation::%display-cwd "/srv/take/project/" 40))
    (expect "/srv/take/project"
            :to-equal (nshell.presentation::%display-cwd "/srv/take/project/" 200)))

  (it "display-cwd-leaves-a-single-component-path-untouched"
    "There is nothing to cut when the path is only a leader and one component."
    (expect "~" :to-equal (nshell.presentation::%display-cwd "~/" 10))
    (expect "/" :to-equal (nshell.presentation::%display-cwd "/" 10))))

(describe "prompt-custom-format-rendering-tests"
  (it "renders-a-custom-left-format-in-place-of-the-built-in-layout"
    "{user} and {host} are separate colored segments, so each is checked on
its own rather than as one contiguous substring across the ANSI codes
%WRITE-COLORED-SEGMENTS emits between them."
    (let ((output (capture-render-prompt :terminal-width 80
                                         :left-format "{user}@{host} $ "
                                         :remote-session-p t :user "alice")))
      (expect (search "alice" output) :to-be-truthy)
      (expect (search "test-host" output) :to-be-truthy)
      (expect (search "$" output) :to-be-truthy)))

  (it "returns-the-custom-left-formats-visible-width"
    "RENDER-PROMPT's left-width return value still reflects whichever layout
(built-in or a custom format) actually rendered."
    (multiple-value-bind (output results)
        (call-render-prompt :terminal-width 80 :left-format "ab> ")
      (declare (ignore output))
      (expect 4 :to-equal (first results))))

  (it "renders-a-custom-right-format-in-place-of-the-built-in-layout"
    (let ((nshell.domain.prompting:*prompt-time-resolver* (lambda () "12:34")))
      (let ((output (capture-render-prompt
                     :terminal-width (+ (current-left-prompt-width) 12)
                     :right-format "{time}")))
        (expect (search "12:34" output) :to-be-truthy))))

  (it "an-unset-left-format-falls-back-to-nshell-prompt-from-the-environment"
    (with-prompt-format-environment '(("NSHELL_PROMPT" . "ab> "))
      (multiple-value-bind (output results)
          (call-render-prompt :terminal-width 80)
        (declare (ignore output))
        (expect 4 :to-equal (first results)))))

  (it "an-installed-left-format-override-wins-over-nshell-prompt"
    "The rc file's `prompt left ...` runs after startup env pickup, so an
installed override must take precedence over NSHELL_PROMPT."
    (with-prompt-format-environment '(("NSHELL_PROMPT" . "should-not-render"))
      (multiple-value-bind (output results)
          (call-render-prompt :terminal-width 80 :left-format "ab> ")
        (declare (ignore output))
        (expect 4 :to-equal (first results)))))

  (it "an-unset-right-format-falls-back-to-nshell-right-prompt-from-the-environment"
    (with-prompt-format-environment '(("NSHELL_RIGHT_PROMPT" . "{time}"))
      (let ((nshell.domain.prompting:*prompt-time-resolver* (lambda () "12:34")))
        (let ((output (capture-render-prompt
                       :terminal-width (+ (current-left-prompt-width) 12))))
          (expect (search "12:34" output) :to-be-truthy))))))
