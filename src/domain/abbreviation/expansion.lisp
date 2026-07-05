;;; Shell abbreviation engine
(in-package #:nshell.domain.abbreviation)

(defstruct (abbreviation
            (:constructor %allocate-abbreviation (expansion position))
            (:copier nil))
  "Abbreviation expansion metadata."
  (expansion "" :type string :read-only t)
  (position :anywhere :type (member :anywhere :command) :read-only t))

(defun make-abbreviation (&key (expansion "") (position :anywhere))
  "Create validated abbreviation expansion metadata."
  (check-type expansion string)
  (check-type position (member :anywhere :command))
  (%allocate-abbreviation (copy-seq expansion) position))

(defstruct (abbreviation-token-range
            (:constructor %make-abbreviation-token-range (start end)))
  "Token boundary used by the abbreviation scanner."
  (start 0 :type fixnum :read-only t)
  (end 0 :type fixnum :read-only t))

(defun abbreviation-boundary-p (ch)
  (member ch '(#\Space #\Tab #\Newline #\| #\; #\& #\< #\>) :test #'char=))

(defun abbreviation-command-separator-p (ch)
  (member ch '(#\Newline #\| #\; #\&) :test #'char=))

(defun abbreviation-token-end (text start limit)
  "Return the shell token end for TEXT starting at START and bounded by LIMIT."
  (let ((pos start)
        (end (min limit (length text)))
        (quote nil)
        (escaped nil))
    (block scan
      (loop while (< pos end)
            for ch = (char text pos)
            do (cond
                 ((eq quote #\')
                  (incf pos)
                  (when (char= ch #\')
                    (setf quote nil)))
                 (escaped
                  (setf escaped nil)
                  (incf pos))
                 ((char= ch #\\)
                  (setf escaped t)
                  (incf pos))
                 ((eq quote #\")
                  (incf pos)
                  (when (char= ch #\")
                    (setf quote nil)))
                 ((or (char= ch #\')
                       (char= ch #\"))
                  (setf quote ch)
                  (incf pos))
                 ((abbreviation-boundary-p ch)
                  (return-from scan pos))
                 (t
                  (incf pos)))))
    pos))

(defun abbreviation-token-ranges-before (text limit)
  "Return shell token ranges before LIMIT, respecting quotes and escapes."
  (let ((pos 0)
        (end (min limit (length text)))
        (ranges nil))
    (loop while (< pos end)
          do (if (abbreviation-boundary-p (char text pos))
                  (incf pos)
                  (let ((token-start pos)
                        (token-end (abbreviation-token-end text pos end)))
                   (push (%make-abbreviation-token-range token-start token-end) ranges)
                   (setf pos (max token-end (1+ pos))))))
    (nreverse ranges)))

(defun abbreviation-token-range-values (buffer range)
  (let ((start (abbreviation-token-range-start range))
        (end (abbreviation-token-range-end range)))
    (values (subseq buffer start end) start end t)))

(defun abbreviation-target-before-cursor (buffer cursor)
  "Return token, start, end, and found-p for a token ending at CURSOR."
  (let* ((end (length buffer))
         (position (min cursor end)))
    (loop for range in (abbreviation-token-ranges-before buffer position)
          when (= (abbreviation-token-range-end range) position)
            do (return (abbreviation-token-range-values buffer range))
          finally (return (values nil nil nil nil)))))

(defun abbreviation-command-position-p (buffer token-start)
  "Return true when TOKEN-START begins a command position."
  (let ((pos (1- token-start)))
    (loop while (and (>= pos 0)
                     (member (char buffer pos) '(#\Space #\Tab) :test #'char=))
          do (decf pos))
    (or (< pos 0)
        (abbreviation-command-separator-p (char buffer pos)))))

(defun abbreviation-expansion-value (expansion)
  (cond
    ((stringp expansion) expansion)
    ((abbreviation-p expansion) (abbreviation-expansion expansion))
    (t nil)))

(defun abbreviation-quoted-token-p (token)
  "Return true when TOKEN contains an unescaped shell quote delimiter."
  (loop with escaped = nil
        for ch across token
        do (cond
             (escaped
              (setf escaped nil))
             ((char= ch #\\)
              (setf escaped t))
             ((or (char= ch #\')
                  (char= ch #\"))
              (return t)))
        finally (return nil)))

(defun abbreviation-position-eligible-p (expansion buffer token-start)
  (or (not (abbreviation-p expansion))
      (case (abbreviation-position expansion)
        (:anywhere t)
        (:command (abbreviation-command-position-p buffer token-start))
        (otherwise nil))))

(defun expand-abbreviation (buffer cursor expander &key max-length)
  "Expand the token ending at CURSOR using EXPANDER.

Returns BUFFER, CURSOR, and expanded-p. MAX-LENGTH, when non-nil, rejects
expansions that would exceed it.
"
  (if (null expander)
      (values buffer cursor nil)
      (multiple-value-bind (token start end found-p)
          (abbreviation-target-before-cursor buffer cursor)
        (if (not found-p)
            (values buffer cursor nil)
            (let ((expansion (funcall expander token)))
              (if (and (not (abbreviation-quoted-token-p token))
                       (abbreviation-position-eligible-p expansion buffer start)
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
                        (values new-buffer
                                (+ start (length value))
                                t)))
                  (values buffer cursor nil)))))))
