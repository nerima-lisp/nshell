(in-package #:nshell/test)

(describe "filesystem-file-completion-tests"
  (it "bare-filename-prefixes-include-files-and-knowledge-base-candidates"
    "Bare argument prefixes produce file candidates without replacing command facts."
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
      (nshell.domain.completion:kb-add-command kb
                                               "tool"
                                               :subcommands
                                               '("feature"))
      (with-test-filesystem
          (:directory-files
           (lambda (directory)
             (declare (ignore directory))
             (list #p"file.txt"))
           :subdirectories
           (constantly nil))
        (let ((texts
               (completion-texts
                (nshell.domain.completion:complete kb
                                                   "tool f"
                                                   :filesystem
                                                   *completion-test-filesystem*))))
          (expect (member "file.txt" texts :test #'string=) :to-be-truthy)
          (expect (member "feature" texts :test #'string=) :to-be-truthy)))))
  (it "hidden-entry-visibility-follows-the-basename-prefix"
    "Dot entries stay hidden for empty prefixes and appear for dot prefixes."
    (with-test-filesystem
        (:directory-files
         (lambda (directory)
           (declare (ignore directory))
           (list #p".hidden" #p"visible.txt"))
         :subdirectories
         (lambda (directory)
           (declare (ignore directory))
           (list #p".hidden-dir/" #p"visible-dir/")))
      (let ((empty-prefix
             (completion-texts
              (nshell.domain.completion::%file-candidates-from-directory
               *completion-test-filesystem*
               "")))
            (dot-prefix
             (completion-texts
              (nshell.domain.completion::%file-candidates-from-directory
               *completion-test-filesystem*
               "."))))
        (expect (member "visible.txt" empty-prefix :test #'string=)
                :to-be-truthy)
        (expect (member "visible-dir/" empty-prefix :test #'string=)
                :to-be-truthy)
        (expect (member ".hidden" empty-prefix :test #'string=) :to-be-falsy)
        (expect (member ".hidden-dir/" empty-prefix :test #'string=)
                :to-be-falsy)
        (expect (member ".hidden" dot-prefix :test #'string=) :to-be-truthy)
        (expect (member ".hidden-dir/" dot-prefix :test #'string=)
                :to-be-truthy))))
  (it "directory-only-commands-exclude-filesystem-files"
    "Directory-only command arguments return matching directories only."
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
      (with-test-filesystem
          (:directory-files
           (lambda (directory)
             (declare (ignore directory))
             (list #p"folder.txt"))
           :subdirectories
           (lambda (directory)
             (declare (ignore directory))
             (list #p"folder/")))
        (let ((texts
               (completion-texts
                (nshell.domain.completion:complete kb
                                                   "cd fo"
                                                   :filesystem
                                                   *completion-test-filesystem*))))
          (expect (member "folder/" texts :test #'string=) :to-be-truthy)
          (expect (member "folder.txt" texts :test #'string=) :to-be-falsy)))))
  (it "filesystem-candidate-insertion-preserves-spaces-and-unicode"
    "Filesystem candidate text is escaped for spaces while Unicode stays intact."
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
      (with-test-filesystem
          (:directory-files
           (lambda (directory)
             (declare (ignore directory))
             (list #p"space name.txt" #p"日本語.txt"))
           :subdirectories
           (constantly nil))
        (let* ((space-candidate
                (completion-candidate-by-text "space name.txt"
                                              (nshell.domain.completion:complete
                                               kb
                                               "cat spa"
                                               :filesystem
                                               *completion-test-filesystem*)))
               (unicode-candidate
                (completion-candidate-by-text "日本語.txt"
                                              (nshell.domain.completion:complete
                                               kb
                                               "cat 日"
                                               :filesystem
                                               *completion-test-filesystem*))))
          (expect "cat space\\ name.txt"
                  :to-equal
                  (nshell.presentation:apply-completion "cat spa"
                                                        space-candidate))
          (expect "cat 日本語.txt"
                  :to-equal
                  (nshell.presentation:apply-completion "cat 日"
                                                        unicode-candidate))))))
  (it "host-filesystem-completion-lists-file-directory-and-broken-links"
  "The host adapter lists links as candidates and treats a broken link as a file."
  (host-kit:with-temporary-directory (directory)
    (let* ((target-file (merge-pathnames "target.txt" directory))
           (target-directory (merge-pathnames "target-dir/" directory))
           (file-link (merge-pathnames "file-link.txt" directory))
           (directory-link (merge-pathnames "directory-link" directory))
           (broken-link (merge-pathnames "broken-link" directory))
           (filesystem (nshell.infrastructure.acl:make-host-filesystem)))
      (host-kit:write-file-string "target" target-file)
      (host-kit:ensure-directory-tree target-directory)
      (host-kit:create-symbolic-link target-file file-link)
      (host-kit:create-symbolic-link target-directory directory-link)
      (host-kit:create-symbolic-link
       (merge-pathnames "missing.txt" directory) broken-link)
      (nshell.infrastructure.acl:clear-directory-listing-cache)
      (unwind-protect
           (let* ((file-reader
                    (nshell.domain.filesystem:filesystem-directory-files filesystem))
                  (directory-reader
                    (nshell.domain.filesystem:filesystem-subdirectories filesystem))
                  (file-names
                    (mapcar #'nshell.domain.completion::%entry-path-name
                            (funcall file-reader directory)))
                  (directory-names
                    (mapcar #'nshell.domain.completion::%entry-path-name
                            (funcall directory-reader directory))))
             (expect (member "target.txt" file-names :test #'string=)
                     :to-be-truthy)
             (expect (member "file-link.txt" file-names :test #'string=)
                     :to-be-truthy)
             (expect (member "broken-link" file-names :test #'string=)
                     :to-be-truthy)
             (expect (member "target-dir" directory-names :test #'string=)
                     :to-be-truthy)
             (expect (member "directory-link" directory-names :test #'string=)
                     :to-be-truthy))
        (nshell.infrastructure.acl:clear-directory-listing-cache))))))
