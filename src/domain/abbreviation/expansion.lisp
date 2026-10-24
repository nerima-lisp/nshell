;;; Shell abbreviation engine
(in-package #:nshell.domain.abbreviation)

(define-value-struct abbreviation
    ((expansion "" :type string)
     (position :anywhere :type (member :anywhere :command)))
  :documentation "Abbreviation expansion metadata."
  :constructor %allocate-abbreviation)

(defun make-abbreviation (&key (expansion "") (position :anywhere))
  "Create validated abbreviation expansion metadata."
  (check-type expansion string)
  (check-type position (member :anywhere :command))
  (%allocate-abbreviation (copy-seq expansion) position))

(define-value-struct abbreviation-token-range
    ((start 0 :type fixnum)
     (end 0 :type fixnum)
     (kind nil)
     (reader-context nil))
  :documentation "Token boundary used by the abbreviation scanner.")

(defun abbreviation-token-ranges-before (text limit &key head-classifier)
  "Return scanner word-token ranges before LIMIT."
  (let* ((end (min limit (length text)))
         (source (subseq text 0 end))
         (result
           (nshell.domain.parsing:scan-input
            source
            :cursor end
            :head-classifier
            (or head-classifier
                (lambda (head)
                  (declare (ignore head))
                  :host-form)))))
    (loop for token in (nshell.domain.parsing:scan-result-tokens result)
          for span = (nshell.domain.parsing:scan-token-span token)
          for kind = (nshell.domain.parsing:scan-token-kind token)
          for context = (nshell.domain.parsing:scan-token-reader-context token)
          when (and (<= (second span) end)
                    (member kind
                            '(:command-head :argument :string :here-doc-delimiter)
                            :test #'eq)
                    (member context '(:bare-line :command-island) :test #'eq))
            collect (%make-abbreviation-token-range
                     (first span) (second span) kind context))))
(defun abbreviation-boundary-p (ch)
  (member ch '(#\Space #\Tab #\Newline #\| #\; #\& #\< #\>) :test #'char=))

(defun abbreviation-token-range-values (buffer range)
  (let ((start (abbreviation-token-range-start range))
        (end (abbreviation-token-range-end range)))
    (values (subseq buffer start end)
            start
            end
            t
            (abbreviation-token-range-kind range)
            (abbreviation-token-range-reader-context range))))

(defun abbreviation-target-before-cursor
    (buffer cursor &key head-classifier)
  "Return token, start, end, and found-p for a token ending at CURSOR."
  (let* ((end (length buffer))
         (position (min cursor end)))
    (loop for range in (abbreviation-token-ranges-before
                        buffer position :head-classifier head-classifier)
          when (= (abbreviation-token-range-end range) position)
            do (return (abbreviation-token-range-values buffer range))
          finally (return (values nil nil nil nil nil nil)))))

(defun abbreviation-command-position-p
    (buffer token-start &key head-classifier)
  "Return true when TOKEN-START is a scanner command-head token."
  (let* ((position (min token-start (length buffer)))
         (result
           (nshell.domain.parsing:scan-input
            buffer
            :cursor position
            :head-classifier
            (or head-classifier
                (lambda (head)
                  (declare (ignore head))
                  :host-form)))))
    (some (lambda (token)
            (let ((span (nshell.domain.parsing:scan-token-span token)))
              (and (= (first span) position)
                   (eq (nshell.domain.parsing:scan-token-kind token) :command-head)
                   (member (nshell.domain.parsing:scan-token-reader-context token)
                           '(:bare-line :command-island)
                           :test #'eq))))
          (nshell.domain.parsing:scan-result-tokens result))))

(defun abbreviation-expansion-value (expansion)
  (cond
    ((stringp expansion) expansion)
    ((abbreviation-p expansion) (abbreviation-expansion expansion))
    (t nil)))

(defun abbreviation-position-eligible-p
    (expansion buffer token-start head-classifier)
  (or (not (abbreviation-p expansion))
      (case (abbreviation-position expansion)
        (:anywhere t)
        (:command
         (abbreviation-command-position-p
          buffer token-start :head-classifier head-classifier))
        (otherwise nil))))

(defun expand-abbreviation
    (buffer cursor expander &key max-length head-classifier)
  "Expand the scanner token ending at CURSOR using EXPANDER.

Returns BUFFER, CURSOR, and expanded-p. MAX-LENGTH, when non-nil, rejects
expansions that would exceed it.
"
  (if (null expander)
      (values buffer cursor nil)
      (multiple-value-bind (token start end found-p kind context)
          (abbreviation-target-before-cursor
           buffer cursor :head-classifier head-classifier)
        (if (or (not found-p) (eq kind :string)
                (not (member context '(:bare-line :command-island) :test #'eq)))
            (values buffer cursor nil)
            (let ((expansion (funcall expander token)))
              (if (and (abbreviation-position-eligible-p
                        expansion buffer start head-classifier)
                       (stringp (abbreviation-expansion-value expansion))
                       (let ((value (abbreviation-expansion-value expansion)))
                         (and (not (string= value ""))
                              (not (string= value token)))))
                  (let* ((value (abbreviation-expansion-value expansion))
                         (new-buffer (concatenate 'string
                                                  (subseq buffer 0 start)
                                                  value
                                                  (subseq buffer end))))
                    (if (and max-length (> (length new-buffer) max-length))
                        (values buffer cursor nil)
                        (values new-buffer (+ start (length value)) t)))
                  (values buffer cursor nil)))))))
