(in-package #:nshell.application)

(defparameter +source-definition-opening-keywords+
  '("if" "for" "while" "switch" "begin" "function"))

(defparameter +source-definition-end-keyword+ "end")

(define-value-struct %source-function-consumption
    ((closed-p nil :type boolean)
     (remaining-lines nil :type list)
     (depth 0 :type integer)
     (body-lines nil :type list)))

(define-value-struct %source-function-definition-result
    ((remaining-lines nil :type list)
     (output-chunk nil :type (or null string))
     (exit-code 0 :type integer)
     (stop-p nil :type boolean)))

(define-value-struct %source-lines-step-result
    ((remaining-lines nil :type list)
     (output-chunks nil :type list)
     (exit-code 0 :type integer)
     (stop-p nil :type boolean)))

(defun %source-line-segments (line)
  (let ((tokens (nshell.domain.parsing:tokenization-result-tokens
                 (nshell.domain.parsing:tokenize line))))
    (let ((segments nil)
          (segment-start 0))
      (loop for token in tokens
            do (when (member (nshell.domain.parsing:token-type token)
                             '(:semicolon :ampersand)
                             :test #'eq)
                 (let ((segment (string-trim '(#\Space #\Tab)
                                             (subseq line
                                                     segment-start
                                                     (nshell.domain.parsing:token-start token)))))
                   (when (plusp (length segment))
                     (push segment segments)))
                 (setf segment-start (nshell.domain.parsing:token-end token)))
            finally
              (let ((segment (string-trim '(#\Space #\Tab)
                                          (subseq line segment-start))))
                (when (plusp (length segment))
                  (push segment segments)))
              (return (nreverse segments))))))

(defun %source-line-segment-offsets (line)
  "The commands on LINE as (OFFSET . TEXT) pairs, offset into LINE."
  (let ((tokens (nshell.domain.parsing:tokenization-result-tokens
                 (nshell.domain.parsing:tokenize line)))
        (segments nil)
        (segment-start 0))
    (flet ((collect (end)
             (let* ((text (subseq line segment-start end))
                    (trimmed (string-left-trim '(#\Space #\Tab) text)))
               (when (plusp (length trimmed))
                 (push (cons (+ segment-start (- (length text) (length trimmed)))
                             (string-right-trim '(#\Space #\Tab) trimmed))
                       segments)))))
      (dolist (token tokens)
        (when (member (nshell.domain.parsing:token-type token)
                      '(:semicolon :ampersand)
                      :test #'eq)
          (collect (nshell.domain.parsing:token-start token))
          (setf segment-start (nshell.domain.parsing:token-end token))))
      (collect (length line)))
    (nreverse segments)))

(defun source-line-function-split (line)
  "When LINE runs something before opening a function definition, return the
text before the definition and the text from the definition onward; otherwise
NIL. The prefix keeps its own separators, so a trailing `&' still backgrounds."
  (let ((entry (find-if (lambda (segment)
                          (and (plusp (car segment))
                               (%function-start-p (cdr segment))))
                        (%source-line-segment-offsets line))))
    (when entry
      (let ((prefix (string-right-trim '(#\Space #\Tab #\;)
                                       (subseq line 0 (car entry)))))
        (when (plusp (length prefix))
          (values prefix (subseq line (car entry))))))))

(defun %function-start-p (line)
  (let ((tokens (nshell.domain.parsing:tokenization-result-tokens
                 (nshell.domain.parsing:tokenize line))))
    (let ((words nil))
      (dolist (token tokens)
        (let ((type (nshell.domain.parsing:token-type token)))
          (when (member type '(:semicolon :ampersand :pipe :and :or)
                        :test #'eq)
            (return))
          (when (eq type :word)
            (push (nshell.domain.parsing:token-value token) words))))
      (let ((words (nreverse words)))
        (when (and (>= (length words) 2)
                   (string= (first words) "function"))
          (second words))))))

(defun function-definition-line-p (line)
  "True when any command on LINE opens a function definition, so the whole block
has to reach the source reader rather than the AST executor. A line may open one
after something else has run, as in `echo pre; function f; echo hi; end'."
  (some (lambda (segment) (%function-start-p segment))
        (%source-line-segments line)))

(defun %source-definition-line-depth-delta (line)
  (let ((tokens (nshell.domain.parsing:tokenization-result-tokens
                 (nshell.domain.parsing:tokenize line))))
    (let ((expect-command t)
          (delta 0))
      (dolist (token tokens delta)
        (let ((type (nshell.domain.parsing:token-type token))
              (value (nshell.domain.parsing:token-value token)))
          (cond
            ((and expect-command (eq type :word))
             (when (and (stringp value)
                        (member value +source-definition-opening-keywords+
                                :test #'string=))
               (incf delta))
             (when (and (stringp value)
                        (string= value +source-definition-end-keyword+))
               (decf delta))
             (setf expect-command nil))
            ((member type '(:semicolon :and :or :ampersand :pipe)
                    :test #'eq)
             (setf expect-command t))
            ((eq type :redirect)
             nil)
            ((eq type :word)
             (setf expect-command nil))))))))
