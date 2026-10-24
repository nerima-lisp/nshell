(in-package #:nshell.domain.completion)

;;; Variable completion: a token starting with $ or ${ completes from the
;;; live shell environment instead of the command/argument knowledge base.

(defun %variable-completion-word-prefix (word)
  "Return the lead-in string (\"$\" or \"${\") when WORD denotes a variable completion token, or NIL otherwise. Candidate TEXT keeps this lead-in because APPLY-COMPLETION replaces the whole shell token verbatim."
  (unless (position #\/ word)
    (cond
      ((and (<= 2 (length word)) (char= (char word 0) #\$) (char= (char word 1) #\{))
       (subseq word 0 2))
      ((and (<= 1 (length word)) (char= (char word 0) #\$))
       (subseq word 0 1)))))

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
(progn
  (defvar *ssh-host-lister* nil)
  (defvar *make-target-lister* nil)
  (defvar *username-lister* nil)

  (defparameter +kill-signal-names+
    '("-HUP" "-INT" "-QUIT" "-KILL" "-TERM" "-USR1" "-USR2"
      "-STOP" "-CONT" "-TSTP" "-TTIN" "-TTOU"))

  (defparameter +completion-wrappers+ '("sudo" "env" "time" "xargs" "nohup"))

  (defun %completion-text-words (line)
    (loop with start = 0
          for word-start = (position-if-not
                            (lambda (character)
                              (member character '(#\Space #\Tab #\Return)))
                            line :start start)
          while word-start
          for end = (position-if
                     (lambda (character)
                       (member character '(#\Space #\Tab #\Return)))
                     line :start word-start)
          collect (subseq line word-start (or end (length line)))
          while end
          do (setf start end)))

  (defun %literal-host-name-p (name)
    (and (plusp (length name))
         (every (lambda (character)
                  (or (alphanumericp character)
                      (member character '(#\- #\_ #\.))))
                name)))

  (defun %host-list-names (field)
    (loop with start = 0
          for end = (position #\, field :start start)
          for name = (subseq field start (or end (length field)))
          when (%literal-host-name-p name) collect name
          while end
          do (setf start (1+ end))))

  (defun %ssh-host-names-from-text (config-lines known-host-lines)
    (let ((names nil))
      (dolist (line config-lines)
        (let ((words (%completion-text-words
                      (subseq line 0 (or (position #\# line) (length line))))))
          (when (and words (string-equal (first words) "Host"))
            (dolist (name (rest words))
              (when (%literal-host-name-p name)
                (push name names))))))
      (dolist (line known-host-lines)
        (let* ((words (%completion-text-words
                       (subseq line 0 (or (position #\# line) (length line)))))
               (host-field (cond
                             ((and words (char= (char (first words) 0) #\@))
                              (second words))
                             (words (first words)))))
          (when (and host-field
                     (not (%starts-with-p "|1|" host-field)))
            (dolist (name (%host-list-names host-field))
              (push name names)))))
      (sort (remove-duplicates names :test #'string-equal) #'string<)))

  (defun %makefile-target-names (lines)
  (let ((targets nil))
    (dolist (line lines)
      (unless (and (plusp (length line)) (char= (char line 0) #\Tab))
        (let* ((comment (position #\# line))
               (content (string-trim '(#\Space #\Tab #\Return)
                                     (subseq line 0 (or comment (length line)))))
               (colon (position #\: content)))
          (when (and colon
                     (plusp colon)
                     (not (and (< (1+ colon) (length content))
                               (char= #\= (char content (1+ colon))))))
            (let ((header (subseq content 0 colon)))
              (unless (or (position #\= header)
                          (position #\% header)
                          (member header '(".PHONY" ".SUFFIXES" ".DEFAULT" ".PRECIOUS"
                                           ".INTERMEDIATE" ".SECONDARY" ".DELETE_ON_ERROR")
                                  :test #'string=))
                (dolist (target (%completion-text-words header))
                  (when (and (plusp (length target))
                             (not (position #\% target))
                             (not (position #\= target)))
                    (push target targets)))))))))
    (sort (remove-duplicates targets :test #'string=) #'string<)))


  (defun %username-name-p (name)
    (and (stringp name)
         (plusp (length name))
         (every (lambda (character)
                  (or (alphanumericp character)
                      (member character '(#\_ #\- #\.))))
                name)))

  (defun %username-completion-candidates (prefix variable-names)
    (when (and (plusp (length prefix))
               (char= (char prefix 0) #\~)
               (not (position #\/ prefix)))
      (let ((names (when (functionp *username-lister*)
                     (ignore-errors (funcall *username-lister*))))
            (name-prefix (subseq prefix 1)))
        (dolist (variable '("USER" "LOGNAME"))
          (let ((value (cdr (assoc variable variable-names :test #'string=))))
            (when (%username-name-p value)
              (push value names))))
        (sort (remove-duplicates
               (loop for name in names
                     when (and (%username-name-p name)
                               (%candidate-matches-prefix-policy-p name-prefix name))
                       collect (make-candidate (concatenate 'string "~" name "/")
                                               :kind :directory
                                               :description "user"))
               :key #'candidate-text :test #'string=)
              #'string< :key #'candidate-text))))

  (defun %ssh-host-candidates (command prefix home-directory)
    (when (and (string= command "ssh") home-directory (functionp *ssh-host-lister*))
      (loop for name in (or (ignore-errors (funcall *ssh-host-lister* home-directory)) nil)
            when (and (stringp name)
                      (%candidate-matches-prefix-policy-p prefix name))
              collect (make-candidate name :kind :command :description "SSH host"))))

  (defun %make-target-candidates (command prefix directory)
    (when (and (member command '("make" "gmake") :test #'string=)
               directory (functionp *make-target-lister*))
      (loop for name in (or (ignore-errors (funcall *make-target-lister* directory)) nil)
            when (and (stringp name)
                      (%candidate-matches-prefix-policy-p prefix name))
              collect (make-candidate name :kind :command :description "make target"))))

  (defun %kill-dynamic-candidates (command prefix process-ids)
    (when (string= command "kill")
      (if (%starts-with-p "-" prefix)
          (loop for name in +kill-signal-names+
                when (%candidate-matches-prefix-policy-p prefix name)
                  collect (make-candidate name :kind :option :description "signal"))
          (loop for pid in process-ids
                for text = (if (stringp pid) pid (princ-to-string pid))
                when (%candidate-matches-prefix-policy-p prefix text)
                  collect (make-candidate text :kind :command :description "process id")))))

  (defun %wrapper-option-value-p (wrapper word)
    (member word
            (cond
              ((string= wrapper "sudo") '("-u" "-g" "-h" "-p" "-C" "-T" "-R" "-r" "-t" "-D"))
              ((string= wrapper "env") '("-u" "--unset" "-C" "--chdir"))
              ((string= wrapper "time") '("-f" "--format" "-o" "--output"))
              ((string= wrapper "xargs") '("-n" "--max-args" "-I" "--replace" "-d" "--delimiter"
                                            "-s" "--max-chars" "-P" "--max-procs"))
              (t nil))
            :test #'string=))

  (defun %wrapper-flag-p (wrapper word)
    (and (%starts-with-p "-" word)
         (or (member word
                     (cond
                       ((string= wrapper "sudo") '("-E" "-H" "-n" "-S" "-s" "-i" "--"))
                       ((string= wrapper "env") '("-i" "--ignore-environment" "-0" "--null" "--"))
                       ((string= wrapper "time") '("-p" "-v" "--verbose" "--"))
                       ((string= wrapper "xargs") '("-0" "-r" "-t" "-p" "-x" "--"))
                       ((string= wrapper "nohup") '("--"))
                       (t nil))
                     :test #'string=)
             (and (> (length word) 2)
                  (member wrapper '("sudo" "env" "xargs") :test #'string=)
                  (char= (char word 0) #\-)
                  (not (char= (char word 1) #\-))))))

  (defun %wrapper-command-index (wrapper words)
    (loop with index = 0
          while (< index (length words))
          for word = (nth index words)
          do (cond
               ((string= word "--")
                (return (1+ index)))
               ((and (string= wrapper "env")
                     (search "=" word)
                     (not (%starts-with-p "-" word)))
                (incf index))
               ((%wrapper-option-value-p wrapper word)
                (incf index 2))
               ((%wrapper-flag-p wrapper word)
                (incf index))
               (t (return index)))
          finally (return nil)))

  (defun %unwrap-completion-context (context)
    (let ((wrapper (nshell.domain.completion:completion-context-command context)))
      (when (member wrapper +completion-wrappers+ :test #'string=)
        (let* ((words (nshell.domain.completion:completion-context-argument-words context))
               (index (%wrapper-command-index wrapper words)))
          (if (or (null index) (>= index (length words)))
              (%make-completion-context :command ""
                                        :command-position-p t
                                        :redirection-target-p
                                        (nshell.domain.completion:completion-context-redirection-target-p context))
              (let* ((command (nth index words))
                     (current-command-p
                       (and (= index (1- (length words)))
                            (not (string= ""
                                          (nshell.domain.completion:completion-context-argument-prefix
                                           context)))))
                     (arguments (nthcdr (1+ index) words)))
                (%make-completion-context
                 :command command
                 :argument-prefix
                 (if current-command-p ""
                     (nshell.domain.completion:completion-context-argument-prefix context))
                 :argument-words (if current-command-p nil arguments)
                 :command-position-p current-command-p
                 :redirection-target-p
                 (nshell.domain.completion:completion-context-redirection-target-p context)))))))))

