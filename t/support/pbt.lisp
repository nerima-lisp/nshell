;;; Reusable property-based testing helpers for nshell tests.

(in-package #:nshell/test)

(defparameter *pbt-default-trials* 100
  "Default number of generated examples checked by PBT helpers.")

(defparameter *pbt-shell-word-characters*
  "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./-"
  "Characters that form unquoted shell words in generated test commands.")

(defparameter *pbt-shell-variable-name-start-characters*
  "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_"
  "Characters that may start a shell variable name.")

(defparameter *pbt-shell-variable-name-characters*
  "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"
  "Characters that may appear in a shell variable name body.")

(defparameter *pbt-prompt-characters*
  "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./- []"
  "Single-width characters used in generated prompt text.")

(defparameter *pbt-prompt-cjk-characters*
  "あいうえお漢字"
  "Double-width characters used in generated prompt text.")

(defparameter *pbt-shell-operator-characters*
  (coerce (list #\Space #\Tab #\Newline #\Return #\| #\; #\& #\< #\>) 'string)
  "Characters that should be treated as shell-operator-only blank input.")

(defun gen-integer (&key (min -1000000) (max 1000000))
  "Return a generator for integers in the inclusive range [MIN, MAX]."
  (check-type min integer)
  (check-type max integer)
  (assert (<= min max) (min max) "MIN must be <= MAX.")
  (let ((width (1+ (- max min))))
    (lambda ()
      (+ min (random width)))))

(defun gen-in-range (min max)
  "Return a generator for integers in the inclusive range [MIN, MAX]."
  (check-type min integer)
  (check-type max integer)
  (assert (<= min max) (min max) "MIN must be <= MAX.")
  (gen-integer :min min :max max))

(defun gen-string (&key (min-length 0) (max-length 24)
                        (characters *pbt-prompt-characters*))
  "Return a generator for strings built from CHARACTERS."
  (%pbt-sampled-string characters
                       :min-length min-length
                       :max-length max-length))

(defun %pbt-sampled-string (characters &key (min-length 1) (max-length 12))
  (let ((length-generator (gen-in-range min-length max-length))
        (index-generator (gen-in-range 0 (1- (length characters)))))
    (lambda ()
      (let ((chars '()))
        (dotimes (i (funcall length-generator))
          (push (char characters (funcall index-generator)) chars))
        (coerce (nreverse chars) 'string)))))

(defun %pbt-joined-string (item-generator separator &key (min-items 1) (max-items 4))
  (let ((item-count-generator (gen-in-range min-items max-items)))
    (lambda ()
      (let ((items '()))
        (dotimes (i (funcall item-count-generator))
          (push (funcall item-generator) items))
        (with-output-to-string (out)
          (when items
            (write-string (first items) out)
            (dolist (item (rest items))
              (write-string separator out)
              (write-string item out))))))))

(defun gen-shell-word (&key (min-length 1) (max-length 12))
  "Return a generator for shell words made of valid unquoted word characters."
  (%pbt-sampled-string *pbt-shell-word-characters*
                       :min-length min-length
                       :max-length max-length))

(defun gen-shell-command (&key (min-words 1) (max-words 4) (max-word-length 12))
  "Return a generator for simple valid shell command strings."
  (%pbt-joined-string (gen-shell-word :max-length max-word-length)
                      " "
                      :min-items min-words
                      :max-items max-words))

(defun gen-shell-variable-name (&key (min-length 1) (max-length 12))
  "Return a generator for valid shell variable names."
  (let ((length-generator (gen-in-range min-length max-length))
        (start-index-generator (gen-in-range 0 (1- (length *pbt-shell-variable-name-start-characters*))))
        (body-index-generator (gen-in-range 0 (1- (length *pbt-shell-variable-name-characters*)))))
    (lambda ()
      (let ((chars '()))
        (push (char *pbt-shell-variable-name-start-characters*
                    (funcall start-index-generator))
              chars)
        (dotimes (i (1- (funcall length-generator)))
          (push (char *pbt-shell-variable-name-characters*
                      (funcall body-index-generator))
                chars))
        (coerce (nreverse chars) 'string)))))

(defun gen-shell-operator-only-input (&key (min-length 1) (max-length 12)
                                           (include-return-p t))
  "Return a generator for strings made only of shell separators/operators.

When INCLUDE-RETURN-P is false, the generator excludes #\\Return so it matches
autosuggest blank-input semantics."
  (%pbt-sampled-string (if include-return-p
                           *pbt-shell-operator-characters*
                           (remove #\Return *pbt-shell-operator-characters*))
                       :min-length min-length
                       :max-length max-length))

(defun gen-prompt-text (&key (min-length 0) (max-length 24) (cjk-probability 0.0))
  "Return a generator for prompt text, optionally mixing in CJK wide chars."
  (let ((length-generator (gen-in-range min-length max-length))
        (ascii-index (gen-in-range 0 (1- (length *pbt-prompt-characters*))))
        (cjk-index (gen-in-range 0 (1- (length *pbt-prompt-cjk-characters*))))
        (choice (gen-in-range 0 99))
        (threshold (round (* 100 cjk-probability))))
    (lambda ()
      (let ((chars nil))
        (dotimes (i (funcall length-generator))
          (push (if (< (funcall choice) threshold)
                    (char *pbt-prompt-cjk-characters* (funcall cjk-index))
                    (char *pbt-prompt-characters* (funcall ascii-index)))
                chars))
        (coerce (nreverse chars) 'string)))))

(defun shrink-prompt-text (text)
  "Return simple prompt-text shrink candidates for direct FiveAM uses."
  (cond
    ((zerop (length text)) nil)
    ((= 1 (length text)) (list ""))
    (t (list (subseq text 0 (floor (length text) 2))
             ""))))

(defun shrink-shell-word (text)
  "Return shrink candidates that keep TEXT within shell-word constraints."
  (cond
    ((<= (length text) 1) nil)
    (t (remove-duplicates
        (list (subseq text 0 (max 1 (floor (length text) 2)))
              (subseq text 0 1))
        :test #'string=))))

(defun shrink-integer (n)
  "Return integers strictly closer to zero than N -- zero, the halfway point,
and one step toward zero -- so a failing numeric property shrinks its
counterexample greedily toward the simplest magnitude."
  (let ((candidates (list 0 (truncate n 2))))
    (cond ((plusp n) (push (1- n) candidates))
          ((minusp n) (push (1+ n) candidates)))
    (remove-duplicates (remove n candidates) :test #'eql)))

(defun gen-terminal-width (&key (min 0) (max 80))
  "Return a generator for terminal widths used by prompt truncation tests."
  (gen-in-range min max))

(defun %pbt-binding-names (bindings)
  (mapcar #'first bindings))

(defun %pbt-binding-generators (bindings)
  (mapcar #'second bindings))

(defun %pbt-binding-shrinkers (bindings)
  (mapcar #'third bindings))

(defun %pbt-report-failure (trial bindings condition)
  (fail "Property failed on trial ~d with counterexample ~s~@[; condition: ~a~]"
        trial bindings condition)
  nil)

(defun %pbt-generated-values (generators)
  (mapcar #'funcall generators))

(defun %pbt-property-holds-p (property values)
  (handler-case
      (not (null (funcall property values)))
    (condition () nil)))

(defun %pbt-condition-for (property values)
  (handler-case
      (progn
        (funcall property values)
        nil)
    (condition (condition) condition)))

(defun %pbt-shrink-values (values shrinkers property)
  (let ((current (copy-list values)))
    (loop repeat 64
          do (let ((changed-p nil))
               (loop for index below (length current)
                     for shrinker in shrinkers
                     when shrinker
                       do (dolist (candidate (funcall shrinker (nth index current)))
                            (let ((next (copy-list current)))
                              (setf (nth index next) candidate)
                              (unless (%pbt-property-holds-p property next)
                                (setf current next
                                      changed-p t)
                                (return)))))
               (unless changed-p
                 (return current)))
          finally (return current))))

(defun %pbt-counterexample-bindings (names values)
  (mapcar #'cons names values))

(defun %pbt-run-property (trials names generators shrinkers property)
  (loop for trial from 1 to trials
        for values = (%pbt-generated-values generators)
        always (if (%pbt-property-holds-p property values)
                   t
                   (%pbt-report-failure
                    trial
                    (%pbt-counterexample-bindings
                     names
                     (%pbt-shrink-values values shrinkers property))
                    (%pbt-condition-for property values)))))

(defmacro check-property ((&key (trials '*pbt-default-trials*)) bindings &body body)
  "Run BODY for TRIALS generated examples from BINDINGS.

BINDINGS has the same shape as FIVEAM:FOR-ALL bindings. BODY should return a
generalized boolean. A binding may optionally include a third element: a
shrinker function of one argument returning smaller candidate values. The first
failing generated binding set is shrunk greedily and reported as the
counterexample. No external shrinking library is used."
  (let ((values (gensym "VALUES-"))
        (property (gensym "PROPERTY-")))
    `(let ((,property
             (lambda (,values)
               (destructuring-bind ,(%pbt-binding-names bindings) ,values
                 (declare (ignorable ,@(%pbt-binding-names bindings)))
                 ,@body))))
       (%pbt-run-property
        ,trials
        ',(%pbt-binding-names bindings)
        (list ,@(mapcar (lambda (generator)
                          `(lambda () (funcall ,generator)))
                        (%pbt-binding-generators bindings)))
        (list ,@(%pbt-binding-shrinkers bindings))
        ,property))))

(defmacro property (name bindings-or-doc &body body)
  "Register a property-based test NAME asserting BODY holds over 50 generated
example sets. This is the systematic shorthand for the recurring
`(it NAME [DOC] (check-property (:trials 50) BINDINGS BODY))` shape, so an
invariant network reads as a list of laws rather than repeated scaffolding.
Call as (PROPERTY NAME BINDINGS . BODY) or, with a law description,
(PROPERTY NAME DOC BINDINGS . BODY). BINDINGS take the same
(VAR GENERATOR &optional SHRINKER) form CHECK-PROPERTY accepts."
  (if (stringp bindings-or-doc)
      (destructuring-bind (bindings &rest real-body) body
        `(it ,name ,bindings-or-doc
           (check-property (:trials 50) ,bindings ,@real-body)))
      `(it ,name (check-property (:trials 50) ,bindings-or-doc ,@body))))

;;; Shared test fixtures and adapters used across integration, e2e, and unit tests.
