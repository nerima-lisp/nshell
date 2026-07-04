(in-package #:nshell.presentation)

;; Highlight data tables and span type.
(defstruct (highlight-span (:constructor %make-highlight-span (start end role)))
  (start 0 :type integer :read-only t)
  (end 0 :type integer :read-only t)
  (role :normal :type keyword :read-only t))

(defvar *builtin-commands*
  '("echo" "pwd" "ls" "cd" "exit" "fg" "bg" "jobs" "disown"
    "set" "export" "alias" "abbr" "function" "source" "exec"
    "true" "false" "contains" "test" "type" "which" "history" "help")
  "Commands built into nshell that get distinct highlighting.")

(defparameter +operator-token-types+
  '(:pipe :and :or :semicolon :ampersand :redirect))

(defparameter +fallback-highlight-ansi+
  '((:command . "~C[34m")
    (:builtin . "~C[34;1m")
    (:argument . "~C[37m")
    (:option . "~C[36m")
    (:operator . "~C[33m")
    (:error . "~C[31m")
    (:comment . "~C[2;37m")
    (:quote . "~C[33m")
    (:normal . "~C[0m")))

;; -- Highlight roles (fish-inspired) ----------------------
(defun builtin-command-p (name)
  (find name *builtin-commands* :test #'string=))

(defun classify-token-role (token-type token-value is-first-word)
  "Map a token to its highlight role. Follows fish shell conventions:
   - first word: command (blue) or builtin (bright blue)
   - subsequent words: argument (normal/cyan for options)
   - pipes/redirects: operator (yellow)
   - strings/quoted: quote (orange)
   - errors: error (red)
   - comments: comment (gray)"
  (case token-type
    (:word
     (cond
       ((not is-first-word)
        (if (and (> (length token-value) 0)
                 (char= (char token-value 0) #\-))
            :option
            :argument))
       ((builtin-command-p token-value) :builtin)
       (t :command)))
    ((:pipe :and :or :semicolon :ampersand :redirect) :operator)
    (:error :error)
    (t :normal)))

(defun diagnostic-overlaps-token-p (diagnostic token)
  (let ((diag-start (nshell.domain.parsing:parse-diagnostic-start diagnostic))
        (diag-end (nshell.domain.parsing:parse-diagnostic-end diagnostic))
        (token-start (nshell.domain.parsing:token-start token))
        (token-end (nshell.domain.parsing:token-end token)))
    (and (< diag-start token-end)
         (< token-start diag-end))))

(defun highlight-line (input)
  "Parse INPUT and return highlight spans for fish-style syntax coloring."
  (let* ((tokenization (nshell.domain.parsing:tokenize input))
         (tokens (nshell.domain.parsing:tokenization-result-tokens tokenization))
         (first-word t)
         (diagnostics (nshell.domain.parsing:parse-errors
                       (nshell.domain.parsing:parse-command-line input))))
    (mapcar (lambda (tok)
              (let* ((type (nshell.domain.parsing:token-type tok))
                     (value (nshell.domain.parsing:token-value tok))
                     (role (if (some (lambda (diagnostic)
                                       (diagnostic-overlaps-token-p diagnostic tok))
                                     diagnostics)
                               :error
                               (classify-token-role type value first-word))))
                (when (eq type :word) (setf first-word nil))
                (when (member type +operator-token-types+ :test #'eq)
                  (setf first-word t))
                (%make-highlight-span
                 (nshell.domain.parsing:token-start tok)
                 (nshell.domain.parsing:token-end tok)
                 role)))
            tokens)))

;; Rendering helpers for highlight spans.
(defun fallback-highlight-control (role)
  (or (cdr (assoc role +fallback-highlight-ansi+ :test #'eq))
      "~C[0m"))

(defun theme-color->ansi (theme role)
  "Convert a highlight ROLE to ANSI escape using THEME colors.
   Falls back to known ANSI 16-color codes when theme lookup fails."
  (let ((color (nshell.domain.configuration:theme-color theme role)))
    (if color
        (let ((code (nshell.infrastructure.terminal::ansi-color-code color)))
          (format nil "~C[3~dm" #\Esc code))
        (format nil (fallback-highlight-control role) #\Esc))))

(defun highlight->ansi (spans input theme)
  "Render highlighted INPUT with THEME colors as ANSI escape sequences."
  (let ((result (make-string-output-stream))
        (pos 0))
    (dolist (span spans)
      ;; Output unhighlighted gap
      (when (> (highlight-span-start span) pos)
        (write-string (subseq input pos (highlight-span-start span)) result))
      ;; Output highlighted span with color
      (format result "~a" (theme-color->ansi theme (highlight-span-role span)))
      (write-string (subseq input (highlight-span-start span)
                            (highlight-span-end span)) result)
      (format result "~C[0m" #\Esc)
      (setf pos (highlight-span-end span)))
    ;; Output remaining text
    (when (< pos (length input))
      (write-string (subseq input pos) result))
    (get-output-stream-string result)))
