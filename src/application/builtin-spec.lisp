(in-package #:nshell.application)

(defun %builtin-string-subcommand-specs (&key manipulation-only-p)
  (if manipulation-only-p
      (remove-if-not #'%builtin-string-spec-manipulation-p
                     +builtin-string-subcommand-specs+)
      +builtin-string-subcommand-specs+))

(defun %builtin-string-subcommand-spec (subcommand)
  (find subcommand +builtin-string-subcommand-specs+
        :key #'%builtin-string-spec-name
        :test #'string=))
