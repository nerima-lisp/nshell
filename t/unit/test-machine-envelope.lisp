(in-package #:nshell/test)

;;; Every machine-interface response is built by a builder in
;;; nshell.feature.machine:+envelope-response-kinds+ and written by
;;; envelope-to-json. These tests validate that written JSON, parsed back,
;;; against docs/design/conformance/envelope.schema.json with cl-json-kit's
;;; validator.

(defun machine-envelope-schema ()
  (json-kit:parse
   (uiop:read-file-string
    (merge-pathnames "docs/design/conformance/envelope.schema.json"
                     (uiop:pathname-directory-pathname
                      (asdf:system-source-file (asdf:find-system "nshell"))))
    :external-format :utf-8)))

(defun machine-envelope-parse (envelope)
  (json-kit:parse (nshell.feature.machine:envelope-to-json envelope)))

(defun machine-envelope-failures (value)
  "Return the schema failures of decoded VALUE; NIL means it is valid."
  (nth-value 1 (json-kit:validate-schema value (machine-envelope-schema))))

(defun machine-envelope-schema-at (&rest keys)
  (let ((node (machine-envelope-schema)))
    (dolist (key keys node)
      (setf node (gethash key node)))))

(defun machine-envelope-same-set-p (left right)
  (and (null (set-difference left right :test #'equal))
       (null (set-difference right left :test #'equal))))

(defun machine-envelope-parts ()
  "Common keyword arguments for the builders: empty output, a read effect, a
safe verdict and a cwd."
  (list :duration-ms 3
        :stdout (nshell.feature.machine:output-from-text "")
        :stderr (nshell.feature.machine:output-from-text "")
        :effects (list (nshell.feature.machine:make-envelope-effect
                        :kind :reads :path "."))
        :safety (nshell.feature.machine:make-envelope-safety :level :safe)
        :state (nshell.feature.machine:make-envelope-state :cwd "/tmp")))

(defun machine-envelope-explain-parts ()
  (let ((parts (machine-envelope-parts)))
    (list* :forms (list (nshell.feature.machine:make-envelope-form
                         :text "(sort data.txt)" :kind "command"))
           (loop for (key value) on parts by #'cddr
                 unless (member key '(:stdout :stderr))
                   append (list key value)))))

(defparameter +machine-envelope-samples+
  (list (cons :result
              (lambda ()
                (apply #'nshell.feature.machine:result-envelope
                       (machine-envelope-parts))))
        (cons :error
              (lambda ()
                (apply #'nshell.feature.machine:error-envelope
                       "E_COMMAND_NOT_FOUND" (machine-envelope-parts))))
        (cons :explain
              (lambda ()
                (apply #'nshell.feature.machine:explain-envelope
                       (machine-envelope-explain-parts)))))
  "One schema sample per response kind. A kind added to
+ENVELOPE-RESPONSE-KINDS+ without an entry here fails the coverage test.")

(defun machine-envelope-sample (kind)
  (funcall (cdr (assoc kind +machine-envelope-samples+))))

(defun machine-envelope-full-sample ()
  "An error envelope with every optional key filled and non-ASCII text."
  (nshell.feature.machine:error-envelope
   "E_COMMAND_FAILED"
   :status 2
   :message "コマンドが失敗した ✗"
   :span (nshell.feature.machine:make-envelope-span :line 1 :column 1 :end 4)
   :fixes (list (nshell.feature.machine:make-envelope-fix
                 :input "git status" :why "edit distance 1" :rule "diagnose/typo"))
   :duration-ms 2140
   :stdout (nshell.feature.machine:make-envelope-output
            :text "先頭…末尾\n" :bytes 418233 :lines 9120 :truncated t
            :path "/tmp/nshell/out/s_4b1/12.txt")
   :stderr (nshell.feature.machine:output-from-text "警告: ü\n")
   :effects (list (nshell.feature.machine:make-envelope-effect
                   :kind :deletes :path "target/" :size "1.2 GB")
                  (nshell.feature.machine:make-envelope-effect
                   :kind :writes :path "result/" :size 4096)
                  (nshell.feature.machine:make-envelope-effect :kind :network))
   :safety (nshell.feature.machine:make-envelope-safety
            :level :confirm
            :reasons (list (nshell.feature.machine:make-envelope-reason
                            :rule "classify/delete-dir" :text "recursive delete")))
   :state (nshell.feature.machine:make-envelope-state
           :cwd "/tmp/データ" :env-changed '("PATH")
           :jobs (list '(("id" . 1) ("command" . "sleep 10") ("state" . "running")))
           :last-status 2)
   :warnings (mapcar (lambda (code)
                       (nshell.feature.machine:make-envelope-warning
                        :code code :message "移行の警告"
                        :fixes (list (nshell.feature.machine:make-envelope-fix
                                      :input "(status (cmd))"))))
                     (nshell.feature.machine:envelope-warning-codes))
   :session "s_4b1"
   :seq 12))

(describe "machine-envelope-schema"
  (it "schema-error-code-enum-equals-the-error-code-table"
    "error.code lists exactly the E_ codes of data/domain/error-codes-data.lisp."
    (let ((schema-codes (coerce (machine-envelope-schema-at
                                 "properties" "error" "properties" "code" "enum")
                                'list))
          (table-codes (nshell.feature.machine:envelope-error-codes)))
      (expect (plusp (length table-codes)) :to-be-truthy)
      (expect (set-difference schema-codes table-codes :test #'equal) :to-be-null)
      (expect (set-difference table-codes schema-codes :test #'equal) :to-be-null)
      (expect schema-codes :to-equal table-codes)))

  (it "schema-warning-code-enum-equals-the-error-code-table"
    "warnings[].code lists exactly the W_ codes of the table."
    (let ((schema-codes (coerce (machine-envelope-schema-at
                                 "properties" "warnings" "items"
                                 "properties" "code" "enum")
                                'list))
          (table-codes (nshell.feature.machine:envelope-warning-codes)))
      (expect (plusp (length table-codes)) :to-be-truthy)
      (expect (machine-envelope-same-set-p schema-codes table-codes) :to-be-truthy)
      (expect schema-codes :to-equal table-codes)))

  (it "schema-enums-match-the-builder-enums"
    "effects[].kind and safety.level list exactly what the builders accept."
    (flet ((names (keywords)
             (mapcar (lambda (keyword) (string-downcase (symbol-name keyword)))
                     keywords)))
      (expect (coerce (machine-envelope-schema-at
                       "properties" "effects" "items" "properties" "kind" "enum")
                      'list)
              :to-equal (names nshell.feature.machine:+effect-kinds+))
      (expect (coerce (machine-envelope-schema-at
                       "properties" "safety" "properties" "level" "enum")
                      'list)
              :to-equal (names nshell.feature.machine:+safety-levels+))))

  (it "schema-requires-the-nine-always-present-keys-and-allows-others"
    "D-70: nine required keys; the top level stays open."
    (expect (coerce (machine-envelope-schema-at "required") 'list)
            :to-equal '("nshell_api" "ok" "status" "duration_ms" "stdout"
                        "stderr" "effects" "safety" "state"))
    (expect (machine-envelope-schema-at "additionalProperties") :to-be t))

  (it "every-response-kind-has-a-schema-sample"
    "The builders form a closed set and each one has a sample in this file."
    (expect (machine-envelope-same-set-p
             (mapcar #'car nshell.feature.machine:+envelope-response-kinds+)
             (mapcar #'car +machine-envelope-samples+))
            :to-be-truthy)
    (dolist (entry nshell.feature.machine:+envelope-response-kinds+)
      (let ((kind (car entry)))
        (expect (list kind (machine-envelope-failures
                            (machine-envelope-parse (machine-envelope-sample kind))))
                :to-equal (list kind nil))
        (expect (list kind (machine-envelope-failures
                            (machine-envelope-parse
                             (apply #'nshell.feature.machine:build-envelope-response
                                    kind
                                    (append
                                     (if (eq kind :error) (list "E_PARSE") nil)
                                     (if (eq kind :explain)
                                         (machine-envelope-explain-parts)
                                         (machine-envelope-parts)))))))
                :to-equal (list kind nil)))))

  (it "every-error-code-builds-a-valid-envelope-with-its-exit-status"
    "Each E_ code gives ok false and the table's exit status."
    (dolist (code (nshell.feature.machine:envelope-error-codes))
      (let* ((child-p (eq :child (nshell.domain.error-codes:error-code-exit-code
                                  (nshell.domain.error-codes:find-error-code code))))
             (envelope (apply #'nshell.feature.machine:error-envelope code
                              (append (if child-p (list :status 2) nil)
                                      (machine-envelope-parts))))
             (parsed (machine-envelope-parse envelope)))
        (expect (list code (machine-envelope-failures parsed))
                :to-equal (list code nil))
        (expect (list code (gethash "status" parsed))
                :to-equal
                (list code (if child-p
                               2
                               (nshell.domain.error-codes:error-code-exit-code
                                (nshell.domain.error-codes:find-error-code code)))))
        (expect (json-kit:json-false-p (gethash "ok" parsed)) :to-be-truthy)
        (expect (gethash "code" (gethash "error" parsed)) :to-equal code))))

  (it "every-status-value-validates-and-sets-ok"
    "ok is true exactly when status is 0 and there is no error."
    (let ((statuses (remove-duplicates
                     (append '(0 1 2 124 126 127 130 255)
                             (loop for entry in nshell.domain.error-codes:+error-codes+
                                   for status = (nshell.domain.error-codes:error-code-exit-code entry)
                                   when (integerp status) collect status)))))
      (dolist (status statuses)
        (let ((parsed (machine-envelope-parse
                       (apply #'nshell.feature.machine:result-envelope
                              :status status (machine-envelope-parts)))))
          (expect (list status (machine-envelope-failures parsed))
                  :to-equal (list status nil))
          (expect (list status (eq t (gethash "ok" parsed)))
                  :to-equal (list status (zerop status)))))))

  (it "empty-output-is-written-with-zero-counts"
    "Empty stdout and stderr still carry text, bytes and lines."
    (let ((parsed (machine-envelope-parse (machine-envelope-sample :result))))
      (dolist (key '("stdout" "stderr"))
        (let ((output (gethash key parsed)))
          (expect (list key (gethash "text" output) (gethash "bytes" output)
                        (gethash "lines" output)
                        (json-kit:json-false-p (gethash "truncated" output)))
                  :to-equal (list key "" 0 0 t))))))

  (it "optional-keys-are-absent-unless-given"
    "A minimal envelope writes only the always-present keys, in U6 order."
    (expect (mapcar #'car (json-kit:parse
                           (nshell.feature.machine:envelope-to-json
                            (machine-envelope-sample :result))
                           :object-type :alist))
            :to-equal '("nshell_api" "ok" "status" "duration_ms" "stdout"
                        "stderr" "effects" "safety" "state")))

  (it "optional-keys-are-present-and-valid-when-given"
    "Every optional key, all W_ codes, and non-ASCII text pass the schema."
    (let* ((envelope (machine-envelope-full-sample))
           (parsed (machine-envelope-parse envelope)))
      (expect (machine-envelope-failures parsed) :to-be-null)
      (expect (mapcar #'car (json-kit:parse
                             (nshell.feature.machine:envelope-to-json envelope)
                             :object-type :alist))
              :to-equal '("nshell_api" "ok" "status" "duration_ms" "stdout"
                          "stderr" "error" "warnings" "effects" "safety"
                          "state" "session" "seq"))
      (expect (length (gethash "warnings" parsed))
              :to-equal (length (nshell.feature.machine:envelope-warning-codes)))
      (expect (gethash "message" (gethash "error" parsed))
              :to-equal "コマンドが失敗した ✗")
      (expect (gethash "cwd" (gethash "state" parsed)) :to-equal "/tmp/データ")
      (expect (gethash "bytes" (gethash "stderr" parsed))
              :to-equal (length (sb-ext:string-to-octets "警告: ü\n"
                                                         :external-format :utf-8)))
      (expect (gethash "size" (aref (gethash "effects" parsed) 0)) :to-equal "1.2 GB")
      (expect (gethash "size" (aref (gethash "effects" parsed) 1)) :to-equal 4096)))

  (it "explain-forms-write-a-null-rule-and-value-may-be-null"
    "P1 explain writes rule as null; a JSON null value is still a value."
    (let* ((explain (machine-envelope-parse (machine-envelope-sample :explain)))
           (form (aref (gethash "forms" explain) 0))
           (with-value (machine-envelope-parse
                        (apply #'nshell.feature.machine:result-envelope
                               :value json-kit:+json-null+
                               (machine-envelope-parts)))))
      (expect (machine-envelope-failures explain) :to-be-null)
      (expect (json-kit:json-null-p (gethash "rule" form)) :to-be-truthy)
      (expect (machine-envelope-failures with-value) :to-be-null)
      (expect (nth-value 1 (gethash "value" with-value)) :to-be-truthy)
      (expect (json-kit:json-null-p (gethash "value" with-value)) :to-be-truthy)))

  (it "design-examples-with-every-required-key-validate"
    "The ux/U6 build example and the proposal/02 --json example pass."
    (dolist (text
             '("{\"nshell_api\": 1, \"ok\": true, \"status\": 0, \"duration_ms\": 2140,
 \"stdout\": {\"text\": \"Compiling nshell…\\n…\\nok 812 tests\\n\",
            \"bytes\": 418233, \"lines\": 9120, \"truncated\": true,
            \"path\": \"/home/me/.cache/nshell/out/s_4b1/12.txt\"},
 \"stderr\": {\"text\": \"\", \"bytes\": 0},
 \"effects\": [{\"kind\": \"writes\", \"path\": \"result/\"}],
 \"safety\": {\"level\": \"safe\", \"reasons\": []},
 \"state\": {\"cwd\": \"/home/me/src/nshell\", \"env_changed\": []},
 \"session\": \"s_4b1\", \"seq\": 12}"
               "{\"nshell_api\": 1, \"ok\": true, \"status\": 0, \"duration_ms\": 41,
 \"stdout\": {\"text\": \"3\\n\", \"bytes\": 2, \"lines\": 1,
            \"truncated\": false},
 \"stderr\": {\"text\": \"\", \"bytes\": 0},
 \"effects\": [{\"kind\": \"reads\", \"path\": \".\"}],
 \"safety\": {\"level\": \"safe\", \"reasons\": []},
 \"state\": {\"cwd\": \"/home/me/src/nshell\"}}"))
      (expect (machine-envelope-failures (json-kit:parse text)) :to-be-null))))

(describe "machine-envelope-schema-rejections"
  (it "unknown-top-level-keys-are-accepted"
    "additionalProperties is true at the top level, as for U7's approval."
    (let ((parsed (machine-envelope-parse (machine-envelope-sample :error)))
          (approval (make-hash-table :test #'equal)))
      (setf (gethash "id" approval) "ap_7f3a09c4e1b2d658"
            (gethash "approval" parsed) approval
            (gethash "x_future" parsed) 1)
      (expect (machine-envelope-failures parsed) :to-be-null)))

  (it "each-missing-required-key-is-rejected"
    "Removing any one always-present key fails at that key."
    (dolist (key (coerce (machine-envelope-schema-at "required") 'list))
      (let ((parsed (machine-envelope-parse (machine-envelope-sample :result))))
        (remhash key parsed)
        (expect (list key (and (member (concatenate 'string "/" key)
                                       (machine-envelope-failures parsed)
                                       :key (lambda (failure) (getf failure :path))
                                       :test #'string=)
                               t))
                :to-equal (list key t)))))

  (it "unknown-or-warning-error-codes-are-rejected"
    "error.code outside the E_ list fails, in the schema and in the builder."
    (dolist (code '("E_NO_SUCH_CODE" "W_NO_MATCH" "e_parse" ""))
      (let ((parsed (machine-envelope-parse (machine-envelope-sample :error))))
        (setf (gethash "code" (gethash "error" parsed)) code)
        (expect (list code (null (machine-envelope-failures parsed)))
                :to-equal (list code nil)))
      (expect (lambda ()
                (apply #'nshell.feature.machine:error-envelope code
                       (machine-envelope-parts)))
              :to-throw 'nshell.feature.machine:invalid-envelope))
    (expect (lambda ()
              (nshell.feature.machine:envelope-to-json
               (apply #'nshell.feature.machine:result-envelope
                      :warnings (list (nshell.feature.machine:make-envelope-warning
                                       :code "E_PARSE"))
                      (machine-envelope-parts))))
            :to-throw 'nshell.feature.machine:invalid-envelope))

  (it "inconsistent-ok-and-wrong-types-are-rejected"
    "ok true needs status 0 and no error; values must have their U6 types."
    (flet ((rejected-p (mutate)
             (let ((parsed (machine-envelope-parse (machine-envelope-sample :result))))
               (funcall mutate parsed)
               (not (null (machine-envelope-failures parsed))))))
      (expect (rejected-p (lambda (p) (setf (gethash "status" p) 1))) :to-be-truthy)
      (expect (rejected-p (lambda (p)
                            (setf (gethash "error" p)
                                  (gethash "error" (machine-envelope-parse
                                                    (machine-envelope-sample :error))))))
              :to-be-truthy)
      (expect (rejected-p (lambda (p) (setf (gethash "nshell_api" p) 2))) :to-be-truthy)
      (expect (rejected-p (lambda (p) (setf (gethash "ok" p) "true"))) :to-be-truthy)
      (expect (rejected-p (lambda (p) (setf (gethash "status" p) "0"))) :to-be-truthy)
      (expect (rejected-p (lambda (p)
                            (setf (gethash "level" (gethash "safety" p)) "unknown")))
              :to-be-truthy)
      (expect (rejected-p (lambda (p)
                            (setf (gethash "kind" (aref (gethash "effects" p) 0))
                                  "executes")))
              :to-be-truthy)
      (expect (rejected-p (lambda (p) (remhash "cwd" (gethash "state" p))))
              :to-be-truthy)
      (expect (rejected-p (lambda (p) (remhash "bytes" (gethash "stdout" p))))
              :to-be-truthy)))

  (it "ok-agrees-with-status-and-error-through-the-one-of"
    "ok is true exactly when status is 0 and there is no error. A
disagreement fails the top-level oneOf and nothing else; a failure with ok
false needs only a non-zero status or an error, not both."
    (flet ((failures-after (kind mutate)
             (let ((parsed (machine-envelope-parse (machine-envelope-sample kind))))
               (funcall mutate parsed)
               (machine-envelope-failures parsed)))
           (one-of-failure-p (failures &rest fragments)
             (and (= 1 (length failures))
                  (string= "" (getf (first failures) :path))
                  (let ((reason (getf (first failures) :reason)))
                    (and (eql 0 (search "oneOf matched 0 schemas" reason))
                         (every (lambda (fragment) (search fragment reason))
                                fragments)))
                  t)))
      (let ((error-object (gethash "error" (machine-envelope-parse
                                            (machine-envelope-sample :error)))))
        (expect (one-of-failure-p
                 (failures-after :result (lambda (p) (setf (gethash "status" p) 1)))
                 "branch 0 [path \"/status\": Value is not in enum]"
                 "branch 1 [path \"/ok\": Value is not in enum]")
                :to-be-truthy)
        (expect (one-of-failure-p
                 (failures-after :result
                                 (lambda (p) (setf (gethash "error" p) error-object)))
                 "branch 0 [path \"/error\": Value does not match the allowed type]"
                 "branch 1 [path \"/ok\": Value is not in enum]")
                :to-be-truthy)
        (expect (one-of-failure-p
                 (failures-after :result
                                 (lambda (p) (setf (gethash "ok" p) json-kit:+json-false+)))
                 "branch 0 [path \"/ok\": Value is not in enum]"
                 "branch 1 [path \"\": oneOf matched 2 schemas")
                :to-be-truthy)
        (expect (one-of-failure-p
                 (failures-after :result
                                 (lambda (p)
                                   (setf (gethash "ok" p) json-kit:+json-false+
                                         (gethash "error" p) json-kit:+json-null+)))
                 "branch 0 [path \"/ok\": Value is not in enum]"
                 "branch 1 [path \"\": oneOf matched 2 schemas")
                :to-be-truthy)
        (expect (failures-after :result
                                (lambda (p)
                                  (setf (gethash "ok" p) json-kit:+json-false+
                                        (gethash "status" p) 1)))
                :to-be-null)
        (expect (failures-after :error (lambda (p) (setf (gethash "status" p) 0)))
                :to-be-null)
        ;; An error written as null counts as no error.
        (expect (failures-after :result
                                (lambda (p) (setf (gethash "error" p) json-kit:+json-null+)))
                :to-be-null)
        (dolist (status '(1 -1))
          (expect (list status
                        (failures-after :result
                                        (lambda (p)
                                          (setf (gethash "ok" p) json-kit:+json-false+
                                                (gethash "status" p) status
                                                (gethash "error" p) json-kit:+json-null+))))
                  :to-equal (list status nil))))))

  (it "builders-reject-malformed-parts"
    "Builders and the JSON conversion signal INVALID-ENVELOPE instead of
writing JSON the schema would reject."
    (flet ((writing (&rest overrides)
             (lambda ()
               (nshell.feature.machine:envelope-to-json
                (apply #'nshell.feature.machine:result-envelope
                       (append overrides (machine-envelope-parts)))))))
      (expect (writing :effects (list (nshell.feature.machine:make-envelope-effect
                                       :kind :executes)))
              :to-throw 'nshell.feature.machine:invalid-envelope)
      (expect (writing :safety (nshell.feature.machine:make-envelope-safety
                                :level :maybe))
              :to-throw 'nshell.feature.machine:invalid-envelope)
      (expect (writing :status "0")
              :to-throw 'nshell.feature.machine:invalid-envelope)
      (expect (writing :state (nshell.feature.machine:make-envelope-state
                               :cwd "/tmp" :jobs (list "sleep 10")))
              :to-throw 'nshell.feature.machine:invalid-envelope))
    (expect (lambda ()
              (nshell.feature.machine:result-envelope
               :duration-ms 1
               :stdout (nshell.feature.machine:output-from-text "")
               :stderr (nshell.feature.machine:output-from-text "")
               :state (nshell.feature.machine:make-envelope-state :cwd "/tmp")))
            :to-throw 'nshell.feature.machine:invalid-envelope)
    (expect (lambda ()
              (apply #'nshell.feature.machine:error-envelope "E_COMMAND_FAILED"
                     (machine-envelope-parts)))
            :to-throw 'nshell.feature.machine:invalid-envelope)
    (expect (lambda ()
              (apply #'nshell.feature.machine:error-envelope "E_COMMAND_FAILED"
                     :status 0 (machine-envelope-parts)))
            :to-throw 'nshell.feature.machine:invalid-envelope)
    (expect (lambda ()
              (apply #'nshell.feature.machine:error-envelope "E_TIMEOUT"
                     :status 1 (machine-envelope-parts)))
            :to-throw 'nshell.feature.machine:invalid-envelope)
    (expect (lambda ()
              (nshell.feature.machine:build-envelope-response :stream))
            :to-throw 'nshell.feature.machine:invalid-envelope)))
