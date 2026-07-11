; Catalog construction helpers for completion data.
(in-package #:nshell.domain.completion)

(defun %catalog-source-entry-property-values (entry property)
  (loop for (key value) on entry by #'cddr
        when (eq key property)
          return (values key value t)
        finally (return (values property nil nil))))

(defun %catalog-source-entry-property-present-p (entry property)
  (nth-value 2 (%catalog-source-entry-property-values entry property)))

(defun %catalog-source-entry-property-value (entry property)
  (nth-value 1 (%catalog-source-entry-property-values entry property)))

(defun %catalog-source-entry-command (entry)
  (%catalog-source-entry-property-value entry :command))

(defun %catalog-source-entry-property (entry property)
  (when (%catalog-source-entry-property-present-p entry property)
    (list property (%catalog-source-entry-property-value entry property))))

(defstruct (%catalog-command-entry
            (:constructor %make-catalog-command-entry
                (&key command synopsis description subcommands flags option-values
                      exclusive-options))
            (:conc-name %catalog-command-entry-))
  command
  synopsis
  description
  subcommands
  flags
  option-values
  exclusive-options)

(defun %catalog-entry-property-value (entry property)
  (ecase property
    (:command (%catalog-command-entry-command entry))
    (:synopsis (%catalog-command-entry-synopsis entry))
    (:description (%catalog-command-entry-description entry))
    (:subcommands (%catalog-command-entry-subcommands entry))
    (:flags (%catalog-command-entry-flags entry))
    (:option-values (%catalog-command-entry-option-values entry))
    (:exclusive-options (%catalog-command-entry-exclusive-options entry))))

(defun %catalog-entry-command (entry)
  (%catalog-entry-property-value entry :command))

(defun %build-command-catalog-entry (entry)
  (let ((command (%catalog-source-entry-command entry)))
    (unless (stringp command)
      (error "Command catalog entry requires a string :command: ~S" entry))
    (%make-catalog-command-entry
     :command command
     :synopsis (%catalog-source-entry-property-value entry :synopsis)
     :description (%catalog-source-entry-property-value entry :description)
     :subcommands (%catalog-source-entry-property-value entry :subcommands)
     :flags (%catalog-source-entry-property-value entry :flags)
     :option-values (%catalog-source-entry-property-value entry :option-values)
     :exclusive-options (%catalog-source-entry-property-value entry :exclusive-options))))

(defun %command-catalog (entries)
  (mapcar #'%build-command-catalog-entry entries))
