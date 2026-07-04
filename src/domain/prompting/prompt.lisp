;;; Prompt model - pure data structure for prompt rendering
;;; fish-inspired: left prompt + right prompt with git/exit/duration/time info
(in-package #:nshell.domain.prompting)

(defparameter *git-status-resolver*
  (lambda (directory)
    (declare (ignore directory))
    (values nil nil))
  "Function called with a directory and returning values BRANCH and DIRTY-P.")

(defparameter *prompt-time-resolver*
  (lambda ()
    (multiple-value-bind (sec min hour) (get-decoded-time)
      (declare (ignore sec))
      (format nil "~2,'0d:~2,'0d" hour min)))
  "Function returning the right-prompt time text, or NIL to omit it.")

(defstruct (prompt-model (:constructor %make-prompt-model (&key hostname cwd directory exit-code duration-ms segments right-segments)))
  "Pure data model for rendering a shell prompt."
  (hostname "localhost" :type string :read-only t)
  (cwd "/" :type string :read-only t)
  (directory nil :type (or null string) :read-only t)
  (exit-code 0 :type (or null integer) :read-only t)
  (duration-ms nil :type (or null integer) :read-only t)
  (segments nil :type list :read-only t)
  (right-segments nil :type list :read-only t))

(defstruct (prompt-segment (:constructor %make-prompt-segment (text kind)))
  "A segment of the prompt (left or right)."
  (text "" :type string :read-only t)
  (kind :literal :type keyword :read-only t))

(defun make-prompt-model (&key hostname cwd directory exit-code duration-ms segments right-segments)
  (%make-prompt-model
   :hostname hostname
   :cwd cwd
   :directory directory
   :exit-code exit-code
   :duration-ms duration-ms
   :segments segments
   :right-segments right-segments))

(defun make-prompt-segment (text kind)
  (%make-prompt-segment text kind))

(defun prompt-hostname (pm) (prompt-model-hostname pm))
(defun prompt-cwd (pm) (prompt-model-cwd pm))
(defun prompt-exit-code (pm) (prompt-model-exit-code pm))
(defun prompt-segments (pm) (prompt-model-segments pm))
(defun prompt-right-segments (pm) (prompt-model-right-segments pm))

(defun %prompt-directory (pm)
  (or (prompt-model-directory pm)
      (prompt-model-cwd pm)))

(defun %git-status-segment (pm)
  (multiple-value-bind (branch dirty-p)
      (funcall *git-status-resolver* (%prompt-directory pm))
    (when branch
      (make-prompt-segment
       (if dirty-p
           (concatenate 'string branch "*")
           branch)
       :git))))

(defun %prompt-time-segment ()
  (let ((text (funcall *prompt-time-resolver*)))
    (when text
      (make-prompt-segment text :time))))

(defun %prompt-duration-segment (pm)
  (let ((duration-ms (prompt-model-duration-ms pm)))
    (when (and duration-ms (plusp duration-ms))
      (make-prompt-segment
       (if (< duration-ms 1000)
           (format nil "~dms" duration-ms)
           (format nil "~,2fs" (/ duration-ms 1000.0)))
       :duration))))

(defun %render-right-segment (pm seg)
  (case (prompt-segment-kind seg)
    (:git
     (let ((resolved (%git-status-segment pm)))
       (when resolved
         (cons (prompt-segment-text resolved)
               (prompt-segment-kind resolved)))))
    (t (cons (prompt-segment-text seg)
             (prompt-segment-kind seg)))))

(defun render-prompt-model (pm)
  "Convert a prompt model into a list of (text . kind) pairs for the left prompt."
  (let ((segs (prompt-model-segments pm)))
    (when (null segs)
      (setf segs
            (list (make-prompt-segment (prompt-model-hostname pm) :host)
                  (make-prompt-segment " " :literal)
                  (make-prompt-segment (prompt-model-cwd pm) :path)
                  (make-prompt-segment " " :literal)
                  (make-prompt-segment
                   (if (and (prompt-model-exit-code pm)
                            (not (zerop (prompt-model-exit-code pm))))
                       "✗" ">")
                   :exit)
                  (make-prompt-segment " " :literal))))
    (mapcar (lambda (seg)
              (cons (prompt-segment-text seg) (prompt-segment-kind seg)))
            segs)))

(defun render-right-prompt-model (pm)
  "Convert prompt model right segments to (text . kind) pairs."
  (let ((segs (prompt-model-right-segments pm)))
    (if segs
        (remove nil (mapcar (lambda (seg)
                              (%render-right-segment pm seg))
                            segs))
        (let ((result nil)
              (git (%git-status-segment pm))
              (ec (prompt-model-exit-code pm))
              (duration (%prompt-duration-segment pm)))
          (when git
            (push (cons (prompt-segment-text git)
                        (prompt-segment-kind git))
                  result))
          (when (and ec (not (zerop ec)))
            (when result
              (push (cons " " :literal) result))
            (push (cons (format nil "[~d]" ec) :exit-error) result))
          (when duration
            (when result
              (push (cons " " :literal) result))
            (push (cons (prompt-segment-text duration)
                        (prompt-segment-kind duration))
                  result))
          (let ((time (%prompt-time-segment)))
            (when time
              (when result
                (push (cons " " :literal) result))
              (push (cons (prompt-segment-text time)
                          (prompt-segment-kind time))
                    result)))
          (nreverse result)))))
