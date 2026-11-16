(in-package #:nshell/test)

(describe "east-asian-ambiguous-width"
  (it "validates-the-three-width-policies"
    (dolist (case '(("auto" :auto) ("narrow" :narrow) ("wide" :wide)))
      (expect (second case) :to-equal
              (nshell.domain.configuration:parse-east-asian-ambiguous-width
               (first case))))
    (expect (lambda ()
              (nshell.domain.configuration:parse-east-asian-ambiguous-width
               "invalid"))
            :to-throw 'type-error))

  (it "uses-locale-precedence-for-auto-fallback"
    (with-repl-test-state
      (repl-test-set-env "LC_ALL" "C")
      (repl-test-set-env "LC_CTYPE" "ja_JP.UTF-8")
      (repl-test-set-env "LANG" "zh_CN.UTF-8")
      (with-temporary-function
          ('nshell.infrastructure.terminal:interactive-terminal-p
           (lambda (&optional fd) (declare (ignore fd)) nil))
        (nshell.presentation::%apply-east-asian-ambiguous-width)
        (expect cl-tty-kit:*east-asian-ambiguous-wide* :to-be nil))
      (let ((environment
              (nshell.domain.environment:env-set
               (nshell.domain.environment:make-environment)
               "LC_CTYPE" "ja_JP.UTF-8" nil)))
        (expect (nshell.presentation::%east-asian-locale-wide-p environment)
                :to-be-truthy)))

  (it "matches-only-locale-language-prefixes"
    (dolist (locale '("ja_JP.UTF-8" "zh.CN" "ko@euckr" "JA"))
      (let ((environment
              (nshell.domain.environment:env-set
               (nshell.domain.environment:make-environment)
               "LANG" locale nil)))
        (expect (nshell.presentation::%east-asian-locale-wide-p environment)
                :to-be-truthy)))
    (let ((environment
            (nshell.domain.environment:env-set
             (nshell.domain.environment:make-environment)
             "LANG" "en_JA.UTF-8" nil)))
      (expect (nshell.presentation::%east-asian-locale-wide-p environment)
              :to-be nil)))

  (it "respects-explicit-width-in-batch-initialization"
    (with-repl-test-state
      (repl-test-set-env "NSHELL_EAST_ASIAN_AMBIGUOUS_WIDTH" "wide")
      (nshell.presentation::%initialize-batch-state)
      (expect cl-tty-kit:*east-asian-ambiguous-wide* :to-be-truthy)
      (repl-test-set-env "NSHELL_EAST_ASIAN_AMBIGUOUS_WIDTH" "narrow")
      (nshell.presentation::%initialize-batch-state)
      (expect cl-tty-kit:*east-asian-ambiguous-wide* :to-be nil)))

  (it "uses-locale-fallback-in-batch-auto-mode"
    (with-repl-test-state
      (repl-test-set-env "NSHELL_EAST_ASIAN_AMBIGUOUS_WIDTH" "auto")
      (repl-test-set-env "LANG" "ja_JP.UTF-8")
      (nshell.presentation::%initialize-batch-state)
      (expect cl-tty-kit:*east-asian-ambiguous-wide* :to-be-truthy)))

  (it "preserves-ordinary-input-when-querying-cpr"
    (let ((*standard-input* (make-string-input-stream "x"))
          (*standard-output* (make-string-output-stream)))
      (multiple-value-bind (row column)
          (nshell.infrastructure.terminal:query-cursor-position
           :attempts 1 :sleep-seconds 0)
        (expect row :to-be nil)
        (expect column :to-be nil)
        (expect (read-char *standard-input*) :to-equal #\x))))

  (it "parses-cpr-and-honors-the-short-timeout"
    (let ((input (list #\Esc #\[ #\3 #\; #\5 #\R)))
      (with-temporary-function
          ('nshell.infrastructure.terminal::read-available-char
           (lambda (&key attempts sleep-seconds)
             (declare (ignore attempts sleep-seconds))
             (pop input)))
        (multiple-value-bind (row column)
            (nshell.infrastructure.terminal:query-cursor-position
             :attempts 10 :sleep-seconds 0.001)
          (expect row :to-be 4)
          (expect column :to-be 6))))
    (let ((input (list #\Esc)))
      (with-temporary-function
          ('nshell.infrastructure.terminal::read-available-char
           (lambda (&key attempts sleep-seconds)
             (declare (ignore attempts sleep-seconds))
             (pop input)))
        (multiple-value-bind (row column)
            (nshell.infrastructure.terminal:query-cursor-position
             :attempts 2 :sleep-seconds 0.001)
          (expect row :to-be nil)
          (expect column :to-be nil)))))

  (it "returns-three-states-for-terminal-probe"
    (let ((queries 0))
      (with-temporary-function
          ('nshell.infrastructure.terminal::query-cursor-position
           (lambda (&key attempts sleep-seconds)
             (declare (ignore attempts sleep-seconds))
             (incf queries)
             (if (= queries 1) (values 1 10) (values 1 12))))
        (let ((*standard-input* (make-string-input-stream ""))
              (*standard-output* (make-string-output-stream)))
          (expect (nshell.infrastructure.terminal:detect-east-asian-ambiguous-wide-p)
                  :to-be :wide)))
      (setf queries 0)
      (with-temporary-function
          ('nshell.infrastructure.terminal::query-cursor-position
           (lambda (&key attempts sleep-seconds)
             (declare (ignore attempts sleep-seconds))
             (incf queries)
             (if (= queries 1) (values 1 10) (values 1 11))))
        (let ((*standard-input* (make-string-input-stream ""))
              (*standard-output* (make-string-output-stream)))
          (expect (nshell.infrastructure.terminal:detect-east-asian-ambiguous-wide-p)
                  :to-be :narrow))))))

  (it "keeps-measured-narrow-over-japanese-locale"
    (with-repl-test-state
      (repl-test-set-env "NSHELL_EAST_ASIAN_AMBIGUOUS_WIDTH" "auto")
      (repl-test-set-env "LANG" "ja_JP.UTF-8")
      (with-temporary-function
          ('nshell.infrastructure.terminal:interactive-terminal-p
           (lambda (&optional fd) (declare (ignore fd)) t))
        (with-temporary-function
            ('nshell.infrastructure.terminal:detect-east-asian-ambiguous-wide-p
             (lambda (&key attempts sleep-seconds)
               (declare (ignore attempts sleep-seconds))
               :narrow))
          (let ((nshell.presentation::*interactive-terminal-installed-p* t))
            (nshell.presentation::%apply-east-asian-ambiguous-width))
          (expect cl-tty-kit:*east-asian-ambiguous-wide* :to-be nil)))))

  (it "measures-ascii-and-unicode-display-widths"
    (let ((vs16 "❤️")
          (family "👨‍👩‍👧‍👦")
          (flag "🇯🇵")
          (combining "é"))
      (dolist (text (list vs16 family flag combining))
        (expect 1 :to-equal
                (length (cl-tty-kit:string-graphemes text))))
      (expect 15 :to-equal
              (nshell.presentation::%string-visible-width "plain ASCII 123"))
      (expect (nshell.presentation::%string-visible-width family) :to-equal 2)
      (expect (nshell.presentation::%string-visible-width vs16) :to-equal 2)
      (expect (nshell.presentation::%string-visible-width flag) :to-equal 2)
      (expect (nshell.presentation::%string-visible-width combining) :to-equal 1)
      (expect (nshell.presentation::%truncate-string-to-width family 1)
              :to-equal "")
      (expect (nshell.presentation::%truncate-string-to-width family 2)
              :to-equal family)))

  (it "moves-and-deletes-input-by-grapheme"
    (let* ((family "👨‍👩‍👧‍👦")
           (state (input-state :buffer (concatenate 'string "a" family "b")
                               :cursor-pos (+ 1 (length family))))
           (backspaced nil)
           (ignored-output nil))
      (declare (ignore ignored-output))
      (multiple-value-setq (backspaced ignored-output)
        (nshell.presentation::backspace-before-cursor state))
      (expect (nshell.presentation:input-state-buffer backspaced)
              :to-equal "ab")
      (expect (nshell.presentation:input-state-cursor-pos backspaced)
              :to-equal 1))
    (let* ((family "👨‍👩‍👧‍👦")
           (state (input-state :buffer (concatenate 'string "a" family "b")
                               :cursor-pos 1))
           (moved nil)
           (ignored-output nil))
      (declare (ignore ignored-output))
      (multiple-value-setq (moved ignored-output)
        (nshell.presentation::move-cursor-clearing-suggestion state 1))
      (expect (nshell.presentation:input-state-cursor-pos moved)
              :to-equal (+ 1 (length family))))))

(defclass scripted-terminal-input (sb-gray:fundamental-character-input-stream)
  ((script :initarg :script :accessor scripted-terminal-input-script)
   (last-read :initform nil :accessor scripted-terminal-input-last-read))
  (:documentation
   "Terminal input whose bytes arrive in pieces.  Each :GAP entry makes one
LISTEN return NIL, as a poll that runs before the next piece arrives; a
blocking READ-CHAR waits past it.  Like a conforming stream, it accepts only
one UNREAD-CHAR of the character most recently read."))

(defun scripted-terminal-input (&rest pieces)
  "Return a SCRIPTED-TERMINAL-INPUT delivering PIECES (strings or :GAP)."
  (make-instance 'scripted-terminal-input
                 :script (loop for piece in pieces
                               if (stringp piece)
                                 append (coerce piece 'list)
                               else
                                 collect piece)))

(defmethod sb-gray:stream-read-char ((stream scripted-terminal-input))
  (loop while (eq :gap (first (scripted-terminal-input-script stream)))
        do (pop (scripted-terminal-input-script stream)))
  (let ((character (pop (scripted-terminal-input-script stream))))
    (setf (scripted-terminal-input-last-read stream) character)
    (or character :eof)))

(defmethod sb-gray:stream-listen ((stream scripted-terminal-input))
  (let ((next (first (scripted-terminal-input-script stream))))
    (cond ((eq next :gap)
           (pop (scripted-terminal-input-script stream))
           nil)
          (t (characterp next)))))

(defmethod interactive-stream-p ((stream scripted-terminal-input))
  t)

(defmethod sb-gray:stream-unread-char ((stream scripted-terminal-input) character)
  (unless (eql character (scripted-terminal-input-last-read stream))
    (error "UNREAD-CHAR of ~S does not undo the most recent READ-CHAR." character))
  (setf (scripted-terminal-input-last-read stream) nil)
  (push character (scripted-terminal-input-script stream))
  nil)

(defun scripted-gaps (count)
  (make-list count :initial-element :gap))

(defun query-scripted-cursor-position (attempts &rest pieces)
  "Query the cursor over PIECES; return the row, column, and the input stream."
  (let ((input (apply #'scripted-terminal-input pieces)))
    (multiple-value-bind (row column)
        (let ((*standard-input* input)
              (*standard-output* (make-string-output-stream)))
          (nshell.infrastructure.terminal:query-cursor-position
           :attempts attempts :sleep-seconds 0))
      (values row column input))))

(defun next-scripted-key (input)
  (let ((*standard-input* input))
    (nshell.infrastructure.terminal:read-key-event)))

(describe "cursor-position-report-input"
  (it "query-decodes-a-report-split-across-reads"
    (multiple-value-bind (row column input)
        (apply #'query-scripted-cursor-position
               12 (append (list (format nil "~C[1" #\Esc)) (scripted-gaps 1)
                         (list ";2") (scripted-gaps 1) (list "0R" "x")))
      (expect row :to-be 1)
      (expect column :to-be 20)
      (expect (nshell.infrastructure.terminal:key-event-char
               (next-scripted-key input))
              :to-equal #\x)))

  (it "report-tail-arriving-after-query-timeout-is-discarded"
    (multiple-value-bind (row column input)
        (apply #'query-scripted-cursor-position
               3 (append (list (format nil "~C[1;" #\Esc)) (scripted-gaps 3)
                         (list "20R" "x")))
      (expect row :to-be nil)
      (expect column :to-be nil)
      (expect (nshell.infrastructure.terminal:key-event-type
               (next-scripted-key input))
              :to-be :ignore)
      (expect (nshell.infrastructure.terminal:key-event-char
               (next-scripted-key input))
              :to-equal #\x)))

  (it "timeout-between-escape-and-bracket-leaves-report-for-decoder"
    (multiple-value-bind (row column input)
        (apply #'query-scripted-cursor-position
               3 (append (list (string #\Esc)) (scripted-gaps 3) (list "[1;20R" "x")))
      (expect row :to-be nil)
      (expect column :to-be nil)
      (expect (nshell.infrastructure.terminal:key-event-type
               (next-scripted-key input))
              :to-be :ignore)
      (expect (nshell.infrastructure.terminal:key-event-char
               (next-scripted-key input))
              :to-equal #\x)))

  (it "user-input-inside-a-report-is-delivered-in-order"
    (let ((typed (format nil "~C[3x;5Ry" #\Esc)))
      (multiple-value-bind (row column input)
          (query-scripted-cursor-position 12 typed)
        (expect row :to-be nil)
        (expect column :to-be nil)
        (expect (let ((*standard-input* input))
                  (coerce (loop for character
                                  = (nshell.infrastructure.terminal::read-available-char
                                     :attempts 1 :sleep-seconds 0)
                                while character
                                collect character)
                          'string))
                :to-equal typed))))

  (it "query-reads-a-late-reply-so-none-is-left-unread"
    ;; Ctrl-Z, exit and external commands release raw mode without reading
    ;; input, so a reply must not be left in the stream after the query.
    (multiple-value-bind (row column input)
        (query-scripted-cursor-position
         3 :gap "ec" :gap (format nil "~C[2;1R" #\Esc) "ho")
      (expect row :to-be 2)
      (expect column :to-be 1)
      (expect (scripted-terminal-input-script input) :to-equal '(#\h #\o))
      (expect (coerce (let ((*standard-input* input))
                        (loop for character
                                = (nshell.infrastructure.terminal::read-available-char
                                   :attempts 1 :sleep-seconds 0)
                              while character
                              collect character))
                      'string)
              :to-equal "echo")))

  (it "input-after-the-reply-stays-in-the-stream-for-an-external-command"
    ;; The scripted stream stands for the inherited descriptor: what is still
    ;; in it when the cooked-terminal extent starts is what a child would read.
    (let ((input (scripted-terminal-input
                  :gap (format nil "~C[2;1R" #\Esc) (format nil "data~%")))
          (seen-by-command :unset))
      (let ((*standard-input* input)
            (*standard-output* (make-string-output-stream)))
        (nshell.infrastructure.terminal:query-cursor-position
         :attempts 3 :sleep-seconds 0)
        (with-temporary-function
            ('nshell.infrastructure.terminal:restore-terminal-mode
             (lambda (&rest arguments) (declare (ignore arguments)) nil))
          (with-temporary-function
              ('nshell.infrastructure.terminal:enable-raw-mode
               (lambda (&rest arguments) (declare (ignore arguments)) nil))
            (with-temporary-function
                ('nshell.infrastructure.terminal:terminal-control-sequences-supported-p
                 (lambda (&rest arguments) (declare (ignore arguments)) nil))
              (nshell.presentation::%call-with-cooked-terminal
               (lambda ()
                 (setf seen-by-command
                       (coerce (remove :gap (scripted-terminal-input-script input))
                               'string))))))))
      (expect seen-by-command :to-equal (format nil "data~%"))))

  (it "reply-split-after-escape-does-not-become-input"
    (multiple-value-bind (row column input)
        (apply #'query-scripted-cursor-position
               40 :gap (string #\Esc)
               (append (scripted-gaps 25) (list "[2;1R" "x")))
      (expect row :to-be 2)
      (expect column :to-be 1)
      (expect (nshell.infrastructure.terminal:key-event-char
               (next-scripted-key input))
              :to-equal #\x)))

  (it "unanswered-query-stops-later-cursor-queries"
    (let ((input (scripted-terminal-input "x"))
          (output (make-string-output-stream)))
      (let ((*standard-input* input)
            (*standard-output* output))
        (nshell.infrastructure.terminal:query-cursor-position
         :attempts 3 :sleep-seconds 0)
        (get-output-stream-string output)
        (multiple-value-bind (row column)
            (nshell.infrastructure.terminal:query-cursor-position
             :attempts 3 :sleep-seconds 0)
          (expect row :to-be nil)
          (expect column :to-be nil))
        (expect (get-output-stream-string output) :to-equal "")
        (expect (nshell.infrastructure.terminal:key-event-char
                 (nshell.infrastructure.terminal:read-key-event))
                :to-equal #\x))))

  (it "builtin-read-sees-input-stashed-during-a-query"
    (let ((input (scripted-terminal-input
                  :gap (format nil "hello~%wor") (format nil "~C[2;1R" #\Esc)
                  (format nil "ld~%next"))))
      (let ((*standard-input* input)
            (*standard-output* (make-string-output-stream)))
        (nshell.infrastructure.terminal:query-cursor-position
         :attempts 3 :sleep-seconds 0)
        (with-builtins-context (context)
          (call-builtin context "read" '("first"))
          (call-builtin context "read" '("second"))
          (let ((environment (nshell.application:shell-context-environment context)))
            (expect (nshell.domain.environment:env-get environment "first")
                    :to-equal "hello")
            (expect (nshell.domain.environment:env-get environment "second")
                    :to-equal "world")))
        (expect (nshell.infrastructure.terminal:key-event-char
                 (nshell.infrastructure.terminal:read-key-event))
                :to-equal #\n))))
  (it "cursor-query-read-ahead-decodes-alt-enter"
    (multiple-value-bind (row column input)
        (query-scripted-cursor-position
         3 (format nil "~C~C" #\Esc #\Return))
      (expect row :to-be nil)
      (expect column :to-be nil)
      (expect (nshell.infrastructure.terminal:key-event-type
               (next-scripted-key input))
              :to-be :alt-enter))))
