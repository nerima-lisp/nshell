;;;; Per-key cost measurement for the interactive REPL path (P0-7 B3).
;;;;
;;;; One "key" is everything the REPL does between reading a key event and
;;;; asking for the next one: %PROCESS-INPUT-EVENT, the output-event handler,
;;;; and RENDER-PROMPT-CONT, driven through the same CPS trampoline steps as
;;;; RUN-REPL. Only the terminal itself is replaced: output goes to a discarding
;;;; stream and the window size is fixed.
;;;;
;;;; This file is loaded both by nshell/test and by scripts/perf/b3-measure.sh
;;;; against an arbitrary nshell source tree, so it names nshell internals only
;;;; through %NSYM at run time; a missing internal is a clear error instead of a
;;;; read-time package failure.

(defpackage #:nshell.perf.key-cost
  (:use #:cl)
  (:export #:io-hook-specs
           #:installed-io-hooks
           #:with-io-hooks
           #:call-counting-io
           #:io-counts-stat
           #:io-counts-file-io
           #:io-counts-spawn
           #:io-counts-by-hook
           #:io-counts-source
           #:io-counts-lisp-totals
           #:libc-counter-available-p
           #:precise-bytes-consed
           #:call-with-key-session
           #:make-fixture
           #:remove-fixture
           #:fixture-root
           #:fixture-work-directory
           #:fixture-big-directory
           #:drive-key
           #:key-event
           #:default-scenarios
           #:measure-scenario
           #:measure-scenarios
           #:scenario-result-name
           #:scenario-result-keys
           #:scenario-result-bytes
           #:scenario-result-stat-per-key
           #:scenario-result-file-io-per-key
           #:scenario-result-spawn-per-key
           #:scenario-result-hook-counts
           #:scenario-result-real-ms
           #:scenario-result-counter-source
           #:scenario-result-io-gate
           #:write-results-json
           #:main))

(in-package #:nshell.perf.key-cost)

(defun %nsym (package-name symbol-name)
  (let ((package (or (find-package package-name)
                     (error "key-cost: package ~a is not loaded" package-name))))
    (multiple-value-bind (symbol status) (find-symbol symbol-name package)
      (unless status
        (error "key-cost: ~a::~a does not exist in the loaded nshell"
               package-name symbol-name))
      symbol)))

(defun %ncall (package-name symbol-name &rest arguments)
  (apply (symbol-function (%nsym package-name symbol-name)) arguments))

(defun %pres (name) (%nsym "NSHELL.PRESENTATION" name))

;;; I/O counters
;;;
;;; Each hook encapsulates the lowest Lisp-visible entry point of one system
;;; call family. Hooks count only while *COUNTING-P* is true, from any thread,
;;; so work a key hands to a worker thread is included while the key runs.

(defparameter *io-hook-specs*
  '((:stat "SB-UNIX" "UNIX-STAT")
    (:stat "SB-UNIX" "UNIX-LSTAT")
    (:stat "SB-UNIX" "UNIX-FSTAT")
    (:stat "SB-UNIX" "UNIX-ACCESS")
    (:stat "SB-UNIX" "UNIX-REALPATH")
    (:stat "SB-UNIX" "UNIX-READLINK")
    (:stat "SB-POSIX" "STAT")
    (:stat "SB-POSIX" "LSTAT")
    (:stat "SB-POSIX" "FSTAT")
    (:stat "SB-POSIX" "ACCESS")
    (:stat "SB-POSIX" "READLINK")
    (:file-io "SB-UNIX" "UNIX-OPEN")
    (:file-io "SB-UNIX" "UNIX-RENAME")
    (:file-io "SB-UNIX" "UNIX-UNLINK")
    (:file-io "SB-UNIX" "UNIX-MKDIR")
    (:file-io "SB-IMPL" "CALL-WITH-NATIVE-DIRECTORY-ITERATOR")
    (:file-io "SB-POSIX" "OPEN")
    (:file-io "SB-POSIX" "CREAT")
    (:file-io "SB-POSIX" "OPENDIR")
    (:file-io "SB-POSIX" "RENAME")
    (:file-io "SB-POSIX" "UNLINK")
    (:file-io "SB-POSIX" "MKDIR")
    (:file-io "SB-POSIX" "RMDIR")
    (:file-io "SB-POSIX" "LINK")
    (:file-io "SB-POSIX" "SYMLINK")
    (:file-io "SB-POSIX" "FSYNC")
    (:spawn "SB-IMPL" "SPAWN")
    (:spawn "SB-IMPL" "PSPAWN")
    (:spawn "SB-POSIX" "FORK"))
  "(CATEGORY PACKAGE NAME) for each counted entry point.")

(defun io-hook-specs () *io-hook-specs*)

(sb-ext:defglobal **counting-p** nil)
(sb-ext:defglobal **installed-hooks** nil
  "List of (SYMBOL CATEGORY . COUNTER-CELL) for the hooks currently installed.")

(defconstant +encapsulation-name+ 'key-cost-counter)

(defun installed-io-hooks ()
  (mapcar #'first **installed-hooks**))

(defun %resolve-hook-symbol (package-name symbol-name)
  (let ((package (find-package package-name)))
    (when package
      (multiple-value-bind (symbol status) (find-symbol symbol-name package)
        (when (and status (fboundp symbol) (not (macro-function symbol))
                   (not (special-operator-p symbol)))
          symbol)))))

(defun %install-io-hooks ()
  (when **installed-hooks**
    (error "key-cost: I/O hooks are already installed"))
  (let ((installed nil))
    (handler-bind ((error (lambda (condition)
                            (declare (ignore condition))
                            (%remove-hooks installed))))
      (dolist (spec *io-hook-specs*)
        (destructuring-bind (category package-name symbol-name) spec
          (let ((symbol (%resolve-hook-symbol package-name symbol-name)))
            (when (and symbol (not (find symbol installed :key #'first)))
              (let ((cell (list 0)))
                (sb-ext:without-package-locks
                  (sb-int:encapsulate
                   symbol +encapsulation-name+
                   (lambda (function &rest arguments)
                     (declare (dynamic-extent arguments))
                     (when **counting-p**
                       (sb-ext:atomic-incf (car cell)))
                     (apply function arguments))))
                (push (list* symbol category cell) installed)))))))
    (setf **installed-hooks** (nreverse installed))))

(defun %remove-hooks (hooks)
  (dolist (hook hooks)
    (sb-ext:without-package-locks
      (sb-int:unencapsulate (first hook) +encapsulation-name+))))

(defun %remove-io-hooks ()
  (%remove-hooks **installed-hooks**)
  (setf **installed-hooks** nil))

(defmacro with-io-hooks (() &body body)
  `(progn
     (%install-io-hooks)
     (unwind-protect (progn ,@body)
       (%remove-io-hooks))))

(defun %reset-hook-counters ()
  (dolist (hook **installed-hooks**)
    (setf (car (cddr hook)) 0)))

;;; libc counters
;;;
;;; SB-POSIX declares OPEN, OPENDIR, RENAME, UNLINK, ACCESS, MKDIR and others
;;; inline, so compiled callers reach libc without a Lisp function call the hooks
;;; above could see. scripts/perf/b3-libc-counter.c interposes those libc entry
;;; points when the process starts with it in DYLD_INSERT_LIBRARIES; when it is
;;; loaded, its counts are the primary figures and the Lisp hooks only attribute
;;; calls to Lisp entry points.

(sb-ext:defglobal **libc-addresses** nil)

(defun %libc-address (name)
  (let ((entry (assoc name **libc-addresses** :test #'string=)))
    (if entry
        (cdr entry)
        (let ((address (sb-sys:find-foreign-symbol-address name)))
          (push (cons name address) **libc-addresses**)
          address))))

(defun libc-counter-available-p ()
  (and (%libc-address "kc_enable") (%libc-address "kc_count") t))

(defun %kc-enable (flag)
  (sb-alien:alien-funcall
   (sb-alien:sap-alien (sb-sys:int-sap (%libc-address "kc_enable"))
                       (function sb-alien:void sb-alien:int))
   flag))

(defun %kc-function-count ()
  (sb-alien:alien-funcall
   (sb-alien:sap-alien (sb-sys:int-sap (%libc-address "kc_function_count"))
                       (function sb-alien:int))))

(defun %kc-count (index)
  (sb-alien:alien-funcall
   (sb-alien:sap-alien (sb-sys:int-sap (%libc-address "kc_count"))
                       (function sb-alien:long sb-alien:int))
   index))

(defun %kc-category (index)
  (sb-alien:alien-funcall
   (sb-alien:sap-alien (sb-sys:int-sap (%libc-address "kc_category"))
                       (function sb-alien:int sb-alien:int))
   index))

(defun %kc-name (index)
  (sb-alien:alien-funcall
   (sb-alien:sap-alien (sb-sys:int-sap (%libc-address "kc_name"))
                       (function sb-alien:c-string sb-alien:int))
   index))

(defstruct (io-counts (:constructor %make-io-counts))
  (source :lisp :type (member :lisp :libc))
  (stat 0 :type integer)
  (file-io 0 :type integer)
  (spawn 0 :type integer)
  (lisp-totals (list 0 0 0) :type list)
  (by-hook nil :type list))

(defun %category-index (category)
  (ecase category (:stat 0) (:file-io 1) (:spawn 2)))

(defun %snapshot-io-counts (libc-p)
  (let ((lisp-totals (list 0 0 0))
        (libc-totals (list 0 0 0))
        (by-hook nil))
    (dolist (hook **installed-hooks**)
      (destructuring-bind (symbol category . cell) hook
        (let ((n (car cell)))
          (incf (nth (%category-index category) lisp-totals) n)
          (when (plusp n)
            (push (cons (format nil "~a:~a" (package-name (symbol-package symbol))
                                (symbol-name symbol))
                        n)
                  by-hook)))))
    (when libc-p
      (dotimes (index (%kc-function-count))
        (let ((n (%kc-count index)))
          (incf (nth (%kc-category index) libc-totals) n)
          (when (plusp n)
            (push (cons (format nil "libc:~a" (%kc-name index)) n) by-hook)))))
    (let ((primary (if libc-p libc-totals lisp-totals)))
      (%make-io-counts :source (if libc-p :libc :lisp)
                       :stat (first primary)
                       :file-io (second primary)
                       :spawn (third primary)
                       :lisp-totals lisp-totals
                       :by-hook by-hook))))

(defun call-counting-io (thunk)
  "Call THUNK while the installed Lisp hooks and, when loaded, the libc counter
count. Return (values RESULT COUNTS)."
  (unless **installed-hooks**
    (error "key-cost: CALL-COUNTING-IO needs WITH-IO-HOOKS"))
  (%reset-hook-counters)
  (let ((result nil)
        (libc-p (libc-counter-available-p)))
    (setf **counting-p** t)
    (when libc-p (%kc-enable 1))
    (unwind-protect (setf result (funcall thunk))
      (when libc-p (%kc-enable 0))
      (setf **counting-p** nil))
    (values result (%snapshot-io-counts libc-p))))

;;; Allocation
;;;
;;; SB-EXT:GET-BYTES-CONSED only advances when a thread allocation region is
;;; closed, so a single key would read as 0 or as a whole region. Adding the
;;; used part of the current thread's open regions removes that quantization.
;;; It is not exact: once the heap is fragmented (for example right after
;;; compiling nshell in the same process, observed on SBCL 2.6.7) regions are
;;; a few hundred bytes long and the global counter catches up on closed
;;; regions late, so one reading can be off by tens of KB. That is far below
;;; the megabytes a key conses. The slot layout (free pointer, end, start) is
;;; SBCL-internal; when the slot constants are missing the plain counter is
;;; used.

(defparameter *tlab-slot-names*
  ;; The sys TLABs take allocation made in system contexts (observed for a
  ;; test body run by cl-weave on SBCL 2.6.7).
  '("THREAD-MIXED-TLAB-SLOT" "THREAD-CONS-TLAB-SLOT" "THREAD-BOXED-TLAB-SLOT"
    "THREAD-SYMBOL-TLAB-SLOT" "THREAD-SYS-MIXED-TLAB-SLOT" "THREAD-SYS-CONS-TLAB-SLOT"))

(defun %tlab-slots ()
  (loop for name in *tlab-slot-names*
        for symbol = (find-symbol name "SB-VM")
        when (and symbol (boundp symbol)) collect (symbol-value symbol)))

(sb-ext:defglobal **tlab-slots** nil)
;; Resolved at load so the first reading does not allocate inside a window.
(setf **tlab-slots** (%tlab-slots))

(defun precise-bytes-consed ()
  (let ((total (sb-ext:get-bytes-consed)))
    (dolist (slot **tlab-slots** total)
      (incf total
            (- (sb-sys:sap-int (sb-vm::current-thread-offset-sap slot))
               (sb-sys:sap-int (sb-vm::current-thread-offset-sap (+ slot 2))))))))

;;; Fixture: isolated HOME/XDG tree, a working directory, a large directory and
;;; a persisted history file.

(defstruct (fixture (:constructor %make-fixture))
  root
  work-directory
  big-directory
  history-count
  big-entry-count)

(defun %directory (root &rest names)
  (let ((path (uiop:ensure-directory-pathname
               (merge-pathnames (format nil "~{~a/~}" names) root))))
    (ensure-directories-exist path)
    path))

(defun %history-text (index)
  (case (mod index 5)
    (0 (format nil "git commit -m 'change ~d'" index))
    (1 (format nil "ls -la dir-~d" index))
    (2 (format nil "echo history-~d" index))
    (3 (format nil "cd /tmp/project-~d" index))
    (t (format nil "make test-~d" index))))

(defun make-fixture (&key (history-count 10000) (big-entry-count 20000))
  (let* ((root (uiop:ensure-directory-pathname
                (merge-pathnames
                 (format nil "nshell-key-cost-~36r/" (random most-positive-fixnum
                                                             (make-random-state t)))
                 (uiop:temporary-directory))))
         (work (%directory root "work"))
         (big (%directory root "work" "big")))
    (dolist (name '("home" "config" "data" "state" "cache"))
      (%directory root name))
    (dolist (name '("README.md" "notes.txt" "build.sh"))
      (with-open-file (stream (merge-pathnames name work)
                              :direction :output :if-exists :supersede)
        (write-line name stream)))
    (dotimes (index big-entry-count)
      (close (open (merge-pathnames (format nil "file-~d" index) big)
                   :direction :output :if-exists :supersede)))
    (%make-fixture :root root :work-directory work :big-directory big
                   :history-count history-count :big-entry-count big-entry-count)))

(defun remove-fixture (fixture)
  (let ((root (fixture-root fixture)))
    (when (and root (search "nshell-key-cost-" (namestring root)))
      (uiop:delete-directory-tree root :validate t :if-does-not-exist :ignore))))

(defun %write-history-file (path count)
  (ensure-directories-exist path)
  (let ((append-record (%nsym "NSHELL.INFRASTRUCTURE.PERSISTENCE" "%APPEND-HISTORY-RECORD"))
        (make-record (%nsym "NSHELL.INFRASTRUCTURE.PERSISTENCE"
                            "%MAKE-HISTORY-RECORD-FROM-VALUES")))
    (with-open-file (stream path :direction :output :if-exists :supersede
                                 :if-does-not-exist :create)
      (dotimes (index count)
        (funcall append-record stream
                 (funcall make-record :text (%history-text index)
                                      :timestamp (+ 1700000000 index)
                                      :cwd "/perf"
                                      :exit-code 0
                                      :duration-ms 1
                                      :origin :typed
                                      :host "key-cost"))))))

;;; Session

(defun %fixture-environment (fixture)
  (let ((root (namestring (fixture-root fixture))))
    `(("HOME" . ,(concatenate 'string root "home"))
      ("XDG_CONFIG_HOME" . ,(concatenate 'string root "config"))
      ("XDG_DATA_HOME" . ,(concatenate 'string root "data"))
      ("XDG_STATE_HOME" . ,(concatenate 'string root "state"))
      ("XDG_CACHE_HOME" . ,(concatenate 'string root "cache"))
      ("NSHELL_AI_COMMAND" . "/nonexistent"))))

(defun %call-with-environment (bindings thunk)
  (let ((saved (mapcar (lambda (binding)
                         (cons (car binding) (sb-posix:getenv (car binding))))
                       bindings)))
    (unwind-protect
         (progn
           (dolist (binding bindings)
             (sb-posix:setenv (car binding) (cdr binding) 1))
           (funcall thunk))
      (dolist (binding saved)
        (if (cdr binding)
            (sb-posix:setenv (car binding) (cdr binding) 1)
            (sb-posix:unsetenv (car binding)))))))

(defun %call-in-directory (directory thunk)
  (let ((saved-cwd (sb-posix:getcwd))
        (*default-pathname-defaults* (pathname directory)))
    (sb-posix:chdir directory)
    (unwind-protect (funcall thunk)
      (sb-posix:chdir saved-cwd))))

(defun %nshell-special-variables ()
  "Every bound special variable of the nshell packages, so INITIALIZE-REPL-STATE
only changes bindings this session owns."
  (let ((symbols nil))
    (dolist (package (list-all-packages))
      (let ((name (package-name package)))
        (when (and (>= (length name) 7)
                   (string= "NSHELL." name :end2 7)
                   (not (string= name "NSHELL.PERF.KEY-COST")))
          (do-symbols (symbol package)
            (when (and (eq (symbol-package symbol) package)
                       (eq (sb-int:info :variable :kind symbol) :special)
                       (boundp symbol))
              (pushnew symbol symbols))))))
    (let ((tty (find-symbol "*EAST-ASIAN-AMBIGUOUS-WIDE*" "CL-TTY-KIT")))
      (when (and tty (boundp tty)) (push tty symbols)))
    symbols))

(defun %override-bindings (fixture)
  (let ((root (fixture-root fixture)))
    (loop for (package name path) in
          `(("NSHELL.INFRASTRUCTURE.PERSISTENCE" "*HISTORY-FILE-PATH-OVERRIDE*"
             ,(merge-pathnames "data/nshell/history" root))
            ("NSHELL.INFRASTRUCTURE.PERSISTENCE" "*CONFIG-FILE-PATH-OVERRIDE*"
             ,(merge-pathnames "config/nshell/config.nsh" root))
            ("NSHELL.FEATURE.ASSISTANT" "*ASSISTANT-STATE-DIRECTORY-PATH-OVERRIDE*"
             ,(merge-pathnames "state/nshell/" root)))
          for symbol = (and (find-package package) (find-symbol name package))
          when (and symbol (boundp symbol))
            collect (cons symbol path))))

(defun %call-in-repl-session (fixture thunk)
  (let ((history-file (%ncall "NSHELL.INFRASTRUCTURE.PERSISTENCE" "HISTORY-FILE-PATH")))
    (unless (search (namestring (fixture-root fixture)) (namestring history-file))
      (error "key-cost: history path ~a escapes the fixture" history-file))
    (%write-history-file history-file (fixture-history-count fixture)))
  ;; RUN-REPL's own bindings around INITIALIZE-REPL-STATE.
  (setf (symbol-value (%pres "*HISTORY-LOADING-ENABLED-P*")) t
        (symbol-value (%pres "*HISTORY-PERSISTENCE-ENABLED-P*")) t
        (symbol-value (%nsym "NSHELL.INFRASTRUCTURE.PERSISTENCE"
                             "*HISTORY-FILE-MUTATIONS-ENABLED-P*"))
        t)
  (%ncall "NSHELL.PRESENTATION" "INITIALIZE-REPL-STATE"
          :load-config-p t :history-p t :private-p nil)
  ;; What INSTALL-INTERACTIVE-TERMINAL and the first prompt establish; with
  ;; these set, per-key snapshot export and terminal integration run as in a
  ;; real session.
  (setf (symbol-value (%pres "*INTERACTIVE-TERMINAL-INSTALLED-P*")) t
        (symbol-value (%pres "*PROMPT-RENDERED-ORIGIN-KNOWN-P*")) t)
  (unless (symbol-value (%pres "*ASSISTANT-SESSION-ID*"))
    (error "key-cost: the session has no assistant session id"))
  (%run-to-next-key (lambda () (%ncall "NSHELL.PRESENTATION" "RENDER-PROMPT-CONT")))
  (funcall thunk))

(defun %call-with-terminal-stubs (thunk)
  (let ((terminal-size (%nsym "NSHELL.INFRASTRUCTURE.ACL" "GET-TERMINAL-SIZE"))
        (read-key-cont (%pres "READ-KEY-CONT")))
    (sb-int:encapsulate terminal-size 'key-cost-terminal
                        (lambda (function &rest arguments)
                          (declare (ignore function arguments))
                          (values 40 120)))
    (unwind-protect
         (progn
           ;; The trampoline step that would block on the terminal ends a key.
           (sb-int:encapsulate read-key-cont 'key-cost-next-key
                               (lambda (function)
                                 (declare (ignore function))
                                 :key-cost-next-key))
           (let ((*standard-output* (make-broadcast-stream)))
             (funcall thunk)))
      (sb-int:unencapsulate read-key-cont 'key-cost-next-key)
      (sb-int:unencapsulate terminal-size 'key-cost-terminal))))

(defun call-with-key-session (fixture thunk)
  "Start an interactive session state over FIXTURE the way RUN-REPL does, minus
the terminal, and call THUNK inside it. Global state is restored afterwards."
  (let ((specials (%nshell-special-variables))
        (overrides (%override-bindings fixture)))
    (%call-with-environment
     (%fixture-environment fixture)
     (lambda ()
       (%call-in-directory
        (namestring (fixture-work-directory fixture))
        (lambda ()
          (progv specials (mapcar #'symbol-value specials)
            (progv (mapcar #'car overrides) (mapcar #'cdr overrides)
              (%call-with-terminal-stubs
               (lambda () (%call-in-repl-session fixture thunk)))))))))))

(defun %run-to-next-key (step)
  (loop for result = (funcall step)
        do (cond
             ((eq result :key-cost-next-key) (return t))
             ((functionp result) (setf step result))
             (t (error "key-cost: REPL step returned ~s instead of asking for the next key"
                       result)))))

(defun key-event (type &optional char)
  (funcall (symbol-function (%nsym "NSHELL.DOMAIN.INPUT" "MAKE-KEY-EVENT"))
           type char nil nil))

(defun drive-key (event)
  "Run one key EVENT through the REPL until it asks for the next key."
  (%run-to-next-key (lambda () (%ncall "NSHELL.PRESENTATION" "%PROCESS-INPUT-EVENT" event))))

;;; Scenarios

(defun %input-state () (symbol-value (%pres "*INPUT-STATE*")))
(defun %buffer () (%ncall "NSHELL.PRESENTATION" "INPUT-STATE-BUFFER" (%input-state)))
(defun %mode () (%ncall "NSHELL.PRESENTATION" "INPUT-STATE-MODE" (%input-state)))

(defun %clear-presentation-table (name)
  "Clear the presentation hash table NAME when the loaded tree defines it."
  (let ((symbol (find-symbol name "NSHELL.PRESENTATION")))
    (when (and symbol (boundp symbol) (hash-table-p (symbol-value symbol)))
      (clrhash (symbol-value symbol)))))

(defun %clear-presentation-variable (name)
  "Set the presentation variable NAME to NIL when the loaded tree defines it."
  (let ((symbol (find-symbol name "NSHELL.PRESENTATION")))
    (when (and symbol (boundp symbol))
      (setf (symbol-value symbol) nil))))

(defun %clear-completion-caches ()
  ;; These caches expire on wall-clock TTLs or per-prompt stamps (directory
  ;; listing 5 s, PATH directory stamp recheck 1 s or 0.25 s after a recent
  ;; change, highlight path probes 2 s, highlight command memo), so whether a
  ;; key hits them depends on machine speed and on the session's history.
  ;; Clearing them before every measured key makes the counts deterministic and
  ;; measures the cache-miss cost. The highlight command cache differs between
  ;; source trees (*REPL-COMMAND-PATH-MEMO*, formerly
  ;; *REPL-HIGHLIGHT-PATH-CACHE*), so whichever the tree defines is cleared.
  (%ncall "NSHELL.INFRASTRUCTURE.ACL" "CLEAR-DIRECTORY-LISTING-CACHE")
  (%ncall "NSHELL.DOMAIN.COMPLETION" "%INVALIDATE-PATH-COMMAND-CACHE")
  (clrhash (symbol-value (%pres "*HIGHLIGHT-PATH-PROBE-CACHE*")))
  (setf (symbol-value (%pres "*HIGHLIGHT-PATH-PROBE-CACHE-STAMP*")) nil)
  (%clear-presentation-table "*REPL-COMMAND-PATH-MEMO*")
  (%clear-presentation-table "*REPL-HIGHLIGHT-PATH-CACHE*")
  ;; Forget the history file stamp so a tree that rereads history on a key
  ;; pays the full read, and one that does not is not credited with a skip.
  (%clear-presentation-variable "*HISTORY-FILE-STAMP*"))

(defun %set-buffer (text &key (cold-caches t))
  "Put TEXT in the editor with the suggestion a previous key would have left."
  (setf (symbol-value (%pres "*INPUT-STATE*"))
        (%ncall "NSHELL.PRESENTATION" "MAKE-REPL-INPUT-STATE"
                :buffer text :cursor-pos (length text)))
  (%ncall "HISTORY-KIT" "HISTORY-RESET-NAVIGATION" (symbol-value (%pres "*HISTORY*")))
  (%ncall "NSHELL.PRESENTATION" "REFRESH-CURRENT-INPUT-STATE-SUGGESTION")
  (when cold-caches
    (%clear-completion-caches)))

(defun %filler (prefix length item-format)
  (let ((text prefix))
    (loop for index from 0
          while (< (length text) length)
          do (setf text (concatenate 'string text (format nil item-format index))))
    (subseq text 0 length)))

(defstruct (scenario (:constructor make-scenario (name setup event guard
                                                  &optional (io-gate t))))
  name setup event guard
  ;; NIL when the I/O counts depend on wall-clock cache TTLs; written to the
  ;; JSON as "io_gate":false so the G3 I/O check skips them.
  io-gate)

(defun %typing-scenario (name base char &key (cold-caches t))
  (make-scenario name
                 (lambda () (%set-buffer base :cold-caches cold-caches))
                 (lambda () (key-event :char char))
                 (let ((expected (concatenate 'string base (string char))))
                   (lambda () (string= expected (%buffer))))
                 cold-caches))

(defun default-scenarios (fixture)
  (declare (ignore fixture))
  (let ((newest (lambda ()
                  (%ncall "HISTORY-KIT" "HISTORY-ENTRY-TEXT"
                          (first (%ncall "HISTORY-KIT" "HISTORY-ENTRIES"
                                         (symbol-value (%pres "*HISTORY*"))))))))
    (list
     (%typing-scenario "bare-type-1" "" #\l)
     (%typing-scenario "bare-type-200" (%filler "echo " 199 "arg~d ") #\x)
     (%typing-scenario "bare-type-1000" (%filler "echo " 999 "arg~d ") #\x)
     (%typing-scenario "sexp-type-1" "" #\()
     (%typing-scenario "sexp-type-200" (%filler "(echo " 199 "\"arg~d\" ") #\x)
     (%typing-scenario "sexp-type-1000" (%filler "(echo " 999 "\"arg~d\" ") #\x)
     (%typing-scenario "command-name-type" "nshellzq" #\x)
     (%typing-scenario "path-20k-type" "ls big/file-1" #\2)
     ;; Typing within the listing cache's 5 s TTL; counts depend on timing.
     (%typing-scenario "path-20k-type-warm" "ls big/file-1" #\2 :cold-caches nil)
     (make-scenario "path-20k-tab"
                    (lambda () (%set-buffer "ls big/file-1"))
                    (lambda () (key-event :tab))
                    (lambda ()
                      (or (not (string= "ls big/file-1" (%buffer)))
                          (%ncall "NSHELL.PRESENTATION" "INPUT-STATE-LAST-CANDIDATES"
                                  (%input-state)))))
     (make-scenario "history-search-start"
                    (lambda () (%set-buffer ""))
                    (lambda () (key-event :ctrl-r))
                    (lambda () (eq :search (%mode))))
     (make-scenario "history-search-type"
                    (lambda ()
                      (%set-buffer "")
                      (drive-key (key-event :ctrl-r))
                      (unless (eq :search (%mode))
                        (error "key-cost: Ctrl-R did not enter history search")))
                    (lambda () (key-event :char #\5))
                    (lambda ()
                      (and (eq :search (%mode))
                           (equal "5" (%ncall "NSHELL.PRESENTATION" "INPUT-STATE-SEARCH-QUERY"
                                              (%input-state))))))
     (make-scenario "history-prev"
                    (lambda () (%set-buffer ""))
                    (lambda () (key-event :ctrl-p))
                    (lambda () (string= (funcall newest) (%buffer)))))))

(defstruct scenario-result
  name keys bytes stat-per-key file-io-per-key spawn-per-key hook-counts real-ms
  counter-source (io-gate t))

(defun %measure-one (scenario)
  "Run SCENARIO's unmeasured setup and return the key event to measure."
  (funcall (scenario-setup scenario))
  (funcall (scenario-event scenario)))

(defun %check-guard (scenario)
  (unless (funcall (scenario-guard scenario))
    (error "key-cost: scenario ~a did not reach its expected state (buffer ~s)"
           (scenario-name scenario) (%buffer))))

(defun measure-scenario (scenario &key (samples 30) (warmup 3))
  "Measure SCENARIO in two passes: allocation with no hooks installed, then I/O
counts with hooks installed, SAMPLES keys each after WARMUP unmeasured keys."
  (let ((bytes nil) (real nil) (totals (list 0 0 0)) (source nil)
        (by-hook (make-hash-table :test #'equal)))
    (dotimes (index (+ warmup samples))
      (let ((event (%measure-one scenario)))
        (let* ((start-real (get-internal-real-time))
               (start (precise-bytes-consed)))
          (drive-key event)
          (let ((consed (- (precise-bytes-consed) start))
                (elapsed (- (get-internal-real-time) start-real)))
            (%check-guard scenario)
            (when (>= index warmup)
              (push consed bytes)
              (push (/ (* 1000.0d0 elapsed) internal-time-units-per-second) real))))))
    (with-io-hooks ()
      (dotimes (index (+ warmup samples))
        (let ((event (%measure-one scenario)))
          (multiple-value-bind (result counts) (call-counting-io (lambda () (drive-key event)))
            (declare (ignore result))
            (%check-guard scenario)
            (when (>= index warmup)
              (setf source (io-counts-source counts))
              (incf (first totals) (io-counts-stat counts))
              (incf (second totals) (io-counts-file-io counts))
              (incf (third totals) (io-counts-spawn counts))
              (dolist (entry (io-counts-by-hook counts))
                (incf (gethash (car entry) by-hook 0) (cdr entry))))))))
    (make-scenario-result
     :name (scenario-name scenario)
     :keys samples
     :bytes (nreverse bytes)
     :stat-per-key (/ (first totals) samples)
     :file-io-per-key (/ (second totals) samples)
     :spawn-per-key (/ (third totals) samples)
     :hook-counts (sort (loop for k being the hash-keys of by-hook using (hash-value v)
                              collect (cons k (/ v samples)))
                        #'string< :key #'car)
     :real-ms (nreverse real)
     :counter-source source
     :io-gate (scenario-io-gate scenario))))

(defun measure-scenarios (fixture &key (samples 30) (warmup 3) names)
  (call-with-key-session
   fixture
   (lambda ()
     (loop for scenario in (default-scenarios fixture)
           when (or (null names) (member (scenario-name scenario) names :test #'string=))
             collect (progn
                       (format *error-output* "~&key-cost: measuring ~a~%"
                               (scenario-name scenario))
                       (finish-output *error-output*)
                       (measure-scenario scenario :samples samples :warmup warmup))))))

;;; Statistics and JSON

(defun %percentile (values fraction)
  "Nearest-rank percentile."
  (let* ((sorted (sort (copy-list values) #'<))
         (rank (max 1 (ceiling (* fraction (length sorted))))))
    (nth (1- rank) sorted)))

(defun %mean (values)
  (/ (reduce #'+ values) (length values)))

(defun %json-string (string stream)
  (write-char #\" stream)
  (loop for char across string
        do (case char
             (#\" (write-string "\\\"" stream))
             (#\\ (write-string "\\\\" stream))
             (#\Newline (write-string "\\n" stream))
             (#\Return (write-string "\\r" stream))
             (#\Tab (write-string "\\t" stream))
             (t (if (< (char-code char) 32)
                    (format stream "\\u~4,'0x" (char-code char))
                    (write-char char stream)))))
  (write-char #\" stream))

(defun %json-number (number stream)
  (if (integerp number)
      (format stream "~d" number)
      (format stream "~,3f" (coerce number 'double-float))))

(defun write-results-json (results stream &key (uptime ""))
  (format stream "{\"scenarios\":[")
  (loop for (result . more) on results
        for bytes = (scenario-result-bytes result)
        do (format stream "{\"name\":")
           (%json-string (scenario-result-name result) stream)
           (format stream ",\"keys\":~d,\"bytes_consed_per_key\":{\"mean\":"
                   (scenario-result-keys result))
           (%json-number (%mean bytes) stream)
           (format stream ",\"p50\":")
           (%json-number (%percentile bytes 0.5) stream)
           (format stream ",\"p95\":")
           (%json-number (%percentile bytes 0.95) stream)
           (format stream "},\"stat_per_key\":")
           (%json-number (scenario-result-stat-per-key result) stream)
           (format stream ",\"file_io_per_key\":")
           (%json-number (scenario-result-file-io-per-key result) stream)
           (format stream ",\"spawn_per_key\":")
           (%json-number (scenario-result-spawn-per-key result) stream)
           (format stream ",\"io_gate\":~:[false~;true~]}~:[~;,~]"
                   (scenario-result-io-gate result) more))
  (format stream "],\"uptime\":")
  (%json-string uptime stream)
  (format stream "}~%"))

(defun %summary (results stream)
  (format stream "~&counter source: ~(~a~); allocation: ~:[region-quantized~;open regions added~]~%"
          (and results (scenario-result-counter-source (first results)))
          **tlab-slots**)
  (format stream "~&~22a ~5a ~12a ~12a ~12a ~8a ~8a ~6a ~9a~%"
          "scenario" "keys" "mean-B" "p50-B" "p95-B" "stat" "file-io" "spawn" "p50-ms")
  (dolist (result results)
    (let ((bytes (scenario-result-bytes result)))
      (format stream "~22a ~5d ~12d ~12d ~12d ~8,2f ~8,2f ~6,2f ~9,1f~%"
              (scenario-result-name result) (scenario-result-keys result)
              (round (%mean bytes)) (%percentile bytes 0.5) (%percentile bytes 0.95)
              (scenario-result-stat-per-key result)
              (scenario-result-file-io-per-key result)
              (scenario-result-spawn-per-key result)
              (%percentile (scenario-result-real-ms result) 0.5))
      (format stream "    hooks/key:~{ ~a=~,2f~}~%"
              (loop for (name . n) in (scenario-result-hook-counts result)
                    append (list name n))))))

(defun main (output-path &key (samples 30) (warmup 3) (uptime "") names
                              (history-count 10000) (big-entry-count 20000))
  "Measure the default scenarios and write OUTPUT-PATH as JSON."
  (let ((fixture (make-fixture :history-count history-count
                               :big-entry-count big-entry-count)))
    (unwind-protect
         (let ((results (measure-scenarios fixture :samples samples :warmup warmup
                                                   :names names)))
           (%summary results *error-output*)
           (format *error-output* "installed hooks: ~{~a~^ ~}~%"
                   (progn (%install-io-hooks)
                          (prog1 (mapcar (lambda (s)
                                           (format nil "~a:~a"
                                                   (package-name (symbol-package s))
                                                   (symbol-name s)))
                                         (installed-io-hooks))
                            (%remove-io-hooks))))
           (with-open-file (stream output-path :direction :output :if-exists :supersede)
             (write-results-json results stream :uptime uptime))
           results)
      (remove-fixture fixture))))
