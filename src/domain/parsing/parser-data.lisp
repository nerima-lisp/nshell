(in-package #:nshell.domain.parsing)

(defparameter +redirect-specs+
  '((">" . :>)
    (">>" . :>>)
    ("<" . :<)
    ("<<" . :<<)
    ("<<<" . :<<<)
    ("1>" . :>)
    ("1>>" . :>>)
    ("2>" . :2>)
    ("2>>" . :2>>)
    ("2>&1" . :2>&1)
    ("&>" . :&>)
    ("&>>" . :&>>)))

(defparameter +redirect-fd-dup-specs+
  '(:2>&1)
  "Redirect specs that duplicate a descriptor and so take no file target.")

(defstruct (%redirect-spec-entry
            (:constructor %make-redirect-spec-entry (text kind)))
  text
  kind)

(defstruct (%redirect-facts
            (:constructor %make-redirect-facts
                (text kind fd-dup-p)))
  text
  kind
  fd-dup-p)

(defstruct (%redirect-target-policy
            (:constructor %make-redirect-target-policy
                (kind target-required-p)))
  kind
  target-required-p)

(defun %redirect-spec-entry (text)
  (let ((spec (and text
                   (assoc text +redirect-specs+ :test #'string=))))
    (when spec
      (%make-redirect-spec-entry (car spec) (cdr spec)))))

(defun %redirect-facts (text)
  (let ((entry (%redirect-spec-entry text)))
    (when entry
      (let ((kind (%redirect-spec-entry-kind entry)))
        (%make-redirect-facts
         (%redirect-spec-entry-text entry)
         kind
         (not (null (member kind +redirect-fd-dup-specs+
                            :test #'eq))))))))

(defun %redirect-target-policy-from-kind (kind)
  (when kind
    (%make-redirect-target-policy
     kind
     (null (member kind +redirect-fd-dup-specs+ :test #'eq)))))

(defun %redirect-target-policy (text)
  (let ((facts (%redirect-facts text)))
    (and facts
         (%redirect-target-policy-from-kind
          (%redirect-facts-kind facts)))))

(defun %redirect-target-required-p (text)
  (let ((policy (%redirect-target-policy text)))
    (and policy
         (%redirect-target-policy-target-required-p policy))))

(defun %redirect-targetless-p (text)
  (let ((policy (%redirect-target-policy text)))
    (and policy
         (not (%redirect-target-policy-target-required-p policy)))))

(defparameter +separator-rules+
  '((:pipe :token-type :pipe :text "|" :continues t)
    (:and :token-type :and :text "&&" :continues t)
    (:or :token-type :or :text "||" :continues t)
    (:semi :token-type :semicolon :text ";")
    (:semi :token-type :newline :text "newline")
    (:amp :token-type :ampersand :text "&")))

(defstruct (%separator-facts
            (:constructor %make-separator-facts
                (kind token-type text continues-p)))
  kind
  token-type
  text
  continues-p)

(defstruct (%separator-rule-entry
            (:constructor %make-separator-rule-entry
                (kind token-type text continues-p)))
  kind
  token-type
  text
  continues-p)

(defun %separator-rule-entry-from-rule (rule)
  (when rule
    (let ((data (rest rule)))
      (%make-separator-rule-entry
       (first rule)
       (getf data :token-type)
       (getf data :text)
       (not (null (getf data :continues)))))))

(defun %separator-rule (separator)
  (find separator +separator-rules+ :key #'first :test #'eq))

(defun %separator-rule-entry (separator)
  (or (%separator-rule-entry-from-rule (%separator-rule separator))
      (and separator
           (%make-separator-rule-entry
            separator
            nil
            (string-downcase (symbol-name separator))
            nil))))

(defun %separator-rule-entry-from-token-type (token-type)
  (when token-type
    (loop for rule in +separator-rules+
          for entry = (%separator-rule-entry-from-rule rule)
          when (eq token-type (%separator-rule-entry-token-type entry))
            return entry)))

(defun %separator-from-token-type (token-type)
  (let ((entry (%separator-rule-entry-from-token-type token-type)))
    (and entry
         (%separator-rule-entry-kind entry))))

(defun %separator-facts (separator)
  (let ((entry (%separator-rule-entry separator)))
    (and entry
         (%make-separator-facts
          (%separator-rule-entry-kind entry)
          (%separator-rule-entry-token-type entry)
          (%separator-rule-entry-text entry)
          (%separator-rule-entry-continues-p entry)))))

(defun %continuation-separator-p (separator)
  (let ((facts (%separator-facts separator)))
    (and facts
         (%separator-facts-continues-p facts))))

(defun %separator-text (separator)
  (let ((facts (%separator-facts separator)))
    (and facts
         (%separator-facts-text facts))))
