(in-package #:nshell/test)

(defun %terminate-in-path-lock-grab-window (grab-index thunk &optional while-paused)
  "Run THUNK in a thread and terminate it right after its GRAB-INDEXth grab of
a PATH cache mutex, before the grabbing form can protect the release; call
WHILE-PAUSED first. Return true when the thread reached that point."
  (let* ((target nil)
         (grabs 0)
         (paused (sb-thread:make-semaphore :count 0))
         (resume nil)
         (hook
           (lambda (function &rest arguments)
             (multiple-value-prog1 (apply function arguments)
               (when (and (eq sb-thread:*current-thread* target)
                          (equal "PATH command directory cache"
                                 (sb-thread:mutex-name (first arguments)))
                          (= (incf grabs) grab-index))
                 (sb-thread:signal-semaphore paused)
                 ;; Spin without an interrupt point: termination lands here
                 ;; only where the grabbing form leaves interrupts enabled.
                 (loop until resume
                       repeat 500000000
                       do (sb-ext:spin-loop-hint)))))))
    (sb-ext:without-package-locks
      (sb-int:encapsulate 'sb-thread:grab-mutex 'path-lock-window hook)
      (sb-int:encapsulate 'sb-thread::grab-mutex-no-check-deadlock
                          'path-lock-window hook))
    (unwind-protect
         (let ((thread (sb-thread:make-thread
                        (lambda ()
                          (loop until target do (sb-thread:thread-yield))
                          (funcall thunk))
                        :name "PATH lock termination test")))
           (setf target thread)
           (prog1 (sb-thread:wait-on-semaphore paused :timeout 5)
             (when while-paused
               (funcall while-paused))
             (sb-thread:terminate-thread thread)
             (sleep 0.05)
             (setf resume t)
             (sb-thread:join-thread thread :default nil :timeout 5)))
      (sb-ext:without-package-locks
        (sb-int:unencapsulate 'sb-thread:grab-mutex 'path-lock-window)
        (sb-int:unencapsulate 'sb-thread::grab-mutex-no-check-deadlock
                              'path-lock-window)))))

(defun %finishes-within-deadline-p (thunk)
  (eq :finished
      (sb-thread:join-thread
       (sb-thread:make-thread (lambda () (funcall thunk) :finished)
                              :name "PATH lock reacquire test")
       :default :timeout :timeout 2)))

(describe "completion-path-reducer-tests"
  (it "filters deduplicates and sorts executable path entries"
    (let ((entries-by-directory
            (list
              (list #p"/first/cat" #p"/first/readme" #p"/first/cargo")
              (list #p"/second/cat" #p"/second/cargo" #p"/second/cmake"))))
      (expect '("cargo" "cat" "cmake")
               :to-equal
               (completion-texts
                (nshell.domain.completion::%path-command-candidates-from-entries
                 entries-by-directory
                 "c"
                 (lambda (entry)
                   (not (string= "readme"
                                 (pathname-name entry)))))))))

  (it "isolates a failing path directory and continues with later directories"
    (expect '("later-tool")
             :to-equal
             (completion-texts
              (nshell.domain.completion::%path-command-candidates-from-entries
               (list (list :broken-directory)
                     (list #p"/later/later-tool"))
               ""
               (lambda (entry)
                 (if (eq entry :broken-directory)
                     (error "broken directory entry")
                     t)))))))

  (it "handles path joining and string command entry projection"
    (expect "bin/git"
            :to-equal
            (nshell.domain.completion::%join-directory-command "bin" "git"))
    (expect "/bin/git"
            :to-equal
            (nshell.domain.completion::%join-directory-command "/bin/" "git"))
    (expect "git"
            :to-equal
            (nshell.domain.completion::%entry-command-name "/usr/bin/git")))

  (it "reports unconfigured path cache lock boundaries"
    (expect (handler-case
                (progn
                  (let ((nshell.domain.completion::*path-command-cache-lock-factory*
                          nil))
                    (nshell.domain.completion::%make-path-command-cache-lock))
                  nil)
              (error () t))
            :to-be-truthy)
    (expect (handler-case
                (progn
                  (let ((nshell.domain.completion::*path-command-directory-cache-lock*
                          nil))
                    (nshell.domain.completion::%require-path-command-directory-cache-lock))
                  nil)
              (error () t))
            :to-be-truthy)
    (expect (handler-case
                (progn
                  (nshell.domain.completion::%configure-path-command-cache-locks nil)
                  nil)
              (error () t))
            :to-be-truthy))

  (it "clears the path cache when its configured limit is reached"
    (unwind-protect
         (let ((generation
                 (nshell.domain.completion::%path-command-directory-cache-generation)))
           (let ((nshell.domain.completion::*path-command-cache-limit* 0))
             (nshell.domain.completion::%path-command-directory-cache-put
              :coverage-boundary
              generation
              (nshell.domain.completion::%make-path-command-directory-cache-entry
               1 0d0 0d0 t '(:entry)))
             (expect 1
                     :to-equal
                     (hash-table-count
                      nshell.domain.completion::*path-command-directory-cache*))))
      (nshell.domain.completion::%invalidate-path-command-cache)))

  (it "turns path directory reader failures into empty results"
    (let ((filesystem
            (make-test-filesystem
             :directory-files (lambda (directory)
                                (declare (ignore directory))
                                (error "directory capability failed"))
             :executable-p (constantly t)))
          (nshell.domain.completion::*path-command-directory-stamp-fn*
            (constantly 1))
          (nshell.domain.completion::*path-command-cache-clock-fn*
            (constantly 0d0)))
      (expect nil
              :to-equal
              (funcall
               (nshell.domain.completion::%make-path-command-directory-reader
                filesystem)
               "/coverage-boundary-reader"))))

  #+sb-thread
  (it "a thread terminated right after taking the PATH cache lock releases it"
    (let ((factory nshell.domain.completion::*path-command-cache-lock-factory*))
      (unwind-protect
           (progn
             (expect (%terminate-in-path-lock-grab-window
                      1
                      (lambda ()
                        (nshell.domain.completion::%path-command-directory-cache-generation)))
                     :to-be-truthy)
             (expect (%finishes-within-deadline-p
                      (lambda ()
                        (nshell.domain.completion::%invalidate-path-command-cache)))
                     :to-be-truthy))
        ;; A leaked lock would hang every later PATH lookup in this image.
        (nshell.domain.completion::%configure-path-command-cache-locks factory))))

  #+sb-thread
  (it "a thread terminated right after taking a PATH key lock releases it"
    ;; A dropped reference alone would let a later caller make a fresh key
    ;; lock, so a contender shares the record while the victim holds it.
    (let ((factory nshell.domain.completion::*path-command-cache-lock-factory*)
          (key "/path-lock-termination-test")
          (contender nil))
      (flet ((references ()
               (nshell.domain.completion::%with-path-command-directory-cache-lock
                 (let ((record (gethash key nshell.domain.completion::*path-command-directory-key-locks*)))
                   (and record (cdr record))))))
        (unwind-protect
             (progn
               ;; The first grab takes the reference under the cache lock,
               ;; the second takes the key lock itself.
               (expect (%terminate-in-path-lock-grab-window
                        2
                        (lambda ()
                          (nshell.domain.completion::%with-path-command-directory-key-lock
                              (key)
                            :held))
                        (lambda ()
                          (setf contender
                                (sb-thread:make-thread
                                 (lambda ()
                                   (nshell.domain.completion::%with-path-command-directory-key-lock
                                       (key)
                                     :again)
                                   :finished)
                                 :name "PATH key lock contender"))
                          (loop repeat 2000
                                until (eql 2 (references))
                                do (sleep 0.001))
                          ;; The contender shares the record the victim holds.
                          (expect (references) :to-equal 2)))
                       :to-be-truthy)
               (expect (sb-thread:join-thread contender :default :timeout :timeout 2)
                       :to-equal :finished)
               (expect (references) :to-be-falsy))
          (nshell.domain.completion::%configure-path-command-cache-locks factory)))))
