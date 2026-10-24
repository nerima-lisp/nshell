(in-package #:nshell.presentation)

(defun expand-history-input (raw-source)
  (declare (special *history*))
  (check-type raw-source string)
  (let* ((scan-result
           (nshell.domain.parsing:scan-input
            raw-source
            :reader-context :auto
            :head-classifier
            (lambda (head)
              (declare (ignore head))
              :host-form)))
         (tokens (nshell.domain.parsing:scan-result-tokens scan-result))
         (source-position 0)
         (origins nil)
         (history *history*))
    (labels ((append-source-range (output start end)
               (loop for position from start below end
                     do (write-char (char raw-source position) output)
                        (push (list position (1+ position)) origins)))
             (expandable-token-p (token)
               (and (eq (nshell.domain.parsing:scan-token-reader-context token)
                        :bare-line)
                    (member (nshell.domain.parsing:scan-token-kind token)
                            '(:command-head :argument :string :here-doc-delimiter)
                            :test #'eq))))
      (if (null history)
          (values raw-source
                  (coerce
                   (loop for position below (length raw-source)
                         collect (list position (1+ position)))
                   'vector))
          (block expansion
            (values
             (with-output-to-string (output)
               (dolist (token tokens)
                 (when (expandable-token-p token)
                   (let* ((span (nshell.domain.parsing:scan-token-span token))
                          (start (first span))
                          (end (second span))
                          (token-source (subseq raw-source start end)))
                     (append-source-range output source-position start)
                     (multiple-value-bind (expanded error token-map)
                         (nshell.domain.history:history-expand-line history
                                                                     token-source)
                       (when error
                         (return-from expansion (values nil error)))
                       (write-string expanded output)
                       (loop for token-origin across token-map
                             do (push
                                 (list (+ start (first token-origin))
                                       (+ start (second token-origin)))
                                 origins)))
                     (setf source-position end))))
               (append-source-range output source-position (length raw-source)))
             (coerce (nreverse origins) 'vector)))))))

(defun source-span-to-origin-span (source-map expanded-span)
  (check-type source-map vector)
  (let ((start (first expanded-span))
        (end (second expanded-span))
        (length (length source-map)))
    (unless (and (integerp start) (integerp end)
                 (<= 0 start end length))
      (error "EXPANDED-SPAN must be a valid half-open span in SOURCE-MAP."))
    (if (= start end)
        (let ((anchor
                (cond
                  ((< start length) (first (aref source-map start)))
                  ((plusp length) (second (aref source-map (1- length))))
                  (t 0))))
          (list anchor anchor))
        (let ((spans (loop for position from start below end
                           collect (aref source-map position))))
          (list (reduce #'min spans :key #'first)
                (reduce #'max spans :key #'second))))))
