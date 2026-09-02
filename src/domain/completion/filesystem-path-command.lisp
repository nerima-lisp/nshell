(in-package #:nshell.domain.completion)

(defun %command-prefix-has-directory-p (prefix)
  (position-if #'%path-separator-p prefix))

(defun %split-path (path)
  (let ((start 0)
        (parts nil))
    (loop for pos = (position #\: path :start start)
          do (push (subseq path start pos) parts)
          while pos
          do (setf start (1+ pos)))
    (nreverse parts)))

(defun %join-directory-command (directory command &key (empty-directory directory))
  (let ((dir (if (string= directory "") empty-directory directory)))
    (cond
      ((string= dir "") command)
      ((%path-separator-p (char dir (1- (length dir))))
       (concatenate 'string dir command))
      (t (concatenate 'string dir "/" command)))))

(defun command-path-candidates (command path executable-p &key (empty-directory ""))
  "Return executable path candidates for COMMAND projected through PATH."
  (if (%command-prefix-has-directory-p command)
      (when (funcall executable-p command)
        (list command))
      (loop for directory in (%split-path (or path ""))
            for candidate = (%join-directory-command
                             directory command :empty-directory empty-directory)
            when (funcall executable-p candidate)
            collect candidate)))

(defun %first-command-path-candidate (command path executable-p
                                      &key (empty-directory ""))
  (if (%command-prefix-has-directory-p command)
      (when (funcall executable-p command)
        command)
      (loop for directory in (%split-path (or path ""))
            for candidate = (%join-directory-command
                             directory command :empty-directory empty-directory)
            when (funcall executable-p candidate)
              do (return candidate))))

(defun %entry-command-name (entry)
  (let ((name (if (pathnamep entry)
                  (file-namestring entry)
                  (let* ((text (princ-to-string entry))
                         (slash (position-if #'%path-separator-p text :from-end t)))
                    (if slash (subseq text (1+ slash)) text)))))
    (and (< 0 (length name)) name)))

(defun %executable-candidate-p (entry filesystem)
  (let ((executable-p
          (and (nshell.domain.filesystem:filesystem-p filesystem)
               (nshell.domain.filesystem:filesystem-executable-p filesystem))))
    (and (functionp executable-p)
         (ignore-errors (funcall executable-p entry)))))

(defun %path-command-query-active-p (query filesystem)
  (and (nshell.domain.filesystem:filesystem-p filesystem)
       (functionp
        (nshell.domain.filesystem:filesystem-directory-files filesystem))
       (%path-command-query-path query)
       (not (%command-prefix-has-directory-p
             (%path-command-query-prefix query)))))

(defun %path-command-entry-candidate (entry prefix executable-p)
  (let ((name (%entry-command-name entry)))
    (when (and name
               (%starts-with-p prefix name)
               (funcall executable-p entry))
      (make-candidate name :kind :command))))

(defun %path-command-candidates-from-entries
    (entries-by-directory prefix executable-p)
  "Reduce ordered PATH entries to deterministic executable candidates.

The caller owns directory enumeration, caching, and concurrency.  This
function only performs filtering, deduplication, error isolation, and
ordering, so those semantics can be tested without a filesystem."
  (let ((candidates (%make-empty-filesystem-candidate-set)))
    (dolist (entries entries-by-directory)
      (handler-case
          (dolist (entry entries)
            (setf candidates
                  (%filesystem-candidate-set-add
                   candidates
                   (%path-command-entry-candidate entry prefix executable-p))))
        (error () candidates)))
    (sort (%filesystem-candidate-set-candidates candidates)
          #'string<
          :key #'candidate-text)))

(defun %make-path-command-directory-reader (filesystem)
  "Return a reader that carries the request-local filesystem into workers."
  (let ((directory-stamp-fn *path-command-directory-stamp-fn*)
        (cache-clock-fn *path-command-cache-clock-fn*)
        (cache-ttl-seconds *path-command-cache-ttl-seconds*)
        (cache-limit *path-command-cache-limit*))
    (lambda (directory)
      (let ((*path-command-directory-stamp-fn* directory-stamp-fn)
            (*path-command-cache-clock-fn* cache-clock-fn)
            (*path-command-cache-ttl-seconds* cache-ttl-seconds)
            (*path-command-cache-limit* cache-limit))
        (handler-case
            (%list-path-command-directory directory filesystem)
          (error () nil))))))

(defun %command-candidates-from-path (path prefix filesystem)
  "Return executable command candidates from PATH that start with PREFIX."
  (let ((query (%make-path-command-query path prefix)))
    (if (not (%path-command-query-active-p query filesystem))
        nil
        (let* ((directory-map
                 (and (nshell.domain.filesystem:filesystem-p filesystem)
                      (nshell.domain.filesystem:filesystem-directory-map
                       filesystem)))
               (query-prefix (%path-command-query-prefix query))
               (directories (%split-path (%path-command-query-path query)))
               (entries-by-directory
                 (and (functionp directory-map)
                      (funcall directory-map
                               (%make-path-command-directory-reader filesystem)
                               directories))))
          (when entries-by-directory
            (%path-command-candidates-from-entries
             entries-by-directory
             query-prefix
             (lambda (entry)
               (%executable-candidate-p entry filesystem))))))))
