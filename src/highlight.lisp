(in-package #:nshell.highlight)

(define-value-struct %highlight-span
    ((start 0 :type integer)
     (end 0 :type integer)
     (role :normal :type keyword)))

(defun builtin-command-p (name)
  (find name +highlight-builtin-names+ :test #'string=))

(defun classify-token-role (token-type token-value is-first-word)
  "Map a token to its syntax-highlight role."
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

(defun fallback-highlight-control (role)
  (or (cdr (assoc role +fallback-highlight-ansi+ :test #'eq))
      "~C[0m"))

(defun theme-color->ansi (theme role)
  "Convert a highlight ROLE to ANSI escape using THEME colors."
  (let ((color (nshell.domain.configuration:theme-color theme role)))
    (if color
        (let ((code (nshell.infrastructure.terminal:ansi-color-code color)))
          (format nil "~C[3~dm" #\Esc code))
        (format nil (fallback-highlight-control role) #\Esc))))

(defun highlight->ansi (spans input theme)
  "Render highlighted INPUT with THEME colors as ANSI escape sequences."
  (let ((result (make-string-output-stream))
        (pos 0))
    (dolist (span spans)
      (when (> (highlight-span-start span) pos)
        (write-string (subseq input pos (highlight-span-start span)) result))
      (format result "~a" (theme-color->ansi theme (highlight-span-role span)))
      (write-string (subseq input (highlight-span-start span)
                            (highlight-span-end span)) result)
      (nshell.infrastructure.terminal:ansi-reset-style result)
      (setf pos (highlight-span-end span)))
    (when (< pos (length input))
      (write-string (subseq input pos) result))
    (get-output-stream-string result)))
