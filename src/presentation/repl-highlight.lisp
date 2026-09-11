;;; Session-aware command classification for syntax highlighting.
(in-package #:nshell.presentation)

(defparameter +repl-highlight-keywords+
  (append nshell.domain.parsing::+control-flow-keywords+ '("function"))
  "Words nshell's parser treats as control-flow syntax rather than commands.")

(defvar *repl-highlight-path-cache* (make-hash-table :test #'equal)
  "Memoizes PATH lookups for %REPL-COMMAND-KIND, keyed by command name.")

(defvar *repl-highlight-path-cache-key* nil
  "The PATH string *REPL-HIGHLIGHT-PATH-CACHE* was built against.")

(defun %repl-environment-path ()
  (and *environment* (nshell.domain.environment:env-get *environment* "PATH")))

(defun %repl-table-member-p (name table)
  (and (hash-table-p table) (nth-value 1 (gethash name table))))

(defun %repl-command-on-path-p (name)
  (let ((path (%repl-environment-path)))
    (unless (equal path *repl-highlight-path-cache-key*)
      (clrhash *repl-highlight-path-cache*)
      (setf *repl-highlight-path-cache-key* path))
    (multiple-value-bind (cached present-p) (gethash name *repl-highlight-path-cache*)
      (if present-p
          cached
          (setf (gethash name *repl-highlight-path-cache*)
                (not (null (host-kit:find-program name :path path))))))))

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
               (nshell.domain.completion::%command-candidates-from-path
                path "" (nshell.infrastructure.acl:make-host-filesystem)))))))

(defun %repl-table-names (table)
  (when (hash-table-p table)
    (loop for name being the hash-keys of table collect name)))

(defun %repl-known-command-names ()
  (append +repl-highlight-keywords+
          (loop for name being the hash-keys of nshell.application::*builtin-registry*
                collect name)
          (%repl-table-names *functions*)
          (%repl-table-names *aliases*)
          (%repl-table-names *abbreviations*)
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
