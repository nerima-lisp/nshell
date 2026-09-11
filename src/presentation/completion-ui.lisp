(in-package #:nshell.presentation)


(defun %kind-icon (kind)
  (case kind
    (:command "λ")
    (:file "∙")
    (:directory "/")
    (:option "-")
    (:variable "$ ")
    (otherwise "·")))

(defun %completion-kind-role (kind)
  (case kind
    (:command :completion-command)
    (:directory :completion-directory)
    (:file :completion-file)
    (:option :completion-option)
    (:variable :completion-variable)
    (otherwise :normal)))

(defun %candidate-display-text (candidate)
  "Return the text CANDIDATE renders with, appending a trailing slash to a
directory candidate that does not already end in one."
  (let ((text (%candidate-text candidate)))
    (if (eq (%candidate-kind candidate) :directory)
        (if (and (plusp (length text))
                 (char= (char text (1- (length text))) #\/))
            text
            (concatenate 'string text "/"))
        text)))

(defun %write-styled (text role theme &optional (stream *standard-output*))
  "Write TEXT to STREAM wrapped in THEME's ROLE prefix, resetting afterward.
Writes only TEXT when the role has no styling for THEME."
  (let ((prefix (theme-color->ansi theme role)))
    (if (string= prefix "")
        (write-string text stream)
        (progn
          (write-string prefix stream)
          (write-string text stream)
          (nshell.infrastructure.terminal:ansi-reset-style stream)))))

(defun %format-candidate (candidate)
  (let* ((text (%candidate-display-text candidate))
         (kind (%candidate-kind candidate))
         (description (%candidate-description candidate)))
    (if (and description (> (length description) 0))
        (format nil "~a ~a  ~a" (%kind-icon kind) text description)
        (format nil "~a ~a" (%kind-icon kind) text))))

(defun %format-candidate-styled (candidate theme)
  "Return CANDIDATE's cell with its text and description styled by kind,
matching the plain layout %FORMAT-CANDIDATE produces for width purposes."
  (let* ((text (%candidate-display-text candidate))
         (kind (%candidate-kind candidate))
         (description (%candidate-description candidate)))
    (with-output-to-string (out)
      (write-string (%kind-icon kind) out)
      (write-char #\Space out)
      (%write-styled text (%completion-kind-role kind) theme out)
      (when (and description (> (length description) 0))
        (write-string "  " out)
        (%write-styled description :completion-description theme out)))))

(defun %pad-to-visible-width (text width)
  "Right-pad TEXT with spaces to occupy WIDTH terminal columns, leaving it
unchanged when it is already at least that wide.  Delegates to cl-tty-kit's
display-width-aware padding so wide glyphs are accounted for correctly."
  (cl-tty-kit:pad-string text width :align :left :pad #\Space))

(defun %pad-styled-cell (styled-text plain-text width)
  "Right-pad STYLED-TEXT to WIDTH columns, measuring visible width from
PLAIN-TEXT since STYLED-TEXT carries SGR bytes that are not visible columns."
  (let ((visible (%string-visible-width plain-text)))
    (if (>= visible width)
        styled-text
        (concatenate 'string styled-text
                     (make-string (- width visible) :initial-element #\Space)))))

(defun %compute-columns (candidates &key (terminal-width (terminal-width)) (padding 2))
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

(defun completion-render-line-count (candidates &key (terminal-width (terminal-width)))
  (multiple-value-bind (columns column-width formatted)
      (%compute-columns candidates :terminal-width terminal-width)
    (declare (ignore column-width))
    (%completion-render-line-count columns formatted)))

(defun render-completions (candidates &key selected-index (terminal-width (terminal-width))
                                       (theme (nshell.domain.configuration:default-theme)))
  (if candidates
      (multiple-value-bind (columns column-width formatted)
          (%compute-columns candidates :terminal-width terminal-width)
        (let* ((limit (min 64 (length formatted)))
               (visible (subseq formatted 0 limit))
               (visible-candidates (subseq candidates 0 limit)))
          (format t "~%")
          (loop for item in visible
                for candidate in visible-candidates
                for index from 0
                do (if (and (integerp selected-index)
                            (= index selected-index))
                       (%write-styled (%pad-to-visible-width item column-width)
                                      :completion-selected theme)
                       (format t "~a"
                               (%pad-styled-cell
                                (%format-candidate-styled candidate theme)
                                item column-width)))
                   (when (or (= (mod (1+ index) columns) 0)
                             (= index (1- limit)))
                     (format t "~%")))
          (when (< limit (length formatted))
            (%write-styled (format nil "… and ~d more" (- (length formatted) limit))
                           :completion-more theme)
            (format t "~%"))
          (%completion-render-line-count columns formatted)))
      0))
