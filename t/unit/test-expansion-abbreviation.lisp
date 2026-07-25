(in-package #:nshell/test)

(describe "expansion-tests"
  (it "abbreviation-domain-construction-boundary-is-factory-only"
    (expect (fboundp 'nshell.domain.abbreviation:make-abbreviation) :to-be-truthy)
    (expect (fboundp 'nshell.domain.abbreviation::%allocate-abbreviation) :to-be-truthy)
    (expect (fboundp 'nshell.domain.abbreviation::copy-abbreviation) :to-be-falsy))

  (it "abbreviation-domain-factory-validates-input"
    (expect (lambda () (nshell.domain.abbreviation:make-abbreviation :expansion '("git checkout"))) :to-throw 'type-error)
    (expect (lambda () (nshell.domain.abbreviation:make-abbreviation :position :middle)) :to-throw 'type-error))

  (it "abbreviation-domain-factory-detaches-mutable-expansion-string"
    (let* ((expansion (copy-seq "git checkout"))
           (abbr (nshell.domain.abbreviation:make-abbreviation
                  :expansion expansion
                  :position :command)))
      (setf (char expansion 0) #\X)
      (expect "git checkout" :to-equal (nshell.domain.abbreviation:abbreviation-expansion abbr))
      (expect :command :to-be (nshell.domain.abbreviation:abbreviation-position abbr))))

  (it "abbreviation-domain-finds-token-before-cursor"
    (multiple-value-bind (token start end found-p)
        (nshell.domain.abbreviation:abbreviation-target-before-cursor
         "echo|gco" 8)
      (expect (null found-p) :to-be-falsy)
      (expect "gco" :to-equal token)
      (expect 5 :to-equal start)
      (expect 8 :to-equal end)))

  (it "abbreviation-domain-expands-token-before-cursor"
    (multiple-value-bind (buffer cursor expanded-p)
        (nshell.domain.abbreviation:expand-abbreviation
         "echo gco tail"
         8
         (lambda (token)
           (when (string= token "gco")
             "git checkout")))
      (expect (null expanded-p) :to-be-falsy)
      (expect "echo git checkout tail" :to-equal buffer)
      (expect 17 :to-equal cursor)))

  (it "abbreviation-domain-command-position-detects-command-starts"
    (expect (nshell.domain.abbreviation:abbreviation-command-position-p "gco" 0) :to-be-truthy)
    (expect (nshell.domain.abbreviation:abbreviation-command-position-p "echo hi; gco" 9) :to-be-truthy)
    (expect (nshell.domain.abbreviation:abbreviation-command-position-p "echo hi | gco" 10) :to-be-truthy)
    (expect (nshell.domain.abbreviation:abbreviation-command-position-p
              "echo gco" 5) :to-be-falsy)
    (expect (nshell.domain.abbreviation:abbreviation-command-position-p
              "cat < gco" 6) :to-be-falsy))

  (it "abbreviation-domain-respects-command-position-expansions"
    (let ((abbr (nshell.domain.abbreviation:make-abbreviation
                 :expansion "git checkout"
                 :position :command)))
      (multiple-value-bind (buffer cursor expanded-p)
          (nshell.domain.abbreviation:expand-abbreviation
           "gco"
           3
           (lambda (token)
             (when (string= token "gco")
               abbr)))
        (expect (null expanded-p) :to-be-falsy)
        (expect "git checkout" :to-equal buffer)
        (expect 12 :to-equal cursor))
      (multiple-value-bind (buffer cursor expanded-p)
          (nshell.domain.abbreviation:expand-abbreviation
           "echo gco"
           8
           (lambda (token)
             (when (string= token "gco")
               abbr)))
        (expect expanded-p :to-be-falsy)
        (expect "echo gco" :to-equal buffer)
        (expect 8 :to-equal cursor))))

  (it "abbreviation-domain-expands-after-leading-space-command-position"
    (let ((abbr (nshell.domain.abbreviation:make-abbreviation
                 :expansion "git checkout"
                 :position :command)))
      (multiple-value-bind (buffer cursor expanded-p)
          (nshell.domain.abbreviation:expand-abbreviation
           "  gco"
           5
           (lambda (token)
             (when (string= token "gco")
               abbr)))
        (expect (null expanded-p) :to-be-falsy)
        (expect "  git checkout" :to-equal buffer)
        (expect 14 :to-equal cursor))))

  (it "abbreviation-domain-respects-escaped-space"
    (multiple-value-bind (buffer cursor expanded-p)
        (nshell.domain.abbreviation:expand-abbreviation
         "echo foo\\ gco"
         13
         (lambda (token)
           (when (string= token "gco")
             "git checkout")))
      (expect expanded-p :to-be-falsy)
      (expect "echo foo\\ gco" :to-equal buffer)
      (expect 13 :to-equal cursor)))

  (it "abbreviation-domain-does-not-expand-quoted-token"
    (multiple-value-bind (buffer cursor expanded-p)
        (nshell.domain.abbreviation:expand-abbreviation
         "echo \"gco\""
         10
         (lambda (token)
           (when (string= token "\"gco\"")
             "git checkout")))
      (expect expanded-p :to-be-falsy)
      (expect "echo \"gco\"" :to-equal buffer)
      (expect 10 :to-equal cursor)))

  (it "abbreviation-domain-allows-escaped-quote-content"
    (multiple-value-bind (buffer cursor expanded-p)
        (nshell.domain.abbreviation:expand-abbreviation
         "foo\\\"bar"
         8
         (lambda (token)
           (when (string= token "foo\\\"bar")
             "git checkout")))
        (expect (null expanded-p) :to-be-falsy)
      (expect "git checkout" :to-equal buffer)
      (expect 12 :to-equal cursor)))

  (it "pbt-abbreviation-domain-expands-token-exactly-at-cursor"
    (check-property (:trials 50)
        ((prefix (gen-shell-command :min-words 1 :max-words 3 :max-word-length 6)
                 #'shrink-prompt-text)
         (token (gen-shell-word :min-length 1 :max-length 8)
                #'shrink-prompt-text)
         (suffix (gen-shell-command :min-words 1 :max-words 3 :max-word-length 6)
                 #'shrink-prompt-text))
      (let* ((expansion (concatenate 'string "expanded-" token))
             (buffer (concatenate 'string prefix " " token " " suffix))
             (cursor (+ (length prefix) 1 (length token))))
        (multiple-value-bind (new-buffer new-cursor expanded-p)
            (nshell.domain.abbreviation:expand-abbreviation
             buffer cursor
             (lambda (candidate)
               (when (string= candidate token)
                 expansion)))
          (and expanded-p
               (string= (concatenate 'string prefix " " expansion " " suffix)
                        new-buffer)
               (= (+ (length prefix) 1 (length expansion))
                  new-cursor)))))))
