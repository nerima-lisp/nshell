(in-package #:nshell/test)

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
              1
              0d0
              '(:entry))
             (expect 1
                     :to-equal
                     (hash-table-count
                      nshell.domain.completion::*path-command-directory-cache*))))
      (nshell.domain.completion::%invalidate-path-command-cache)))

  (it "turns path directory reader failures into empty results"
    (let ((nshell.domain.completion::*path-command-directory-files-fn*
            (lambda (directory)
              (declare (ignore directory))
              (error "directory adapter failed")))
          (nshell.domain.completion::*path-command-directory-stamp-fn*
            (constantly 1))
          (nshell.domain.completion::*path-command-cache-clock-fn*
            (constantly 0d0)))
      (expect nil
              :to-equal
              (funcall
               (nshell.domain.completion::%make-path-command-directory-reader)
               "/coverage-boundary-reader"))))
