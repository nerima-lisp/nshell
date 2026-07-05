(in-package #:nshell/test)

(def-suite configuration-domain-tests
  :description "Configuration and prompt domain tests"
  :in nshell-tests)

(in-suite configuration-domain-tests)

(test configuration-raw-constructors-are-internal-boundaries
  "Configuration public factories wrap internal raw constructors"
  (let ((theme (nshell.domain.configuration:make-theme :name "custom"))
        (config (nshell.domain.configuration:make-config)))
    (is (nshell.domain.configuration:theme-p theme))
    (is (string= "custom" (nshell.domain.configuration:theme-name theme)))
    (is (nshell.domain.configuration:config-p config))
    (is (nshell.domain.configuration:theme-p (nshell.domain.configuration:config-theme config)))
    (is (string= "[%u@%h %w]> " (nshell.domain.configuration:config-prompt config)))
    (is (not (fboundp 'nshell.domain.configuration::theme-colors)))
    (is (not (fboundp 'nshell.domain.configuration::copy-theme)))
    (is (not (fboundp 'nshell.domain.configuration::%make-theme)))
    (is (fboundp 'nshell.domain.configuration::%allocate-theme))
    (is (not (fboundp 'nshell.domain.configuration::config-prompt-format)))
    (is (not (fboundp 'nshell.domain.configuration::copy-config)))
    (is (not (fboundp 'nshell.domain.configuration::%make-config)))
    (is (fboundp 'nshell.domain.configuration::%allocate-config))))

(test config-construction-validates-aggregate-values
  "Configuration construction accepts only valid aggregate values."
  (signals type-error
    (nshell.domain.configuration:make-config :theme nil))
  (signals type-error
    (nshell.domain.configuration:make-config :prompt-format 42)))

(test theme-colors-are-detached-from-constructor-input
  "Theme construction owns the mutable color table."
  (let ((colors (make-hash-table :test #'eq)))
    (setf (gethash :command colors) "00AFFF")
    (let ((theme (nshell.domain.configuration:make-theme
                  :name "custom"
                  :colors colors)))
      (setf (gethash :command colors) "FF0000")
      (is (string= "00AFFF"
                   (nshell.domain.configuration:theme-color theme :command))))))

(test default-theme-creation
  "Default theme has all expected colors"
  (let ((theme (nshell.domain.configuration:default-theme)))
    (is (nshell.domain.configuration:theme-p theme))
    (is (stringp (nshell.domain.configuration:theme-color theme :command)))
    (is (stringp (nshell.domain.configuration:theme-color theme :error)))
    (is (stringp (nshell.domain.configuration:theme-color theme :autosuggestion)))))

(test theme-color-missing
  "Unknown color keys return nil"
  (let ((theme (nshell.domain.configuration:default-theme)))
    (is (null (nshell.domain.configuration:theme-color theme :nonexistent)))))

(test theme-set-color
  "Can set and retrieve custom color"
  (let ((theme (nshell.domain.configuration:make-theme :name "test")))
    (nshell.domain.configuration:theme-set-color theme :custom "FF00FF")
    (is (string= "FF00FF" (nshell.domain.configuration:theme-color theme :custom)))))

(test default-config
  "Default config has sensible values"
  (let ((cfg (nshell.domain.configuration:default-config)))
    (is (nshell.domain.configuration:config-p cfg))
    (is (nshell.domain.configuration:theme-p (nshell.domain.configuration:config-theme cfg)))))

(test prompt-model-creation
  "Prompt model can be created"
  (let ((pm (nshell.domain.prompting:make-prompt-model
             :hostname "myhost" :cwd "/home/user" :exit-code 0)))
    (is (string= "myhost" (nshell.domain.prompting:prompt-model-hostname pm)))
    (is (string= "/home/user" (nshell.domain.prompting:prompt-model-cwd pm)))
    (is (= 0 (nshell.domain.prompting:prompt-model-exit-code pm)))))

(test render-prompt-model-default
  "Rendering prompt model produces non-empty result"
  (let* ((pm (nshell.domain.prompting:make-prompt-model
              :hostname "test" :cwd "/tmp" :exit-code 0))
         (result (nshell.domain.prompting:render-prompt-model pm)))
    (is (consp result))
    (is (typep (car result) 'nshell.domain.prompting:prompt-segment))
    (is (stringp (nshell.domain.prompting:prompt-segment-text (car result))))))

(test prompt-with-error-exit-code
  "Prompt model with non-zero exit code renders correctly"
  (let* ((pm (nshell.domain.prompting:make-prompt-model
              :hostname "test" :cwd "/" :exit-code 1))
         (result (nshell.domain.prompting:render-prompt-model pm)))
    (is (consp result))))
