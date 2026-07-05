(in-package #:nshell/test)


(in-suite expansion-tests)

(test abbreviation-domain-construction-boundary-is-factory-only
  (is (fboundp 'nshell.domain.abbreviation:make-abbreviation))
  (is (fboundp 'nshell.domain.abbreviation::%allocate-abbreviation))
  (is (not (fboundp 'nshell.domain.abbreviation::copy-abbreviation))))

(test abbreviation-domain-factory-validates-input
  (signals type-error
    (nshell.domain.abbreviation:make-abbreviation :expansion '("git checkout")))
  (signals type-error
    (nshell.domain.abbreviation:make-abbreviation :position :middle)))

(test abbreviation-domain-factory-detaches-mutable-expansion-string
  (let* ((expansion (copy-seq "git checkout"))
         (abbr (nshell.domain.abbreviation:make-abbreviation
                :expansion expansion
                :position :command)))
    (setf (char expansion 0) #\X)
    (is (string= "git checkout"
                 (nshell.domain.abbreviation:abbreviation-expansion abbr)))
    (is (eq :command
            (nshell.domain.abbreviation:abbreviation-position abbr)))))

(test abbreviation-domain-finds-token-before-cursor
  (multiple-value-bind (token start end found-p)
      (nshell.domain.abbreviation:abbreviation-target-before-cursor
       "echo|gco" 8)
    (is (not (null found-p)))
    (is (string= "gco" token))
    (is (= 5 start))
    (is (= 8 end))))

(test abbreviation-domain-expands-token-before-cursor
  (multiple-value-bind (buffer cursor expanded-p)
      (nshell.domain.abbreviation:expand-abbreviation
       "echo gco tail"
       8
       (lambda (token)
         (when (string= token "gco")
           "git checkout")))
    (is (not (null expanded-p)))
    (is (string= "echo git checkout tail" buffer))
    (is (= 17 cursor))))

(test abbreviation-domain-command-position-detects-command-starts
  (is (nshell.domain.abbreviation:abbreviation-command-position-p "gco" 0))
  (is (nshell.domain.abbreviation:abbreviation-command-position-p "echo hi; gco" 9))
  (is (nshell.domain.abbreviation:abbreviation-command-position-p "echo hi | gco" 10))
  (is (not (nshell.domain.abbreviation:abbreviation-command-position-p
            "echo gco" 5)))
  (is (not (nshell.domain.abbreviation:abbreviation-command-position-p
            "cat < gco" 6))))

(test abbreviation-domain-respects-command-position-expansions
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
      (is (not (null expanded-p)))
      (is (string= "git checkout" buffer))
      (is (= 12 cursor)))
    (multiple-value-bind (buffer cursor expanded-p)
        (nshell.domain.abbreviation:expand-abbreviation
         "echo gco"
         8
         (lambda (token)
           (when (string= token "gco")
             abbr)))
      (is (not expanded-p))
      (is (string= "echo gco" buffer))
      (is (= 8 cursor)))))

(test abbreviation-domain-expands-after-leading-space-command-position
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
      (is (not (null expanded-p)))
      (is (string= "  git checkout" buffer))
      (is (= 14 cursor)))))

(test abbreviation-domain-respects-escaped-space
  (multiple-value-bind (buffer cursor expanded-p)
      (nshell.domain.abbreviation:expand-abbreviation
       "echo foo\\ gco"
       13
       (lambda (token)
         (when (string= token "gco")
           "git checkout")))
    (is (not expanded-p))
    (is (string= "echo foo\\ gco" buffer))
    (is (= 13 cursor))))

(test abbreviation-domain-does-not-expand-quoted-token
  (multiple-value-bind (buffer cursor expanded-p)
      (nshell.domain.abbreviation:expand-abbreviation
       "echo \"gco\""
       10
       (lambda (token)
         (when (string= token "\"gco\"")
           "git checkout")))
    (is (not expanded-p))
    (is (string= "echo \"gco\"" buffer))
    (is (= 10 cursor))))

(test abbreviation-domain-allows-escaped-quote-content
  (multiple-value-bind (buffer cursor expanded-p)
      (nshell.domain.abbreviation:expand-abbreviation
       "foo\\\"bar"
       8
       (lambda (token)
         (when (string= token "foo\\\"bar")
           "git checkout")))
      (is (not (null expanded-p)))
    (is (string= "git checkout" buffer))
    (is (= 12 cursor))))

(test pbt-abbreviation-domain-expands-token-exactly-at-cursor
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
                new-cursor))))))
