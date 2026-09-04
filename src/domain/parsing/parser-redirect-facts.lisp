(in-package #:nshell.domain.parsing)

(defun %redirect-facts (text)
  (let ((entry (%redirect-spec-entry text)))
    (if entry
        (let ((kind (%redirect-spec-entry-kind entry)))
          (%make-redirect-facts
           (%redirect-spec-entry-text entry)
           kind
           (not (null (member kind +redirect-fd-dup-specs+
                              :test #'eq)))))
        (let ((dynamic-target (%redirect-dynamic-fd-dup-target text)))
          (when dynamic-target
            (%make-redirect-facts text :fd-dup t dynamic-target))))))

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
  (let ((facts-var (gensym "FACTS-")))
    `(defun ,name (kind)
       (let ((,facts-var (%redirect-kind-facts kind)))
         (and ,facts-var
              (,accessor ,facts-var))))))

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
