; Here-document line and body consumption.
(in-package #:nshell.domain.parsing)

(defun %line-end-position (input start)
  (or (position #\Newline input :start start)
      (length input)))

(defun %line-start-after (input line-end)
  (if (< line-end (length input))
      (1+ line-end)
      line-end))

(defun %read-here-doc-line (input start)
  (let* ((end (%line-end-position input start))
         (has-newline (< end (length input))))
    (%make-here-doc-line (subseq input start end)
                         (if has-newline (1+ end) end)
                         has-newline)))

(defun %consume-here-doc-body (input start delimiter &optional strip-tabs-p)
  (let* ((delimiter-text (if (consp delimiter) (car delimiter) delimiter))
         (strip-leading-tabs-p
           (or strip-tabs-p
               (and (consp delimiter) (cdr delimiter)))))
    (with-output-to-string (body)
      (loop with pos = start
            while (< pos (length input))
            do (let* ((line (%read-here-doc-line input pos))
                      (line-text (%here-doc-line-text line))
                      (normalized-line-text
                        (if strip-leading-tabs-p
                            (string-left-trim '(#\Tab) line-text)
                            line-text)))
                 (when (string= normalized-line-text delimiter-text)
                   (return-from %consume-here-doc-body
                     (%make-here-doc-body
                      (get-output-stream-string body)
                      (%here-doc-line-next-position line)
                      nil)))
                 (write-string normalized-line-text body)
                 (when (%here-doc-line-newline-p line)
                   (write-char #\Newline body))
                 (setf pos (%here-doc-line-next-position line)))
            finally (return-from %consume-here-doc-body
                      (%make-here-doc-body
                       (get-output-stream-string body)
                       pos
                       t))))))

(defun %empty-here-doc-consumption-state (start)
  (%make-here-doc-consumption-state '() start nil))

(defun %here-doc-consumption-state-add-body (state body)
  (%make-here-doc-consumption-state
   (cons (%here-doc-body-body body)
         (%here-doc-consumption-state-reversed-bodies state))
   (%here-doc-body-next-position body)
   (%here-doc-body-missing-delimiter-p body)))

(defun %here-doc-consumption-state-consume-delimiter (input state delimiter)
  (%here-doc-consumption-state-add-body
   state
   (%consume-here-doc-body
    input
    (%here-doc-consumption-state-next-position state)
    delimiter)))

(defun %here-doc-consumption-from-state (state)
  (%make-here-doc-consumption
   (nreverse (%here-doc-consumption-state-reversed-bodies state))
   (%here-doc-consumption-state-next-position state)
   (%here-doc-consumption-state-incomplete-p state)))

(defun %consume-here-docs-result (input start delimiters)
  (labels ((consume (state remaining-delimiters)
             (if (or (endp remaining-delimiters)
                     (%here-doc-consumption-state-incomplete-p state))
                 (%here-doc-consumption-from-state state)
                 (consume
                  (%here-doc-consumption-state-consume-delimiter
                   input
                   state
                   (first remaining-delimiters))
                  (rest remaining-delimiters)))))
    (consume (%empty-here-doc-consumption-state start) delimiters)))
