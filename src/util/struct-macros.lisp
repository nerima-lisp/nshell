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

(defmacro define-value-struct (name (&rest slot-specs) &key documentation keyword-constructor)
  "Define a private DEFSTRUCT NAME (which must start with %) plus public,
read-only accessors that delegate to it.

NAME becomes a struct with a private conc-name NAME- and a constructor
%MAKE-<NAME sans leading %> taking one argument per SLOT-SPECS entry, in
order; the constructor's arguments are positional unless KEYWORD-CONSTRUCTOR
is true, in which case they are all &key. Each SLOT-SPECS entry is
(SLOT-NAME DEFAULT &key TYPE OPTIONAL); TYPE is optional, and a true OPTIONAL
makes this (and it must be a trailing) slot an &optional constructor argument
defaulting to DEFAULT when omitted. For every slot, a public function
<NAME sans leading %>-SLOT-NAME is defined that delegates to the private
accessor. No COPY-NAME function is generated, matching this codebase's
convention that value structs are opaque and never shallow-copied."
  (let* ((private-name (symbol-name name))
         (public-prefix (if (char= (char private-name 0) #\%)
                             (subseq private-name 1)
                             private-name))
         (slot-names (mapcar #'first slot-specs))
         (constructor-name (intern (format nil "%MAKE-~A" public-prefix)))
         (conc-name (intern (format nil "~A-" private-name)))
         (constructor-lambda-list
           (%value-struct-constructor-lambda-list slot-specs keyword-constructor)))
    `(progn
       (defstruct (,name
                   (:constructor ,constructor-name ,constructor-lambda-list)
                   (:conc-name ,conc-name)
                   (:copier nil))
         ,@(when documentation (list documentation))
         ,@(mapcar (lambda (spec)
                     (destructuring-bind (slot-name default &key type optional) spec
                       (declare (ignore optional))
                       (if type
                           `(,slot-name ,default :type ,type :read-only t)
                           `(,slot-name ,default :read-only t))))
                   slot-specs))
       ,@(mapcar (lambda (slot-name)
                   (let ((public-fn (intern (format nil "~A-~A" public-prefix slot-name)))
                         (private-fn (intern (format nil "~A-~A" private-name slot-name))))
                     `(defun ,public-fn (instance)
                        (,private-fn instance))))
                 slot-names))))
