(in-package #:nshell/test)

(defmacro is-input-state (state &key
                          ((:mode mode) nil mode-p)
                          ((:buffer buffer) nil buffer-p)
                          ((:cursor-pos cursor-pos) nil cursor-pos-p)
                          ((:completion-index completion-index) nil completion-index-p)
                          ((:suggestion suggestion) nil suggestion-p)
                          ((:search-query search-query) nil search-query-p)
                          ((:search-original-buffer search-original-buffer)
                           nil
                           search-original-buffer-p)
                          ((:search-original-cursor search-original-cursor)
                           nil
                           search-original-cursor-p)
                          ((:search-index search-index) nil search-index-p)
                          ((:completion-base-buffer completion-base-buffer)
                           nil
                           completion-base-buffer-p)
                          ((:completion-base-cursor completion-base-cursor)
                           nil
                           completion-base-cursor-p)
                          ((:last-candidates last-candidates) nil last-candidates-p)
                          ((:vi-visual-anchor vi-visual-anchor)
                           nil
                           vi-visual-anchor-p)
                          ((:kill-ring kill-ring) nil kill-ring-p)
                          ((:last-argument-start last-argument-start)
                           nil
                           last-argument-start-p)
                          ((:last-argument-end last-argument-end)
                           nil
                           last-argument-end-p)
                          ((:last-argument-index last-argument-index)
                           nil
                           last-argument-index-p))
  (let ((state-var (gensym "STATE")))
    `(let ((,state-var ,state))
       ,@(append
          (when mode-p
            `((is-maybe-symbol
               ,mode
               (nshell.presentation:input-state-mode ,state-var))))
          (when buffer-p
            `((is (string= ,buffer
                           (nshell.presentation:input-state-buffer ,state-var)))))
          (when cursor-pos-p
            `((is (= ,cursor-pos
                     (nshell.presentation:input-state-cursor-pos ,state-var)))))
          (when completion-index-p
            `((is (= ,completion-index
                     (nshell.presentation:input-state-completion-index ,state-var)))))
          (when suggestion-p
            `((is-maybe-string
               ,suggestion
               (nshell.presentation:input-state-suggestion ,state-var))))
          (when search-query-p
            `((is-maybe-string
               ,search-query
               (nshell.presentation:input-state-search-query ,state-var))))
          (when search-original-buffer-p
            `((is-maybe-string
               ,search-original-buffer
               (nshell.presentation:input-state-search-original-buffer
                ,state-var))))
          (when search-original-cursor-p
            `((is-maybe-number
               ,search-original-cursor
               (nshell.presentation:input-state-search-original-cursor
                ,state-var))))
          (when search-index-p
            `((is-maybe-number
               ,search-index
               (nshell.presentation:input-state-search-index ,state-var))))
          (when completion-base-buffer-p
            `((is-maybe-string
               ,completion-base-buffer
               (nshell.presentation:input-state-completion-base-buffer ,state-var))))
          (when completion-base-cursor-p
            `((is-maybe-number
               ,completion-base-cursor
               (nshell.presentation:input-state-completion-base-cursor ,state-var))))
          (when last-candidates-p
            `((is (equal ,last-candidates
                         (nshell.presentation:input-state-last-candidates ,state-var)))))
          (when vi-visual-anchor-p
            `((is-maybe-number
               ,vi-visual-anchor
               (nshell.presentation:input-state-vi-visual-anchor ,state-var))))
          (when kill-ring-p
            `((is (equal ,kill-ring
                         (nshell.presentation:input-state-kill-ring ,state-var)))))
          (when last-argument-start-p
            `((is-maybe-number
               ,last-argument-start
               (nshell.presentation:input-state-last-argument-start ,state-var))))
          (when last-argument-end-p
            `((is-maybe-number
               ,last-argument-end
               (nshell.presentation:input-state-last-argument-end ,state-var))))
          (when last-argument-index-p
            `((is-maybe-number
               ,last-argument-index
               (nshell.presentation:input-state-last-argument-index ,state-var))))))))

(defmacro is-search-state (state &key
                           ((:mode mode) nil mode-p)
                           ((:buffer buffer) nil buffer-p)
                           ((:cursor-pos cursor-pos) nil cursor-pos-p)
                           ((:query query) nil query-p)
                           ((:original-buffer original-buffer)
                            nil
                            original-buffer-p)
                           ((:original-cursor original-cursor)
                            nil
                            original-cursor-p)
                           ((:index index) nil index-p))
  `(is-input-state ,state
                   ,@(when mode-p `(:mode ,mode))
                   ,@(when buffer-p `(:buffer ,buffer))
                   ,@(when cursor-pos-p `(:cursor-pos ,cursor-pos))
                   ,@(when query-p `(:search-query ,query))
                   ,@(when original-buffer-p
                       `(:search-original-buffer ,original-buffer))
                   ,@(when original-cursor-p
                       `(:search-original-cursor ,original-cursor))
                   ,@(when index-p `(:search-index ,index))))

(defmacro is-search-state-with-completion-cleared (state &rest state-args)
  `(progn
     (is-search-state ,state ,@state-args)
     (is-completion-session-cleared ,state)))

(defmacro is-search-session-with-completion-cleared (state)
  `(is-search-state-with-completion-cleared ,state
     :mode :insert
     :query ""
     :original-buffer ""
     :original-cursor nil
     :index 0))

(defmacro is-search-session-cleared (state)
  `(is-search-state ,state
                    :mode :insert
                    :query ""
                    :original-buffer ""
                    :original-cursor nil
                    :index 0))

(defmacro is-completion-session-cleared (state)
  `(is-input-state ,state
                   :completion-index -1
                   :completion-base-buffer nil
                   :completion-base-cursor nil
                   :last-candidates nil
                   :suggestion nil))

(defmacro is-input-state-with-completion-cleared (state &rest state-args)
  `(progn
     (is-input-state ,state ,@state-args)
     (is-completion-session-cleared ,state)))

(defmacro is-vi-command-state (state &rest state-args)
  `(is-input-state ,state
                   :mode :vi-command
                   :vi-visual-anchor nil
                   ,@state-args))

(defmacro is-vi-visual-state (state &rest state-args)
  `(is-input-state ,state
                   :mode :vi-visual
                   ,@state-args))
