;;; Prompt format strings -- turning a user-supplied template into the same
;;; PROMPT-SEGMENT list RENDER-PROMPT-MODEL produces for the built-in layout.
;;; Pure: git status and the clock still arrive through the resolver hooks
;;; PROMPT.LISP already defines; job counts and assistant-usage text are not
;;; part of PROMPT-MODEL, so the caller supplies them explicitly.
(in-package #:nshell.domain.prompting)

(define-condition invalid-prompt-format (error)
  ((segment :initarg :segment :reader invalid-prompt-format-segment))
  (:report (lambda (condition stream)
             (format stream "Unknown prompt segment: {~a}"
                     (invalid-prompt-format-segment condition)))))

(defparameter +default-left-prompt-format+ "{path} {git} {status} ")
(defparameter +default-right-prompt-format+ "{exit} {duration} {time} {ai}")

(defun %format-segment-path (pm fe jc at)
  (declare (ignore fe jc at))
  (values (prompt-model-cwd pm) :path))

(defun %format-segment-git (pm fe jc at)
  (declare (ignore fe jc at))
  (let ((seg (%git-status-segment pm)))
    (if seg
        (values (prompt-segment-text seg) (prompt-segment-kind seg))
        (values "" :literal))))

(defun %format-segment-host (pm fe jc at)
  (declare (ignore fe jc at))
  (values (prompt-model-hostname pm) :host))

(defun %format-segment-user (pm fe jc at)
  (declare (ignore fe jc at))
  (values (or (prompt-model-user pm) "") :user))

(defun %format-segment-status (pm fe jc at)
  (declare (ignore fe jc at))
  (let ((seg (%prompt-exit-segment pm)))
    (values (prompt-segment-text seg) (prompt-segment-kind seg))))

(defun %format-segment-exit (pm failure-explain-p jc at)
  (declare (ignore jc at))
  (let ((exit-code (prompt-model-exit-code pm)))
    (if (and exit-code (not (zerop exit-code)))
        (values (if failure-explain-p
                    (format nil "[~d · ?]" exit-code)
                    (format nil "[~d]" exit-code))
                :exit-error)
        (values "" :literal))))

(defun %format-segment-duration (pm fe jc at)
  (declare (ignore fe jc at))
  (let ((seg (%prompt-duration-segment pm)))
    (if seg
        (values (prompt-segment-text seg) (prompt-segment-kind seg))
        (values "" :literal))))

(defun %format-segment-time (pm fe jc at)
  (declare (ignore pm fe jc at))
  (let ((seg (%prompt-time-segment)))
    (if seg
        (values (prompt-segment-text seg) (prompt-segment-kind seg))
        (values "" :literal))))

(defun %format-segment-jobs (pm fe jobs-count at)
  (declare (ignore pm fe at))
  (if (and jobs-count (plusp jobs-count))
      (values (princ-to-string jobs-count) :jobs)
      (values "" :literal)))

(defun %format-segment-ai (pm fe jc assistant-text)
  (declare (ignore pm fe jc))
  (if (and assistant-text (plusp (length assistant-text)))
      (values assistant-text :assistant)
      (values "" :literal)))

(defparameter *prompt-format-segment-resolvers*
  (list (cons "path" #'%format-segment-path)
        (cons "git" #'%format-segment-git)
        (cons "host" #'%format-segment-host)
        (cons "user" #'%format-segment-user)
        (cons "status" #'%format-segment-status)
        (cons "exit" #'%format-segment-exit)
        (cons "duration" #'%format-segment-duration)
        (cons "time" #'%format-segment-time)
        (cons "jobs" #'%format-segment-jobs)
        (cons "ai" #'%format-segment-ai))
  "Alist of segment name to a resolver of (PM FAILURE-EXPLAIN-P JOBS-COUNT
ASSISTANT-TEXT), returning the segment's TEXT and KIND. The single source of
truth for which {name}s a format string may use.")

(defun parse-prompt-format (format)
  "Split FORMAT into a list of (:LITERAL TEXT) and (:SEGMENT NAME) tokens.
{{ and }} stand for a literal brace; any other {name} names a segment, and an
unrecognized or unterminated one signals INVALID-PROMPT-FORMAT."
  (let ((tokens nil)
        (buffer (make-string-output-stream))
        (length (length format))
        (index 0))
    (flet ((flush-literal ()
             (let ((text (get-output-stream-string buffer)))
               (when (plusp (length text))
                 (push (list :literal text) tokens)))))
      (loop while (< index length)
            do (let ((char (char format index)))
                 (cond
                   ((and (char= char #\{) (< (1+ index) length)
                         (char= (char format (1+ index)) #\{))
                    (write-char #\{ buffer)
                    (incf index 2))
                   ((and (char= char #\}) (< (1+ index) length)
                         (char= (char format (1+ index)) #\}))
                    (write-char #\} buffer)
                    (incf index 2))
                   ((char= char #\{)
                    (let ((close (position #\} format :start index)))
                      (unless close
                        (error 'invalid-prompt-format
                               :segment (subseq format (1+ index))))
                      (let ((name (subseq format (1+ index) close)))
                        (unless (assoc name *prompt-format-segment-resolvers*
                                       :test #'string=)
                          (error 'invalid-prompt-format :segment name))
                        (flush-literal)
                        (push (list :segment name) tokens)
                        (setf index (1+ close)))))
                   (t
                    (write-char char buffer)
                    (incf index)))))
      (flush-literal))
    (nreverse tokens)))

(defun %prompt-format-strip-leading-space-run (text)
  (subseq text (or (position-if-not (lambda (c) (char= c #\Space)) text)
                    (length text))))

(defun %prompt-format-strip-trailing-space-run (text)
  (subseq text 0
          (1+ (or (position-if-not (lambda (c) (char= c #\Space)) text
                                    :from-end t)
                  -1))))

(defun %prompt-format-collapse-empty-runs (items)
  "Drop one adjacent run of spaces around every empty resolved segment in the
vector ITEMS, in place, so an empty segment does not leave a double space
where a literal run of spaces flanked it on both sides."
  (loop for index from 0 below (length items)
        for item = (aref items index)
        when (and (eq (first item) :resolved) (zerop (length (second item))))
          do (let ((next (and (< (1+ index) (length items)) (1+ index)))
                   (previous (and (plusp index) (1- index))))
               (cond
                 ((and next
                       (eq (first (aref items next)) :literal)
                       (plusp (length (second (aref items next))))
                       (char= (char (second (aref items next)) 0) #\Space))
                  (setf (aref items next)
                        (list :literal
                              (%prompt-format-strip-leading-space-run
                               (second (aref items next))))))
                 ((and previous
                       (eq (first (aref items previous)) :literal)
                       (plusp (length (second (aref items previous))))
                       (char= (char (second (aref items previous))
                                    (1- (length (second (aref items previous)))))
                              #\Space))
                  (setf (aref items previous)
                        (list :literal
                              (%prompt-format-strip-trailing-space-run
                               (second (aref items previous))))))))))

(defun render-prompt-format (format pm &key failure-explain-p jobs-count assistant-text)
  "Render FORMAT against PM into the PROMPT-SEGMENT list RENDER-PROMPT-MODEL
returns for the built-in layout. JOBS-COUNT and ASSISTANT-TEXT feed the
{jobs} and {ai} segments, since neither lives on PROMPT-MODEL."
  (let ((items (coerce
                (mapcar (lambda (token)
                          (if (eq (first token) :literal)
                              token
                              (multiple-value-bind (text kind)
                                  (funcall (cdr (assoc (second token)
                                                        *prompt-format-segment-resolvers*
                                                        :test #'string=))
                                           pm failure-explain-p jobs-count assistant-text)
                                (list :resolved text kind))))
                        (parse-prompt-format format))
                'vector)))
    (%prompt-format-collapse-empty-runs items)
    (loop for item across items
          for text = (second item)
          unless (zerop (length text))
            collect (make-prompt-segment
                     text
                     (if (eq (first item) :literal) :literal (third item))))))
