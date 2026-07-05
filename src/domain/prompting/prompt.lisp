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

(defstruct (prompt-model
            (:constructor %allocate-prompt-model)
            (:conc-name %prompt-model-)
            (:copier nil)
            (:predicate %prompt-model-p))
  "Pure data model for rendering a shell prompt."
  (hostname "localhost" :type string :read-only t)
  (cwd "/" :type string :read-only t)
  (directory nil :type (or null string) :read-only t)
  (exit-code 0 :type (or null integer) :read-only t)
  (duration-ms nil :type (or null integer) :read-only t)
  (segments nil :type list :read-only t)
  (right-segments nil :type list :read-only t))

(defstruct (prompt-segment
            (:constructor %allocate-prompt-segment)
            (:conc-name %prompt-segment-)
            (:copier nil)
            (:predicate %prompt-segment-p))
  "A segment of the prompt (left or right)."
  (text "" :type string :read-only t)
  (kind :literal :type keyword :read-only t))

(defun %ensure-string (value field-name)
  (unless (stringp value)
    (error "~a must be a string: ~s" field-name value))
  value)

(defun %ensure-optional-string (value field-name)
  (when value
    (%ensure-string value field-name))
  value)

(defun %ensure-optional-integer (value field-name)
  (when value
    (unless (integerp value)
      (error "~a must be NIL or an integer: ~s" field-name value)))
  value)

(defun %ensure-keyword (value field-name)
  (unless (keywordp value)
    (error "~a must be a keyword: ~s" field-name value))
  value)

(defun %ensure-list (value field-name)
  (unless (listp value)
    (error "~a must be a list: ~s" field-name value))
  value)

(defun make-prompt-model (&key (hostname "localhost")
                               (cwd "/")
                               directory
                               (exit-code 0)
                               duration-ms
                               segments
                               right-segments)
  (%allocate-prompt-model
   :hostname (%ensure-string hostname "HOSTNAME")
   :cwd (%ensure-string cwd "CWD")
   :directory (%ensure-optional-string directory "DIRECTORY")
   :exit-code (%ensure-optional-integer exit-code "EXIT-CODE")
   :duration-ms (%ensure-optional-integer duration-ms "DURATION-MS")
   :segments (copy-list (%ensure-list segments "SEGMENTS"))
   :right-segments (copy-list (%ensure-list right-segments "RIGHT-SEGMENTS"))))

(defun prompt-model-hostname (pm)
  (%prompt-model-hostname pm))

(defun prompt-model-cwd (pm)
  (%prompt-model-cwd pm))

(defun prompt-model-directory (pm)
  (%prompt-model-directory pm))

(defun prompt-model-exit-code (pm)
  (%prompt-model-exit-code pm))

(defun prompt-model-duration-ms (pm)
  (%prompt-model-duration-ms pm))

(defun prompt-model-segments (pm)
  (copy-list (%prompt-model-segments pm)))

(defun prompt-model-right-segments (pm)
  (copy-list (%prompt-model-right-segments pm)))

(defun make-prompt-segment (text kind)
  (%allocate-prompt-segment
   :text (%ensure-string text "TEXT")
   :kind (%ensure-keyword kind "KIND")))

(defun prompt-segment-text (segment)
  (%prompt-segment-text segment))

(defun prompt-segment-kind (segment)
  (%prompt-segment-kind segment))

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
     (%git-status-segment pm))
    (t seg)))

(defun render-prompt-model (pm)
  "Convert a prompt model into left prompt segments."
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
    segs))

(defun render-right-prompt-model (pm)
  "Convert prompt model right segments to prompt segments."
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
            (push git result))
          (when (and ec (not (zerop ec)))
            (when result
              (push (make-prompt-segment " " :literal) result))
            (push (make-prompt-segment (format nil "[~d]" ec) :exit-error) result))
          (when duration
            (when result
              (push (make-prompt-segment " " :literal) result))
            (push duration result))
          (let ((time (%prompt-time-segment)))
            (when time
              (when result
                (push (make-prompt-segment " " :literal) result))
              (push time result)))
          (nreverse result)))))
