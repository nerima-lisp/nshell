(in-package #:nshell.domain.parsing)

(defstruct (%here-doc-delimiter-scan
            (:constructor %make-here-doc-delimiter-scan
                (reversed-delimiters))
            (:copier nil))
  (reversed-delimiters '() :type list :read-only t))

(defstruct (%here-doc-line
            (:constructor %make-here-doc-line
                (text next-position newline-p))
            (:copier nil))
  (text "" :type string :read-only t)
  (next-position nil :read-only t)
  (newline-p nil :type boolean :read-only t))

(defstruct (%here-doc-body
            (:constructor %make-here-doc-body
                (body next-position missing-delimiter-p))
            (:copier nil))
  (body "" :type string :read-only t)
  (next-position nil :read-only t)
  (missing-delimiter-p nil :type boolean :read-only t))

(defstruct (%here-doc-consumption
            (:constructor %make-here-doc-consumption
                (bodies next-position incomplete-p))
            (:copier nil))
  (bodies '() :type list :read-only t)
  (next-position nil :read-only t)
  (incomplete-p nil :type boolean :read-only t))

(defstruct (%here-doc-consumption-state
            (:constructor %make-here-doc-consumption-state
                (reversed-bodies next-position incomplete-p))
            (:copier nil))
  (reversed-bodies '() :type list :read-only t)
  (next-position nil :read-only t)
  (incomplete-p nil :type boolean :read-only t))
