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

(defstruct (%redirect-kind-facts
            (:constructor %make-redirect-kind-facts
                (kind input-p output-p stderr-p append-p)))
  kind
  input-p
  output-p
  stderr-p
  append-p)

(defstruct (%redirect-entry
            (:constructor %make-redirect-entry (kind target)))
  kind
  target)

(defparameter +redirect-kind-fact-specs+
  '((:< t nil nil nil)
    (:<< t nil nil nil)
    (:<<< t nil nil nil)
    (:> nil t nil nil)
    (:>> nil t nil t)
    (:2> nil nil t nil)
    (:2>> nil nil t t)
    (:2>&1 nil nil t nil)
    (:&> nil t t nil)
    (:&>> nil t t t)))

(defun %redirect-spec-entry (text)
  (let ((spec (and text
                   (assoc text +redirect-specs+ :test #'string=))))
    (when spec
      (%make-redirect-spec-entry (car spec) (cdr spec)))))

(defun %redirect-entry-from-raw (redirect)
  (when redirect
    (%make-redirect-entry (car redirect) (cdr redirect))))

(defun %redirect-facts (text)
  (let ((entry (%redirect-spec-entry text)))
    (when entry
      (let ((kind (%redirect-spec-entry-kind entry)))
        (%make-redirect-facts
         (%redirect-spec-entry-text entry)
         kind
         (not (null (member kind +redirect-fd-dup-specs+
                            :test #'eq))))))))

(defun %redirect-target-policy-from-facts (facts)
  (when facts
    (%make-redirect-target-policy
     (%redirect-facts-kind facts)
     (not (%redirect-facts-fd-dup-p facts)))))

(defun %redirect-target-policy (text)
  (%redirect-target-policy-from-facts (%redirect-facts text)))

(defun %redirect-target-required-p (text)
  (let ((policy (%redirect-target-policy text)))
    (and policy
         (%redirect-target-policy-target-required-p policy))))

(defun %redirect-targetless-p (text)
  (let ((policy (%redirect-target-policy text)))
    (and policy
         (not (%redirect-target-policy-target-required-p policy)))))

(defun %redirect-kind-facts (kind)
  (let ((spec (and kind
                   (assoc kind +redirect-kind-fact-specs+ :test #'eq))))
    (when spec
      (destructuring-bind (stored-kind input-p output-p stderr-p append-p)
          spec
        (%make-redirect-kind-facts
         stored-kind
         input-p
         output-p
         stderr-p
         append-p)))))

(defun redirect-input-kind-p (kind)
  (let ((facts (%redirect-kind-facts kind)))
    (and facts
         (%redirect-kind-facts-input-p facts))))

(defun redirect-output-kind-p (kind)
  (let ((facts (%redirect-kind-facts kind)))
    (and facts
         (%redirect-kind-facts-output-p facts))))

(defun redirect-stderr-kind-p (kind)
  (let ((facts (%redirect-kind-facts kind)))
    (and facts
         (%redirect-kind-facts-stderr-p facts))))

(defun redirect-append-kind-p (kind)
  (let ((facts (%redirect-kind-facts kind)))
    (and facts
         (%redirect-kind-facts-append-p facts))))

(defun %redirect-mode (kind)
  (let ((facts (%redirect-kind-facts kind)))
    (if (and facts
             (%redirect-kind-facts-append-p facts))
        :append
        :supersede)))

(defun %last-redirect-entry-matching (redirects predicate)
  (loop for redirect in (reverse redirects)
        for entry = (%redirect-entry-from-raw redirect)
        when (and entry
                  (funcall predicate (%redirect-entry-kind entry)))
          return entry))

(defun map-redirect-entries (function redirects)
  "Call FUNCTION with kind and target for each redirect in REDIRECTS."
  (dolist (redirect redirects)
    (let ((entry (%redirect-entry-from-raw redirect)))
      (when entry
        (funcall function
                 (%redirect-entry-kind entry)
                 (%redirect-entry-target entry)))))
  nil)

(defun redirect-input-spec (redirects)
  "Return kind and target for the last input redirect in REDIRECTS."
  (let ((entry (%last-redirect-entry-matching redirects #'redirect-input-kind-p)))
    (when entry
      (values (%redirect-entry-kind entry)
              (%redirect-entry-target entry)))))

(defun redirect-input-file-target (redirects)
  "Return the file path for the last :< input redirect, or NIL."
  (let ((entry (%last-redirect-entry-matching redirects #'redirect-input-kind-p)))
    (when (and entry (eq (%redirect-entry-kind entry) :<))
      (%redirect-entry-target entry))))

(defun redirect-output-spec (redirects)
  "Return (target mode) for the last stdout redirect, or NIL."
  (let ((entry (%last-redirect-entry-matching redirects #'redirect-output-kind-p)))
    (when entry
      (values (%redirect-entry-target entry)
              (%redirect-mode (%redirect-entry-kind entry))))))

(defun redirect-stderr-spec (redirects)
  "Return (kind target mode) for stderr handling: :MERGE, :FILE, or NIL."
  (let ((entry (%last-redirect-entry-matching redirects #'redirect-stderr-kind-p)))
    (when entry
      (case (%redirect-entry-kind entry)
        (:2>&1 (values :merge nil nil))
        ((:2> :2>> :&> :&>>)
         (values :file
                 (%redirect-entry-target entry)
                 (%redirect-mode (%redirect-entry-kind entry))))))))

(defun redirect-output-p (redirects)
  (not (null (%last-redirect-entry-matching redirects #'redirect-output-kind-p))))

(defun redirect-output-destinations (redirects)
  "Return stdout/stderr file destinations as four values.
The values are stdout-target, stdout-mode, stderr-target, and stderr-mode after
applying REDIRECTS from left to right."
  (let ((stdout-target nil)
        (stdout-mode :supersede)
        (stderr-target nil)
        (stderr-mode :supersede))
    (dolist (redirect redirects)
      (let ((entry (%redirect-entry-from-raw redirect)))
        (when entry
          (case (%redirect-entry-kind entry)
            ((:> :>>)
             (setf stdout-target (%redirect-entry-target entry)
                   stdout-mode (%redirect-mode (%redirect-entry-kind entry))))
            ((:&> :&>>)
             (let ((mode (%redirect-mode (%redirect-entry-kind entry))))
               (setf stdout-target (%redirect-entry-target entry)
                     stdout-mode mode
                     stderr-target (%redirect-entry-target entry)
                     stderr-mode mode)))
            ((:2> :2>>)
             (setf stderr-target (%redirect-entry-target entry)
                   stderr-mode (%redirect-mode (%redirect-entry-kind entry))))
            (:2>&1
             (setf stderr-target stdout-target
                   stderr-mode stdout-mode))
            (t nil)))))
    (values stdout-target stdout-mode stderr-target stderr-mode)))

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

(defparameter +separator-rules+
  (list (%make-separator-rule-entry :pipe :pipe "|" t)
        (%make-separator-rule-entry :and :and "&&" t)
        (%make-separator-rule-entry :or :or "||" t)
        (%make-separator-rule-entry :semi :semicolon ";" nil)
        (%make-separator-rule-entry :semi :newline "newline" nil)
        (%make-separator-rule-entry :amp :ampersand "&" nil)))

(defun %separator-rule (separator)
  (find separator +separator-rules+
        :key #'%separator-rule-entry-kind
        :test #'eq))

(defun %separator-rule-entry (separator)
  (or (%separator-rule separator)
      (and separator
           (%make-separator-rule-entry
            separator
            nil
            (string-downcase (symbol-name separator))
            nil))))

(defun %separator-rule-entry-from-token-type (token-type)
  (when token-type
    (loop for entry in +separator-rules+
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

(defstruct (%reduced-command-entry
            (:constructor %make-reduced-command-entry
                (command separator separator-token)))
  (command nil :read-only t)
  (separator nil :read-only t)
  (separator-token nil :read-only t))

(defun %reduced-command-entry-from-reducer-entry (entry)
  (destructuring-bind (command separator separator-token) entry
    (%make-reduced-command-entry command separator separator-token)))

(defun %reduced-command-entries-from-reducer-entries (entries)
  (mapcar #'%reduced-command-entry-from-reducer-entry entries))
