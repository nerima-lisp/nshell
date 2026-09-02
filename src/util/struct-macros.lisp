;;; A DEFINE-VALUE-STRUCT macro for the small immutable value objects used
;;; throughout nshell (parse results, prompt segments, input-state "plan"/
;;; "edit" records, ...). Each such struct pairs a private, %-prefixed
;;; DEFSTRUCT with hand-written public accessors that only strip the leading
;;; %; this macro generates both from one declaration. It lives in this
;;; dependency-free package so every layer (domain included) may use it.

(in-package #:nshell.util)

(defun %value-struct-constructor-lambda-list (slot-specs keyword-constructor)
  (let ((slot-names (mapcar #'first slot-specs)))
    (cond
      (keyword-constructor (cons '&key slot-names))
      ((notany (lambda (spec) (getf (cddr spec) :optional)) slot-specs)
       slot-names)
      (t (append (loop for spec in slot-specs
                        until (getf (cddr spec) :optional)
                        collect (first spec))
                 '(&optional)
                 (loop for spec in slot-specs
                       when (getf (cddr spec) :optional)
                         collect (list (first spec) (second spec))))))))

(defun %value-struct-accessor-copy (copy form)
  "Wrap FORM so a public accessor hands back a defensive copy: :LIST copies a
list, :SEQ copies any sequence, a symbol names a one-argument copier to call,
and NIL returns the slot value directly."
  (cond
    ((null copy) form)
    ((eq copy :list) `(copy-list ,form))
    ((eq copy :seq) `(copy-seq ,form))
    ((symbolp copy) `(,copy ,form))
    (t (error "DEFINE-VALUE-STRUCT :COPY must be :LIST, :SEQ, or a copier symbol, got ~S."
              copy))))

(defmacro define-value-struct (name (&rest slot-specs)
                               &key documentation keyword-constructor accessor-prefix
                                    (public-accessors t)
                                    constructor (predicate nil predicate-supplied-p))
  "Define an opaque, read-only value struct NAME plus public accessors that
delegate to its private slots.

NAME may be public (e.g. PROMPT-SEGMENT) or private (e.g. %KILL-EDIT, leading
%). Either way the struct's slots live behind a private %<NAME sans %>- conc-name
and are reached through public <NAME sans %>-SLOT functions; the struct type and
its DEFSTRUCT predicate keep NAME's own visibility (PROMPT-SEGMENT-P stays
public, %KILL-EDIT-P stays private), so a public value type can be named with
this macro without leaking its accessors. The constructor is
%MAKE-<NAME sans %> taking one argument per slot in order (all &key when
KEYWORD-CONSTRUCTOR is true).

Each SLOT-SPECS entry is (SLOT-NAME DEFAULT &key TYPE OPTIONAL COPY). A true
OPTIONAL makes this (trailing) slot an &optional constructor argument defaulting
to DEFAULT. COPY (:LIST, :SEQ, or a one-argument copier symbol) makes the public
accessor return a fresh copy, for slots holding shared mutable sequences. No
COPY-NAME is generated: value structs are opaque and never shallow-copied.

Keyword options tune the generated names to fit existing code:
:ACCESSOR-PREFIX overrides the public accessor prefix (default: NAME sans %),
so a type like %COMPLETION-CANDIDATE can expose CANDIDATE-* readers.
:PUBLIC-ACCESSORS controls whether those public readers are emitted; set it to
NIL for opaque implementation values that must not cross a package boundary.
:CONSTRUCTOR overrides the private constructor name (default: %MAKE-<NAME sans
%>), e.g. to keep an %ALLOCATE-* raw-allocation convention. :PREDICATE overrides
the DEFSTRUCT predicate name (NIL suppresses it), for custom-named or
deliberately-private predicates."
  (let* ((bare-name (let ((text (symbol-name name)))
                      (if (char= (char text 0) #\%) (subseq text 1) text)))
         (public-prefix (if accessor-prefix (symbol-name accessor-prefix) bare-name))
         (constructor-name (or constructor (intern (format nil "%MAKE-~A" bare-name))))
         (private-prefix (format nil "%~A" bare-name))
         (conc-name (intern (format nil "~A-" private-prefix)))
         (constructor-lambda-list
           (%value-struct-constructor-lambda-list slot-specs keyword-constructor)))
    `(progn
       (defstruct (,name
                   (:constructor ,constructor-name ,constructor-lambda-list)
                   (:conc-name ,conc-name)
                   (:copier nil)
                   ,@(when predicate-supplied-p `((:predicate ,predicate))))
         ,@(when documentation (list documentation))
         ,@(mapcar (lambda (spec)
                     (destructuring-bind (slot-name default &key type optional copy) spec
                       (declare (ignore optional copy))
                       (if type
                           `(,slot-name ,default :type ,type :read-only t)
                           `(,slot-name ,default :read-only t))))
                   slot-specs))
       ,@(when public-accessors (mapcar (lambda (spec)
                   (destructuring-bind (slot-name default &key type optional copy) spec
                     (declare (ignore default type optional))
                     (let ((public-fn (intern (format nil "~A-~A" public-prefix slot-name)))
                           (private-fn (intern (format nil "~A-~A" private-prefix slot-name))))
                       `(defun ,public-fn (instance)
                          ,(%value-struct-accessor-copy copy `(,private-fn instance))))))
                 slot-specs)))))
