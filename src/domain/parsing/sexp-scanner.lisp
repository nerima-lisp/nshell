(in-package #:nshell.domain.parsing)

(defstruct scan-token kind text span reader-context)
  (defstruct delimiter-frame opener expected-close opener-span)
  (defstruct delimiter-pair open-span close-span)
  (defstruct scan-result status tokens open-delimiters delimiter-pairs
    invalid-span incomplete-span next-indent cursor-role)
  (defstruct (%depth-scan-frame
            (:constructor %make-depth-scan-frame
                (opener-span close-position parent-context context kind resolved-p
                 open-token head-seen-p direct-count last-kind pending-redirect
                 here-docs pending-prefixes forced-host-p events)))
  opener-span close-position parent-context context kind resolved-p open-token
  head-seen-p direct-count last-kind pending-redirect here-docs
  pending-prefixes forced-host-p events)
  (defstruct (%depth-scan-heredoc
            (:constructor %make-depth-scan-heredoc
                (delimiter strip-tabs-p reader-context)))
  delimiter strip-tabs-p reader-context)
  (defstruct (%depth-scan-state
            (:constructor %make-depth-scan-state
                (source length cursor mode classifier position tokens-reversed
                 pairs-reversed frames active-frames invalids incomplete-span
                 roles head-cursor-role forced-list-host-p bare-command-seen-p
                 bare-expect-command-p bare-pending-operator bare-pending-redirect
                 bare-heredocs bare-last-kind)))
  source length cursor mode classifier position tokens-reversed pairs-reversed
  frames active-frames invalids incomplete-span roles head-cursor-role
  forced-list-host-p bare-command-seen-p bare-expect-command-p
  bare-pending-operator bare-pending-redirect bare-heredocs bare-last-kind)
  (defvar *depth-scan-state* nil)

  (defun %depth-scan-whitespace-p (character)
    (find character '(#\Space #\Tab #\Newline #\Return)))

  (defun %depth-scan-line-end (source start)
    (or (position #\Newline source :start start) (length source)))

  (defun %depth-scan-column (source position)
    (let ((line-start (or (position #\Newline source :end position) -1)))
      (- position (1+ line-start))))

  (defun %depth-scan-atom-delimiter-p (character context)
  (or (%depth-scan-whitespace-p character)
      (find character '(#\( #\)))
      (and (eq context :host-form)
           (find character '(#\; #\" #\' #\` #\, #\# #\|)))
      (and (eq context :command-island)
           (char= character #\"))))

  (defun %depth-scan-reader-boundary-p (source position)
    (or (>= position (length source))
        (%depth-scan-whitespace-p (char source position))
        (find (char source position) '(#\( #\) #\;))))

  (defun %depth-scan-redirect-spelling-p (text)
    (or (member text
                '("<" "0<" ">" "1>" ">>" "1>>" ">|" "2>" "2>>"
                  "&>" "&>>" "<&" ">&" "<<" "<<-" "<<<")
                :test #'string=)
        (loop for operator in '("<&" ">&")
              for offset = (search operator text :from-end t)
              thereis (and offset
                           (> offset 0)
                           (= (+ offset (length operator)) (length text))
                           (every #'digit-char-p (subseq text 0 offset)))))
)

  (defun %depth-scan-heredoc-operator-p (text)
    (member text '("<<" "<<-") :test #'string=))

  (defun %depth-scan-bare-redirect-at (source position)
    (let* ((length (length source))
           (fd-end position)
           (operators (quote ("&>>" "<<<" "<<-" "2>&1" "1>>" "2>>" "&>"
                              "&&" "||" "|&" ">>" ">|" "<<" "<&" ">&"
                              "0<" "1>" "2>" "<" ">" "|" ";" "&"))))
      (loop while (and (< fd-end length)
                       (digit-char-p (char source fd-end)))
            do (incf fd-end))
      (when (> fd-end position)
        (loop for operator in (quote ("<&" ">&"))
              when (and (<= (+ fd-end (length operator)) length)
                        (string= operator source
                                 :start2 fd-end
                                 :end2 (+ fd-end (length operator))))
                do (return-from %depth-scan-bare-redirect-at
                     (subseq source position (+ fd-end (length operator)))))
        (when (and (< fd-end length)
                   (member (char source fd-end) (quote (#\< #\>))))
          (let ((end (1+ fd-end)))
            (when (and (char= (char source fd-end) #\>)
                       (< end length)
                       (char= (char source end) #\>))
              (incf end))
            (return-from %depth-scan-bare-redirect-at
              (subseq source position end)))))
      (loop for operator in operators
            when (and (<= (+ position (length operator)) length)
                      (string= operator source
                               :start2 position
                               :end2 (+ position (length operator))))
              do (return-from %depth-scan-bare-redirect-at operator))
      nil))

  (defun %depth-scan-bare-delimiter-value (source start end)
    (with-output-to-string (result)
      (let ((quote nil)
            (position start))
        (loop while (< position end)
              for character = (char source position)
              do (cond
                   ((and quote (char= character quote))
                    (setf quote nil))
                   ((and (null quote) (find character '(#\' #\")))
                    (setf quote character))
                   ((char= character #\\)
                    (cond
                      ((null quote)
                       (when (< (1+ position) end)
                         (incf position)
                         (write-char (char source position) result)))
                      ((char= quote #\")
                       (if (and (< (1+ position) end)
                                (find (char source (1+ position))
                                      '(#\\ #\" #\$ #\` #\Newline)))
                           (progn
                             (incf position)
                             (write-char (char source position) result))
                           (write-char character result)))
                      (t
                       (write-char character result))))
                   (t
                    (write-char character result)))
                 (incf position)))))

  (defun %depth-scan-string-delimiter-value (source start end)
    (if (and (< start end)
             (char= (char source start) #\"))
        (let* ((closing-p
                 (and (char= (char source (1- end)) #\")
                      (evenp
                       (let ((position (1- end)))
                         (loop while (and (> position start)
                                          (char= (char source (1- position)) #\\))
                               do (decf position))
                         (- (1- end) position)))))
               (content-end (if closing-p (1- end) end))
               (position (1+ start)))
          (with-output-to-string (result)
            (loop while (< position content-end)
                  for character = (char source position)
                  do (if (and (char= character #\\)
                              (< (1+ position) content-end))
                         (progn
                           (incf position)
                           (write-char (char source position) result))
                         (write-char character result))
                     (incf position))))
        (subseq source start end)))

  (defun %depth-scan-text-at (state start end)
    (subseq (%depth-scan-state-source state) start end))

  (defun %depth-scan-emit (kind start end context &optional role)
  (let* ((state *depth-scan-state*)
         (token (make-scan-token
                 :kind kind
                 :text (%depth-scan-text-at state start end)
                 :span (list start end)
                 :reader-context context)))
    (push token (%depth-scan-state-tokens-reversed state))
    (when role
      (setf (gethash token (%depth-scan-state-roles state)) role))
    token))

  (defun %depth-scan-role (token role)
    (setf (gethash token (%depth-scan-state-roles *depth-scan-state*)) role)
    token)

  (defun %depth-scan-invalid (start end)
    (push (list start end) (%depth-scan-state-invalids *depth-scan-state*)))

  (defun %depth-scan-incomplete ()
    (setf (%depth-scan-state-incomplete-span *depth-scan-state*)
          (list (%depth-scan-state-length *depth-scan-state*)
                (%depth-scan-state-length *depth-scan-state*))))

  (defun %depth-scan-frame-role (frame &optional closing-p)
  (cond
    ((eq (%depth-scan-frame-kind frame) :pipeline) :command-head)
    ((and (not closing-p)
          (or (not (%depth-scan-frame-resolved-p frame))
              (not (%depth-scan-frame-head-seen-p frame))))
     :command-head)
    ((eq (%depth-scan-frame-context frame) :host-form) :host-form)
    ((not (%depth-scan-frame-resolved-p frame)) :command-head)
    ((not (%depth-scan-frame-head-seen-p frame)) :command-head)
    (t :argument)))

  (defun %depth-scan-parent-role (frame)
  (cond
    ((null frame) :host-form)
    ((eq (%depth-scan-frame-kind frame) :pipeline) :command-head)
    ((eq (%depth-scan-frame-context frame) :host-form) :host-form)
    ((not (%depth-scan-frame-head-seen-p frame)) :command-head)
    (t :argument)))

  (defun %depth-scan-record-direct (frame kind token start end)
    (when frame
      (let ((redirect (%depth-scan-frame-pending-redirect frame)))
        (when redirect
          (let ((redirect-text (scan-token-text redirect)))
            (when (or (null token) (eq kind :redirect))
              (%depth-scan-invalid start end))
            (when (and token (%depth-scan-heredoc-operator-p redirect-text))
              (let ((delimiter
                      (if (eq kind :string)
                          (%depth-scan-string-delimiter-value
                           (%depth-scan-state-source *depth-scan-state*) start end)
                          (%depth-scan-text-at *depth-scan-state* start end))))
                (setf (scan-token-kind token) :here-doc-delimiter)
                (%depth-scan-role token :redirect-target)
                (push (%make-depth-scan-heredoc
                       delimiter (string= redirect-text "<<-")
                       (scan-token-reader-context redirect))
                      (%depth-scan-frame-here-docs frame))))
            (setf (%depth-scan-frame-pending-redirect frame) nil))))
      (when (and (eq kind :redirect)
                 (null (%depth-scan-frame-pending-redirect frame)))
        (setf (%depth-scan-frame-pending-redirect frame) token))
      (setf (%depth-scan-frame-last-kind frame) kind
            (%depth-scan-frame-head-seen-p frame) t)
      (incf (%depth-scan-frame-direct-count frame))
      (when (%depth-scan-frame-pending-prefixes frame)
        (setf (%depth-scan-frame-pending-prefixes frame) nil))
      (push (list start end kind token) (%depth-scan-frame-events frame))))

  (defun %depth-scan-update-nested-end (frame end)
    (when (and frame (%depth-scan-frame-events frame))
      (setf (second (first (%depth-scan-frame-events frame))) end)))

  (defun %depth-scan-comment (start context)
    (let* ((state *depth-scan-state*)
           (source (%depth-scan-state-source state))
           (end (%depth-scan-line-end source start)))
      (%depth-scan-emit :line-comment start end context :comment)
      (setf (%depth-scan-state-position state) end)))

  (defun %depth-scan-block-comment (start context)
    (let* ((state *depth-scan-state*)
           (source (%depth-scan-state-source state))
           (length (%depth-scan-state-length state))
           (depth 1)
           (end (+ start 2)))
      (loop while (< end length)
            do (cond
                 ((and (<= (+ end 2) length)
                       (string= "#|" source :start2 end :end2 (+ end 2)))
                  (incf depth)
                  (incf end 2))
                 ((and (<= (+ end 2) length)
                       (string= "|#" source :start2 end :end2 (+ end 2)))
                  (decf depth)
                  (incf end 2)
                  (when (zerop depth) (return)))
                 (t (incf end))))
      (%depth-scan-emit :block-comment start end context :comment)
      (setf (%depth-scan-state-position state) end)
      (when (> depth 0) (%depth-scan-incomplete))))

  (defun %depth-scan-string (start context)
  (let* ((state *depth-scan-state*)
         (source (%depth-scan-state-source state))
         (length (%depth-scan-state-length state))
         (end (1+ start))
         (closed-p nil))
    (loop while (< end length)
          for character = (char source end)
          do (cond
               ((char= character #\\)
                (if (< (1+ end) length)
                    (incf end 2)
                    (setf end length)))
               ((char= character #\")
                (incf end)
                (setf closed-p t)
                (return))
               (t (incf end))))
    (let ((token (%depth-scan-emit
                  :string start end context
                  (if (eq context :host-form) :host-form :argument))))
      (setf (%depth-scan-state-position state) end)
      (unless closed-p (%depth-scan-incomplete))
      token)))

  (defun %depth-scan-escaped-symbol (start context)
  (let* ((state *depth-scan-state*)
         (source (%depth-scan-state-source state))
         (length (%depth-scan-state-length state))
         (end (1+ start))
         (closed-p nil))
    (loop while (< end length)
          for character = (char source end)
          do (cond
               ((char= character #\\)
                (if (< (1+ end) length)
                    (incf end 2)
                    (setf end length)))
               ((char= character #\|)
                (incf end)
                (setf closed-p t)
                (return))
               (t (incf end))))
    (let ((token (%depth-scan-emit
                  :escaped-symbol start end context :argument)))
      (setf (%depth-scan-state-position state) end)
      (unless closed-p (%depth-scan-incomplete))
      token)))

  (defun %depth-scan-simple-head-end (source start)
    (when (and (< start (length source))
               (not (find (char source start)
                          '(#\( #\) #\" #\' #\` #\, #\# #\;))))
      (if (char= (char source start) #\|)
          (cond
            ((and (< (+ start 2) (length source))
                  (char= (char source (1+ start)) #\&)
                  (%depth-scan-reader-boundary-p source (+ start 2)))
             (+ start 2))
            ((%depth-scan-reader-boundary-p source (1+ start))
             (1+ start))
            (t
             (let ((end (1+ start)))
               (loop while (< end (length source))
                     do (cond
                          ((char= (char source end) #\\)
                           (incf end (if (< (1+ end) (length source)) 2 1)))
                          ((char= (char source end) #\|)
                           (return-from %depth-scan-simple-head-end (1+ end)))
                          (t (incf end))))
               nil)))
          (%depth-scan-atom-end source start :host-form))))

  (defun %depth-scan-atom-end (source start context)
    (let ((end start)
          (length (length source)))
      (loop while (< end length)
            for character = (char source end)
            do (cond
                 ((and (eq context :host-form)
                       (char= character #\\))
                  (incf end (if (< (1+ end) length) 2 1)))
                 ((%depth-scan-atom-delimiter-p character context)
                  (return))
                 (t (incf end))))
      (and (> end start) end)))

  (defun %depth-scan-classify-head (frame start end pipeline-p)
  (let* ((state *depth-scan-state*)
         (source (%depth-scan-state-source state))
         (spelling (subseq source start end))
         (classifier (%depth-scan-state-classifier state))
         (classification (if pipeline-p
                             :command-island
                             (if classifier
                                 (funcall classifier spelling)
                                 :command-island)))
         (cursor (%depth-scan-state-cursor state))
         (cursor-inside (and (<= start cursor)
                             (or (< cursor end)
                                 (and (= cursor end)
                                      (= end (%depth-scan-state-length state))
                                      (not (some #'%depth-scan-whitespace-p
                                                 spelling)))))))
    (unless (member classification '(:host-form :command-island))
      (error "HEAD-CLASSIFIER returned an invalid classification."))
    (setf (%depth-scan-frame-context frame) classification
          (%depth-scan-frame-kind frame) (if pipeline-p :pipeline :normal)
          (%depth-scan-frame-resolved-p frame) t)
    (when (and cursor-inside
               (< start cursor)
               (not pipeline-p)
               classifier)
      (let ((partial
              (funcall classifier
                       (subseq source start (max start (min cursor end))))))
        (unless (member partial '(:host-form :command-island))
          (error "HEAD-CLASSIFIER returned an invalid classification."))
        (setf (%depth-scan-state-head-cursor-role state)
              (if (eq partial :host-form) :host-form :command-head))))))

  (defun %depth-scan-heredoc-body (heredocs start)
    (let* ((state *depth-scan-state*)
           (source (%depth-scan-state-source state))
           (length (%depth-scan-state-length state))
           (position start)
           (body-start start)
           (incomplete nil))
      (dolist (heredoc (reverse heredocs))
        (let ((found nil))
          (loop while (<= position length)
                for line-end = (%depth-scan-line-end source position)
                for content-end = (if (and (> line-end position)
                                           (char= (char source (1- line-end)) #\Return))
                                      (1- line-end)
                                      line-end)
                for line-text = (subseq source position content-end)
                for compare-text = (if (%depth-scan-heredoc-strip-tabs-p heredoc)
                                       (string-left-trim '(#\Tab) line-text)
                                       line-text)
                do (if (string= compare-text
                               (%depth-scan-heredoc-delimiter heredoc))
                       (progn
                         (when (< body-start position)
                           (%depth-scan-emit :here-doc-body body-start position
                                             :here-doc-body :none))
                         (%depth-scan-emit :here-doc-delimiter position content-end
                                           (%depth-scan-heredoc-reader-context heredoc)
                                           :redirect-target)
                         (setf position (if (< line-end length)
                                             (1+ line-end)
                                             line-end)
                               body-start position
                               found t)
                         (return))
                       (if (< line-end length)
                           (setf position (1+ line-end))
                           (progn
                             (setf position length)
                             (return)))))
          (unless found
            (when (< body-start length)
              (%depth-scan-emit :here-doc-body body-start length
                                :here-doc-body :none))
            (setf position length incomplete t)
            (%depth-scan-incomplete)
            (return))))
      (setf (%depth-scan-state-position state) position)
      incomplete))

  (defun %depth-scan-reader-dispatch (frame context)
    (let* ((state *depth-scan-state*)
           (source (%depth-scan-state-source state))
           (length (%depth-scan-state-length state))
           (start (%depth-scan-state-position state))
           (next (and (< (1+ start) length) (char source (1+ start))))
           (end (min length (+ start 2)))
           (valid-p nil)
           (force-host-p nil))
      (cond
        ((and next (char= next #\|))
         (%depth-scan-block-comment start context)
         (return-from %depth-scan-reader-dispatch :comment))
        ((and next (char= next #\\))
         (let ((char-end (+ start 2)))
           (if (= char-end length)
               (progn
                 (let ((token (%depth-scan-emit :character-literal start char-end context :host-form)))
  (%depth-scan-record-top-datum frame :character-literal token start char-end))
                 (setf (%depth-scan-state-position state) char-end)
                 (%depth-scan-incomplete))
               (progn
                 (if (%depth-scan-atom-delimiter-p (char source char-end) :host-form)
                     (incf char-end)
                     (loop while (and (< char-end length)
                                      (not (%depth-scan-atom-delimiter-p
                                            (char source char-end) :host-form)))
                           do (incf char-end)))
                 (let ((token (%depth-scan-emit :character-literal start char-end context :host-form)))
  (%depth-scan-record-top-datum frame :character-literal token start char-end))
                 (setf (%depth-scan-state-position state) char-end)))
           (return-from %depth-scan-reader-dispatch :datum)))
        ((and next (char= next #\.))
         (%depth-scan-invalid start end)
         (%depth-scan-emit :invalid start end context :host-form)
         (setf (%depth-scan-state-position state) end)
         (return-from %depth-scan-reader-dispatch :invalid))
        ((and next (char= next #\())
         (setf valid-p t force-host-p t end (1+ start)
               (%depth-scan-state-forced-list-host-p state) t))
        ((and next (or (char= next #\') (find next '(#\+ #\- #\:))))
         (setf valid-p t)
         (push start (%depth-scan-frame-pending-prefixes frame))
         (when (char= next #\')
           (setf (%depth-scan-frame-forced-host-p frame) t)))
        ((and next (find (char-upcase next)
                         '(#\A #\B #\C #\O #\P #\R #\S #\X #\*)))
         (setf valid-p t
               force-host-p (and (< (+ start 2) length)
                                 (char= (char source (+ start 2)) #\()))
         (push start (%depth-scan-frame-pending-prefixes frame)))
        ((and next (digit-char-p next))
         (let ((digits-end (1+ start)))
           (loop while (and (< digits-end length)
                            (digit-char-p (char source digits-end)))
                 do (incf digits-end))
           (if (and (< digits-end length)
                    (find (char-upcase (char source digits-end))
                          '(#\A #\B #\C #\O #\P #\R #\S #\X #\*)))
               (setf end (1+ digits-end)
                     valid-p t
                     force-host-p (and (< end length)
                                       (char= (char source end) #\()))
               (push start (%depth-scan-frame-pending-prefixes frame)))
               (if (and (< digits-end length)
                        (find (char source digits-end) '(#\= #\#)))
                   (setf end (1+ digits-end)))))
        (t nil))
      (unless valid-p
        (%depth-scan-invalid start end)
        (%depth-scan-emit :invalid start end context :host-form)
        (setf (%depth-scan-state-position state) end)
        (return-from %depth-scan-reader-dispatch :invalid))
      (%depth-scan-emit :reader-prefix start end context :host-form)
      (setf (%depth-scan-state-position state) end)
      (when force-host-p
        (setf (%depth-scan-state-forced-list-host-p state) t))
      :prefix))

  (defun %depth-scan-record-top-datum (frame kind token start end)
    (when frame
      (%depth-scan-record-direct frame kind token start end)))

  (defun %depth-scan-datum (context frame &optional force-host-p)
  (let* ((state *depth-scan-state*)
         (source (%depth-scan-state-source state))
         (length (%depth-scan-state-length state))
         (start (%depth-scan-state-position state))
         (character (char source start))
         (effective-context (if force-host-p :host-form context)))
    (cond
      ((char= character #\()
       (%depth-scan-list effective-context force-host-p))
      ((char= character #\))
       nil)
      ((char= character #\")
       (let ((token (%depth-scan-string start effective-context)))
         (%depth-scan-record-top-datum
          frame :string token start (%depth-scan-state-position state))))
      ((and (eq effective-context :host-form) (char= character #\#))
       (let ((result (%depth-scan-reader-dispatch frame effective-context)))
         (when (eq result :invalid)
           (%depth-scan-record-top-datum
            frame :invalid nil start (%depth-scan-state-position state)))))
      ((and frame
            (eq (%depth-scan-frame-kind frame) :pipeline)
            (not (%depth-scan-frame-head-seen-p frame))
            (char= character #\|)
            (let* ((end (%depth-scan-atom-end source start effective-context))
                   (spelling (and end (subseq source start end))))
              (and (member spelling '("|" "|&") :test #'string=)
                   (%depth-scan-reader-boundary-p source end))))
       (let* ((end (%depth-scan-atom-end source start effective-context))
              (kind (if (char= (char source (1+ start)) #\&)
                        :pipeline-stderr
                        :pipeline))
              (token (%depth-scan-emit kind start end :command-island
                                       :command-head)))
         (setf (%depth-scan-state-position state) end)
         (%depth-scan-record-top-datum frame kind token start end)))
      ((and (eq effective-context :command-island)
            (char= character #\|)
            (let* ((end (%depth-scan-atom-end source start effective-context))
                   (spelling (and end (subseq source start end))))
              (and (string= spelling "|&")
                   (%depth-scan-reader-boundary-p source end))))
       (let* ((end (%depth-scan-atom-end source start effective-context))
              (token (%depth-scan-emit :argument start end :command-island
                                       :argument)))
         (setf (%depth-scan-state-position state) end)
         (%depth-scan-record-top-datum frame :argument token start end)))
      ((and (char= character #\|)
            (or (eq effective-context :host-form)
                (not (and (< (1+ start) length)
                          (%depth-scan-reader-boundary-p source (1+ start))))))
       (let ((token (%depth-scan-escaped-symbol start effective-context)))
         (%depth-scan-record-top-datum
          frame :escaped-symbol token start (%depth-scan-state-position state))))
      ((char= character #\;)
       (%depth-scan-comment start effective-context))
      ((and frame
            (eq (%depth-scan-frame-parent-context frame) :bare-line)
            (char= character #\'))
       (let* ((quote-end (position #\' source :start (1+ start)))
              (closed-p quote-end)
              (token-end (if quote-end (1+ quote-end) length))
              (token (%depth-scan-emit
                      :string start token-end :bare-line :argument)))
         (setf (%depth-scan-state-position state) token-end)
         (unless closed-p (%depth-scan-incomplete))
         (%depth-scan-record-top-datum
          frame :string token start token-end)))
      ((member character '(#\' #\`))
       (%depth-scan-emit :reader-prefix start (1+ start) effective-context
                         :host-form)
       (setf (%depth-scan-state-position state) (1+ start))
       (push start (%depth-scan-frame-pending-prefixes frame))
       (setf (%depth-scan-frame-forced-host-p frame) t))
      ((char= character #\,)
       (let ((end (if (and (< (1+ start) length)
                           (char= (char source (1+ start)) #\@))
                      (+ start 2)
                      (1+ start))))
         (%depth-scan-emit :comma-unquote start end effective-context :host-form)
         (setf (%depth-scan-state-position state) end)
         (push start (%depth-scan-frame-pending-prefixes frame))))
      ((char= character #\$)
       (%depth-scan-emit :dollar-unquote start (1+ start) effective-context
                         :host-form)
       (setf (%depth-scan-state-position state) (1+ start))
       (push start (%depth-scan-frame-pending-prefixes frame)))
      ((and frame
            (eq effective-context :command-island)
            (%depth-scan-frame-head-seen-p frame)
            (find character '(#\< #\>))
            (< (1+ start) length)
            (char= (char source (1+ start)) #\())
       (let ((token (%depth-scan-emit
                     :process-substitution start (1+ start) :command-island
                     (if (%depth-scan-frame-pending-redirect frame)
                         :redirect-target
                         :argument))))
         (setf (%depth-scan-state-position state) (1+ start))
         (%depth-scan-record-top-datum frame :process-substitution
                                       token start (1+ start))))
      (t
       (let* ((end (or (%depth-scan-atom-end source start effective-context)
                       (1+ start)))
              (text (subseq source start end))
              (redirect-p (and frame
                               (%depth-scan-frame-head-seen-p frame)
                               (eq effective-context :command-island)
                               (eq (%depth-scan-frame-context frame)
                                   :command-island)
                               (%depth-scan-redirect-spelling-p text)))
              (kind (cond
                      ((eq effective-context :host-form) :host-form)
                      (redirect-p :redirect)
                      ((and frame
                            (not (%depth-scan-frame-head-seen-p frame))
                            (eq effective-context :command-island))
                       :command-head)
                      (t :argument)))
              (token (%depth-scan-emit
                      kind start end effective-context
                      (case kind
                        (:command-head :command-head)
                        (:host-form :host-form)
                        (:redirect :redirect-target)
                        (otherwise :argument)))))
         (setf (%depth-scan-state-position state) end)
         (%depth-scan-record-top-datum frame kind token start end))))))

  (defun %depth-scan-bare-word-end (source start)
  (let ((position start)
        (quote nil)
        (quoted-p nil)
        (escaped-p nil))
    (loop while (< position (length source))
          for character = (char source position)
          do (cond
               ((and (null quote)
                     (or (%depth-scan-whitespace-p character)
                         (and (or (find character '(#\< #\> #\| #\& #\;))
                                  (and (= position start)
                                       (digit-char-p character)))
                              (%depth-scan-bare-redirect-at source position))))
                (return))
               ((and quote (char= character quote))
                (setf quote nil quoted-p t)
                (incf position))
               ((and (null quote) (find character '(#\' #\")))
                (setf quote character quoted-p t)
                (incf position))
               ((char= character #\\)
                (setf escaped-p t)
                (if (< (1+ position) (length source))
                    (incf position 2)
                    (progn
                      (incf position)
                      (%depth-scan-incomplete)
                      (return))))
               (t (incf position))))
    (when quote (%depth-scan-incomplete))
    (values position quoted-p escaped-p)))

  (defun %depth-scan-bare-word-token (start end kind)
    (%depth-scan-emit kind start end :bare-line
                      (if (eq kind :command-head) :command-head :argument)))

  (defun %depth-scan-bare-note-word (kind token)
    (let ((state *depth-scan-state*))
      (cond
        ((%depth-scan-state-bare-pending-redirect state)
         (let* ((redirect (%depth-scan-state-bare-pending-redirect state))
                (operator (scan-token-text redirect)))
           (when (eq kind :redirect)
             (%depth-scan-invalid (first (scan-token-span token))
                                  (second (scan-token-span token))))
           (when (%depth-scan-heredoc-operator-p operator)
             (let ((span (scan-token-span token)))
               (setf (scan-token-kind token) :here-doc-delimiter)
               (%depth-scan-role token :redirect-target)
               (push (%make-depth-scan-heredoc
                      (%depth-scan-bare-delimiter-value
                       (%depth-scan-state-source state)
                       (first span) (second span))
                      (string= operator "<<-") :bare-line)
                     (%depth-scan-state-bare-heredocs state))))
           (setf (%depth-scan-state-bare-pending-redirect state) nil
                 (%depth-scan-state-bare-expect-command-p state) nil
                 (%depth-scan-state-bare-pending-operator state) nil
                 (%depth-scan-state-bare-command-seen-p state) t
                 (%depth-scan-state-bare-last-kind state) kind)))
        ((eq kind :redirect)
         (when (or (%depth-scan-state-bare-expect-command-p state)
                   (%depth-scan-state-bare-pending-operator state)
                   (%depth-scan-state-bare-pending-redirect state))
           (%depth-scan-invalid (first (scan-token-span token))
                                (second (scan-token-span token))))
         (setf (%depth-scan-state-bare-pending-redirect state) token
               (%depth-scan-state-bare-expect-command-p state) nil
               (%depth-scan-state-bare-command-seen-p state) t
               (%depth-scan-state-bare-last-kind state) :redirect))
        (t
         (when (%depth-scan-state-bare-expect-command-p state)
           (setf (%depth-scan-state-bare-expect-command-p state) nil
                 (%depth-scan-state-bare-pending-operator state) nil))
         (setf (%depth-scan-state-bare-command-seen-p state) t
               (%depth-scan-state-bare-last-kind state) kind)))))

  (defun %depth-scan-bare-operator (start spelling kind)
    (let* ((state *depth-scan-state*)
           (end (+ start (length spelling)))
           (token (%depth-scan-emit kind start end :bare-line
                                    (if (eq kind :redirect)
                                        :redirect-target
                                        :command-head))))
      (setf (%depth-scan-state-position state) end)
      (cond
        ((eq kind :redirect)
         (when (or (%depth-scan-state-bare-expect-command-p state)
                   (%depth-scan-state-bare-pending-operator state)
                   (%depth-scan-state-bare-pending-redirect state))
           (%depth-scan-invalid start end))
         (setf (%depth-scan-state-bare-pending-redirect state) token
               (%depth-scan-state-bare-expect-command-p state) nil
               (%depth-scan-state-bare-command-seen-p state) t
               (%depth-scan-state-bare-last-kind state) :redirect))
        ((member kind '(:pipeline :pipeline-stderr :and :or) :test #'eq)
         (when (or (%depth-scan-state-bare-expect-command-p state)
                   (%depth-scan-state-bare-pending-operator state)
                   (%depth-scan-state-bare-pending-redirect state))
           (%depth-scan-invalid start end))
         (setf (%depth-scan-state-bare-expect-command-p state) t
               (%depth-scan-state-bare-pending-operator state) kind
               (%depth-scan-state-bare-last-kind state) kind))
        ((member kind '(:sequence-separator :background) :test #'eq)
         (when (and (or (%depth-scan-state-bare-expect-command-p state)
                        (%depth-scan-state-bare-pending-operator state)
                        (%depth-scan-state-bare-pending-redirect state))
                    (not (and (eq kind :sequence-separator)
                              (eq (%depth-scan-state-bare-last-kind state)
                                  :background)
                              (%depth-scan-state-bare-expect-command-p state)
                              (null (%depth-scan-state-bare-pending-operator state))
                              (null (%depth-scan-state-bare-pending-redirect state)))))
           (%depth-scan-invalid start end))
         (setf (%depth-scan-state-bare-expect-command-p state) t
               (%depth-scan-state-bare-pending-operator state) nil
               (%depth-scan-state-bare-last-kind state) kind)))
      (when (member kind '(:pipeline :pipeline-stderr :and :or) :test #'eq)
        (setf (%depth-scan-state-bare-last-kind state) kind))
      token))

  (defun %depth-scan-bare-line ()
  (let* ((state *depth-scan-state*)
         (source (%depth-scan-state-source state))
         (length (%depth-scan-state-length state)))
    (setf (%depth-scan-state-bare-expect-command-p state) t)
    (loop while (< (%depth-scan-state-position state) length)
          for position = (%depth-scan-state-position state)
          for character = (char source position)
          do (cond
               ((%depth-scan-whitespace-p character)
                (let* ((end position)
                       (newline-position
                         (and (%depth-scan-state-bare-heredocs state)
                              (position #\Newline source :start position))))
                  (if newline-position
                      (setf end (1+ newline-position))
                      (loop while (and (< end length)
                                       (%depth-scan-whitespace-p (char source end)))
                            do (incf end)))
                  (%depth-scan-emit :whitespace position end :bare-line :none)
                  (setf (%depth-scan-state-position state) end)
                  (when (and newline-position
                             (%depth-scan-state-bare-heredocs state))
                    (%depth-scan-heredoc-body
                     (%depth-scan-state-bare-heredocs state) end)
                    (setf (%depth-scan-state-bare-heredocs state) nil))
                  (when (and (search (string #\Newline) source
                                     :start2 position :end2 end)
                             (null (%depth-scan-state-bare-pending-operator state))
                             (null (%depth-scan-state-bare-pending-redirect state)))
                    (setf (%depth-scan-state-bare-expect-command-p state) t
                          (%depth-scan-state-bare-command-seen-p state) nil
                          (%depth-scan-state-bare-last-kind state) nil))))
               ((and (char= character #\#)
                     (or (= position 0)
                         (%depth-scan-whitespace-p (char source (1- position)))
                         (find (char source (1- position)) '(#\; #\| #\& #\< #\>))))
                (%depth-scan-comment position :bare-line))
               ((and (char= character #\$)
                     (or (= position 0)
                         (%depth-scan-whitespace-p (char source (1- position)))))
                (%depth-scan-emit :dollar-unquote position (1+ position)
                                  :bare-line :host-form)
                (setf (%depth-scan-state-position state) (1+ position))
                (if (and (< (1+ position) length)
                         (char= (char source (1+ position)) #\())
                    (%depth-scan-list :host-form)
                    (multiple-value-bind (end quoted-p escaped-p)
                        (%depth-scan-bare-word-end source (1+ position))
                      (declare (ignore quoted-p escaped-p))
                      (when (= end (1+ position))
                        (setf end (1+ position)))
                      (let ((token (%depth-scan-bare-word-token
                                    (1+ position) end :argument)))
                        (%depth-scan-bare-note-word :argument token)
                        (setf (%depth-scan-state-position state) end)))))
               ((and (or (char= character #\<) (char= character #\>))
                     (< (1+ position) length)
                     (char= (char source (1+ position)) #\())
                (let ((token (%depth-scan-emit
                              :process-substitution position (1+ position)
                              :bare-line
                              (if (%depth-scan-state-bare-pending-redirect state)
                                  :redirect-target
                                  :argument))))
                  (setf (%depth-scan-state-position state) (1+ position))
                  (%depth-scan-bare-note-word :argument token)
                  (%depth-scan-list :bare-line)))
               ((%depth-scan-bare-redirect-at source position)
                (let* ((operator (%depth-scan-bare-redirect-at source position))
                       (kind (cond
                               ((string= operator "|") :pipeline)
                               ((string= operator "|&") :pipeline-stderr)
                               ((string= operator "&&") :and)
                               ((string= operator "||") :or)
                               ((string= operator ";") :sequence-separator)
                               ((string= operator "&") :background)
                               (t :redirect))))
                  (%depth-scan-bare-operator position operator kind)))
               ((and (char= character #\\) (= (1+ position) length))
                (%depth-scan-emit :argument position length :bare-line :argument)
                (setf (%depth-scan-state-position state) length)
                (%depth-scan-incomplete))
               (t
                (multiple-value-bind (end quoted-p escaped-p)
                    (%depth-scan-bare-word-end source position)
                  (when (= end position) (incf end))
                  (let* ((kind (if (%depth-scan-state-bare-expect-command-p state)
                                   :command-head
                                   (if quoted-p :string :argument)))
                         (token (%depth-scan-bare-word-token position end kind)))
                    (declare (ignore escaped-p))
                    (%depth-scan-bare-note-word kind token)
                    (setf (%depth-scan-state-position state) end))))))
    (when (%depth-scan-state-bare-pending-redirect state)
      (%depth-scan-invalid length length))
    (when (member (%depth-scan-state-bare-pending-operator state)
                  '(:pipeline :pipeline-stderr :and :or) :test #'eq)
      (%depth-scan-incomplete))))

  (defun %depth-scan-initialize-list (frame)
    (let* ((state *depth-scan-state*)
           (source (%depth-scan-state-source state))
           (length (%depth-scan-state-length state)))
      (loop while (< (%depth-scan-state-position state) length)
            for position = (%depth-scan-state-position state)
            for character = (char source position)
            do (cond
                 ((%depth-scan-whitespace-p character)
                  (let ((end position))
                    (loop while (and (< end length)
                                     (%depth-scan-whitespace-p (char source end)))
                          do (incf end))
                    (%depth-scan-emit :whitespace position end :host-form :none)
                    (setf (%depth-scan-state-position state) end)))
                 ((char= character #\;)
                  (%depth-scan-comment position :host-form))
                 ((and (char= character #\#)
                       (< (1+ position) length)
                       (char= (char source (1+ position)) #\|))
                  (%depth-scan-block-comment position :host-form))
                 (t (return))))
      (let ((position (%depth-scan-state-position state)))
        (cond
          ((or (>= position length) (char= (char source position) #\)))
           (setf (%depth-scan-frame-context frame) :host-form
                 (%depth-scan-frame-kind frame) :normal
                 (%depth-scan-frame-resolved-p frame) t))
          ((%depth-scan-frame-forced-host-p frame)
           (setf (%depth-scan-frame-context frame) :host-form
                 (%depth-scan-frame-kind frame) :normal
                 (%depth-scan-frame-resolved-p frame) t))
          (t
           (let* ((end (%depth-scan-simple-head-end source position))
                  (pipeline-p (and end
                                   (member (subseq source position end)
                                           '("|" "|&") :test #'string=)
                                   (%depth-scan-reader-boundary-p source end))))
             (if end
                 (%depth-scan-classify-head frame position end pipeline-p)
                 (setf (%depth-scan-frame-context frame) :host-form
                       (%depth-scan-frame-kind frame) :normal
                       (%depth-scan-frame-resolved-p frame) t))))))
      (cond
        ((eq (%depth-scan-frame-context frame) :host-form)
         (%depth-scan-role (%depth-scan-frame-open-token frame) :host-form))
        ((eq (%depth-scan-frame-context frame) :command-island)
         (%depth-scan-role (%depth-scan-frame-open-token frame) :command-head)))))

  (defun %depth-scan-list (parent-context &optional force-host-p)
    (let* ((state *depth-scan-state*)
           (source (%depth-scan-state-source state))
           (length (%depth-scan-state-length state))
           (start (%depth-scan-state-position state))
           (parent (first (%depth-scan-state-active-frames state)))
           (open-token (%depth-scan-emit
                        :delimiter-open start (1+ start)
                        (if (member parent-context '(:bare-line :host-form :command-island))
                            parent-context
                            :host-form)
                        (%depth-scan-parent-role parent)))
           (frame (%make-depth-scan-frame
                   (list start (1+ start)) nil parent-context :host-form :normal nil
                   open-token nil 0 nil nil nil '() force-host-p '())))
      (when parent
        (unless (eq (%depth-scan-frame-last-kind parent) :process-substitution)
          (%depth-scan-record-direct parent :nested nil start (1+ start))))
      (setf (%depth-scan-state-position state) (1+ start))
      (push frame (%depth-scan-state-active-frames state))
      (push frame (%depth-scan-state-frames state))
      (%depth-scan-initialize-list frame)
      (loop while (< (%depth-scan-state-position state) length)
            for position = (%depth-scan-state-position state)
            for character = (char source position)
            do (cond
                 ((%depth-scan-whitespace-p character)
                  (let* ((end position)
                         (newline-position
                           (and (%depth-scan-frame-here-docs frame)
                                (position #\Newline source :start position))))
                    (if newline-position
                        (setf end (1+ newline-position))
                        (loop while (and (< end length)
                                         (%depth-scan-whitespace-p (char source end)))
                              do (incf end)))
                    (%depth-scan-emit
                     :whitespace position end
                     (%depth-scan-frame-context frame) :none)
                    (setf (%depth-scan-state-position state) end)
                    (when (and newline-position
                               (%depth-scan-frame-here-docs frame))
                      (%depth-scan-heredoc-body
                       (%depth-scan-frame-here-docs frame) end)
                      (setf (%depth-scan-frame-here-docs frame) nil))))
                 ((char= character #\))
                  (when (%depth-scan-frame-pending-redirect frame)
                    (%depth-scan-invalid position (1+ position)))
                  (when (%depth-scan-frame-here-docs frame)
                    (%depth-scan-invalid position (1+ position)))
                  (when (%depth-scan-frame-pending-prefixes frame)
                    (%depth-scan-invalid position (1+ position)))
                  (%depth-scan-emit :delimiter-close position (1+ position)
                                    (%depth-scan-frame-context frame)
                                    (%depth-scan-frame-role frame t))
                  (setf (%depth-scan-frame-close-position frame) position)
                  (push (make-delimiter-pair
                         :open-span
                         (copy-list (%depth-scan-frame-opener-span frame))
                         :close-span
                         (list position (1+ position)))
                        (%depth-scan-state-pairs-reversed state))
                  (setf (%depth-scan-state-position state) (1+ position))
                  (pop (%depth-scan-state-active-frames state))
                  (%depth-scan-update-nested-end
                   (first (%depth-scan-state-active-frames state)) (1+ position))
                  (return))
                 ((char= character #\()
                  (let ((force-list-host (%depth-scan-state-forced-list-host-p state)))
                    (setf (%depth-scan-state-forced-list-host-p state) nil)
                    (%depth-scan-list (%depth-scan-frame-context frame)
                                      force-list-host)))
                 ((char= character #\;)
                  (%depth-scan-comment position (%depth-scan-frame-context frame)))
                 (t
                  (let ((force (%depth-scan-frame-forced-host-p frame)))
                    (setf (%depth-scan-frame-forced-host-p frame) nil)
                    (%depth-scan-datum (%depth-scan-frame-context frame) frame force)))))
      (unless (%depth-scan-frame-close-position frame)
        (%depth-scan-incomplete)
        (when (%depth-scan-frame-pending-prefixes frame)
          (%depth-scan-incomplete))
        (when (%depth-scan-frame-here-docs frame)
          (%depth-scan-incomplete))
        (when (eq (first (%depth-scan-state-active-frames state)) frame)
          (pop (%depth-scan-state-active-frames state)))
        (%depth-scan-update-nested-end parent length))))

  (defun %depth-scan-sexp ()
  (let* ((state *depth-scan-state*)
         (source (%depth-scan-state-source state))
         (length (%depth-scan-state-length state))
         (frame (%make-depth-scan-frame
                 nil nil nil :host-form :normal t nil t 0 nil nil nil '() nil '())))
    (loop while (< (%depth-scan-state-position state) length)
          for position = (%depth-scan-state-position state)
          for character = (char source position)
          do (cond
               ((%depth-scan-whitespace-p character)
                (let ((end position))
                  (loop while (and (< end length)
                                   (%depth-scan-whitespace-p (char source end)))
                        do (incf end))
                  (%depth-scan-emit :whitespace position end :host-form :none)
                  (setf (%depth-scan-state-position state) end)))
               ((char= character #\()
                (let* ((start position)
                       (force-host-p
                         (or (%depth-scan-frame-forced-host-p frame)
                             (%depth-scan-state-forced-list-host-p state))))
                  (setf (%depth-scan-frame-forced-host-p frame) nil
                        (%depth-scan-state-forced-list-host-p state) nil)
                  (%depth-scan-list :host-form force-host-p)
                  (%depth-scan-record-top-datum
                   frame :nested nil start (%depth-scan-state-position state))))
               ((char= character #\))
                (%depth-scan-emit :invalid position (1+ position)
                                  :host-form :host-form)
                (%depth-scan-invalid position (1+ position))
                (incf (%depth-scan-state-position state)))
               ((char= character #\;)
                (%depth-scan-comment position :host-form))
               (t
                (let ((force-host-p (%depth-scan-frame-forced-host-p frame)))
                  (setf (%depth-scan-frame-forced-host-p frame) nil)
                  (%depth-scan-datum :host-form frame force-host-p)))))
    (when (%depth-scan-frame-pending-prefixes frame)
      (%depth-scan-incomplete))))

  (defun %depth-scan-token-role (token)
    (or (gethash token (%depth-scan-state-roles *depth-scan-state*))
        (case (scan-token-kind token)
          (:command-head :command-head)
          ((:argument :string :escaped-symbol) :argument)
          ((:redirect :here-doc-delimiter) :redirect-target)
          ((:pipeline :pipeline-stderr :sequence-separator :and :or :background)
           :command-head)
          ((:host-form :reader-prefix :character-literal :comma-unquote
            :dollar-unquote)
           :host-form)
          ((:line-comment :block-comment) :comment)
          (:here-doc-body :none)
          (otherwise :none)))
)

  (defun %depth-scan-bare-cursor-role (tokens cursor)
  (let* ((state *depth-scan-state*)
         (source (%depth-scan-state-source state))
         (expect-command-p t)
         (command-seen-p nil)
         (pending-redirect-p nil)
         (pending-operator nil))
    (dolist (token tokens)
      (let* ((span (scan-token-span token))
             (start (first span))
             (end (second span)))
        (when (>= start cursor) (return))
        (case (scan-token-kind token)
          (:whitespace
           (let* ((prefix-end (min end cursor))
                  (text (subseq source start prefix-end)))
             (when (and (search (string #\Newline) text)
                        (null pending-operator)
                        (null pending-redirect-p))
               (setf expect-command-p t command-seen-p nil))))
          (:redirect
           (setf pending-redirect-p t expect-command-p nil
                 command-seen-p t))
          (:here-doc-delimiter
           (setf pending-redirect-p nil expect-command-p nil
                 command-seen-p t))
          ((:command-head :argument :string :escaped-symbol :process-substitution)
           (setf pending-redirect-p nil expect-command-p nil
                 pending-operator nil command-seen-p t))
          ((:pipeline :pipeline-stderr :and :or)
           (setf expect-command-p t pending-operator (scan-token-kind token)
                 command-seen-p t))
          ((:sequence-separator :background)
           (setf expect-command-p t pending-operator nil command-seen-p nil)))))
    (cond
      (pending-redirect-p :redirect-target)
      ((or expect-command-p pending-operator) :command-head)
      (command-seen-p :argument)
      (t :command-head))))

  (defun %depth-scan-cursor-role (tokens)
  (let* ((state *depth-scan-state*)
         (cursor (%depth-scan-state-cursor state))
         (head-role (%depth-scan-state-head-cursor-role state))
         (token
           (find-if
            (lambda (candidate)
              (let ((span (scan-token-span candidate)))
                (and (<= (first span) cursor)
                     (< cursor (second span))
                     (not (eq (scan-token-kind candidate) :whitespace)))))
            tokens)))
    (when head-role
      (return-from %depth-scan-cursor-role head-role))
    (when token
      (return-from %depth-scan-cursor-role (%depth-scan-token-role token)))
    (when (some (lambda (candidate)
                  (and (eq (scan-token-kind candidate) :here-doc-body)
                       (<= (first (scan-token-span candidate)) cursor)
                       (<= cursor (second (scan-token-span candidate)))))
                tokens)
      (return-from %depth-scan-cursor-role :none))
    (if (eq (%depth-scan-state-mode state) :bare-line)
        (%depth-scan-bare-cursor-role tokens cursor)
        (let ((frame (%depth-scan-open-frame-at cursor)))
          (cond
            ((null frame) :none)
            ((eq (%depth-scan-frame-kind frame) :pipeline) :command-head)
            ((not (%depth-scan-frame-resolved-p frame)) :command-head)
            ((and (not (%depth-scan-frame-head-seen-p frame))
                  (null (%depth-scan-frame-close-position frame)))
             :command-head)
            ((eq (%depth-scan-frame-context frame) :host-form) :host-form)
            (t
             (let ((last-event nil))
               (dolist (event (reverse (%depth-scan-frame-events frame)))
                 (when (<= (second event) cursor)
                   (setf last-event event)))
               (cond
                 ((null last-event) :command-head)
                 ((eq (third last-event) :redirect) :redirect-target)
                 ((member (third last-event)
                          '(:pipeline :pipeline-stderr :sequence-separator :and :or)
                          :test #'eq)
                  :command-head)
                 (t :argument))))))))
)

  (defun %depth-scan-open-frame-at (cursor)
  (find-if
   (lambda (frame)
     (let ((span (%depth-scan-frame-opener-span frame))
           (close (%depth-scan-frame-close-position frame)))
       (and span
            (< (first span) cursor)
            (or (null close) (<= cursor close)))))
   (%depth-scan-state-frames *depth-scan-state*)))

  (defun %depth-scan-open-indent (cursor indent-width)
  (let* ((state *depth-scan-state*)
         (source (%depth-scan-state-source state))
         (frame (%depth-scan-open-frame-at cursor)))
    (when frame
      (let* ((opener (first (%depth-scan-frame-opener-span frame)))
             (line-end (%depth-scan-line-end source cursor))
             (next (position-if-not (lambda (character)
                                      (find character '(#\Space #\Tab)))
                                    source :start cursor :end line-end)))
        (if (and next (char= (char source next) #\)))
            (%depth-scan-column source opener)
            (+ (%depth-scan-column source opener) indent-width))))))

  (defun %depth-scan-bare-continuation-indent (tokens cursor indent-width)
  (labels ((line-leading-spaces (position)
             (let* ((source (%depth-scan-state-source *depth-scan-state*))
                    (line-start (or (position #\Newline source :end position) -1))
                    (index (1+ line-start)))
               (loop while (and (< index position)
                                (find (char source index) '(#\Space #\Tab)))
                     do (incf index))
               (- index (1+ line-start))))
           (trailing-escape-position (text)
             (let* ((end (length text))
                    (slash-start end))
               (loop while (and (plusp slash-start)
                                (char= (char text (1- slash-start)) #\\))
                     do (decf slash-start))
               (if (oddp (- end slash-start))
                   (1- end)
                   (when (and (plusp end)
                              (char= (char text (1- end)) #\Newline))
                     (setf slash-start (1- end))
                     (loop while (and (plusp slash-start)
                                      (char= (char text (1- slash-start)) #\\))
                           do (decf slash-start))
                     (and (oddp (- (1- end) slash-start))
                          (1- end)))))))
    (let* ((state *depth-scan-state*)
           (source (%depth-scan-state-source state))
           (continuation nil))
      (dolist (token tokens)
        (let* ((span (scan-token-span token))
               (start (first span))
               (end (second span)))
          (when (>= start cursor) (return))
          (case (scan-token-kind token)
            ((:pipeline :pipeline-stderr :and :or)
             (when (<= end cursor)
               (setf continuation (line-leading-spaces start))))
            ((:command-head :argument :string :escaped-symbol :process-substitution)
             (let* ((prefix-end (min end cursor))
                    (text (subseq source start prefix-end))
                    (escape-position (trailing-escape-position text)))
               (if escape-position
                   (setf continuation
                         (line-leading-spaces (+ start escape-position)))
                   (when (<= end cursor)
                     (setf continuation nil))))))))
      (when continuation (+ continuation indent-width))))
)

  (defun %depth-scan-indent (tokens indent-width)
  (labels ((unclosed-token-p (token)
             (let* ((kind (scan-token-kind token))
                    (text (scan-token-text token))
                    (length (length text)))
               (case kind
                 ((:string :escaped-symbol)
                  (let ((delimiter (if (eq kind :string) #\" #\|))
                        (position 1))
                    (loop while (< position length)
                          for character = (char text position)
                          do (cond
                               ((char= character #\\)
                                (incf position
                                      (if (< (1+ position) length) 2 1)))
                               ((char= character delimiter)
                                (return nil))
                               (t (incf position)))
                          finally (return t))))
                 (:block-comment
                  (let ((position 2)
                        (depth 1))
                    (loop while (< position length)
                          do (cond
                               ((and (<= (+ position 2) length)
                                     (string= "#|" text
                                              :start2 position
                                              :end2 (+ position 2)))
                                (incf depth)
                                (incf position 2))
                               ((and (<= (+ position 2) length)
                                     (string= "|#" text
                                              :start2 position
                                              :end2 (+ position 2)))
                                (decf depth)
                                (incf position 2)
                                (when (zerop depth) (return)))
                               (t (incf position))))
                    (plusp depth)))
                 (otherwise nil)))))
    (let* ((state *depth-scan-state*)
           (cursor (%depth-scan-state-cursor state))
           (source (%depth-scan-state-source state))
           (body
             (find-if
              (lambda (token)
                (and (eq (scan-token-kind token) :here-doc-body)
                     (<= (first (scan-token-span token)) cursor)
                     (<= cursor (second (scan-token-span token)))))
              tokens))
           (unfinished
             (find-if
              (lambda (token)
                (let ((start (first (scan-token-span token)))
                      (end (second (scan-token-span token))))
                  (and (member (scan-token-kind token)
                               '(:string :escaped-symbol :block-comment)
                               :test #'eq)
                       (< start cursor)
                       (<= cursor end)
                       (or (< cursor end)
                           (and (%depth-scan-state-incomplete-span state)
                                (unclosed-token-p token))))))
              (reverse tokens))))
      (cond
        (body 0)
        (unfinished
         (%depth-scan-column source (first (scan-token-span unfinished))))
        ((eq (%depth-scan-state-mode state) :sexp)
         (or (%depth-scan-open-indent cursor indent-width) 0))
        (t
         (or (%depth-scan-open-indent cursor indent-width)
             (%depth-scan-bare-continuation-indent tokens cursor indent-width)
             0))))))

  (defun scan-input (source &key (cursor (length source))
                          (reader-context :auto)
                          (indent-width 2)
                          head-classifier)
  (check-type source string)
  (unless (and (integerp cursor) (<= 0 cursor (length source)))
    (error "CURSOR must be a character offset into SOURCE."))
  (unless (and (integerp indent-width) (plusp indent-width))
    (error "INDENT-WIDTH must be a positive integer."))
  (unless (member reader-context '(:auto :bare-line :sexp))
    (error "READER-CONTEXT must be :AUTO, :BARE-LINE, or :SEXP."))
  (let* ((first-nonwhite (position-if-not #'%depth-scan-whitespace-p source))
         (mode (if (eq reader-context :auto)
                   (if (and first-nonwhite
                            (char= (char source first-nonwhite) #\())
                       :sexp
                       :bare-line)
                   reader-context)))
    (when (and (eq mode :sexp) (not (functionp head-classifier)))
      (error "HEAD-CLASSIFIER is required in :SEXP context."))
    (let* ((*depth-scan-state*
             (%make-depth-scan-state
              source (length source) cursor mode head-classifier 0 '() '() '()
              '() '() nil (make-hash-table :test #'eq) nil nil nil t nil nil
              nil nil))
           (state *depth-scan-state*))
      (if (eq mode :bare-line)
          (%depth-scan-bare-line)
          (%depth-scan-sexp))
      (let* ((tokens (nreverse (%depth-scan-state-tokens-reversed state)))
             (unmatched
               (sort (loop for frame in (%depth-scan-state-frames state)
                           unless (%depth-scan-frame-close-position frame)
                             collect (make-delimiter-frame
                                      :opener #\( :expected-close #\)
                                      :opener-span
                                      (copy-list
                                       (%depth-scan-frame-opener-span frame))))
                     #'< :key (lambda (frame)
                                (first (delimiter-frame-opener-span frame)))))
             (first-invalid
               (car (stable-sort
                     (copy-list (%depth-scan-state-invalids state))
                     #'< :key #'first)))
             (status (cond
                       (first-invalid :invalid)
                       ((or (%depth-scan-state-incomplete-span state) unmatched)
                        :incomplete)
                       (t :complete)))
             (incomplete-span
               (and (eq status :incomplete)
                    (or (%depth-scan-state-incomplete-span state)
                        (list (length source) (length source)))))
             (pairs
               (stable-sort
                (nreverse (%depth-scan-state-pairs-reversed state))
                #'< :key (lambda (pair)
                           (first (delimiter-pair-open-span pair))))))
        (make-scan-result
         :status status
         :tokens tokens
         :open-delimiters unmatched
         :delimiter-pairs pairs
         :invalid-span first-invalid
         :incomplete-span incomplete-span
         :next-indent (%depth-scan-indent tokens indent-width)
         :cursor-role (%depth-scan-cursor-role tokens))))))
