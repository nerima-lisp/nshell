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
