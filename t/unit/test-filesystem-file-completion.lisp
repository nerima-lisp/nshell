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
  (it "host-filesystem-completion-lists-special-filenames-and-links"
  "The host adapter preserves raw entry names and classifies symbolic links."
  (host-kit:with-temporary-directory (directory)
    (let* ((target-file (merge-pathnames "target.txt" directory))
           (target-directory (merge-pathnames "target-dir/" directory))
           (file-link (merge-pathnames "file-link.txt" directory))
           (directory-link (merge-pathnames "directory-link" directory))
           (broken-link (merge-pathnames "broken-link" directory))
           (directory-prefix
             (namestring (host-kit:ensure-directory-pathname directory)))
           (backslash-name (format nil "back~cslash.txt" (code-char 92)))
           (backslash-path (concatenate 'string directory-prefix backslash-name))
           (backslash-prefix (concatenate 'string directory-prefix "back"))
           (filesystem (nshell.infrastructure.acl:make-host-filesystem)))
      (host-kit:write-file-string "target" target-file)
      (host-kit:ensure-directory-tree target-directory)
      (host-kit:create-symbolic-link target-file file-link)
      (host-kit:create-symbolic-link target-directory directory-link)
      (host-kit:create-symbolic-link
       (merge-pathnames "missing.txt" directory) broken-link)
      (let ((fd (sb-posix:open
                 backslash-path
                 (logior sb-posix:o-wronly sb-posix:o-creat sb-posix:o-trunc)
                 #o600)))
        (sb-posix:close fd))
      (nshell.infrastructure.acl:clear-directory-listing-cache)
      (unwind-protect
           (let* ((file-reader
                    (nshell.domain.filesystem:filesystem-directory-files filesystem))
                  (directory-reader
                    (nshell.domain.filesystem:filesystem-subdirectories filesystem))
                  (file-names
                    (let ((lstat-count 0))
                      (with-rebound-function
                          (sb-posix:lstat
                           (lambda (path)
                             (incf lstat-count)
                             (funcall original-function path)))
                        (let ((names
                                (mapcar
                                 (function nshell.domain.completion::%entry-path-name)
                                 (funcall file-reader directory))))
                          (expect #+(and darwin 64-bit) 3
                                  #-(and darwin 64-bit) 6
                                  :to-equal
                                  lstat-count)
                          names))))
                  (directory-names
                    (mapcar #'nshell.domain.completion::%entry-path-name
                            (funcall directory-reader directory)))
                  (backslash-candidate
                    (completion-candidate-by-text
                     (concatenate 'string directory-prefix backslash-name)
                     (nshell.domain.completion:complete
                      (nshell.domain.completion:make-empty-knowledge-base)
                      (concatenate 'string "cat " backslash-prefix)
                      :filesystem
                      filesystem))))
             (expect (member "target.txt" file-names :test #'string=)
                     :to-be-truthy)
             (expect (member "file-link.txt" file-names :test #'string=)
                     :to-be-truthy)
             (expect (member "broken-link" file-names :test #'string=)
                     :to-be-truthy)
             (expect (member backslash-name file-names :test #'string=)
                     :to-be-truthy)
             (expect (member "target-dir" directory-names :test #'string=)
                     :to-be-truthy)
             (expect (member "directory-link" directory-names :test #'string=)
                     :to-be-truthy)
             (expect backslash-candidate :to-be-truthy)
             (expect (concatenate 'string "cat " backslash-prefix
                                  (make-string 2 :initial-element (code-char 92))
                                  "slash.txt")
                     :to-equal
                     (nshell.presentation:apply-completion
                      (concatenate 'string "cat " backslash-prefix)
                      backslash-candidate)))
        (nshell.infrastructure.acl:clear-directory-listing-cache)))))
  (it "file-completion-filters-subsequence-candidates-when-a-prefix-exists"
    (let ((kb (nshell.domain.completion:make-empty-knowledge-base)))
      (with-test-filesystem
          (:directory-files
           (lambda (directory)
             (declare (ignore directory))
             (list #p"status" #p"s-t-a-t-u-s"))
           :subdirectories
           (constantly nil))
        (expect (list "status")
                :to-equal
                (completion-texts
                 (nshell.domain.completion:complete
                  kb "cat st" :filesystem *completion-test-filesystem*))))))
  (it "regular-file-preview-reader-bounds-byte-prefix"
    (host-kit:with-temporary-directory (directory)
      (let ((path (merge-pathnames "preview.txt" directory)))
        (host-kit:write-file-string "small" path)
        (let ((bytes (nshell.infrastructure.acl:read-regular-file-bytes path 8)))
          (expect "small" :to-equal
                  (sb-ext:octets-to-string bytes :external-format :utf-8)))
        (host-kit:write-file-string
         (make-string 100000 :initial-element #\x) path)
        (let ((bytes (nshell.infrastructure.acl:read-regular-file-bytes path 5)))
          (expect 5 :to-equal (length bytes))
          (expect "xxxxx" :to-equal
                  (sb-ext:octets-to-string bytes :external-format :utf-8))))))
  (it "regular-file-preview-reader-rejects-directories"
    (host-kit:with-temporary-directory (directory)
      (expect nil :to-equal
              (nshell.infrastructure.acl:read-regular-file-bytes directory 8))))
  (it "regular-file-preview-reader-rejects-permission-denied-files"
    (host-kit:with-temporary-directory (directory)
      (let ((path (merge-pathnames "private.txt" directory)))
        (host-kit:write-file-string "private" path)
        (unwind-protect
             (progn
               (sb-posix:chmod (namestring path) #o000)
               (expect nil :to-equal
                       (nshell.infrastructure.acl:read-regular-file-bytes
                        path 8)))
          (sb-posix:chmod (namestring path) #o600)))))
  (it "regular-file-preview-reader-rejects-symlinks"
    (host-kit:with-temporary-directory (directory)
      (let ((target (merge-pathnames "target.txt" directory))
            (link (merge-pathnames "preview-link.txt" directory)))
        (host-kit:write-file-string "target" target)
        (host-kit:create-symbolic-link target link)
        (expect nil :to-equal
                (nshell.infrastructure.acl:read-regular-file-bytes link 8)))))
  (it "regular-file-preview-reader-does-not-block-on-fifo"
    (host-kit:with-temporary-directory (directory)
      (let ((path (merge-pathnames "preview.fifo" directory))
            (finished-p nil)
            (result :not-finished)
            (reader-thread nil))
        (sb-posix:mkfifo (namestring path) #o600)
        (unwind-protect
             (progn
               (setf reader-thread
                     (sb-thread:make-thread
                      (lambda ()
                        (setf result
                              (handler-case
                                  (nshell.infrastructure.acl:read-regular-file-bytes
                                   path 8)
                                (error (condition) condition))
                              finished-p t))))
               (sb-thread:join-thread reader-thread :timeout 1)
               (expect finished-p :to-be-truthy)
               (expect nil :to-equal result))
          (when (and reader-thread
                     (sb-thread:thread-alive-p reader-thread))
            (sb-thread:terminate-thread reader-thread)
            (sb-thread:join-thread reader-thread)))))))
(describe "filesystem-completion-port-tests"
  (it "host port preserves kinds and ordered legacy candidates"
    (host-kit:with-temporary-directory (directory)
      (let* ((target-file (merge-pathnames "target.txt" directory))
             (target-directory (merge-pathnames "target-dir/" directory))
             (file-link (merge-pathnames "file-link" directory))
             (directory-link (merge-pathnames "directory-link" directory))
             (broken-link (merge-pathnames "broken-link" directory))
             (hidden-file (merge-pathnames ".hidden-file" directory))
             (hidden-directory (merge-pathnames ".hidden-directory/" directory))
             (special-file (merge-pathnames "special.fifo" directory))
             (filesystem (nshell.infrastructure.acl:make-host-filesystem))
             (entries nil)
             (directory-prefix (namestring (host-kit:ensure-directory-pathname directory)))
             (legacy-filesystem nil))
        (host-kit:write-file-string "target" target-file)
        (host-kit:write-file-string "hidden" hidden-file)
        (host-kit:ensure-directory-tree target-directory)
        (host-kit:ensure-directory-tree hidden-directory)
        (host-kit:create-symbolic-link target-file file-link)
        (host-kit:create-symbolic-link target-directory directory-link)
        (host-kit:create-symbolic-link
         (merge-pathnames "missing.txt" directory) broken-link)
        (sb-posix:mkfifo (namestring special-file) #o600)
        (nshell.infrastructure.acl:clear-directory-listing-cache)
        (unwind-protect
             (progn
               (setf entries
                     (funcall
                      (nshell.domain.filesystem:filesystem-completion-entries filesystem)
                      directory)
                     legacy-filesystem
                     (nshell.domain.filesystem:make-filesystem
                      :directory-files
                      (nshell.domain.filesystem:filesystem-directory-files filesystem)
                      :subdirectories
                      (nshell.domain.filesystem:filesystem-subdirectories filesystem)
                      :executable-p (constantly nil)))
               (labels ((entry (name)
                          (find name entries
                                :key (function nshell.domain.filesystem:filesystem-completion-entry-name)
                                :test (function string=)))
                        (signature (source prefix)
                          (mapcar
                           (lambda (candidate)
                             (list (nshell.domain.completion:candidate-text candidate)
                                   (nshell.domain.completion:candidate-kind candidate)
                                   (nshell.domain.completion:candidate-score candidate)
                                   (nshell.domain.completion:candidate-description candidate)))
                           (nshell.domain.completion::%file-candidates-from-directory
                            source (concatenate (quote string) directory-prefix prefix))))
                        (path-text (name) (concatenate (quote string) directory-prefix name))
                        (texts (source prefix)
                          (mapcar (function first) (signature source prefix))))
                 (expect :regular-file :to-be
                         (nshell.domain.filesystem:filesystem-completion-entry-kind
                          (entry "target.txt")))
                 (expect :directory :to-be
                         (nshell.domain.filesystem:filesystem-completion-entry-kind
                          (entry "target-dir")))
                 (expect :symbolic-link :to-be
                         (nshell.domain.filesystem:filesystem-completion-entry-kind
                          (entry "file-link")))
                 (expect :regular-file :to-be
                         (nshell.domain.filesystem:filesystem-completion-entry-target-kind
                          (entry "file-link")))
                 (expect :symbolic-link :to-be
                         (nshell.domain.filesystem:filesystem-completion-entry-kind
                          (entry "directory-link")))
                 (expect :directory :to-be
                         (nshell.domain.filesystem:filesystem-completion-entry-target-kind
                          (entry "directory-link")))
                 (expect :missing :to-be
                         (nshell.domain.filesystem:filesystem-completion-entry-target-kind
                          (entry "broken-link")))
                 (expect :unknown :to-be
                         (nshell.domain.filesystem:filesystem-completion-entry-kind
                          (entry "special.fifo")))
                 (expect (signature legacy-filesystem "") :to-equal
                         (signature filesystem ""))
                 (expect (signature legacy-filesystem ".") :to-equal
                         (signature filesystem "."))
                 (expect (member (path-text "file-link") (texts filesystem "")
                                 :test (function string=)) :to-be-truthy)
                 (expect (member (path-text "broken-link") (texts filesystem "")
                                 :test (function string=)) :to-be-truthy)
                 (expect (member (path-text "directory-link/") (texts filesystem "")
                                 :test (function string=)) :to-be-truthy)
                 (expect (member (path-text "target-dir/") (texts filesystem "")
                                 :test (function string=)) :to-be-truthy)
                 (expect (member (path-text "special.fifo") (texts filesystem "")
                                 :test (function string=)) :to-be-falsy)
                 (expect (member (concatenate (quote string) directory-prefix ".hidden-file") (texts filesystem "")
                                 :test (function string=)) :to-be-falsy)
                 (expect (member (concatenate (quote string) directory-prefix ".hidden-file") (texts filesystem ".")
                                 :test (function string=)) :to-be-truthy)
                 (expect (member (path-text ".hidden-directory/") (texts filesystem ".")
                                 :test (function string=)) :to-be-truthy))) (nshell.infrastructure.acl:clear-directory-listing-cache)))

  ) )
  (it "uses known dirent kinds and falls back for unknown types"
  (host-kit:with-temporary-directory (directory)
    (let* ((regular-file (merge-pathnames "regular.txt" directory))
           (subdirectory (merge-pathnames "sample-dir/" directory))
           (special-file (merge-pathnames "special.fifo" directory))
           (filesystem (nshell.infrastructure.acl:make-host-filesystem))
           (completion-entries
             (nshell.domain.filesystem:filesystem-completion-entries filesystem))
           (lstat-paths nil))
      (host-kit:write-file-string "regular" regular-file)
      (host-kit:ensure-directory-tree subdirectory)
      (sb-posix:mkfifo (namestring special-file) #o600)
      (nshell.infrastructure.acl:clear-directory-listing-cache)
      (unwind-protect
           (progn
             (with-rebound-function
                 (nshell.infrastructure.acl::%filesystem-completion-dirent-type-hint
                  (lambda (dirent)
                    (let ((name (sb-posix:dirent-name dirent)))
                      (cond
                        ((string= name "regular.txt") 8)
                        ((string= name "sample-dir") 4)
                        (t 0)))))
               (with-rebound-function
                   (sb-posix:lstat
                    (lambda (path)
                      (push path lstat-paths)
                      (funcall original-function path)))
                 (funcall completion-entries directory)))
             (expect
              (member (namestring regular-file) lstat-paths
                      :test (function string=))
              :to-be-falsy)
             (expect
              (member (namestring subdirectory) lstat-paths
                      :test (function string=))
              :to-be-falsy)
             (expect
              (member (namestring special-file) lstat-paths
                      :test (function string=))
              :to-be-truthy))
        (nshell.infrastructure.acl:clear-directory-listing-cache))))) (it "preserves directory-first duplicate precedence and deduplication"
    (let* ((entries
             (list (nshell.domain.filesystem:make-filesystem-completion-entry
                    :name "duplicate" :kind :directory)
                   (nshell.domain.filesystem:make-filesystem-completion-entry
                    :name "duplicate" :kind :regular-file)
                   (nshell.domain.filesystem:make-filesystem-completion-entry
                    :name "repeat" :kind :regular-file)
                   (nshell.domain.filesystem:make-filesystem-completion-entry
                    :name "repeat" :kind :regular-file)
                   (nshell.domain.filesystem:make-filesystem-completion-entry
                    :name "unknown" :kind :unknown)))
           (port-filesystem
             (nshell.domain.filesystem:make-filesystem
              :directory-files
              (lambda (directory)
                (declare (ignore directory))
                (list #p"duplicate" #p"repeat" #p"repeat"))
              :subdirectories
              (lambda (directory)
                (declare (ignore directory))
                (list #p"duplicate/" #p"duplicate/"))
              :completion-entries
              (lambda (directory)
                (declare (ignore directory))
                entries)
              :executable-p (constantly nil)))
           (legacy-filesystem
             (nshell.domain.filesystem:make-filesystem
              :directory-files
              (nshell.domain.filesystem:filesystem-directory-files port-filesystem)
              :subdirectories
              (nshell.domain.filesystem:filesystem-subdirectories port-filesystem)
              :executable-p (constantly nil)))
           (legacy-candidates
             (nshell.domain.completion::%file-candidates-from-directory
              legacy-filesystem ""))
           (port-candidates
             (nshell.domain.completion::%file-candidates-from-directory
              port-filesystem ""))
           (texts (mapcar (function nshell.domain.completion:candidate-text)
                          port-candidates)))
      (expect
       (mapcar
        (lambda (candidate)
          (list (nshell.domain.completion:candidate-text candidate)
                (nshell.domain.completion:candidate-kind candidate)
                (nshell.domain.completion:candidate-score candidate)
                (nshell.domain.completion:candidate-description candidate)))
        legacy-candidates)
       :to-equal
       (mapcar
        (lambda (candidate)
          (list (nshell.domain.completion:candidate-text candidate)
                (nshell.domain.completion:candidate-kind candidate)
                (nshell.domain.completion:candidate-score candidate)
                (nshell.domain.completion:candidate-description candidate)))
        port-candidates))
      (expect (list "repeat" "duplicate" "duplicate/") :to-equal texts)
      (expect 3 :to-equal (length texts)))) (it "reclassifies cached symlinks after external target changes"
    (host-kit:with-temporary-directory (directory)
      (host-kit:with-temporary-directory (target-directory)
        (let* ((target (merge-pathnames "external-target" target-directory))
               (link (merge-pathnames "external-link" directory))
               (directory-prefix
                 (namestring (host-kit:ensure-directory-pathname directory)))
               (filesystem (nshell.infrastructure.acl:make-host-filesystem))
               (completion-entries
                 (nshell.domain.filesystem:filesystem-completion-entries filesystem))
               (legacy-filesystem
                 (nshell.domain.filesystem:make-filesystem
                  :directory-files
                  (nshell.domain.filesystem:filesystem-directory-files filesystem)
                  :subdirectories
                  (nshell.domain.filesystem:filesystem-subdirectories filesystem)
                  :executable-p (constantly nil)))
               (signature
                 (lambda (source)
                   (mapcar
                    (lambda (candidate)
                      (list (nshell.domain.completion:candidate-text candidate)
                            (nshell.domain.completion:candidate-kind candidate)
                            (nshell.domain.completion:candidate-score candidate)
                            (nshell.domain.completion:candidate-description candidate)))
                    (nshell.domain.completion::%file-candidates-from-directory
                     source directory-prefix))))
               (before-entries nil)
               (entries nil)
               (before-port-signature nil)
               (before-legacy-signature nil)
               (port-signature nil)
               (legacy-signature nil))
          (host-kit:write-file-string "target" target)
          (host-kit:create-symbolic-link target link)
          (nshell.infrastructure.acl:clear-directory-listing-cache)
          (unwind-protect
               (progn
                 (setf before-entries
                       (funcall completion-entries directory)
                       before-port-signature
                       (funcall signature filesystem)
                       before-legacy-signature
                       (funcall signature legacy-filesystem))
                 (expect :regular-file :to-be
                         (nshell.domain.filesystem:filesystem-completion-entry-target-kind
                          (find "external-link" before-entries
                                :key (function nshell.domain.filesystem:filesystem-completion-entry-name)
                                :test (function string=))))
                 (expect before-port-signature :to-equal before-legacy-signature)
                 (expect (member
                          (concatenate (quote string) directory-prefix "external-link")
                          (mapcar (function first) before-port-signature)
                          :test (function string=))
                         :to-be-truthy)
                 (sb-posix:unlink (namestring target))
                 (sb-posix:mkdir (namestring target) #o700)
                 (setf entries (funcall completion-entries directory)
                       port-signature (funcall signature filesystem)
                       legacy-signature (funcall signature legacy-filesystem))
                 (expect :directory :to-be
                         (nshell.domain.filesystem:filesystem-completion-entry-target-kind
                          (find "external-link" entries
                                :key (function nshell.domain.filesystem:filesystem-completion-entry-name)
                                :test (function string=))))
                 (expect legacy-signature :to-equal port-signature)
                 (expect (member
                          (list (concatenate (quote string) directory-prefix "external-link/")
                                :directory 70 "directory")
                          port-signature
                          :test (function equal))
                         :to-be-truthy))
            (nshell.infrastructure.acl:clear-directory-listing-cache)))))))
