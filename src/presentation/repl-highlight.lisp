;;; Session-aware command classification for syntax highlighting.
(in-package #:nshell.presentation)

(defparameter +repl-highlight-keywords+
  (append nshell.domain.parsing:+control-flow-keywords+ '("function"))
  "Words nshell's parser treats as control-flow syntax rather than commands.")

(defvar *repl-filesystem* nil)

(defun %repl-environment-path ()
  (and *environment* (nshell.domain.environment:env-get *environment* "PATH")))

(defun %repl-table-member-p (name table)
  (and (hash-table-p table) (nth-value 1 (gethash name table))))

;;; PATH lookups for highlighting, memoized per command name.
;;;
;;; A memo entry records the PATH value and the stamp (mtime) of every PATH
;;; directory its search visited, and stays valid while the per-prompt stamp
;;; snapshot still shows those stamps. The snapshot is retaken once per prompt
;;; (REFRESH-REPL-COMMAND-PATH-STAMPS), never per key, so classifying a
;;; memoized name does no file I/O. An unmemoized name is searched exactly as
;;; HOST-KIT:FIND-PROGRAM searches PATH. Execution resolves commands on its own
;;; and never reads this memo.

(defparameter *repl-command-path-stamp-settle-seconds* 2
  "A directory mtime at least this many seconds older than the snapshot is
settled: a later change gets a later whole-second mtime.")

(defparameter *repl-command-path-memo-max-age-seconds* 30
  "Memo entries older than this are dropped at the next prompt, which bounds
how long an execute-permission change (no mtime change) stays unseen.")

(defparameter *repl-command-path-memo-limit* 512)

(defvar *repl-command-path-stamp-fn* #'file-write-date
  "Function of an absolute directory namestring returning its mtime.")

(defvar *repl-command-path-search-fn*
  (lambda (name directory)
    (host-kit:find-program name :path directory))
  "Function of NAME and one PATH element returning the executable or NIL.")

(defvar *repl-command-path-clock-fn* #'get-universal-time)

(defvar *repl-command-path-stamps* nil
  "(PATH . VECTOR) of per-element stamps taken at the last prompt. An element
is an integer mtime, :MISSING, or :VOLATILE (relative element or unsettled
mtime), which no memo entry may depend on.")

(defvar *repl-command-path-memo* (make-hash-table :test #'equal)
  "NAME -> (PATH STAMPS FOUND-P CREATED-AT).")

(defun %repl-path-elements (path)
  (loop with start = 0
        for end = (position #\: path :start start)
        collect (subseq path start end)
        while end
        do (setf start (1+ end))))

(defun %repl-path-directory-stamp (directory now)
  (if (or (zerop (length directory))
          (char/= (char directory 0) #\/))
      :volatile
      (let ((stamp (ignore-errors
                    (funcall *repl-command-path-stamp-fn* directory))))
        (cond
          ((null stamp) :missing)
          ((and (integerp stamp)
                (<= (+ stamp *repl-command-path-stamp-settle-seconds*) now))
           stamp)
          (t :volatile)))))

(defun refresh-repl-command-path-stamps ()
  "Retake the PATH directory stamps and drop aged memo entries. Runs once per
prompt, outside key handling."
  (let ((path (%repl-environment-path))
        (now (funcall *repl-command-path-clock-fn*)))
    (setf *repl-command-path-stamps*
          (and path
               (cons path
                     (map 'vector
                          (lambda (directory)
                            (%repl-path-directory-stamp directory now))
                          (%repl-path-elements path)))))
    (maphash (lambda (name entry)
               (when (> (- now (fourth entry))
                        *repl-command-path-memo-max-age-seconds*)
                 (remhash name *repl-command-path-memo*)))
             *repl-command-path-memo*)
    nil))

(defun %repl-path-snapshot-for (path)
  (let ((snapshot *repl-command-path-stamps*))
    (and snapshot (equal (car snapshot) path) (cdr snapshot))))

(defun %repl-memoized-path-lookup (name path)
  "Return the memoized result for NAME and T, or NIL and NIL."
  (let ((entry (gethash name *repl-command-path-memo*))
        (stamps (%repl-path-snapshot-for path)))
    (if (and entry
             stamps
             (equal (first entry) path)
             (loop for stamp in (second entry)
                   for index from 0
                   always (eql stamp (aref stamps index))))
        (values (third entry) t)
        (values nil nil))))

(defun %repl-search-path (name path)
  "Search PATH like HOST-KIT:FIND-PROGRAM and memoize the result when every
visited directory has a settled stamp in the current snapshot."
  (let ((stamps (%repl-path-snapshot-for path))
        (visited nil)
        (found-p nil))
    (loop for directory in (%repl-path-elements path)
          for index from 0
          do (push (if (and stamps (< index (length stamps)))
                       (aref stamps index)
                       :volatile)
                   visited)
             (when (funcall *repl-command-path-search-fn* name directory)
               (setf found-p t)
               (loop-finish)))
    (setf visited (nreverse visited))
    (when (and stamps (notany (lambda (stamp) (eq stamp :volatile)) visited))
      (when (>= (hash-table-count *repl-command-path-memo*)
                *repl-command-path-memo-limit*)
        (clrhash *repl-command-path-memo*))
      (setf (gethash name *repl-command-path-memo*)
            (list path visited found-p
                  (funcall *repl-command-path-clock-fn*))))
    found-p))

(defun %repl-command-on-path-p (name)
  (let ((path (%repl-environment-path)))
    (cond
      ((find #\/ name)
       (not (null (host-kit:find-program name :path path))))
      ((null path) nil)
      (t
       (multiple-value-bind (found-p memoized-p)
           (%repl-memoized-path-lookup name path)
         (if memoized-p
             found-p
             (%repl-search-path name path)))))))

(defun %repl-command-kind (name)
  "Classify NAME for syntax highlighting by consulting, in order, shell
keywords, the builtin registry, the session's functions, aliases, and
abbreviations, and finally PATH."
  (cond
    ((member name +repl-highlight-keywords+ :test #'string=) :keyword)
    ((nshell.application:lookup-builtin name) :builtin)
    ((%repl-table-member-p name *functions*) :function)
    ((%repl-table-member-p name *aliases*) :alias)
    ((%repl-table-member-p name *abbreviations*) :abbreviation)
    ((%repl-command-on-path-p name) :external)
    (t nil)))

(setf *highlight-command-resolver* #'%repl-command-kind)

(defun %edit-distance-within-one-p (a b)
  "True when A and B differ by at most one insertion, deletion, substitution,
or transposition of adjacent characters."
  (let ((la (length a))
        (lb (length b)))
    (cond
      ((> (abs (- la lb)) 1) nil)
      ((= la lb)
       (let ((mismatch (mismatch a b)))
         (or (null mismatch)
             (string= a b :start1 (1+ mismatch) :start2 (1+ mismatch))
             (and (< (1+ mismatch) la)
                  (char= (char a mismatch) (char b (1+ mismatch)))
                  (char= (char a (1+ mismatch)) (char b mismatch))
                  (string= a b :start1 (+ mismatch 2) :start2 (+ mismatch 2))))))
      (t
       (let* ((long (if (> la lb) a b))
              (short (if (> la lb) b a))
              (mismatch (or (mismatch short long) (length short))))
         (string= short long :start1 mismatch :start2 (1+ mismatch)))))))

(defun %repl-path-command-names ()
  "Every executable basename on PATH, through the completion engine's cached
directory listing so a correction never walks PATH itself."
  (let ((path (%repl-environment-path)))
    (when path
      (ignore-errors
       (mapcar (lambda (candidate)
                 (nshell.domain.completion:candidate-text candidate))
               (nshell.domain.completion:%command-candidates-from-path
                path "" *repl-filesystem*))))))

(defun %repl-table-names (table)
  (when (hash-table-p table)
    (loop for name being the hash-keys of table collect name)))

(defun %repl-known-command-names ()
  (append +repl-highlight-keywords+
          (loop for name being the hash-keys of nshell.application:*builtin-registry*
                collect name)
          (%repl-table-names *functions*)
          (%repl-table-names *aliases*)
          (%repl-table-names *abbreviations*)
          (when *kb*
            (nshell.domain.completion::kb-registered-commands *kb*))
          (%repl-path-command-names)))

(defun %repl-command-corrections (name &key (limit 3))
  "Up to LIMIT known command names within one edit of NAME, nearest first: an
exact match differing only in case, then one edit away."
  (when (plusp (length name))
    (let ((exact '())
          (near '()))
      (dolist (candidate (remove-duplicates (%repl-known-command-names)
                                            :test #'string=))
        (unless (string= candidate name)
          (cond
            ((string-equal candidate name) (push candidate exact))
            ((%edit-distance-within-one-p candidate name) (push candidate near)))))
      (let ((ordered (append (sort exact #'string<) (sort near #'string<))))
        (subseq ordered 0 (min limit (length ordered)))))))
