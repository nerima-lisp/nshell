(in-package #:nshell.domain.parsing)

;;; Redirect syntax is immutable runtime data.  Keep it outside the parser
;;; logic so the parser file contains policies and transformations only.
(setf +redirect-specs+
      (list
       (%make-redirect-spec-entry "0<" :<)
       (%make-redirect-spec-entry "0<<" :<<)
       (%make-redirect-spec-entry "0<<-" :<<-)
       (%make-redirect-spec-entry "0<<<" :<<<)
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

(setf +redirect-fd-dup-specs+
      '(:2>&1))

(setf +redirect-kind-fact-specs+
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
       (%make-redirect-kind-fact-spec :&>> nil t t t)
       (%make-redirect-kind-fact-spec :fd-dup nil nil nil nil)))
