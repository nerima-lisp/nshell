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

(defparameter +input-redirect-kinds+ '(:< :<< :<<<)
  "Redirect kinds that provide input to a command stage.")

(defparameter +output-redirect-kinds+ '(:> :>> :&> :&>>)
  "Redirect kinds that capture output from a command stage.")

(defparameter +stderr-redirect-kinds+ '(:2> :2>> :2>&1 :&> :&>>)
  "Redirect kinds that affect the standard error stream.")

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

(defun redirect-input-kind-p (kind)
  (not (null (member kind +input-redirect-kinds+ :test #'eq))))

(defun redirect-output-kind-p (kind)
  (not (null (member kind +output-redirect-kinds+ :test #'eq))))

(defun redirect-stderr-kind-p (kind)
  (not (null (member kind +stderr-redirect-kinds+ :test #'eq))))

(defun redirect-append-kind-p (kind)
  (not (null (member kind '(:>> :2>> :&>>) :test #'eq))))

(defun %redirect-mode (kind)
  (if (redirect-append-kind-p kind) :append :supersede))

(defun %last-redirect-matching (redirects predicate)
  (find-if (lambda (redirect)
             (and redirect
                  (funcall predicate (car redirect))))
           redirects :from-end t))

(defun redirect-input-spec (redirects)
  "Return the last input redirect from REDIRECTS, or NIL."
  (%last-redirect-matching redirects #'redirect-input-kind-p))

(defun redirect-input-file-target (redirects)
  "Return the file path for the last :< input redirect, or NIL."
  (let ((redirect (redirect-input-spec redirects)))
    (when (and redirect (eq (car redirect) :<))
      (cdr redirect))))

(defun redirect-output-spec (redirects)
  "Return (target mode) for the last stdout redirect, or NIL."
  (let ((redirect (%last-redirect-matching redirects #'redirect-output-kind-p)))
    (when redirect
      (values (cdr redirect) (%redirect-mode (car redirect))))))

(defun redirect-stderr-spec (redirects)
  "Return (kind target mode) for stderr handling: :MERGE, :FILE, or NIL."
  (let ((redirect (%last-redirect-matching redirects #'redirect-stderr-kind-p)))
    (when redirect
      (case (car redirect)
        (:2>&1 (values :merge nil nil))
        ((:2> :2>> :&> :&>>)
         (values :file (cdr redirect) (%redirect-mode (car redirect))))))))

(defun redirect-output-p (redirects)
  (not (null (%last-redirect-matching redirects #'redirect-output-kind-p))))

(defun redirect-output-destinations (redirects)
  "Return stdout/stderr file destinations as four values.
The values are stdout-target, stdout-mode, stderr-target, and stderr-mode after
applying REDIRECTS from left to right."
  (let ((stdout-target nil)
        (stdout-mode :supersede)
        (stderr-target nil)
        (stderr-mode :supersede))
    (dolist (redirect redirects)
      (case (car redirect)
        ((:> :>>)
         (setf stdout-target (cdr redirect)
               stdout-mode (%redirect-mode (car redirect))))
        ((:&> :&>>)
         (let ((mode (%redirect-mode (car redirect))))
           (setf stdout-target (cdr redirect)
                 stdout-mode mode
                 stderr-target (cdr redirect)
                 stderr-mode mode)))
        ((:2> :2>>)
         (setf stderr-target (cdr redirect)
               stderr-mode (%redirect-mode (car redirect))))
        (:2>&1
         (setf stderr-target stdout-target
               stderr-mode stdout-mode))
        (t nil)))
    (values stdout-target stdout-mode stderr-target stderr-mode)))

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
