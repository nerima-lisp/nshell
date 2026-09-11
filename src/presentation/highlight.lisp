(in-package #:nshell.presentation)

;; Highlight span value object; literal data tables live under data/.
(define-value-struct %highlight-span
    ((start 0 :type integer)
     (end 0 :type integer)
     (role :normal :type keyword)))

;; -- Highlight roles (fish-inspired) ----------------------
(defun builtin-command-p (name)
  (find name *builtin-commands* :test #'string=))

(defvar *highlight-command-resolver* nil
  "Function (NAME) -> :builtin :function :alias :abbreviation :keyword
:external, or NIL when NAME resolves to nothing. NIL keeps every command
word's role at :command; installed by repl-highlight.lisp in a running
session.")

(defvar *highlight-path-probe-cache* (make-hash-table :test #'equal))

(defvar *highlight-path-probe-cache-stamp* nil
  "The (working directory . universal time) the cache was filled for.")

(defparameter *highlight-path-probe-cache-ttl-seconds* 2)

(defun %highlight-path-probe-cache-valid-p (directory now)
  (let ((stamp *highlight-path-probe-cache-stamp*))
    (and stamp
         (equal (car stamp) directory)
         (< (- now (cdr stamp)) *highlight-path-probe-cache-ttl-seconds*))))

(defun %path-exists-on-disk-p (path)
  (not (null (ignore-errors (probe-file path)))))

(defun %highlight-probe-path (path)
  ;; Every redraw reclassifies the whole line, so an uncached probe means one
  ;; stat per argument per keystroke. The cache is scoped to the working
  ;; directory and expires quickly, since a path that appears while the line is
  ;; being typed should still colour as one.
  (and (plusp (length path))
       (let ((directory (ignore-errors (namestring (host-kit:getcwd))))
             (now (get-universal-time)))
         (unless (%highlight-path-probe-cache-valid-p directory now)
           (clrhash *highlight-path-probe-cache*)
           (setf *highlight-path-probe-cache-stamp* (cons directory now)))
         (multiple-value-bind (cached present-p)
             (gethash path *highlight-path-probe-cache*)
           (if present-p
               cached
               (setf (gethash path *highlight-path-probe-cache*)
                     (%path-exists-on-disk-p path)))))))

(defvar *highlight-path-exists-p* #'%highlight-probe-path
  "Predicate (PATH) reporting whether PATH exists on disk; stubbed in tests.")

(defun %expand-home-prefix (value)
  (if (and (plusp (length value)) (char= (char value 0) #\~))
      (let ((home (host-kit:getenv "HOME")))
        (if home (concatenate 'string home (subseq value 1)) value))
      value))

(defun %glob-word-p (value)
  (not (null (find-if (lambda (ch) (member ch '(#\* #\? #\[))) value))))

(defun %existing-path-word-p (value)
  (and (plusp (length value))
       (funcall *highlight-path-exists-p* (%expand-home-prefix value))))

(defun %variable-word-p (value)
  (and (plusp (length value)) (char= (char value 0) #\$)))

(defun %option-word-p (value)
  (and (plusp (length value)) (char= (char value 0) #\-)))

(defun %path-like-command-word-p (value)
  (and (plusp (length value))
       (or (char= (char value 0) #\/)
           (char= (char value 0) #\~)
           (char= (char value 0) #\$)
           (and (>= (length value) 2)
                (char= (char value 0) #\.)
                (char= (char value 1) #\/)))))

(defun %resolved-command-role (kind)
  (case kind
    (:builtin :builtin)
    ((:function :alias :abbreviation) :function)
    (:keyword :keyword)
    (:external :command)
    (t nil)))

(defun %command-word-role (value)
  (cond
    ((nshell.domain.parsing:shell-assignment-word-p value) :variable)
    ((null *highlight-command-resolver*) :command)
    (t
     (let ((role (%resolved-command-role (funcall *highlight-command-resolver* value))))
       (cond
         (role role)
         ((and (%path-like-command-word-p value) (%existing-path-word-p value))
          :command)
         (t :error))))))

(defun %highlight-word-role (value is-first-word quoted-p)
  (cond
    (quoted-p
     (if (and (not is-first-word)
              (not (%glob-word-p value))
              (%existing-path-word-p value))
         :path
         :quote))
    (is-first-word (%command-word-role value))
    ((%variable-word-p value) :variable)
    ((%option-word-p value) :option)
    ((%glob-word-p value) :argument)
    ((%existing-path-word-p value) :path)
    (t :argument)))

(defun classify-token-role (token-type token-value is-first-word &key quoted-p)
  "Map a token to its highlight role. Follows fish shell conventions:
   - first word: command, builtin, function, keyword, or error when
     the resolver cannot place it
   - subsequent words: path, option, variable, quote, or argument
   - pipes/redirects: operator
   - tokenizer errors: error"
  (case token-type
    (:word (%highlight-word-role token-value is-first-word quoted-p))
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

(defun %highlight-blank-char-p (ch)
  (member ch '(#\Space #\Tab #\Newline #\Return) :test #'char=))

(defun %highlight-comment-span-in-gap (input start end)
  "Return a :comment %highlight-span when the first non-blank character in
INPUT[START,END) is #, spanning from there to the next newline or END."
  (let ((hash-pos (position-if-not #'%highlight-blank-char-p input
                                    :start start :end end)))
    (when (and hash-pos (char= (char input hash-pos) #\#))
      (let ((newline-pos (position #\Newline input :start hash-pos :end end)))
        (%make-highlight-span hash-pos (or newline-pos end) :comment)))))

(defun %highlight-comment-spans (input tokens)
  "Return :comment spans for the stretches of INPUT the tokenizer discarded
when reading past a comment #."
  (let ((pos 0)
        (len (length input))
        (spans nil))
    (dolist (tok tokens)
      (let ((start (nshell.domain.parsing:token-start tok))
            (end (nshell.domain.parsing:token-end tok)))
        (when (> start pos)
          (let ((span (%highlight-comment-span-in-gap input pos start)))
            (when span (push span spans))))
        (setf pos (max pos end))))
    (when (< pos len)
      (let ((span (%highlight-comment-span-in-gap input pos len)))
        (when span (push span spans))))
    (nreverse spans)))

(defun highlight-line (input)
  "Parse INPUT and return highlight spans for fish-style syntax coloring."
  (let* ((tokenization (nshell.domain.parsing:tokenize input))
         (tokens (nshell.domain.parsing:tokenization-result-tokens tokenization))
         (first-word t)
         (diagnostics (nshell.domain.parsing:parse-errors
                       (nshell.domain.parsing:parse-command-line input)))
         (token-spans
           (mapcar (lambda (tok)
                     (let* ((type (nshell.domain.parsing:token-type tok))
                            (value (nshell.domain.parsing:token-value tok))
                            (quoted-p (not (null (nshell.domain.parsing:token-quote-style tok))))
                            (role (if (some (lambda (diagnostic)
                                              (diagnostic-overlaps-token-p diagnostic tok))
                                            diagnostics)
                                      :error
                                      (classify-token-role type value first-word
                                                            :quoted-p quoted-p))))
                       (when (and (eq type :word)
                                  (not (and first-word
                                            (not quoted-p)
                                            (nshell.domain.parsing:shell-assignment-word-p value))))
                         (setf first-word nil))
                       (when (member type +operator-token-types+ :test #'eq)
                         (setf first-word t))
                       (%make-highlight-span
                        (nshell.domain.parsing:token-start tok)
                        (nshell.domain.parsing:token-end tok)
                        role)))
                   tokens)))
    (sort (append token-spans (%highlight-comment-spans input tokens))
          #'< :key #'highlight-span-start)))

;; Rendering helpers for highlight spans.
(defun fallback-highlight-control (role)
  (or (cdr (assoc role +fallback-highlight-ansi+ :test #'eq))
      "~C[0m"))

(defun text-style->ansi (style)
  "Render a parsed TEXT-STYLE as the SGR sequence for the current color depth."
  (nshell.infrastructure.terminal:ansi-style-sequence
   :foreground (nshell.domain.configuration:text-style-foreground style)
   :background (nshell.domain.configuration:text-style-background style)
   :bold (nshell.domain.configuration:text-style-bold style)
   :dim (nshell.domain.configuration:text-style-dim style)
   :italic (nshell.domain.configuration:text-style-italic style)
   :underline (nshell.domain.configuration:text-style-underline style)
   :reverse (nshell.domain.configuration:text-style-reverse style)))

(defun theme-color->ansi (theme role)
  "Convert a highlight ROLE to its SGR prefix using THEME. A role the theme
does not configure falls back to the fixed 16-color table."
  (let ((style (nshell.domain.configuration:theme-style theme role)))
    (if style
        (text-style->ansi style)
        (format nil (fallback-highlight-control role) #\Esc))))

(defun highlight->ansi (spans input theme)
  "Render highlighted INPUT with THEME colors as ANSI escape sequences."
  (let ((result (make-string-output-stream))
        (pos 0))
    (dolist (span spans)
      ;; Output unhighlighted gap
      (when (> (highlight-span-start span) pos)
        (write-string (subseq input pos (highlight-span-start span)) result))
      ;; Output the span, coloring it only when the theme has a sequence for
      ;; its role -- an empty sequence gets no reset either.
      (let ((prefix (theme-color->ansi theme (highlight-span-role span)))
            (text (subseq input (highlight-span-start span) (highlight-span-end span))))
        (if (plusp (length prefix))
            (progn
              (write-string prefix result)
              (write-string text result)
              (nshell.infrastructure.terminal:ansi-reset-style result))
            (write-string text result)))
      (setf pos (highlight-span-end span)))
    ;; Output remaining text
    (when (< pos (length input))
      (write-string (subseq input pos) result))
    (get-output-stream-string result)))
