(in-package #:nshell.feature.command-line)

;;; The infrastructure boundary is the only feature layer that knows cl-cli.
;;; The composition root and the presentation layer consume this app spec via
;;; the feature's public functions instead of constructing it themselves.
(defun build-cli-app ()
  "Build the cl-cli application spec describing nshell's command line."
  (cl-cli:make-app
   :name "nshell"
   :summary "fish-inspired shell in Common Lisp"
   :auto-help nil
   :global-options
   (list
    (cl-cli:make-option :key :show-help :name "help" :short #\h :kind :flag
                        :description "Show usage and exit.")
    (cl-cli:make-option :key :show-version :name "version" :short #\V :kind :flag
                        :description "Show version and exit.")
    (cl-cli:make-option :key :command :name "command" :short #\c :kind :value
                        :stop-parsing-p t
                        :description
                        "Execute COMMAND once in batch mode; ARGS become $argv."))
   :positionals
   ;; Only reached via the `-c` stop-parsing tail; a leading SCRIPT is handled
   ;; before parsing by the composition root to preserve its arguments.
   (list (cl-cli:make-positional :key :command-args :rest-p t))))
