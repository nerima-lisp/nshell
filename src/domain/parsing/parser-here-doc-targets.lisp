(in-package #:nshell.domain.parsing)

(defun %here-doc-target-token-p (token)
  (eq (token-type token) :word))

(defun %replace-here-doc-target-token (token body)
  (make-token (token-type token)
              body
              (token-start token)
              (token-end token)
              (token-quote-style token)))

(defstruct (here-doc-target-replacer
            (:constructor %make-here-doc-target-replacer (bodies))
            (:copier nil))
  bodies
  (target-pending-p nil :type boolean))

(define-value-struct %here-doc-target-body-cursor
    ((body nil)
     (remaining-bodies nil))
  :public-accessors nil)

(defun %here-doc-target-body-cursor (bodies)
  (%make-here-doc-target-body-cursor (first bodies) (rest bodies)))

(defun %here-doc-target-replacer-has-body-p (replacer)
  (not (null (here-doc-target-replacer-bodies replacer))))

(defun %mark-here-doc-target-pending (replacer)
  (when (%here-doc-target-replacer-has-body-p replacer)
    (setf (here-doc-target-replacer-target-pending-p replacer) t))
  replacer)

(defun %consume-next-here-doc-target-body (replacer)
  (let ((cursor (%here-doc-target-body-cursor
                 (here-doc-target-replacer-bodies replacer))))
    (setf (here-doc-target-replacer-bodies replacer)
          (%here-doc-target-body-cursor-remaining-bodies cursor))
    (%here-doc-target-body-cursor-body cursor)))

(defun %here-doc-target-replacer-should-replace-p (replacer token)
  (and (here-doc-target-replacer-target-pending-p replacer)
       (%here-doc-target-replacer-has-body-p replacer)
       (%here-doc-target-token-p token)))

(defun %here-doc-target-replacer-accept (replacer token)
  (cond
    ((%here-doc-target-replacer-should-replace-p replacer token)
     (setf (here-doc-target-replacer-target-pending-p replacer) nil)
     (%replace-here-doc-target-token
      token
      (%consume-next-here-doc-target-body replacer)))
    (t
     (when (%here-doc-redirect-token-p token)
       (%mark-here-doc-target-pending replacer))
     token)))

(defun %replace-here-doc-targets (tokens bodies)
  (let ((replacer (%make-here-doc-target-replacer bodies)))
    (loop for tok in tokens
          collect (%here-doc-target-replacer-accept replacer tok))))
