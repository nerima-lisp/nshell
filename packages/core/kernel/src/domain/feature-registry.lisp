(in-package #:nshell.architecture)

(defstruct (feature-descriptor
            (:constructor %make-feature-descriptor (name root layers)))
  "A package-by-feature source boundary and its DDD layer names.

ROOT is repository-relative and intentionally remains a string.  Keeping the
descriptor independent of pathnames lets it be used by documentation and
tests without making the domain depend on the host filesystem."
  (name nil :type keyword)
  (root "" :type string)
  (layers nil :type list))

(defvar *feature-registry* (make-hash-table :test #'eq)
  "The loaded feature descriptors, keyed by their keyword names.")

(defmacro define-feature (name &key root layers)
  "Declare a feature descriptor at load time.

NAME, ROOT, and LAYERS are source-level architecture data.  The generated
registration remains an ordinary function call so reloads retain the same
runtime semantics as programmatic registration."
  `(eval-when (:load-toplevel :execute)
     (register-feature ,name :root ,root :layers ',layers)))

(defun register-feature (name &key root layers)
  "Register NAME as a feature rooted at ROOT and split across LAYERS.

Registering the same name replaces its descriptor, which keeps ASDF reloads
deterministic while still making malformed descriptors fail early."
  (check-type name keyword)
  (check-type root string)
  (check-type layers list)
  (dolist (layer layers)
    (check-type layer keyword))
  (setf (gethash name *feature-registry*)
        (%make-feature-descriptor name root (copy-list layers))))

(defun find-feature (name)
  "Return the descriptor registered for keyword NAME, or NIL."
  (gethash name *feature-registry*))

(defun all-features ()
  "Return registered feature descriptors in stable name order."
  (sort (loop for descriptor being the hash-values of *feature-registry*
              collect descriptor)
        #'string<
        :key (lambda (descriptor)
               (symbol-name (feature-descriptor-name descriptor)))))

(defun %resolve-feature (feature)
  (etypecase feature
    (feature-descriptor feature)
    (keyword
     (or (find-feature feature)
         (error "Unknown nshell feature ~s." feature)))))

(defun feature-layer-path (feature layer)
  "Return FEATURE's repository-relative path for keyword LAYER."
  (let* ((descriptor (%resolve-feature feature))
         (layers (feature-descriptor-layers descriptor)))
    (check-type layer keyword)
    (unless (member layer layers :test #'eq)
      (error "Feature ~s has no ~s layer."
             (feature-descriptor-name descriptor)
             layer))
    (format nil "~a/~a"
            (feature-descriptor-root descriptor)
            (string-downcase (symbol-name layer)))))
