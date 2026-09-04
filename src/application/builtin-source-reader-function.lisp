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
