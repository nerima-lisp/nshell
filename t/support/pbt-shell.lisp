(in-package #:nshell/test)

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
                                  (history (history-kit:make-history))
                                  (config (nshell.domain.configuration:default-config))
                                  (knowledge-base (nshell.domain.completion:make-empty-knowledge-base))
                                  (environment (nshell.domain.environment:make-default-environment))
                                  (job-monitor (nshell.domain.job-control:make-job-monitor))
                                  (alias-table (make-hash-table :test #'equal))
                                  (abbreviation-table (make-hash-table :test #'equal))
                                  (function-table (make-hash-table :test #'equal))
                                  (function-source-table (make-hash-table :test #'equal))
                                  (filesystem-fns nil filesystem-fns-supplied-p)
                                  (process-fns nil process-fns-supplied-p)
                                  redirect-fns
                                  (terminal-fns nil terminal-fns-supplied-p)
                                  (execution-strategy :cps)
                                  (running nil))
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
     :job-monitor job-monitor
     :alias-table alias-table
     :abbreviation-table abbreviation-table
     :function-table function-table
     :function-source-table function-source-table
     :filesystem-fns filesystem-fns
     :process-fns process-fns
     :redirect-fns redirect-fns
     :terminal-fns terminal-fns
     :execution-strategy execution-strategy
     :running running)))

(defmacro with-parsed-command-line ((result line) &body body)
  `(nshell.domain.parsing:with-parsed-command-line (,result ,line)
     ,@body))

(defmacro assert-arg-quote-styles (args &rest styles)
  `(expect ',styles :to-equal (mapcar #'nshell.domain.parsing:arg-quote-style ,args)))

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
           `((expect (null ,diagnostic) :to-be-falsy)))
       ,@(when incomplete
           `((expect (nshell.domain.parsing:parse-result-incomplete ,result) :to-be-truthy)))
       ,@(when complete
           `((expect (nshell.domain.parsing:parse-complete-p ,result) :to-be-truthy)))
       ,@(when kind
           `((expect ,kind :to-be (nshell.domain.parsing:parse-diagnostic-kind ,diagnostic))))
       ,@(when (and start end)
           `((expect (parse-diagnostic-span= ,diagnostic ,start ,end) :to-be-truthy)))
       ,@(when within-input
           `((expect (parse-diagnostic-within-input-p ,diagnostic ,line) :to-be-truthy))))))

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

(defun make-test-job (id command &key (args nil) (pgid 0) (pids nil))
  (let* ((cmd (nshell.domain.execution:make-command command args))
         (pipeline (nshell.domain.execution:make-pipeline cmd))
         (job (nshell.domain.execution:make-job id pipeline))
         (command-line (format nil "~{~a~^ ~}"
                               (nshell.domain.execution:command-to-list cmd))))
    (nshell.domain.execution:job-record-runtime-metadata
     job
     :pids pids
     :pgid pgid
     :command-line command-line)))

(defstruct (test-monitor-entry (:constructor make-test-monitor-entry (job-id job)))
  (job-id 0 :type integer :read-only t)
  (job nil :read-only t))

(defun collect-monitor-entries (monitor)
  (let (entries)
    (nshell.domain.job-control:monitor-map-jobs
     monitor
     (lambda (job-id job)
       (push (make-test-monitor-entry job-id job) entries)))
    (nreverse entries)))

(defun test-source-path (prefix)
  (merge-pathnames
   (make-pathname :name prefix :type "lisp")
   (host-kit:temporary-directory)))

(defun test-source-root (prefix)
  (merge-pathnames
   (make-pathname :directory `(:relative ,prefix))
   (host-kit:temporary-directory)))

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
       (when (host-kit:directory-exists-p ,root)
         (host-kit:delete-directory-tree ,root :validate t)))))
