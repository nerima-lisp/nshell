(in-package #:nshell.presentation)


(defun %kind-icon (kind)
  (case kind
    (:command "λ")
    (:file "∙")
    (:directory "/")
    (:option "-")
    (:variable "$ ")
    (otherwise "·")))

(defun %terminal-width ()
  (handler-case
      (multiple-value-bind (rows columns) (nshell.infrastructure.acl:get-terminal-size)
        (declare (ignore rows))
        (or columns 80))
    (error () 80)))

(defun %format-candidate (candidate)
  (let* ((text (%candidate-text candidate))
         (kind (%candidate-kind candidate))
         (description (%candidate-description candidate)))
    (if (and description (> (length description) 0))
        (format nil "~a ~a  ~a" (%kind-icon kind) text description)
        (format nil "~a ~a" (%kind-icon kind) text))))

(defun %pad-to-visible-width (text width)
  "Right-pad TEXT with spaces to occupy WIDTH terminal columns, leaving it
unchanged when it is already at least that wide.  Delegates to cl-tty-kit's
display-width-aware padding so wide glyphs are accounted for correctly."
  (cl-tty-kit:pad-string text width :align :left :pad #\Space))

(defun %compute-columns (candidates &key (terminal-width (%terminal-width)) (padding 2))
  (let* ((formatted (mapcar #'%format-candidate candidates))
         (max-width (if formatted
                        (apply #'max (mapcar #'%string-visible-width formatted))
                        1))
         (column-width (+ max-width padding))
         (columns (max 1 (floor terminal-width column-width))))
    (values columns column-width formatted)))

(defun %completion-render-line-count (columns formatted)
  (if formatted
      (+ (ceiling (min 64 (length formatted)) columns)
         (if (< 64 (length formatted)) 1 0))
      0))

(defun completion-render-line-count (candidates &key (terminal-width (%terminal-width)))
  (multiple-value-bind (columns column-width formatted)
      (%compute-columns candidates :terminal-width terminal-width)
    (declare (ignore column-width))
    (%completion-render-line-count columns formatted)))

(defun render-completions (candidates &key selected-index (terminal-width (%terminal-width)))
  (if candidates
      (multiple-value-bind (columns column-width formatted)
          (%compute-columns candidates :terminal-width terminal-width)
        (let* ((limit (min 64 (length formatted)))
               (visible (subseq formatted 0 limit)))
          (format t "~%")
          (loop for item in visible
                for index from 0
                do (let ((cell (%pad-to-visible-width item column-width)))
                     (if (and (integerp selected-index)
                              (= index selected-index))
                         (format t "~C[7m~a~C[0m" #\Esc cell #\Esc)
                         (format t "~a" cell)))
                   (when (or (= (mod (1+ index) columns) 0)
                             (= index (1- limit)))
                     (format t "~%")))
          (when (< limit (length formatted))
            (format t "… and ~d more~%" (- (length formatted) limit)))
          (%completion-render-line-count columns formatted)))
      0))
