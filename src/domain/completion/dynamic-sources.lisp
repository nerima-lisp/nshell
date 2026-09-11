(in-package #:nshell.domain.completion)

;;; Variable completion: a token starting with $ or ${ completes from the
;;; live shell environment instead of the command/argument knowledge base.

(defun %variable-completion-word-prefix (word)
  "Return the lead-in string (\"$\" or \"${\") when WORD denotes a variable
completion token, or NIL otherwise. A produced candidate's TEXT keeps this
lead-in: APPLY-COMPLETION (src/presentation/completion-ui-logic.lisp)
replaces the whole shell token verbatim, the same convention a directory
candidate already relies on by carrying its own trailing slash in TEXT."
  (cond
    ((and (<= 2 (length word)) (char= (char word 0) #\$) (char= (char word 1) #\{))
     (subseq word 0 2))
    ((and (<= 1 (length word)) (char= (char word 0) #\$))
     (subseq word 0 1))))

(defun %truncate-variable-value (value &optional (limit 40))
  (if (> (length value) limit)
      (subseq value 0 limit)
      value))

(defun %variable-candidate (lead-in name value)
  (make-candidate (concatenate 'string lead-in name)
                  :kind :variable
                  :description (%truncate-variable-value (or value ""))))

(defun %variable-completion-candidates (word variable-names)
  "Return :VARIABLE candidates for WORD (a token starting with $ or ${)
against VARIABLE-NAMES, an alist of (NAME . VALUE) shell bindings."
  (let ((lead-in (%variable-completion-word-prefix word)))
    (when lead-in
      (let ((name-prefix (subseq word (length lead-in))))
        (sort
         (loop for entry in variable-names
               for name = (car entry)
               for value = (cdr entry)
               when (and (stringp name)
                         (%candidate-matches-prefix-policy-p name-prefix name))
                 collect (%variable-candidate lead-in name value))
         (function string<)
         :key (function candidate-text))))))

;;; git-aware dynamic completion: local branch names for checkout/switch/
;;; merge/rebase/branch -d, and modified paths for add/restore/diff. The
;;; domain performs no process I/O -- *GIT-BRANCH-LISTER* and
;;; *GIT-MODIFIED-PATH-LISTER* are hooks the composition root
;;; (src/presentation/repl-completion-seed.lisp) installs with the real git
;;; runner, mirroring NSHELL.DOMAIN.PROMPTING:*GIT-STATUS-RESOLVER*.

(defvar *git-branch-lister* nil
  "NIL, or a function of one argument (a directory) returning a list of
local git branch name strings for that directory.")

(defvar *git-modified-path-lister* nil
  "NIL, or a function of one argument (a directory) returning a list of
modified or staged path strings for that directory.")

(defparameter *git-dynamic-cache-ttl-seconds* 5
  "Seconds a cached git branch or modified-path listing stays valid, so
pressing Tab repeatedly does not fork a git subprocess per keystroke.")

(defparameter *git-dynamic-cache-clock-fn* (function get-universal-time)
  "Function of no arguments returning the current time; tests rebind it for
a deterministic clock.")

(defvar *git-dynamic-cache* (make-hash-table :test #'equal)
  "Directory- and kind-keyed cache of git dynamic completion listings.")

(defun %git-dynamic-cache-key (kind directory)
  (list kind (princ-to-string directory)))

(defun %git-dynamic-cached-listing (lister kind directory)
  (when (functionp lister)
    (let* ((key (%git-dynamic-cache-key kind directory))
           (now (funcall *git-dynamic-cache-clock-fn*))
           (entry (gethash key *git-dynamic-cache*)))
      (if (and entry (< (- now (car entry)) *git-dynamic-cache-ttl-seconds*))
          (cdr entry)
          (let ((listing (or (ignore-errors (funcall lister directory)) nil)))
            (setf (gethash key *git-dynamic-cache*) (cons now listing))
            listing)))))

(defun %invalidate-git-dynamic-cache ()
  "Discard all cached git branch and modified-path listings."
  (clrhash *git-dynamic-cache*)
  nil)

(defun %git-branches-for-directory (directory)
  (%git-dynamic-cached-listing *git-branch-lister* :branches directory))

(defun %git-modified-paths-for-directory (directory)
  (%git-dynamic-cached-listing *git-modified-path-lister* :modified-paths directory))

(defparameter +git-branch-argument-subcommands+ '("checkout" "switch" "merge" "rebase")
  "git subcommands whose first argument is a branch name.")

(defparameter +git-path-argument-subcommands+ '("add" "restore" "diff")
  "git subcommands whose arguments are working-tree paths.")

(defun %git-branch-argument-position-p (argument-words)
  (let ((subcommand (first argument-words)))
    (or (member subcommand +git-branch-argument-subcommands+ :test #'string=)
        (and (equal subcommand "branch")
             (member "-d" argument-words :test #'string=)))))

(defun %git-path-argument-position-p (argument-words)
  (member (first argument-words) +git-path-argument-subcommands+ :test #'string=))

(defun %git-branch-candidate (name)
  (make-candidate name :kind :command :description "branch"))

(defun %git-modified-path-candidate (path)
  (make-candidate path :kind :file :description "modified"))

(defun %git-dynamic-candidates (command argument-words prefix directory)
  (when (and directory (string= command "git"))
    (cond
      ((%git-branch-argument-position-p argument-words)
       (loop for name in (%git-branches-for-directory directory)
             when (and (stringp name) (%candidate-matches-prefix-policy-p prefix name))
               collect (%git-branch-candidate name)))
      ((%git-path-argument-position-p argument-words)
       (loop for path in (%git-modified-paths-for-directory directory)
             when (and (stringp path) (%candidate-matches-prefix-policy-p prefix path))
               collect (%git-modified-path-candidate path))))))

;;; Pure text parsing for the git plumbing output the composition root feeds
;;; into *GIT-BRANCH-LISTER* / *GIT-MODIFIED-PATH-LISTER*. Kept here, rather
;;; than in the presentation seed, so it is testable without process I/O.

(defun %git-output-lines (output)
  "Split OUTPUT into non-blank lines, trimming a trailing carriage return."
  (let ((lines nil) (start 0) (length (length (or output ""))))
    (loop
      (let ((newline (position #\Newline output :start start)))
        (push (string-right-trim '(#\Return) (subseq output start (or newline length))) lines)
        (if newline
            (setf start (1+ newline))
            (return))))
    (remove-if (lambda (line) (zerop (length line))) (nreverse lines))))

(defun %git-porcelain-status-path (line)
  "Return the path named by one `git status --porcelain` LINE, following a
rename's arrow to its destination path."
  (when (> (length line) 3)
    (let* ((rest (subseq line 3))
           (arrow (search " -> " rest)))
      (if arrow (subseq rest (+ arrow 4)) rest))))

(defun %git-porcelain-status-paths (output)
  (remove-if #'null (mapcar (function %git-porcelain-status-path) (%git-output-lines output))))
