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
unchanged when it is already at least that wide."
  (let ((padding (- width (%string-visible-width text))))
    (if (plusp padding)
        (concatenate 'string text (make-string padding :initial-element #\Space))
        text)))

(defun %pad-styled-cell (styled-text plain-text width)
  "Right-pad STYLED-TEXT to WIDTH columns, measuring visible width from
PLAIN-TEXT since STYLED-TEXT carries SGR bytes that are not visible columns."
  (let ((visible (%string-visible-width plain-text)))
    (if (>= visible width)
        styled-text
        (concatenate 'string styled-text
                     (make-string (- width visible) :initial-element #\Space)))))

(defun %compute-columns (candidates &key (terminal-width (terminal-width)) (padding 2))
  (labels ((candidate-visible-width (candidate)
             (let* ((kind (%candidate-kind candidate))
                    (text (%candidate-display-text candidate))
                    (description (%candidate-description candidate)))
               (+ (loop for char across (%kind-icon kind)
                        sum (%char-visible-width char))
                  1
                  (%string-visible-width text)
                  (if (and description (plusp (length description)))
                      (+ 2 (%string-visible-width description))
                      0)))))
    (let* ((padding (min padding (max 0 (1- terminal-width))))
           (max-cell-width (max 1 (- terminal-width padding)))
           (max-width
             (if candidates
                 (min max-cell-width
                      (loop with max-width = 1
                            for candidate in candidates
                            for width = (candidate-visible-width candidate)
                            do (setf max-width (max max-width width))
                               (when (>= max-width max-cell-width)
                                 (return max-cell-width))
                            finally (return max-width)))
                 1))
           (column-width (+ max-width padding))
           (columns (max 1 (floor terminal-width column-width))))
      (values columns column-width))))

(defun %completion-footer-visible-p (candidate-count footer-p max-rows)
  (and footer-p
       (or (null max-rows)
           (and (plusp max-rows)
                (or (> max-rows 1)
                    (zerop candidate-count))))))
(defun %completion-preview-visible-lines (preview-lines candidate-count footer-p max-rows)
  (if (or (null preview-lines)
          (zerop candidate-count))
      nil
      (let* ((preview-limit
               (if max-rows
                   (max 0
                        (- max-rows
                           (if (plusp candidate-count) 1 0)
                           (if (%completion-footer-visible-p
                                candidate-count footer-p max-rows)
                               1
                               0)))
                   (length preview-lines))))
        (subseq preview-lines
                0
                (min (length preview-lines) preview-limit)))))
(defun %completion-render-line-count (columns candidates &key max-rows footer-p preview-lines)
  (let* ((candidate-count (length candidates))
         (visible-preview-lines
           (%completion-preview-visible-lines
            preview-lines candidate-count footer-p max-rows))
         (candidate-max-rows
           (and max-rows
                (max 0 (- max-rows (length visible-preview-lines)))))
         (total-rows
           (if (plusp candidate-count)
               (ceiling candidate-count columns)
               0))
         (footer-lines
           (if (%completion-footer-visible-p
                candidate-count footer-p candidate-max-rows)
               1
               0))
         (content-limit
           (if candidate-max-rows
               (max 0 (- candidate-max-rows footer-lines))
               total-rows)))
    (+ (min total-rows content-limit)
       footer-lines
       (length visible-preview-lines))))

(defun completion-render-line-count (candidates
                                      &key
                                        (terminal-width (terminal-width))
                                        max-rows
                                        footer-p
                                        preview-lines)
  (multiple-value-bind (columns)
      (%compute-columns candidates :terminal-width terminal-width)
    (%completion-render-line-count columns
                                   candidates
                                   :max-rows max-rows
                                   :footer-p footer-p
                                   :preview-lines preview-lines)))

(defun render-completions (candidates
                           &key
                           selected-index
                           (terminal-width (terminal-width))
                           (theme (nshell.domain.configuration:default-theme))
                           max-rows
                           footer
                           empty-message
                           preview-lines)
  (multiple-value-bind (columns column-width)
      (%compute-columns candidates :terminal-width terminal-width)
    (let* ((candidate-count (length candidates))
           (visible-preview-lines
             (%completion-preview-visible-lines
              preview-lines candidate-count footer max-rows))
           (candidate-max-rows
             (and max-rows
                  (max 0 (- max-rows (length visible-preview-lines)))))
           (footer-visible-p
             (%completion-footer-visible-p
              candidate-count footer candidate-max-rows))
           (total-rows (if (plusp candidate-count)
                           (ceiling candidate-count columns)
                           0))
           (content-budget (if candidate-max-rows
                               (max 0 (- candidate-max-rows
                                         (if footer-visible-p 1 0)))
                             (max total-rows (if empty-message 1 0))))
           (visible-rows (min total-rows content-budget))
           (selected-index (and (integerp selected-index)
                                (<= 0 selected-index)
                                (< selected-index candidate-count)
                                selected-index))
           (selected-row (if selected-index
                             (floor selected-index columns)
                             0))
           (start-row (if (plusp visible-rows)
                          (max 0
                               (min (- total-rows visible-rows)
                                    (- selected-row
                                       (floor (1- visible-rows) 2))))
                          0))
           (empty-row-p (and (zerop candidate-count)
                             empty-message
                             (plusp content-budget)))
           (rendered-lines (+ visible-rows
                              (if empty-row-p 1 0)
                              (length visible-preview-lines)
                              (if footer-visible-p 1 0)))
           (content-width (max 1
                               (- column-width
                                  (min 2 (max 0 (1- terminal-width)))))))
      (when (plusp rendered-lines)
        (format t "~%")
        (when (plusp candidate-count)
          (loop for row from start-row below (+ start-row visible-rows)
                do (progn
                     (loop for index from (* row columns)
                           below (min candidate-count (* (1+ row) columns))
                           for candidate = (nth index candidates)
                           for item = (%format-candidate candidate)
                           for visible-item = (%truncate-string-to-width
                                               item content-width)
                           do (if (eql index selected-index)
                                  (%write-styled
                                   (%pad-to-visible-width visible-item column-width)
                                   :completion-selected
                                   theme)
                                  (if (string= visible-item item)
                                      (format t "~a"
                                              (%pad-styled-cell
                                               (%format-candidate-styled candidate theme)
                                               item
                                               column-width))
                                      (format t "~a"
                                              (%pad-to-visible-width
                                               visible-item column-width)))))
                     (format t "~%"))))
        (when empty-row-p
          (format t "~a~%"
                  (%truncate-string-to-width empty-message terminal-width)))
        (dolist (line visible-preview-lines)
          (format t "~a~%"
                  (%truncate-string-to-width line terminal-width)))
        (when footer-visible-p
          (format t "~a~%"
                  (%truncate-string-to-width footer terminal-width)))
        rendered-lines))))
