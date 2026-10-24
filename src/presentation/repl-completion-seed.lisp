;;; REPL completion seed data
(in-package #:nshell.presentation)

;;; Keep process I/O outside the domain by supplying Git-backed hooks
;;; for completion requests that carry the current directory.

(defun %seed-git-branch-lister (directory)
  (multiple-value-bind (output exit-code)
      (nshell.infrastructure.acl:%run-git
       directory '("for-each-ref" "--format=%(refname:short)" "refs/heads/"))
    (when (zerop exit-code)
      (nshell.domain.completion:%git-output-lines output))))

(defun %seed-git-modified-path-lister (directory)
  (multiple-value-bind (output exit-code)
      (nshell.infrastructure.acl:%run-git
       directory '("status" "--porcelain" "--untracked-files=no"))
    (when (zerop exit-code)
      (nshell.domain.completion:%git-porcelain-status-paths output))))

(defun seed-repl-completion-knowledge-base (knowledge-base)
  (setf nshell.domain.completion:*git-branch-lister* (function %seed-git-branch-lister)
        nshell.domain.completion:*git-modified-path-lister* (function %seed-git-modified-path-lister))
  (dolist (spec (append (nshell.domain.completion:builtin-completion-command-specs)
                        (nshell.domain.completion:external-completion-command-specs)
                        (nshell.domain.completion:external-subcommand-completion-command-specs))
                knowledge-base)
    (destructuring-bind (command &key subcommands flags option-values option-value-kinds
                         exclusive-options description &allow-other-keys)
        spec
      (nshell.domain.completion:kb-add-command knowledge-base command
                                               :subcommands subcommands
                                               :flags flags
                                               :option-values option-values
                                               :option-value-kinds option-value-kinds
                                               :exclusive-options exclusive-options
                                               :description description))))
(progn
  (defun %seed-bounded-lines (path byte-limit line-limit)
    (handler-case
        (with-open-file (stream path :direction :input
                                :if-does-not-exist nil
                                :element-type '(unsigned-byte 8))
          (when stream
            (let* ((octets (make-array (1+ byte-limit)
                                       :element-type '(unsigned-byte 8)))
                   (count (read-sequence octets stream :end (1+ byte-limit)))
                   (limit (min count byte-limit))
                   (end (if (> count byte-limit)
                            (let ((newline (position 10 octets :end limit :from-end t)))
                              (if newline (1+ newline) 0))
                            count))
                   (text (make-string end)))
              (dotimes (index end)
                (setf (char text index)
                      (if (< (aref octets index) 128)
                          (code-char (aref octets index))
                          #\?)))
              (with-input-from-string (input text)
                (loop repeat line-limit
                      for line = (read-line input nil nil)
                      while line
                      collect (string-right-trim '(#\Return) line))))))
      (file-error () nil)))

  (defun %seed-home-file (home-directory relative-path)
    (when (and (stringp home-directory) (plusp (length home-directory)))
      (merge-pathnames relative-path
                       (uiop:ensure-directory-pathname home-directory))))

  (defun %seed-ssh-hosts (home-directory)
    (nshell.domain.completion::%ssh-host-names-from-text
     (%seed-bounded-lines (%seed-home-file home-directory ".ssh/config") 32768 512)
     (%seed-bounded-lines (%seed-home-file home-directory ".ssh/known_hosts") 1048576 4096)))

  (defun %seed-make-targets (directory)
    (when (stringp directory)
      (let ((base (uiop:ensure-directory-pathname directory)))
        (nshell.domain.completion::%makefile-target-names
         (loop for name in '("GNUmakefile" "Makefile" "makefile")
               append (%seed-bounded-lines (merge-pathnames name base) 262144 8192))))))

  (defun %seed-usernames ()
    (loop for line in (%seed-bounded-lines #P"/etc/passwd" 1048576 8192)
          for separator = (position #\: line)
          when (and separator (plusp separator))
            collect (subseq line 0 separator)))

  (setf nshell.domain.completion::*ssh-host-lister* (function %seed-ssh-hosts)
        nshell.domain.completion::*make-target-lister* (function %seed-make-targets)
        nshell.domain.completion::*username-lister* (function %seed-usernames)))

