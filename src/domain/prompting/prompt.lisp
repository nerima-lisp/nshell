;;; Prompt model - pure data structure for prompt rendering
;;; fish-inspired: left prompt (host/path/git/exit char) + right prompt
;;; (failed exit code/duration/time/assistant usage).
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

(define-value-struct prompt-model
    ((hostname "localhost" :type string)
     (cwd "/" :type string)
     (directory nil :type (or null string))
     (exit-code 0 :type (or null integer))
     (duration-ms nil :type (or null integer))
     (remote-session-p nil)
     (user nil :type (or null string))
     (segments nil :type list :copy :list)
     (right-segments nil :type list :copy :list))
  :documentation "Pure data model for rendering a shell prompt."
  :keyword-constructor t)

(define-value-struct prompt-segment
    ((text "" :type string)
     (kind :literal :type keyword))
  :documentation "A segment of the prompt (left or right).")

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

(defun %ensure-boolean (value field-name)
  (unless (member value '(t nil))
    (error "~a must be T or NIL: ~s" field-name value))
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
                               remote-session-p
                               user
                               segments
                               right-segments)
  (%make-prompt-model
   :hostname (%ensure-string hostname "HOSTNAME")
   :cwd (%ensure-string cwd "CWD")
   :directory (%ensure-optional-string directory "DIRECTORY")
   :exit-code (%ensure-optional-integer exit-code "EXIT-CODE")
   :duration-ms (%ensure-optional-integer duration-ms "DURATION-MS")
   :remote-session-p (%ensure-boolean remote-session-p "REMOTE-SESSION-P")
   :user (%ensure-optional-string user "USER")
   :segments (copy-list (%ensure-list segments "SEGMENTS"))
   :right-segments (copy-list (%ensure-list right-segments "RIGHT-SEGMENTS"))))

(defun make-prompt-segment (text kind)
  (%make-prompt-segment (%ensure-string text "TEXT")
                        (%ensure-keyword kind "KIND")))

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
       (if dirty-p :git-dirty :git)))))

(defun %host-segment (pm)
  (when (prompt-model-remote-session-p pm)
    (make-prompt-segment
     (if (prompt-model-user pm)
         (format nil "~a@~a " (prompt-model-user pm) (prompt-model-hostname pm))
         (format nil "~a " (prompt-model-hostname pm)))
     :host)))

(defun %prompt-exit-segment (pm)
  (make-prompt-segment
   "❯"
   (if (and (prompt-model-exit-code pm)
            (not (zerop (prompt-model-exit-code pm))))
       :exit-error
       :exit)))

(defun %prompt-time-segment ()
  (let ((text (funcall *prompt-time-resolver*)))
    (when text
      (make-prompt-segment text :time))))

(defun %prompt-duration-text (duration-ms)
  (let ((total-seconds (floor duration-ms 1000)))
    (cond
      ((< total-seconds 60) (format nil "~,1fs" (/ duration-ms 1000.0)))
      ((< total-seconds 3600)
       (format nil "~dm ~ds" (floor total-seconds 60) (mod total-seconds 60)))
      (t
       (format nil "~dh ~dm" (floor total-seconds 3600) (mod (floor total-seconds 60) 60))))))

(defun %prompt-duration-segment (pm)
  (let ((duration-ms (prompt-model-duration-ms pm)))
    (when (and duration-ms (>= duration-ms 1000))
      (make-prompt-segment (%prompt-duration-text duration-ms) :duration))))

(defun render-prompt-model (pm)
  "Convert a prompt model into left prompt segments: an optional remote-session
host segment, the path, an optional git segment, and the exit-status prompt
character."
  (let ((segs (prompt-model-segments pm)))
    (if segs
        segs
        (let ((result nil)
              (host (%host-segment pm))
              (git (%git-status-segment pm)))
          (when host (push host result))
          (push (make-prompt-segment (prompt-model-cwd pm) :path) result)
          (when git
            (push (make-prompt-segment " " :literal) result)
            (push git result))
          (push (make-prompt-segment " " :literal) result)
          (push (%prompt-exit-segment pm) result)
          (push (make-prompt-segment " " :literal) result)
          (nreverse result)))))

(defun render-right-prompt-model (pm &key failure-explain-p)
  "Convert prompt model right segments to prompt segments: a non-zero exit
code, the last command duration, and the time."
  (let ((segs (prompt-model-right-segments pm)))
    (if segs
        segs
        (let ((result nil)
              (ec (prompt-model-exit-code pm))
              (duration (%prompt-duration-segment pm)))
          (when (and ec (not (zerop ec)))
            (push (make-prompt-segment
                   (if failure-explain-p
                       (format nil "[~d · ?]" ec)
                       (format nil "[~d]" ec))
                   :exit-error)
                  result))
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
