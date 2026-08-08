(in-package #:nshell.domain.parsing)

(defstruct (%redirect-spec-entry
            (:constructor %make-redirect-spec-entry (text kind)))
  text
  kind)

(defparameter +redirect-specs+
  (list
   (%make-redirect-spec-entry ">" :>)
   (%make-redirect-spec-entry ">>" :>>)
   (%make-redirect-spec-entry "<" :<)
   (%make-redirect-spec-entry "<<" :<<)
   (%make-redirect-spec-entry "<<-" :<<-)
   (%make-redirect-spec-entry "<<<" :<<<)
   (%make-redirect-spec-entry "1>" :>)
   (%make-redirect-spec-entry "1>>" :>>)
   (%make-redirect-spec-entry "2>" :2>)
   (%make-redirect-spec-entry "2>>" :2>>)
   (%make-redirect-spec-entry "2>&1" :2>&1)
   (%make-redirect-spec-entry "&>" :&>)
   (%make-redirect-spec-entry "&>>" :&>>)))

(defparameter +redirect-fd-dup-specs+
  '(:2>&1)
  "Redirect specs that duplicate a descriptor and so take no file target.")

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

(defstruct (%redirect-kind-fact-spec
            (:constructor %make-redirect-kind-fact-spec
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

(defstruct (%redirect-output-destination-state
            (:constructor %make-redirect-output-destination-state
                (stdout-target stdout-mode stderr-target stderr-mode)))
  stdout-target
  stdout-mode
  stderr-target
  stderr-mode)

(defparameter +redirect-kind-fact-specs+
  (list
   (%make-redirect-kind-fact-spec :< t nil nil nil)
   (%make-redirect-kind-fact-spec :<< t nil nil nil)
   (%make-redirect-kind-fact-spec :<<- t nil nil nil)
   (%make-redirect-kind-fact-spec :<<< t nil nil nil)
   (%make-redirect-kind-fact-spec :> nil t nil nil)
   (%make-redirect-kind-fact-spec :>> nil t nil t)
   (%make-redirect-kind-fact-spec :2> nil nil t nil)
   (%make-redirect-kind-fact-spec :2>> nil nil t t)
   (%make-redirect-kind-fact-spec :2>&1 nil nil t nil)
   (%make-redirect-kind-fact-spec :&> nil t t nil)
   (%make-redirect-kind-fact-spec :&>> nil t t t)))

(defun %redirect-spec-entry (text)
  (and text
       (find text +redirect-specs+
             :key #'%redirect-spec-entry-text
             :test #'string=)))

(defun %redirect-entry-from-raw (redirect)
  (when redirect
    (%make-redirect-entry (car redirect) (cdr redirect))))

(defun %redirect-entries-from-raw (redirects)
  (loop for redirect in redirects
        for entry = (%redirect-entry-from-raw redirect)
        when entry
          collect entry))

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

(defun %redirect-kind-fact-spec (kind)
  (and kind
       (find kind +redirect-kind-fact-specs+
             :key #'%redirect-kind-fact-spec-kind
             :test #'eq)))

(defun %redirect-kind-facts-from-spec (spec)
  (when spec
    (%make-redirect-kind-facts
     (%redirect-kind-fact-spec-kind spec)
     (%redirect-kind-fact-spec-input-p spec)
     (%redirect-kind-fact-spec-output-p spec)
     (%redirect-kind-fact-spec-stderr-p spec)
     (%redirect-kind-fact-spec-append-p spec))))

(defun %redirect-kind-facts (kind)
  (let ((spec (%redirect-kind-fact-spec kind)))
    (when spec
      (%redirect-kind-facts-from-spec spec))))

(defmacro %define-redirect-kind-predicate (name accessor)
  `(defun ,name (kind)
     (let ((facts (%redirect-kind-facts kind)))
       (and facts
            (,accessor facts)))))

(%define-redirect-kind-predicate redirect-input-kind-p
  %redirect-kind-facts-input-p)
(%define-redirect-kind-predicate redirect-output-kind-p
  %redirect-kind-facts-output-p)
(%define-redirect-kind-predicate redirect-stderr-kind-p
  %redirect-kind-facts-stderr-p)
(%define-redirect-kind-predicate redirect-append-kind-p
  %redirect-kind-facts-append-p)

(defun %redirect-mode (kind)
  (let ((facts (%redirect-kind-facts kind)))
    (if (and facts
             (%redirect-kind-facts-append-p facts))
        :append
        :supersede)))

(defun %last-redirect-entry-matching (redirects predicate)
  (loop for entry in (reverse (%redirect-entries-from-raw redirects))
        when (funcall predicate (%redirect-entry-kind entry))
          return entry))

(defun map-redirect-entries (function redirects)
  "Call FUNCTION with kind and target for each redirect in REDIRECTS."
  (dolist (entry (%redirect-entries-from-raw redirects))
    (funcall function
             (%redirect-entry-kind entry)
             (%redirect-entry-target entry)))
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

(defun %empty-redirect-output-destination-state ()
  (%make-redirect-output-destination-state nil :supersede nil :supersede))

(defstruct (redirect-output-destinations
            (:constructor %make-redirect-output-destinations
                (stdout-target stdout-mode stderr-target stderr-mode)))
  stdout-target
  stdout-mode
  stderr-target
  stderr-mode)

(defun %redirect-output-destinations-from-state (state)
  (%make-redirect-output-destinations
   (%redirect-output-destination-state-stdout-target state)
   (%redirect-output-destination-state-stdout-mode state)
   (%redirect-output-destination-state-stderr-target state)
   (%redirect-output-destination-state-stderr-mode state)))

(defun %redirect-output-destination-state-apply-entry (state kind target)
  (case kind
    ((:> :>>)
     (%make-redirect-output-destination-state
      target
      (%redirect-mode kind)
      (%redirect-output-destination-state-stderr-target state)
      (%redirect-output-destination-state-stderr-mode state)))
    ((:&> :&>>)
     (let ((mode (%redirect-mode kind)))
       (%make-redirect-output-destination-state target mode target mode)))
    ((:2> :2>>)
     (%make-redirect-output-destination-state
      (%redirect-output-destination-state-stdout-target state)
      (%redirect-output-destination-state-stdout-mode state)
      target
      (%redirect-mode kind)))
    (:2>&1
     (%make-redirect-output-destination-state
      (%redirect-output-destination-state-stdout-target state)
      (%redirect-output-destination-state-stdout-mode state)
      (%redirect-output-destination-state-stdout-target state)
      (%redirect-output-destination-state-stdout-mode state)))
    (otherwise state)))

(defun %redirect-output-destination-state-apply-redirect-entry (state entry)
  (%redirect-output-destination-state-apply-entry
   state
   (%redirect-entry-kind entry)
   (%redirect-entry-target entry)))

(defun %redirect-output-destination-state-from-redirects (redirects)
  (reduce #'%redirect-output-destination-state-apply-redirect-entry
          (%redirect-entries-from-raw redirects)
          :initial-value (%empty-redirect-output-destination-state)))

(defun redirect-output-destinations (redirects)
  "Return stdout/stderr file destinations after applying REDIRECTS left to right."
  (%redirect-output-destinations-from-state
   (%redirect-output-destination-state-from-redirects redirects)))
