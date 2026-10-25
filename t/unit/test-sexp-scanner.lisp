(in-package #:nshell/test)

(defun %sexp-scanner-test-head-classifier (head)
  (if (string= head "echo") :command-island :host-form))

(defun %sexp-scanner-fixed-byte-string (size)
  (let ((state #x6d2b79f5)
        (source (make-string size)))
    (dotimes (position size source)
      (setf state (logand #xffffffff (logxor state (ash state 13))))
      (setf state (logand #xffffffff (logxor state (ash state -17))))
      (setf state (logand #xffffffff (logxor state (ash state 5))))
      (setf (char source position) (code-char (logand state #xff))))))
(describe "sexp-scanner-malformed-bare-line-and-fuzz-contracts"
  (it "accepts-one-semicolon-after-background-and-rejects-misordered-separators"
    (progn
      (let* ((source "sleep 0.1 &; wait")
             (result
               (nshell.domain.parsing:scan-input
                source :reader-context :bare-line))
             (tokens (nshell.domain.parsing:scan-result-tokens result)))
        (expect :complete :to-be
                (nshell.domain.parsing:scan-result-status result))
        (expect 1 :to-equal
                (count :background tokens
                       :key (function nshell.domain.parsing:scan-token-kind)))
        (expect 1 :to-equal
                (count :sequence-separator tokens
                       :key (function nshell.domain.parsing:scan-token-kind)))
        (expect (nshell.domain.parsing:scan-result-invalid-span result)
                :to-be-null)
        (expect (nshell.domain.parsing:scan-result-incomplete-span result)
                :to-be-null))
      (dolist (case (list (list "; echo" 0 1)
                          (list "echo && ; next" 8 9)
                          (list "echo && && next" 8 10)
                          (list "sleep &;; wait" 8 9)))
        (let* ((source (first case))
               (start (second case))
               (end (third case))
               (result
                 (nshell.domain.parsing:scan-input
                  source :reader-context :bare-line)))
          (expect :invalid :to-be
                  (nshell.domain.parsing:scan-result-status result))
          (expect (list start end) :to-equal
                  (nshell.domain.parsing:scan-result-invalid-span result))
          (expect (nshell.domain.parsing:scan-result-incomplete-span result)
                  :to-be-null)))))

  (it "reports-trailing-bare-line-pipeline-and-sequence-operators-incomplete"
    (dolist (source '("echo &&" "echo ||" "echo |" "echo |&"))
      (let ((result
              (nshell.domain.parsing:scan-input
               source :reader-context :bare-line)))
        (expect :incomplete :to-be
                (nshell.domain.parsing:scan-result-status result))
        (expect (list (length source) (length source)) :to-equal
                (nshell.domain.parsing:scan-result-incomplete-span result))
        (expect (nshell.domain.parsing:scan-result-invalid-span result) :to-be-null))))

  (it "reports-a-missing-bare-line-redirect-target-invalid-at-eof"
    (let* ((source "echo >")
           (result
             (nshell.domain.parsing:scan-input
              source :reader-context :bare-line)))
      (expect :invalid :to-be
              (nshell.domain.parsing:scan-result-status result))
      (expect (list (length source) (length source)) :to-equal
              (nshell.domain.parsing:scan-result-invalid-span result))
      (expect (nshell.domain.parsing:scan-result-incomplete-span result) :to-be-null)))

  (it "scan-input-fuzzes-one-hundred-thousand-fixed-seed-byte-strings"
    (let ((state #x6d2b79f5)
          (case-count 0))
      (labels ((next-byte ()
                 (setf state (logand #xffffffff (logxor state (ash state 13))))
                 (setf state (logand #xffffffff (logxor state (ash state -17))))
                 (setf state (logand #xffffffff (logxor state (ash state 5))))
                 (logand state #xff))
               (next-source ()
                 (let* ((length (mod (next-byte) 17))
                        (source (make-string length)))
                   (dotimes (position length source)
                     (setf (char source position) (code-char (next-byte)))))))
        (dotimes (case-index 100000)
          (let* ((source (next-source))
                 (result
                   (nshell.domain.parsing:scan-input
                    source :reader-context :bare-line))
                 (status (and (nshell.domain.parsing:scan-result-p result)
                              (nshell.domain.parsing:scan-result-status result))))
            (unless (member status '(:complete :incomplete :invalid))
              (error "Scanner fuzz case ~D returned status ~S for ~S"
                     case-index status source))
            (incf case-count)))
        (expect 100000 :to-equal case-count)))))

(describe "sexp-depth-scanner-tests"
  (it "pairs-structural-delimiters-and-preserves-reader-contexts"
    (let* ((result
             (nshell.domain.parsing:scan-input
              "(echo (x))"
              :reader-context :sexp
              :head-classifier #'%sexp-scanner-test-head-classifier))
           (tokens (nshell.domain.parsing:scan-result-tokens result))
           (pairs (nshell.domain.parsing:scan-result-delimiter-pairs result)))
      (expect :complete :to-be
              (nshell.domain.parsing:scan-result-status result))
      (expect '((0 1) (6 7)) :to-equal
              (mapcar #'nshell.domain.parsing:delimiter-pair-open-span pairs))
      (expect '((9 10) (8 9)) :to-equal
              (mapcar #'nshell.domain.parsing:delimiter-pair-close-span pairs))
      (expect '(:delimiter-open :command-head :whitespace :delimiter-open
                :host-form :delimiter-close :delimiter-close)
              :to-equal
              (mapcar #'nshell.domain.parsing:scan-token-kind tokens))
      (expect '(:host-form :command-island :command-island :command-island
                :host-form :host-form :command-island)
              :to-equal
              (mapcar #'nshell.domain.parsing:scan-token-reader-context tokens))))

  (it "assigns-cursor-roles-by-half-open-token-boundaries"
    (let ((head-result
            (nshell.domain.parsing:scan-input
             "(echo arg)"
             :cursor 1
             :reader-context :sexp
             :head-classifier #'%sexp-scanner-test-head-classifier))
          (gap-result
            (nshell.domain.parsing:scan-input
             "(echo arg)"
             :cursor 5
             :reader-context :sexp
             :head-classifier #'%sexp-scanner-test-head-classifier))
          (argument-result
            (nshell.domain.parsing:scan-input
             "(echo arg)"
             :cursor 6
             :reader-context :sexp
             :head-classifier #'%sexp-scanner-test-head-classifier)))
      (expect :command-head :to-be
              (nshell.domain.parsing:scan-result-cursor-role head-result))
      (expect :argument :to-be
              (nshell.domain.parsing:scan-result-cursor-role gap-result))
      (expect :argument :to-be
              (nshell.domain.parsing:scan-result-cursor-role argument-result)))
    (expect :command-head :to-be
            (nshell.domain.parsing:scan-result-cursor-role
             (nshell.domain.parsing:scan-input "echo arg" :cursor 0)))
    (expect :argument :to-be
            (nshell.domain.parsing:scan-result-cursor-role
             (nshell.domain.parsing:scan-input "echo arg" :cursor 4))))

  (it "calls-the-head-classifier-for-complete-and-partial-heads"
    (let ((calls nil)
          (result nil))
      (setf result
            (nshell.domain.parsing:scan-input
             "(echo arg)"
             :cursor 3
             :reader-context :sexp
             :head-classifier
             (lambda (head)
               (push head calls)
               (if (string= head "echo") :command-island :host-form))))
      (expect '("echo" "ec") :to-equal (nreverse calls))
      (expect :host-form :to-be
              (nshell.domain.parsing:scan-result-cursor-role result)))
    (let ((calls nil))
      (nshell.domain.parsing:scan-input
       "(|)"
       :reader-context :sexp
       :head-classifier
       (lambda (head)
         (push head calls)
         :command-island))
      (expect calls :to-be-null)))

  (it "reports-empty-unclosed-and-invalid-lists-without-classifying-an-empty-head"
    (let ((calls nil)
          (empty-result nil)
          (open-result nil)
          (invalid-result nil))
      (setf empty-result
            (nshell.domain.parsing:scan-input
             "()"
             :cursor 1
             :reader-context :sexp
             :head-classifier
             (lambda (head)
               (push head calls)
               :command-island)))
      (setf open-result
            (nshell.domain.parsing:scan-input
             "("
             :reader-context :sexp
             :head-classifier
             (lambda (head)
               (push head calls)
               :command-island)))
      (setf invalid-result
            (nshell.domain.parsing:scan-input
             ")"
             :reader-context :sexp
             :head-classifier
             (lambda (head)
               (push head calls)
               :command-island)))
      (expect calls :to-be-null)
      (expect :complete :to-be
              (nshell.domain.parsing:scan-result-status empty-result))
      (expect :host-form :to-be
              (nshell.domain.parsing:scan-result-cursor-role empty-result))
      (expect :incomplete :to-be
              (nshell.domain.parsing:scan-result-status open-result))
      (expect (list 1 1) :to-equal
              (nshell.domain.parsing:scan-result-incomplete-span open-result))
      (expect :command-head :to-be
              (nshell.domain.parsing:scan-result-cursor-role open-result))
      (expect :invalid :to-be
              (nshell.domain.parsing:scan-result-status invalid-result))
      (expect (list 0 1) :to-equal
              (nshell.domain.parsing:scan-result-invalid-span invalid-result))
      (expect (nshell.domain.parsing:scan-result-incomplete-span invalid-result) :to-be-null)))

  (it "carries-top-level-reader-prefixes-through-their-operands"
    (dolist (source '("'x" "#'f" "'(x)" ", (echo status)"))
      (let ((result
              (nshell.domain.parsing:scan-input
               source
               :reader-context :sexp
               :head-classifier #'%sexp-scanner-test-head-classifier)))
        (expect :complete :to-be
                (nshell.domain.parsing:scan-result-status result))
        (expect (nshell.domain.parsing:scan-result-incomplete-span result) :to-be-null)))
    (let ((incomplete-prefix
            (nshell.domain.parsing:scan-input
             "'"
             :reader-context :sexp
             :head-classifier #'%sexp-scanner-test-head-classifier)))
      (expect :incomplete :to-be
              (nshell.domain.parsing:scan-result-status incomplete-prefix))))

  (it "recognizes-host-character-literals-with-delimiter-characters"
    (let* ((result
             (nshell.domain.parsing:scan-input
              "#\\)"
              :reader-context :sexp
              :head-classifier #'%sexp-scanner-test-head-classifier))
           (token (first (nshell.domain.parsing:scan-result-tokens result))))
      (expect :complete :to-be
              (nshell.domain.parsing:scan-result-status result))
      (expect :character-literal :to-be
              (nshell.domain.parsing:scan-token-kind token))
      (expect "#\\)" :to-equal
              (nshell.domain.parsing:scan-token-text token))))

  (it "tokenizes-bare-line-pipelines-separators-and-redirects"
    (let* ((pipeline-result
             (nshell.domain.parsing:scan-input
              "echo arg | cat; done"
              :reader-context :bare-line))
           (pipeline-kinds
             (mapcar #'nshell.domain.parsing:scan-token-kind
                     (nshell.domain.parsing:scan-result-tokens pipeline-result)))
           (redirect-result
             (nshell.domain.parsing:scan-input
              "echo > out"
              :reader-context :bare-line
              :cursor 6))
           (redirect-token
             (find :redirect
                   (nshell.domain.parsing:scan-result-tokens redirect-result)
                   :key #'nshell.domain.parsing:scan-token-kind)))
      (expect :complete :to-be
              (nshell.domain.parsing:scan-result-status pipeline-result))
      (expect '(:command-head :whitespace :argument :whitespace :pipeline
                :whitespace :command-head :sequence-separator :whitespace
                :command-head)
              :to-equal pipeline-kinds)
      (expect :complete :to-be
              (nshell.domain.parsing:scan-result-status redirect-result))
      (expect ">" :to-equal
              (nshell.domain.parsing:scan-token-text redirect-token))
      (expect :redirect-target :to-be
              (nshell.domain.parsing:scan-result-cursor-role redirect-result))))
  (it "decodes-common-lisp-string-escapes-in-here-doc-delimiters"
    (let* ((source (format nil "(echo <<\"E\\OF\"~%body~%EOF~%)"))
           (result
             (nshell.domain.parsing:scan-input
              source
              :reader-context :sexp
              :head-classifier #'%sexp-scanner-test-head-classifier))
           (tokens (nshell.domain.parsing:scan-result-tokens result))
           (delimiters
             (remove-if-not
              (lambda (token)
                (eq (nshell.domain.parsing:scan-token-kind token)
                    :here-doc-delimiter))
              tokens))
           (body
             (find :here-doc-body
                   tokens
                   :key #'nshell.domain.parsing:scan-token-kind)))
      (expect :complete :to-be
              (nshell.domain.parsing:scan-result-status result))
      (expect '("\"E\\OF\"" "EOF") :to-equal
              (mapcar #'nshell.domain.parsing:scan-token-text delimiters))
      (expect (format nil "body~%") :to-equal
              (nshell.domain.parsing:scan-token-text body))))
  (it "scans-a-long-numeric-bare-token-with-its-full-span"
      (let* ((source (make-string 65536 :initial-element (char "7" 0)))
             (result
              (nshell.domain.parsing:scan-input
               source
               :reader-context :bare-line))
             (token (first (nshell.domain.parsing:scan-result-tokens result))))
        (expect :complete :to-be
                (nshell.domain.parsing:scan-result-status result))
        (expect :command-head :to-be
                (nshell.domain.parsing:scan-token-kind token))
        (expect source :to-equal
                (nshell.domain.parsing:scan-token-text token))
        (expect (list 0 (length source)) :to-equal
                (nshell.domain.parsing:scan-token-span token))))
  (it "reports-definite-invalidity-before-later-incompleteness"
      (let ((result
             (nshell.domain.parsing:scan-input
              "(echo ) ) ("
              :reader-context :sexp
              :head-classifier (function %sexp-scanner-test-head-classifier))))
        (expect :invalid :to-be
                (nshell.domain.parsing:scan-result-status result))
        (expect (list 8 9) :to-equal
                (nshell.domain.parsing:scan-result-invalid-span result))
        (expect (nshell.domain.parsing:scan-result-incomplete-span result) :to-be-null)))
  (it "keeps-delimiters-opaque-in-host-strings-and-comments"
      (dolist (case
                  (list
                   (list "(host \")\")" :string)
                   (list (format nil "(host x ; )~%y)") :line-comment)
                   (list "(host #| ) ( #| ) |# ( |# x)" :block-comment)
                   (list "(host |)| x)" :escaped-symbol)))
        (let* ((result
                (nshell.domain.parsing:scan-input
                 (first case)
                 :reader-context :sexp
                 :head-classifier
                 (lambda (head)
                   (declare (ignore head))
                   :host-form)))
               (tokens (nshell.domain.parsing:scan-result-tokens result))
               (opaque-token
                (find (second case) tokens
                      :key (function nshell.domain.parsing:scan-token-kind))))
          (expect :complete :to-be
                  (nshell.domain.parsing:scan-result-status result))
          (expect (second case) :to-be
                  (nshell.domain.parsing:scan-token-kind opaque-token))
          (expect 1 :to-equal
                  (length (nshell.domain.parsing:scan-result-delimiter-pairs
                           result))))))
  (it "keeps-full-buffer-scan-data-independent-of-cursor"
      (labels ((token-signature (token)
                                (list (nshell.domain.parsing:scan-token-kind token)
                                      (nshell.domain.parsing:scan-token-text token)
                                      (nshell.domain.parsing:scan-token-span token)
                                      (nshell.domain.parsing:scan-token-reader-context token)))
               (pair-signature (pair)
                               (list (nshell.domain.parsing:delimiter-pair-open-span pair)
                                     (nshell.domain.parsing:delimiter-pair-close-span pair))))
        (let* ((source "(echo arg)")
               (results
                (mapcar
                 (lambda (cursor)
                   (nshell.domain.parsing:scan-input
                    source
                    :cursor cursor
                    :reader-context :sexp
                    :head-classifier (function %sexp-scanner-test-head-classifier)))
                 (list 1 5 6)))
               (first-result (first results))
               (tokens
                (mapcar (function token-signature)
                        (nshell.domain.parsing:scan-result-tokens first-result)))
               (pairs
                (mapcar (function pair-signature)
                        (nshell.domain.parsing:scan-result-delimiter-pairs
                         first-result))))
          (expect :complete :to-be
                  (nshell.domain.parsing:scan-result-status first-result))
          (expect :command-head :to-be
                  (nshell.domain.parsing:scan-result-cursor-role first-result))
          (expect :argument :to-be
                  (nshell.domain.parsing:scan-result-cursor-role (second results)))
          (dolist (result (rest results))
            (expect :complete :to-be
                    (nshell.domain.parsing:scan-result-status result))
            (expect tokens :to-equal
                    (mapcar (function token-signature)
                            (nshell.domain.parsing:scan-result-tokens result)))
            (expect pairs :to-equal
                    (mapcar (function pair-signature)
                            (nshell.domain.parsing:scan-result-delimiter-pairs
                             result)))))))
  (it "does-not-classify-an-unclosed-bar-escaped-list-head"
      (let* ((calls nil)
             (result
              (nshell.domain.parsing:scan-input
               "(|unfinished"
               :reader-context :sexp
               :head-classifier
               (lambda (head)
                 (push head calls)
                 :command-island)))
             (tokens (nshell.domain.parsing:scan-result-tokens result))
             (escaped-symbol
              (find :escaped-symbol tokens
                    :key (function nshell.domain.parsing:scan-token-kind))))
        (expect :incomplete :to-be
                (nshell.domain.parsing:scan-result-status result))
        (expect calls :to-be-null)
        (expect :escaped-symbol :to-be
                (nshell.domain.parsing:scan-token-kind escaped-symbol))))
  (it "keeps-single-escaped-host-atom-delimiters-inside-the-atom"
      (let* ((close-source "(foo\\)bar)")
             (close-result
              (nshell.domain.parsing:scan-input
               close-source
               :reader-context :sexp
               :head-classifier (function %sexp-scanner-test-head-classifier)))
             (close-atoms
              (remove-if-not
               (lambda (token)
                 (eq (nshell.domain.parsing:scan-token-kind token) :host-form))
               (nshell.domain.parsing:scan-result-tokens close-result)))
             (space-source "(foo\\ bar baz)")
             (space-result
              (nshell.domain.parsing:scan-input
               space-source
               :reader-context :sexp
               :head-classifier (function %sexp-scanner-test-head-classifier)))
             (space-atoms
              (remove-if-not
               (lambda (token)
                 (eq (nshell.domain.parsing:scan-token-kind token) :host-form))
               (nshell.domain.parsing:scan-result-tokens space-result))))
        (expect :complete :to-be
                (nshell.domain.parsing:scan-result-status close-result))
        (expect (list "foo\\)bar")
                :to-equal
                (mapcar (function nshell.domain.parsing:scan-token-text)
                        close-atoms))
        (expect (list (list 1 9))
                :to-equal
                (mapcar (function nshell.domain.parsing:scan-token-span)
                        close-atoms))
        (expect (list (list 9 10))
                :to-equal
                (mapcar (function nshell.domain.parsing:delimiter-pair-close-span)
                        (nshell.domain.parsing:scan-result-delimiter-pairs
                         close-result)))
        (expect :complete :to-be
                (nshell.domain.parsing:scan-result-status space-result))
        (expect (list "foo\\ bar" "baz")
                :to-equal
                (mapcar (function nshell.domain.parsing:scan-token-text)
                        space-atoms))
        (expect (list (list 1 9) (list 10 13))
                :to-equal
                (mapcar (function nshell.domain.parsing:scan-token-span)
                        space-atoms))))
  (it "aligns-unfinished-constructs-at-EOF-using-the-cursor-prefix"
    (dolist (source '("  \"open" "  |open" "  #|open"))
      (let* ((before-opener
               (nshell.domain.parsing:scan-input
                source
                :cursor 2
                :reader-context :sexp
                :head-classifier #'%sexp-scanner-test-head-classifier))
             (at-eof
               (nshell.domain.parsing:scan-input
                source
                :reader-context :sexp
                :head-classifier #'%sexp-scanner-test-head-classifier)))
        (expect 0 :to-equal
                (nshell.domain.parsing:scan-result-next-indent before-opener))
        (expect :incomplete :to-be
                (nshell.domain.parsing:scan-result-status at-eof))
        (expect 2 :to-equal
                (nshell.domain.parsing:scan-result-next-indent at-eof))))
    (let* ((source "  \"closed\"")
           (before-close
             (nshell.domain.parsing:scan-input
              source
              :cursor 9
              :reader-context :sexp
              :head-classifier #'%sexp-scanner-test-head-classifier))
           (after-close
             (nshell.domain.parsing:scan-input
              source
              :reader-context :sexp
              :head-classifier #'%sexp-scanner-test-head-classifier)))
      (expect 2 :to-equal
              (nshell.domain.parsing:scan-result-next-indent before-close))
      (expect 0 :to-equal
              (nshell.domain.parsing:scan-result-next-indent after-close))))
  (it "matches-quoted-bare-line-here-doc-delimiter-values"
    (dolist (case
             (list
              (list (format nil "cat <<'E\\OF'~%body~%E\\OF")
                    (list "'E\\OF'" "E\\OF"))
              (list (format nil "cat <<\"E\\\"OF\"~%body~%E\"OF")
                    (list "\"E\\\"OF\"" "E\"OF"))))
      (let* ((source (first case))
             (expected-delimiters (second case))
             (result
               (nshell.domain.parsing:scan-input
                source
                :reader-context :bare-line))
             (tokens (nshell.domain.parsing:scan-result-tokens result))
             (delimiters
               (remove-if-not
                (lambda (token)
                  (eq (nshell.domain.parsing:scan-token-kind token)
                      :here-doc-delimiter))
                tokens))
             (body
               (find :here-doc-body
                     tokens
                     :key #'nshell.domain.parsing:scan-token-kind)))
        (expect :complete :to-be
                (nshell.domain.parsing:scan-result-status result))
        (expect expected-delimiters :to-equal
                (mapcar #'nshell.domain.parsing:scan-token-text delimiters))
        (expect (format nil "body~%") :to-equal
                (nshell.domain.parsing:scan-token-text body)))))

  (it "indents-at-a-close-delimiter-using-the-frame-open-in-the-cursor-prefix"
    (let* ((source "(echo
    (x
    )")
           (cursor (position #\) source :from-end t))
           (result
             (nshell.domain.parsing:scan-input
              source
              :cursor cursor
              :reader-context :sexp
              :head-classifier #'%sexp-scanner-test-head-classifier)))
      (expect 4 :to-equal
              (nshell.domain.parsing:scan-result-next-indent result))))

  (it "scans-a-fixed-seed-131072-byte-input-to-an-explicit-status"
    (let* ((source (%sexp-scanner-fixed-byte-string 131072))
           (result
             (nshell.domain.parsing:scan-input
              source
              :reader-context :bare-line)))
      (expect 131072 :to-equal (length source))
      (expect (member (nshell.domain.parsing:scan-result-status result)
                      '(:complete :incomplete :invalid)) :to-be-truthy))))
