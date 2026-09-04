(in-package #:nshell.domain.parsing)

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

(defun %redirect-parse-dynamic-fd-dup-target (text separator-text operator)
  (let ((separator (and text (search separator-text text))))
    (when (and separator
               (> separator 0)
               (< (+ separator (length separator-text))
                  (length text)))
      (let ((source-text (subseq text 0 separator))
            (target-text
              (subseq text (+ separator (length separator-text)))))
        (when (and (every #'digit-char-p source-text)
                   (or (string= target-text "-")
                       (every #'digit-char-p target-text)))
          (make-redirect-fd-dup-target
           (parse-integer source-text)
           (if (string= target-text "-")
               :close
               (parse-integer target-text))
           operator))))))

(defun %redirect-dynamic-fd-dup-target (text)
  (or (%redirect-parse-dynamic-fd-dup-target text ">&" :output)
      (%redirect-parse-dynamic-fd-dup-target text "<&" :input)))

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
  (%make-redirect-output-destination-state nil :supersede nil :supersede
                                           :stdout :stderr))

(defun %redirect-output-destinations-from-state (state)
  (%make-redirect-output-destinations
   (%redirect-output-destination-state-stdout-target state)
   (%redirect-output-destination-state-stdout-mode state)
   (%redirect-output-destination-state-stderr-target state)
   (%redirect-output-destination-state-stderr-mode state)
   (%redirect-output-destination-state-stdout-endpoint state)
   (%redirect-output-destination-state-stderr-endpoint state)))

(defun %redirect-file-endpoint (target mode)
  (cons target mode))

(defun %redirect-output-destination-state-apply-entry (state kind target)
  (case kind
    ((:> :>>)
     (let ((endpoint (%redirect-file-endpoint target (%redirect-mode kind))))
       (%make-redirect-output-destination-state
        target
        (%redirect-mode kind)
        (%redirect-output-destination-state-stderr-target state)
        (%redirect-output-destination-state-stderr-mode state)
        endpoint
        (%redirect-output-destination-state-stderr-endpoint state))))
    ((:&> :&>>)
     (let* ((mode (%redirect-mode kind))
            (endpoint (%redirect-file-endpoint target mode)))
       (%make-redirect-output-destination-state target mode target mode
                                                endpoint endpoint)))
    ((:2> :2>>)
     (let ((endpoint (%redirect-file-endpoint target (%redirect-mode kind))))
       (%make-redirect-output-destination-state
        (%redirect-output-destination-state-stdout-target state)
        (%redirect-output-destination-state-stdout-mode state)
        target
        (%redirect-mode kind)
        (%redirect-output-destination-state-stdout-endpoint state)
        endpoint)))
    (:2>&1
     (%make-redirect-output-destination-state
      (%redirect-output-destination-state-stdout-target state)
      (%redirect-output-destination-state-stdout-mode state)
      (%redirect-output-destination-state-stdout-target state)
      (%redirect-output-destination-state-stdout-mode state)
      (%redirect-output-destination-state-stdout-endpoint state)
      (%redirect-output-destination-state-stdout-endpoint state)))
    (:fd-dup
     (let ((source (redirect-fd-dup-target-source target))
           (destination (redirect-fd-dup-target-target target))
           (operator (redirect-fd-dup-target-operator target)))
       (cond
         ((and (eq operator :output)
               (integerp destination)
               (= source 1)
               (= destination 2))
          (%make-redirect-output-destination-state
           (%redirect-output-destination-state-stderr-target state)
           (%redirect-output-destination-state-stderr-mode state)
           (%redirect-output-destination-state-stderr-target state)
           (%redirect-output-destination-state-stderr-mode state)
           (%redirect-output-destination-state-stderr-endpoint state)
           (%redirect-output-destination-state-stderr-endpoint state)))
         ((and (eq operator :output)
               (integerp destination)
               (= source 2)
               (= destination 1))
          (%make-redirect-output-destination-state
           (%redirect-output-destination-state-stdout-target state)
           (%redirect-output-destination-state-stdout-mode state)
           (%redirect-output-destination-state-stdout-target state)
           (%redirect-output-destination-state-stdout-mode state)
           (%redirect-output-destination-state-stdout-endpoint state)
           (%redirect-output-destination-state-stdout-endpoint state)))
         (t state))))
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
