; Derived fact and rule generators: build completion data from the static catalogs.
(in-package #:nshell.domain.completion)

(defun %catalog-subcommand-name (subcommand)
  (if (consp subcommand)
      (getf subcommand :name)
      subcommand))

(defun %catalog-subcommand-description (subcommand)
  (when (consp subcommand)
    (getf subcommand :description)))

(defun %catalog-command (entry)
  (getf entry :command))

(defun %catalog-description (entry)
  (getf entry :description))

(defun %catalog-synopsis (entry)
  (getf entry :synopsis))

(defun %catalog-subcommands (entry)
  (getf entry :subcommands))

(defun %catalog-flags (entry)
  (getf entry :flags))

(defun %catalog-option-values (entry)
  (getf entry :option-values))

(defun %catalog-exclusive-options (entry)
  (getf entry :exclusive-options))

(defstruct (%catalog-command-projection
            (:constructor %make-catalog-command-projection
                (&key command description synopsis subcommands flags option-values
                      exclusive-options))
            (:conc-name %catalog-command-projection-))
  command
  description
  synopsis
  subcommands
  flags
  option-values
  exclusive-options)

(defun %catalog-entry-command-projection (entry)
  (%make-catalog-command-projection
   :command (%catalog-command entry)
   :description (%catalog-description entry)
   :synopsis (%catalog-synopsis entry)
   :subcommands (%catalog-subcommands entry)
   :flags (%catalog-flags entry)
   :option-values (%catalog-option-values entry)
   :exclusive-options (%catalog-exclusive-options entry)))

(defun %catalog-command-projections (catalog)
  (mapcar #'%catalog-entry-command-projection catalog))

(defun %catalog-command-fact (projection)
  (let ((command (%catalog-command-projection-command projection)))
    (list 'completes command command)))

(defun %catalog-description-fact (projection)
  (list 'describes
        (%catalog-command-projection-command projection)
        (%catalog-command-projection-description projection)))

(defun %catalog-flag-facts (projection)
  (let ((command (%catalog-command-projection-command projection)))
    (mapcar (lambda (flag)
              (list 'has-flag command flag))
            (%catalog-command-projection-flags projection))))

(defun %catalog-subcommand-completion-facts (projection)
  (let ((command (%catalog-command-projection-command projection)))
    (mapcar (lambda (subcommand)
              (list 'completes command
                    (%catalog-subcommand-name subcommand)))
            (%catalog-command-projection-subcommands projection))))

(defun %catalog-subcommand-description-facts (projection)
  (mapcan (lambda (subcommand)
            (let ((name (%catalog-subcommand-name subcommand))
                  (description (%catalog-subcommand-description subcommand)))
              (when description
                (list (list 'describes name description)))))
          (%catalog-command-projection-subcommands projection)))

(defun %catalog-command-rule-facts (projection)
  (list (%catalog-command-fact projection)
        (%catalog-description-fact projection)))

(defun %catalog-command-with-subcommand-rule-facts (projection)
  (append (%catalog-command-rule-facts projection)
          (%catalog-subcommand-completion-facts projection)
          (%catalog-subcommand-description-facts projection)
          (%catalog-flag-facts projection)))

(defun %catalog-help-entry (projection)
  (list :command (%catalog-command-projection-command projection)
        :synopsis (%catalog-command-projection-synopsis projection)
        :description (%catalog-command-projection-description projection)))

(defun %catalog-completion-metadata (projection)
  (append (when (%catalog-command-projection-subcommands projection)
            (list :subcommands
                  (mapcar #'%catalog-subcommand-name
                          (%catalog-command-projection-subcommands projection))))
          (when (%catalog-command-projection-flags projection)
            (list :flags (%catalog-command-projection-flags projection)))
          (when (%catalog-command-projection-option-values projection)
            (list :option-values (%catalog-command-projection-option-values projection)))
          (when (%catalog-command-projection-exclusive-options projection)
            (list :exclusive-options
                  (%catalog-command-projection-exclusive-options projection)))
          (when (%catalog-command-projection-description projection)
            (list :description (%catalog-command-projection-description projection)))))

(defun %catalog-completion-command-spec (projection)
  (append (list (%catalog-command-projection-command projection))
          (%catalog-completion-metadata projection)))

(defun %builtin-command-flag-facts ()
  (mapcan #'%catalog-flag-facts
          (%catalog-command-projections +builtin-command-catalog+)))

(defun %external-command-rule-facts ()
  (mapcan #'%catalog-command-with-subcommand-rule-facts
          (%catalog-command-projections +external-command-catalog+)))

(defun builtin-help-entries ()
  (mapcar #'%catalog-help-entry
          (%catalog-command-projections +builtin-command-catalog+)))

(defun %completion-command-specs-from-catalog (catalog)
  (mapcar #'%catalog-completion-command-spec
          (%catalog-command-projections catalog)))

(defun builtin-completion-command-specs ()
  (%completion-command-specs-from-catalog +builtin-command-catalog+))

(defun external-completion-command-specs ()
  (%completion-command-specs-from-catalog +external-command-catalog+))

(defun builtin-rule-facts ()
  (append
   '((command-is "cd" "cd")
     (command-is "source" "source")
     (command-is "." "source"))
   (mapcan #'%catalog-command-rule-facts
           (%catalog-command-projections +builtin-command-catalog+))
   (%builtin-command-flag-facts)
   (%external-command-rule-facts)
   '((describes "--help" "show command help"))))

(defun builtin-rule-rules ()
  '(((suggests-dir ?input)
     (command-is ?input "cd"))
    ((completes ?cmd "--help")
     (has-flag ?cmd "--help"))
    ((completes ?cmd ?flag)
     (has-flag ?cmd ?flag))
    ((suggests-file ?input)
     (command-is ?input "source"))))
