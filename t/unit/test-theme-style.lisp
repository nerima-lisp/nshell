(in-package #:nshell/test)

(describe "theme-style-spec-tests"
  (it "style-spec-parses-hex-color-and-flags"
    (let ((style (nshell.domain.configuration:parse-style-spec "5fafff --bold")))
      (expect (nshell.domain.configuration:text-style-p style) :to-be-truthy)
      (expect '(:rgb 95 175 255)
              :to-equal
              (nshell.domain.configuration:text-style-foreground style))
      (expect (nshell.domain.configuration:text-style-bold style) :to-be-truthy)
      (expect (nshell.domain.configuration:text-style-underline style) :to-be-falsy)
      (expect (nshell.domain.configuration:text-style-background style) :to-be-null)))

  (it "style-spec-parses-short-hex-named-colors-and-background"
    (let ((style (nshell.domain.configuration:parse-style-spec
                  "#fff --underline --background=303030")))
      (expect '(:rgb 255 255 255)
              :to-equal
              (nshell.domain.configuration:text-style-foreground style))
      (expect '(:rgb 48 48 48)
              :to-equal
              (nshell.domain.configuration:text-style-background style))
      (expect (nshell.domain.configuration:text-style-underline style) :to-be-truthy))
    (let ((style (nshell.domain.configuration:parse-style-spec "brblue -i -r")))
      (expect '(:named 12)
              :to-equal
              (nshell.domain.configuration:text-style-foreground style))
      (expect (nshell.domain.configuration:text-style-italic style) :to-be-truthy)
      (expect (nshell.domain.configuration:text-style-reverse style) :to-be-truthy)))

  (it "style-spec-normal-and-empty-carry-no-color"
    (dolist (spec '("normal" "" "  " "default --dim"))
      (let ((style (nshell.domain.configuration:parse-style-spec spec)))
        (expect (nshell.domain.configuration:text-style-foreground style) :to-be-null)))
    (expect (nshell.domain.configuration:text-style-dim
             (nshell.domain.configuration:parse-style-spec "default --dim"))
            :to-be-truthy))

  (it "style-spec-rejects-unknown-tokens-and-repeated-colors"
    (expect (lambda () (nshell.domain.configuration:parse-style-spec "bogus"))
            :to-throw 'nshell.domain.configuration:invalid-style-spec)
    (expect (lambda () (nshell.domain.configuration:parse-style-spec "red blue"))
            :to-throw 'nshell.domain.configuration:invalid-style-spec)
    (expect (lambda () (nshell.domain.configuration:parse-style-spec "--background=nope"))
            :to-throw 'nshell.domain.configuration:invalid-style-spec)
    (expect (nshell.domain.configuration:valid-style-spec-p "red --bold") :to-be-truthy)
    (expect (nshell.domain.configuration:valid-style-spec-p "12345") :to-be-falsy))

  (it "theme-set-color-validates-the-spec"
    (let ((theme (nshell.domain.configuration:default-theme)))
      (expect (lambda ()
                (nshell.domain.configuration:theme-set-color theme :command "nope"))
              :to-throw 'nshell.domain.configuration:invalid-style-spec)
      (let ((updated (nshell.domain.configuration:theme-set-color theme :command "red")))
        (expect "red" :to-equal (nshell.domain.configuration:theme-color updated :command))
        (expect '(:named 1)
                :to-equal
                (nshell.domain.configuration:text-style-foreground
                 (nshell.domain.configuration:theme-style updated :command)))))))

(describe "theme-preset-tests"
  (it "default-theme-configures-editor-prompt-and-completion-roles"
    (let ((theme (nshell.domain.configuration:default-theme)))
      (expect "nshell" :to-equal (nshell.domain.configuration:theme-name theme))
      (dolist (role '(:command :builtin :keyword :option :quote :variable :path
                      :operator :comment :error :autosuggestion
                      :prompt-path :prompt-git :prompt-git-dirty :prompt-ok
                      :prompt-error :prompt-time :prompt-duration
                      :prompt-continuation
                      :completion-command :completion-directory
                      :completion-description :completion-selected))
        (expect (nshell.domain.configuration:text-style-p
                 (nshell.domain.configuration:theme-style theme role))
                :to-be-truthy))
      (expect (nshell.domain.configuration:text-style-bold
               (nshell.domain.configuration:theme-style theme :command))
              :to-be-truthy)
      (expect (nshell.domain.configuration:text-style-underline
               (nshell.domain.configuration:theme-style theme :path))
              :to-be-truthy)
      (expect (member :command (nshell.domain.configuration:theme-roles theme))
              :to-be-truthy)
      (expect (assoc :command (nshell.domain.configuration:theme-entries theme))
              :to-be-truthy)))

  (it "presets-resolve-by-name-and-share-the-role-set"
    (expect "nshell" :to-equal (first (nshell.domain.configuration:theme-preset-names)))
    (expect (member "dracula" (nshell.domain.configuration:theme-preset-names)
                    :test #'string=)
            :to-be-truthy)
    (let ((dracula (nshell.domain.configuration:find-theme-preset "Dracula"))
          (default (nshell.domain.configuration:default-theme)))
      (expect "dracula" :to-equal (nshell.domain.configuration:theme-name dracula))
      (expect (nshell.domain.configuration:theme-roles default)
              :to-equal
              (nshell.domain.configuration:theme-roles dracula))
      (expect '(:rgb 189 147 249)
              :to-equal
              (nshell.domain.configuration:text-style-foreground
               (nshell.domain.configuration:theme-style dracula :command))))
    (expect (nshell.domain.configuration:find-theme-preset "no-such-theme") :to-be-null)
    (let ((mono (nshell.domain.configuration:find-theme-preset "mono")))
      (expect (nshell.domain.configuration:text-style-foreground
               (nshell.domain.configuration:theme-style mono :command))
              :to-be-null)
      (expect (nshell.domain.configuration:text-style-bold
               (nshell.domain.configuration:theme-style mono :command))
              :to-be-truthy)))

  (it "theme-rename-keeps-entries"
    (let ((renamed (nshell.domain.configuration:theme-rename
                    (nshell.domain.configuration:default-theme) "custom")))
      (expect "custom" :to-equal (nshell.domain.configuration:theme-name renamed))
      (expect (nshell.domain.configuration:theme-color renamed :command)
              :to-equal
              (nshell.domain.configuration:theme-color
               (nshell.domain.configuration:default-theme) :command)))))

(describe "ansi-style-sequence-tests"
  (it "style-sequence-emits-truecolor-256-and-16-color-forms"
    (expect (esc-sequence "[1;38;2;95;175;255m")
            :to-equal
            (nshell.infrastructure.terminal:ansi-style-sequence
             :foreground '(:rgb 95 175 255) :bold t :depth :truecolor))
    (expect (esc-sequence (format nil "[38;5;~dm" (cl-tty-kit:rgb-to-256 95 175 255)))
            :to-equal
            (nshell.infrastructure.terminal:ansi-style-sequence
             :foreground '(:rgb 95 175 255) :depth :256))
    (let ((sixteen (nshell.infrastructure.terminal:ansi-style-sequence
                    :foreground '(:rgb 255 0 0) :depth :16)))
      (expect (or (string= sixteen (esc-sequence "[31m"))
                  (string= sixteen (esc-sequence "[91m")))
              :to-be-truthy)))

  (it "style-sequence-keeps-the-hue-of-pastel-colors-on-16-color-terminals"
    (expect (esc-sequence "[94m")
            :to-equal
            (nshell.infrastructure.terminal:ansi-style-sequence
             :foreground (quote (:rgb 95 175 255)) :depth :16))
    (expect (esc-sequence "[96m")
            :to-equal
            (nshell.infrastructure.terminal:ansi-style-sequence
             :foreground (quote (:rgb 95 215 215)) :depth :16))
    (expect (esc-sequence "[93m")
            :to-equal
            (nshell.infrastructure.terminal:ansi-style-sequence
             :foreground (quote (:rgb 215 175 95)) :depth :16))
    (expect (esc-sequence "[90m")
            :to-equal
            (nshell.infrastructure.terminal:ansi-style-sequence
             :foreground (quote (:rgb 128 128 128)) :depth :16))
    (expect (esc-sequence "[100m")
            :to-equal
            (nshell.infrastructure.terminal:ansi-style-sequence
             :background (quote (:rgb 97 110 136)) :depth :16)))

  (it "style-sequence-maps-named-colors-to-basic-codes"
    (expect (esc-sequence "[94m")
            :to-equal
            (nshell.infrastructure.terminal:ansi-style-sequence
             :foreground '(:named 12) :depth :truecolor))
    (expect (esc-sequence "[4;41m")
            :to-equal
            (nshell.infrastructure.terminal:ansi-style-sequence
             :background '(:named 1) :underline t :depth :16)))

  (it "style-sequence-drops-colors-without-color-support"
    (expect (esc-sequence "[1m")
            :to-equal
            (nshell.infrastructure.terminal:ansi-style-sequence
             :foreground '(:rgb 95 175 255) :bold t :depth :none))
    (expect "" :to-equal (nshell.infrastructure.terminal:ansi-style-sequence
                          :depth :truecolor)))

  (it "color-depth-honours-an-explicit-binding"
    (let ((nshell.infrastructure.terminal:*terminal-color-depth* :256))
      (expect :256 :to-be (nshell.infrastructure.terminal:terminal-color-depth)))
    (let ((nshell.infrastructure.terminal:*terminal-color-depth* nil))
      (expect (member (nshell.infrastructure.terminal:terminal-color-depth)
                      '(:truecolor :256 :16 :none))
              :to-be-truthy)))

  (it "theme-color-to-ansi-uses-the-theme-style-or-the-fallback-table"
    (let ((nshell.infrastructure.terminal:*terminal-color-depth* :truecolor)
          (theme (nshell.domain.configuration:default-theme)))
      (expect (esc-sequence "[1;38;2;95;175;255m")
              :to-equal
              (nshell.presentation:theme-color->ansi theme :command))
      (expect (esc-sequence "[4m")
              :to-equal
              (nshell.presentation:theme-color->ansi theme :path))
      (expect (esc-sequence "[34;1m")
              :to-equal
              (nshell.presentation:theme-color->ansi
               (nshell.domain.configuration:make-theme :name "empty") :builtin)))))
