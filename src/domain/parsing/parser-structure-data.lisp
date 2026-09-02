(in-package #:nshell.domain.parsing)

(defstruct (%command-list-components
            (:constructor %make-command-list-components
                (commands separators separator-tokens))
            (:copier nil))
  (commands nil :type list :read-only t)
  (separators nil :type list :read-only t)
  (separator-tokens nil :type list :read-only t))

(defstruct (%reduced-command-stream
            (:constructor %make-reduced-command-stream
                (commands separators separator-tokens ast))
            (:copier nil))
  (commands nil :type list :read-only t)
  (separators nil :type list :read-only t)
  (separator-tokens nil :type list :read-only t)
  (ast nil :read-only t))

(defstruct (%structural-diagnostics
            (:constructor %make-structural-diagnostics
                (incomplete-p diagnostics))
            (:copier nil))
  (incomplete-p nil :type boolean :read-only t)
  (diagnostics nil :type list :read-only t))

(defstruct (%structural-diagnostics-accumulator
            (:constructor %make-structural-diagnostics-accumulator
                (&key (incomplete-p nil) (diagnostics nil)))
            (:copier nil))
  (incomplete-p nil :type boolean)
  (diagnostics nil :type list))

(defstruct (%structural-diagnostics-input
            (:constructor %make-structural-diagnostics-input
                (commands last-separator last-separator-token input-length))
            (:copier nil))
  (commands nil :type list :read-only t)
  (last-separator nil :read-only t)
  (last-separator-token nil :read-only t)
  (input-length 0 :type integer :read-only t))
