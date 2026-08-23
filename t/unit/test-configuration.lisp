(in-package #:nshell/test)

(describe "configuration-domain-tests"
  (it "configuration-raw-constructors-are-internal-boundaries"
    "Configuration public factories wrap internal raw constructors"
    (let ((theme (nshell.domain.configuration:make-theme :name "custom"))
          (config (nshell.domain.configuration:make-config)))
      (expect (nshell.domain.configuration:theme-p theme) :to-be-truthy)
      (expect "custom" :to-equal (nshell.domain.configuration:theme-name theme))
      (expect (nshell.domain.configuration:config-p config) :to-be-truthy)
      (expect (nshell.domain.configuration:theme-p (nshell.domain.configuration:config-theme config)) :to-be-truthy)
      (expect (fboundp 'nshell.domain.configuration::theme-colors) :to-be-falsy)
      (expect (fboundp 'nshell.domain.configuration::copy-theme) :to-be-falsy)
      (expect (fboundp 'nshell.domain.configuration::%make-theme) :to-be-falsy)
      (expect (fboundp 'nshell.domain.configuration::%allocate-theme) :to-be-truthy)
      (expect (fboundp 'nshell.domain.configuration::copy-config) :to-be-falsy)
      (expect (fboundp 'nshell.domain.configuration::%make-config) :to-be-falsy)
      (expect (fboundp 'nshell.domain.configuration::%allocate-config) :to-be-truthy)))

  (it "config-construction-validates-aggregate-values"
    "Configuration construction accepts only valid aggregate values."
    (expect (lambda () (nshell.domain.configuration:make-config :theme nil)) :to-throw 'type-error))

  (it "theme-colors-are-detached-from-constructor-input"
    "Theme construction owns the mutable color table."
    (let ((colors (make-hash-table :test #'eq)))
      (setf (gethash :command colors) "00AFFF")
      (let ((theme (nshell.domain.configuration:make-theme
                    :name "custom"
                    :colors colors)))
        (setf (gethash :command colors) "FF0000")
        (expect "00AFFF" :to-equal (nshell.domain.configuration:theme-color theme :command)))))

  (it "default-theme-creation"
    "Default theme has all expected colors"
    (let ((theme (nshell.domain.configuration:default-theme)))
      (expect (nshell.domain.configuration:theme-p theme) :to-be-truthy)
      (expect (stringp (nshell.domain.configuration:theme-color theme :command)) :to-be-truthy)
      (expect (stringp (nshell.domain.configuration:theme-color theme :error)) :to-be-truthy)
      (expect (stringp (nshell.domain.configuration:theme-color theme :autosuggestion)) :to-be-truthy)))

  (it "theme-color-missing"
    "Unknown color keys return nil"
    (let ((theme (nshell.domain.configuration:default-theme)))
      (expect (nshell.domain.configuration:theme-color theme :nonexistent) :to-be-null)))

  (it "theme-set-color"
    "Can set and retrieve custom color"
    (let ((theme (nshell.domain.configuration:make-theme :name "test")))
      (nshell.domain.configuration:theme-set-color theme :custom "FF00FF")
      (expect "FF00FF" :to-equal (nshell.domain.configuration:theme-color theme :custom))))

  (it "default-config"
    "Default config has sensible values"
    (let ((cfg (nshell.domain.configuration:default-config)))
      (expect (nshell.domain.configuration:config-p cfg) :to-be-truthy)
      (expect (nshell.domain.configuration:theme-p (nshell.domain.configuration:config-theme cfg)) :to-be-truthy)))

  (it "prompt-model-creation"
    "Prompt model can be created"
    (let ((pm (nshell.domain.prompting:make-prompt-model
               :hostname "myhost" :cwd "/home/user" :exit-code 0)))
      (expect "myhost" :to-equal (nshell.domain.prompting:prompt-model-hostname pm))
      (expect "/home/user" :to-equal (nshell.domain.prompting:prompt-model-cwd pm))
      (expect 0 :to-equal (nshell.domain.prompting:prompt-model-exit-code pm))))

  (it "render-prompt-model-default"
    "Rendering prompt model produces non-empty result"
    (let* ((pm (nshell.domain.prompting:make-prompt-model
                :hostname "test" :cwd "/tmp" :exit-code 0))
           (result (nshell.domain.prompting:render-prompt-model pm)))
      (expect (consp result) :to-be-truthy)
      (expect (car result) :to-be-type-of 'nshell.domain.prompting:prompt-segment)
      (expect (stringp (nshell.domain.prompting:prompt-segment-text (car result))) :to-be-truthy)))

  (it "prompt-with-error-exit-code"
    "Prompt model with non-zero exit code renders correctly"
    (let* ((pm (nshell.domain.prompting:make-prompt-model
                :hostname "test" :cwd "/" :exit-code 1))
           (result (nshell.domain.prompting:render-prompt-model pm)))
      (expect (consp result) :to-be-truthy))))
