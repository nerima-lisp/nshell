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

(defun gen-in-range (min max)
  "Return a generator for integers in the inclusive range [MIN, MAX]."
  (check-type min integer)
  (check-type max integer)
  (assert (<= min max) (min max) "MIN must be <= MAX.")
  (let ((integer-generator (gen-integer))
        (width (1+ (- max min))))
    (lambda ()
      (+ min (mod (abs (funcall integer-generator)) width)))))

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

(defun gen-shell-pipeline (&key (min-commands 1) (max-commands 4))
  "Return a generator for pipe-separated valid shell command strings."
  (%pbt-joined-string (gen-shell-command)
                      " | "
                      :min-items min-commands
                      :max-items max-commands))

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
  (is (null t) "Property failed on trial ~d with counterexample ~s~@[; condition: ~a~]"
      trial bindings condition)
  nil)

(defmacro check-property ((&key (trials '*pbt-default-trials*)) bindings &body body)
  "Run BODY for TRIALS generated examples from BINDINGS.

BINDINGS has the same shape as FIVEAM:FOR-ALL bindings. BODY should return a
generalized boolean. A binding may optionally include a third element: a
shrinker function of one argument returning smaller candidate values. The first
failing generated binding set is shrunk greedily and reported as the
counterexample. No external shrinking library is used."
  (let ((trial (gensym "TRIAL-"))
        (values (gensym "VALUES-"))
        (current (gensym "CURRENT-"))
        (candidate (gensym "CANDIDATE-"))
        (next (gensym "NEXT-"))
        (changed-p (gensym "CHANGED-P"))
        (condition-var (gensym "CONDITION-")))
    `(loop for ,trial from 1 to ,trials
           for ,values = (list ,@(mapcar (lambda (generator)
                                           `(funcall ,generator))
                                         (%pbt-binding-generators bindings)))
           always
              (labels ((try-property (,values)
                         (destructuring-bind ,(%pbt-binding-names bindings) ,values
                           (handler-case
                               (not (null (progn ,@body)))
                             (condition () nil))))
                       (shrink-values (,values)
	                         (let ((,current (copy-list ,values)))
	                           (loop repeat 64
	                                 do (let ((,changed-p nil))
	                                      (loop for index below (length ,current)
	                                            for shrinker in (list ,@(%pbt-binding-shrinkers bindings))
                                            when shrinker
                                              do (dolist (,candidate
                                                          (funcall shrinker (nth index ,current)))
                                                   (let ((,next (copy-list ,current)))
                                                     (setf (nth index ,next) ,candidate)
                                                     (unless (try-property ,next)
                                                       (setf ,current ,next
                                                             ,changed-p t)
	                                                       (return)))))
	                                      (unless ,changed-p
	                                        (return ,current)))
	                                 finally (return ,current)))))
                (if (try-property ,values)
                    t
                    (let ((,condition-var
                            (handler-case
                                (progn
                                  (destructuring-bind ,(%pbt-binding-names bindings) ,values
                                    (declare (ignorable ,@(%pbt-binding-names bindings)))
                                    ,@body)
                                  nil)
                              (condition (condition) condition))))
                      (%pbt-report-failure
                       ,trial
                       (mapcar #'cons
                               ',(%pbt-binding-names bindings)
                               (shrink-values ,values))
                       ,condition-var)))))))

