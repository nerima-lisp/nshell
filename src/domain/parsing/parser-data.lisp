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

(defparameter +separator-rules+
  '((:pipe :token-type :pipe :text "|" :continues t)
    (:and :token-type :and :text "&&" :continues t)
    (:or :token-type :or :text "||" :continues t)
    (:semi :token-type :semicolon :text ";")
    (:semi :token-type :newline :text "newline")
    (:amp :token-type :ampersand :text "&")))

(defun %separator-rule (separator)
  (find separator +separator-rules+ :key #'first :test #'eq))

(defun %separator-from-token-type (token-type)
  (first (find token-type +separator-rules+
               :key (lambda (rule) (getf (rest rule) :token-type))
               :test #'eq)))

(defun %continuation-separator-p (separator)
  (not (null (getf (rest (%separator-rule separator)) :continues))))

(defun %separator-text (separator)
  (or (getf (rest (%separator-rule separator)) :text)
      (string-downcase (symbol-name separator))))