(defmacro for-all-property ((&key (trials '*pbt-default-trials*)) bindings &body body)
  "Run FIVEAM:FOR-ALL with TRIALS examples and BODY assertions."
  `(let ((*num-trials* ,trials)
         (*max-trials* ,trials))
     (for-all ,bindings
       ,@body)))

(defmacro with-event-capture ((events dispatcher &rest types) projection &body body)
  "Subscribe to TYPES on DISPATCHER and collect PROJECTION values into EVENTS."
  `(let ((,events nil))
     (dolist (type ',types)
       (nshell.application:subscribe ,dispatcher type
                                     (lambda (event)
                                       (push ,projection ,events))))
     ,@body))

;;; Shared test fixtures and adapters used across integration, e2e, and unit tests.

(defun %default-test-filesystem-fns ()
  (list :list-dir (lambda (dir)
                    (declare (ignore dir))
                    '("a" "b"))
        :stat (lambda (path)
                (declare (ignore path))
                nil)
        :file-exists-p (lambda (path)
                         (declare (ignore path))
                         nil)
        :directory-exists-p (lambda (path)
                              (declare (ignore path))
                              nil)
        :cwd (lambda ()
               #p"/tmp/")
        :chdir (lambda (path)
                 (declare (ignore path))
                 t)))

(defun %default-test-process-fns ()
  (list :spawn (lambda (&rest args)
                 (declare (ignore args))
                 :spawned)
        :wait (lambda (&rest args)
                (declare (ignore args))
                :waited)
        :signal (lambda (&rest args)
                  (declare (ignore args))
                  :signaled)
        :run-external (lambda (command args)
                        (declare (ignore command args))
                        0)
        :run-external-capture (lambda (command args)
                                (declare (ignore command args))
                                (values nil 0))))

(defun %default-test-terminal-fns ()
  (list :get-size (lambda ()
                    (values 80 24))
        :raw-mode (lambda ()
                    t)
        :restore-mode (lambda ()
                        t)))

(defun make-test-shell-context (&key
                                  (history (nshell.domain.history:make-command-history))
                                  (config (nshell.domain.configuration:default-config))
                                  (knowledge-base (nshell.domain.completion:make-knowledge-base))
                                  (environment (nshell.domain.environment:make-default-environment))
                                  (dispatcher (nshell.application:make-event-dispatcher))
                                  (job-monitor (nshell.domain.job-control:make-job-monitor))
                                  (alias-table (make-hash-table :test #'equal))
                                  (abbreviation-table (make-hash-table :test #'equal))
                                  (function-table (make-hash-table :test #'equal))
                                  (function-source-table (make-hash-table :test #'equal))
                                  (filesystem-fns nil filesystem-fns-supplied-p)
                                  (process-fns nil process-fns-supplied-p)
                                  redirect-fns
                                  (terminal-fns nil terminal-fns-supplied-p)
                                  (execution-strategy :cps))
  (let ((filesystem-fns (if filesystem-fns-supplied-p
                            filesystem-fns
                            (%default-test-filesystem-fns)))
        (process-fns (if process-fns-supplied-p
                         process-fns
                         (%default-test-process-fns)))
        (terminal-fns (if terminal-fns-supplied-p
                          terminal-fns
                          (%default-test-terminal-fns))))
    (nshell.application:make-shell-context
     :history history
     :config config
     :knowledge-base knowledge-base
     :environment environment
     :dispatcher dispatcher
     :job-monitor job-monitor
     :alias-table alias-table
     :abbreviation-table abbreviation-table
     :function-table function-table
     :function-source-table function-source-table
     :filesystem-fns filesystem-fns
     :process-fns process-fns
     :redirect-fns redirect-fns
     :terminal-fns terminal-fns
     :execution-strategy execution-strategy)))

(defmacro with-parsed-command-line ((result line) &body body)
  `(nshell.domain.parsing:with-parsed-command-line (,result ,line)
     ,@body))

(defmacro assert-arg-quote-styles (args &rest styles)
  `(is (equal ',styles
              (mapcar #'nshell.domain.parsing:arg-quote-style ,args))))

(defmacro with-complete-command-line ((result ast line) &body body)
  `(nshell.domain.parsing:with-complete-command-line (,result ,ast ,line)
     ,@body))

(defmacro with-complete-ast ((ast line) &body body)
  (let ((result (gensym "RESULT")))
    `(nshell.domain.parsing:with-parsed-command-line (,result ,line)
       (when (nshell.domain.parsing:parse-complete-p ,result)
         (let ((,ast (nshell.domain.parsing:parse-result-ast ,result)))
           ,@body)))))

(defmacro with-first-parsed-diagnostic ((diagnostic result line) &body body)
  `(nshell.domain.parsing:with-parsed-command-line (,result ,line)
     (let ((,diagnostic (first (nshell.domain.parsing:parse-errors ,result))))
       ,@body)))

(defmacro with-last-parsed-diagnostic ((diagnostic result line) &body body)
  `(nshell.domain.parsing:with-parsed-command-line (,result ,line)
     (let ((,diagnostic (first (last (nshell.domain.parsing:parse-errors ,result)))))
       ,@body)))

(defmacro with-parsed-diagnostic-of-kind ((diagnostic result line kind) &body body)
  `(nshell.domain.parsing:with-parsed-command-line (,result ,line)
     (let ((,diagnostic (find ,kind
                              (nshell.domain.parsing:parse-errors ,result)
                              :key #'nshell.domain.parsing:parse-diagnostic-kind)))
       ,@body)))

(defmacro assert-parsed-diagnostic (result diagnostic &rest options)
  (let ((kind (getf options :kind))
        (start (getf options :span-start))
        (end (getf options :span-end))
        (present (getf options :present))
        (incomplete (getf options :incomplete))
        (complete (getf options :complete))
        (within-input (getf options :within-input))
        (line (getf options :line)))
    `(progn
       ,@(when present
           `((is (not (null ,diagnostic)))))
       ,@(when incomplete
           `((is (nshell.domain.parsing:parse-result-incomplete ,result))))
       ,@(when complete
           `((is (nshell.domain.parsing:parse-complete-p ,result))))
       ,@(when kind
           `((is (eq ,kind
                     (nshell.domain.parsing:parse-diagnostic-kind ,diagnostic)))))
       ,@(when (and start end)
           `((is (parse-diagnostic-span= ,diagnostic ,start ,end))))
       ,@(when within-input
           `((is (parse-diagnostic-within-input-p ,diagnostic ,line)))))))

(defmacro assert-all-parsed-diagnostics-within-input (result line)
  `(dolist (diagnostic (nshell.domain.parsing:parse-errors ,result))
     (is (parse-diagnostic-within-input-p diagnostic ,line))))

(defun parse-diagnostic-span= (diagnostic start end)
  (and (= start (nshell.domain.parsing:parse-diagnostic-start diagnostic))
       (= end (nshell.domain.parsing:parse-diagnostic-end diagnostic))))

(defun parse-diagnostic-within-input-p (diagnostic line)
  (<= 0
      (nshell.domain.parsing:parse-diagnostic-start diagnostic)
      (nshell.domain.parsing:parse-diagnostic-end diagnostic)
      (length line)))

(defmacro do-command-lines ((line lines) &body body)
  `(dolist (,line ,lines)
     ,@body))

(defun make-test-job (id command &key (args nil) (pgid 0))
  (let* ((cmd (nshell.domain.execution:make-command command args))
         (pipeline (nshell.domain.execution:make-pipeline cmd))
         (job (nshell.domain.execution:make-job id pipeline)))
    (setf (nshell.domain.execution:job-command-line job)
          (format nil "~{~a~^ ~}"
                  (nshell.domain.execution:command-to-list cmd))
          (nshell.domain.execution:job-pgid job) pgid)
    job))

(defun test-source-path (prefix)
  (merge-pathnames
   (make-pathname :name prefix :type "lisp")
   (uiop:temporary-directory)))

(defun test-source-root (prefix)
  (merge-pathnames
   (make-pathname :directory `(:relative ,prefix))
   (uiop:temporary-directory)))

(defun write-test-lines (path lines)
  (with-open-file (stream path
                          :direction :output
                          :if-exists :supersede
                          :if-does-not-exist :create)
    (dolist (line lines)
      (write-line line stream))))

(defun read-test-file-line (path)
  (with-open-file (stream path :direction :input)
    (read-line stream nil nil)))

(defmacro with-test-source-file ((name path &key (prefix "nshell-test-source")) &body body)
  `(let ((,name (or ,path (test-source-path ,prefix))))
     (unwind-protect
          (progn ,@body)
       (when (probe-file ,name)
         (delete-file ,name)))))

(defmacro with-test-source-tree ((root path &key (prefix "nshell-test-source")) &body body)
  `(let* ((,root (test-source-root ,prefix))
          (,path (merge-pathnames
                  (make-pathname :name ,prefix :type "lisp")
                  ,root)))
     (ensure-directories-exist ,path)
     (unwind-protect
          (progn ,@body)
       (when (uiop:directory-exists-p ,root)
         (uiop:delete-directory-tree ,root :validate t)))))
