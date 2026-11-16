(in-package #:nshell/spec)

;;; Fixture access

(defparameter *probe-fixture-path*
  (merge-pathnames #p"docs/design/conformance/language-probes-v0.7.0.json"
                   (asdf:system-source-directory "nshell")))

(defvar *probe-fixture-cache* nil)

(defun %read-probe-fixture ()
  (with-open-file (stream *probe-fixture-path*
                          :direction :input
                          :external-format :utf-8)
    (json-kit:read-json stream :object-type :alist :array-type :list)))

(defun %probe-fixture ()
  (or *probe-fixture-cache*
      (setf *probe-fixture-cache* (%read-probe-fixture))))

(defun %field (object key)
  (cdr (assoc key object :test #'string=)))

(defun %fixture-cases ()
  (%field (%probe-fixture) "cases"))

(defun %fixture-case (id)
  (or (find id (%fixture-cases)
            :key (lambda (case) (%field case "id"))
            :test #'string=)
      (error "No language-probe fixture case named ~a" id)))

(defun %probe-ids-at-expansion ()
  (let ((cases (%fixture-cases)))
    (unless (= 151 (length cases))
      (error "Expected 151 language probes, found ~d" (length cases)))
    (mapcar (lambda (case) (%field case "id")) cases)))

;;; Environment

(defun %required-nshell-bin ()
  (or (uiop:getenv "NSHELL_BIN")
      (error "NSHELL_BIN must name the nshell script-mode executable")))

(defun %required-single-bin-path ()
  (let* ((path (uiop:getenv "PATH"))
         (expected (uiop:getenv "NSHELL_SPEC_BIN_DIR"))
         (resolved-path
           (and path
                (uiop:directory-exists-p path)
                (string-right-trim "/" (namestring (truename path))))))
    (unless (and path expected
                 (string= path expected)
                 resolved-path
                 (not (member resolved-path
                              '("/usr/bin" "/bin" "/usr/local/bin")
                              :test #'string=)))
      (error "t/spec PATH must equal its fixed bin directory"))
    path))

(defun %check-spec-false-exits-nonzero ()
  (let ((false-bin
          (merge-pathnames
           #p"false"
           (uiop:ensure-directory-pathname (%required-single-bin-path)))))
    (unless (uiop:file-exists-p false-bin)
      (error "The fixed t/spec bin directory has no false executable"))
    (host-kit:with-temporary-directory (directory)
      (let ((result
              (host-kit:run-program (namestring false-bin) nil
                                    :directory directory
                                    :input ""
                                    :timeout 20)))
        (expect (host-kit:process-result-exit-code result)
                :to-equal 1)))))

(defun %fixture-environment (directory home)
  (flet ((dir (pathname) (string-right-trim "/" (namestring pathname))))
    (list (format nil "HOME=~a" (dir home))
          (format nil "XDG_CONFIG_HOME=~a" (dir (merge-pathnames #p".config/" home)))
          (format nil "XDG_DATA_HOME=~a" (dir (merge-pathnames #p".data/" home)))
          (format nil "XDG_STATE_HOME=~a" (dir (merge-pathnames #p".state/" home)))
          (format nil "XDG_CACHE_HOME=~a" (dir (merge-pathnames #p".cache/" home)))
          (format nil "TMPDIR=~a" (dir directory))
          (format nil "PATH=~a" (%required-single-bin-path))
          "NSHELL_AI_COMMAND=/nonexistent"
          "NO_COLOR=1"
          "LANG=C.UTF-8")))

(defun %safe-fixture-path (name directory)
  (let ((relative (pathname name)))
    (when (or (uiop:absolute-pathname-p relative)
              (member :up (pathname-directory relative)))
      (error "Fixture path must stay inside its temporary work directory: ~a" name))
    (merge-pathnames relative directory)))

(defun %write-text-file (path text)
  (ensure-directories-exist path)
  (with-open-file (stream path
                          :direction :output
                          :if-exists :supersede
                          :external-format :utf-8)
    (write-string text stream)))

;;; Normalisation: only environment-dependent text is rewritten.

(defun %replace-all (text old new)
  (if (zerop (length old))
      text
      (with-output-to-string (output)
        (loop with start = 0
              for position = (search old text :start2 start)
              while position
              do (write-string text output :start start :end position)
                 (write-string new output)
                 (setf start (+ position (length old)))
              finally (write-string text output :start start)))))

(defparameter *normalized-tools*
  '("cat" "false" "ls" "printf" "sh" "tr" "wc"
    "sleep" "sort" "last" "join" "find"))

(defun %normalize-nix-tool-path (text tool)
  (let ((suffix (format nil "/bin/~a" tool))
        (prefix "/nix/store/"))
    (with-output-to-string (output)
      (loop with start = 0
            for end = (search suffix text :start2 start)
            while end
            do (let ((store
                       (search prefix text
                               :start2 start
                               :end2 end
                               :from-end t)))
                 (if (and store
                          (> end (+ store (length prefix)))
                          (not (position-if
                                (lambda (character)
                                  (member character
                                          '(#\Space #\Tab #\Newline
                                            #\Return #\: #\/)))
                                text
                                :start (+ store (length prefix))
                                :end end)))
                     (progn
                       (write-string text output :start start :end store)
                       (format output "<tool>/~a" tool))
                     (write-string text output :start start
                                               :end (+ end (length suffix))))
                 (setf start (+ end (length suffix))))
            finally (write-string text output :start start)))))

(defun %normalize-tool-paths (text)
  (labels ((path-character-p (character)
             (or (alphanumericp character)
                 (find character '(#\/ #\. #\_ #\-))))
           (replace-exact-path (input path replacement)
             (with-output-to-string (output)
               (loop with start = 0
                     for position = (search path input :start2 start)
                     while position
                     for end = (+ position (length path))
                     do (write-string input output :start start :end position)
                        (if (and (or (zerop position)
                                     (not (path-character-p
                                           (char input (1- position)))))
                                 (or (= end (length input))
                                     (not (path-character-p (char input end)))))
                            (write-string replacement output)
                            (write-string input output :start position :end end))
                        (setf start end)
                     finally (write-string input output :start start)))))
    (let ((normalized text))
      (dolist (tool *normalized-tools* normalized)
        (let ((replacement (format nil "<tool>/~a" tool))
              (bare-prefix (format nil "~a:" tool)))
          ;; A tool run by bare name reports itself as "NAME:"; v0.7.0 ran it
          ;; from /usr/bin, so both forms name the same program.
          (setf normalized (%normalize-nix-tool-path normalized tool)
                normalized (replace-exact-path normalized
                                               (format nil "/usr/bin/~a" tool)
                                               replacement)
                normalized (replace-exact-path normalized
                                               (format nil "/bin/~a" tool)
                                               replacement)
                normalized (%replace-all normalized
                                         (format nil "~%~a" bare-prefix)
                                         (format nil "~%~a:" replacement)))
          (when (eql 0 (search bare-prefix normalized))
            (setf normalized
                  (concatenate 'string replacement
                               (subseq normalized (length tool))))))))))

(defparameter *crash-log-marker* "nshell: crash log:")

(defun %output-lines (text)
  (with-input-from-string (input text)
    (loop for line = (read-line input nil nil)
          while line
          collect line)))

(defun %output-final-newline-p (text)
  (and (plusp (length text))
       (char= (char text (1- (length text))) #\Newline)))

(defun %normalize-crash-log-path (line)
  (let ((position (search *crash-log-marker* line)))
    (if position
        (concatenate 'string
                     (subseq line 0 (+ position (length *crash-log-marker*)))
                     " <CRASH_LOG>")
        line)))

(defun %wrapped-continuation-p (line)
  ;; SBCL's type-error report breaks with ~I~_ before "is not of type" and
  ;; "when binding", which puts them at the block's own indentation: indented
  ;; in the v0.7.0 recording, column 0 in later builds.
  (and (plusp (length line))
       (or (member (char line 0) '(#\Space #\Tab))
           (eql 0 (search "is not of type" line))
           (eql 0 (search "when binding " line)))))

(defun %join-wrapped-diagnostics (lines)
  ;; SBCL wraps a condition report at a width that depends on the length of
  ;; the script path, so continuation lines are joined back into one line.
  ;; A line too long for the margin can also leave an empty line before the
  ;; next continuation; that empty line is part of the wrap.
  (let ((joined nil))
    (loop for (line next) on lines
          do (cond
               ((not (and joined
                          (eql 0 (search "source: $WORK/case.nsh:" (first joined)))))
                (push line joined))
               ((%wrapped-continuation-p line)
                (setf (first joined)
                      (format nil "~a ~a"
                              (string-right-trim '(#\Space #\Tab) (first joined))
                              (string-trim '(#\Space #\Tab) line))))
               ((and (zerop (length (string-trim '(#\Space #\Tab) line)))
                     next
                     (%wrapped-continuation-p next)))
               (t (push line joined))))
    (nreverse joined)))

(defun %normalize-text (text work-directories)
  (let ((replaced text))
    ;; Longest first: /tmp/x is a suffix of its truename /private/tmp/x.
    (dolist (directory (sort (copy-list work-directories) #'> :key #'length))
      (setf replaced
            (%replace-all replaced (string-right-trim "/" directory) "$WORK")))
    (setf replaced (%normalize-tool-paths replaced))
    (let ((lines (%join-wrapped-diagnostics
                  (mapcar #'%normalize-crash-log-path (%output-lines replaced))))
          (final-newline (%output-final-newline-p replaced)))
      (format nil "~{~a~^~%~}~:[~;~%~]" lines (and lines final-newline)))))

(defun %stream-shape (text)
  (list :lines (%output-lines text)
        :final-newline (%output-final-newline-p text)))

(defun %observation (exit stdout stderr work-directories home)
  (unless (and (integerp exit) (stringp stdout) (stringp stderr))
    (error "A probe observation needs an integer exit and string streams"))
  (let ((stdout (%normalize-text stdout work-directories))
        (stderr (%normalize-text stderr work-directories)))
    (list :exit exit
          :stdout (%stream-shape stdout)
          :stderr (%stream-shape stderr)
          :stdout-text stdout
          :text (format nil "~a~%~a" stdout stderr)
          :home home)))

;;; Running a probe

(defun %probe-source (input case)
  (let ((source (or input (%field case "src"))))
    (unless (stringp source)
      (error "A probe input must be a script string, got ~s" source))
    source))

(defun %run-probe (input case)
  (host-kit:with-temporary-directory (directory)
    (let ((home (merge-pathnames #p"home/" directory))
          (script (merge-pathnames #p"case.nsh" directory)))
      (ensure-directories-exist home)
      (dolist (entry (%field case "files"))
        (%write-text-file (%safe-fixture-path (car entry) directory) (cdr entry)))
      (%write-text-file script (%probe-source input case))
      (let* ((result (host-kit:run-program (%required-nshell-bin)
                                           (list (namestring script))
                                           :directory directory
                                           :input ""
                                           :environment
                                           (%fixture-environment directory home)
                                           :timeout 20))
             (work-directories (list (namestring directory)
                                     (namestring (truename directory)))))
        (%observation (host-kit:process-result-exit-code result)
                      (host-kit:process-result-stdout result)
                      (host-kit:process-result-stderr result)
                      work-directories
                      (%normalize-text (string-right-trim "/" (namestring home))
                                       work-directories))))))

(defun %v07-observation (case)
  (let ((observed (%field case "observed_v0_7_0")))
    (%observation (%field observed "exit")
                  (%field observed "stdout")
                  (%field observed "stderr")
                  nil
                  nil)))

;;; Occurrence counting

(defun %substring-occurrences (text needle)
  (when (zerop (length needle))
    (error "Cannot count an empty substring"))
  (loop with start = 0
        for position = (search needle text :start2 start)
        while position
        count t
        do (setf start (+ position (length needle)))))

(defun %token-occurrences (text token)
  ;; A code or position token counts only when it is not part of a longer
  ;; identifier or number: case.nsh:1:1 must not match case.nsh:1:12.
  (flet ((word-character-p (index)
           (and (< -1 index (length text))
                (let ((character (char text index)))
                  (or (alphanumericp character) (char= character #\_))))))
    (when (zerop (length token))
      (error "Cannot count an empty token"))
    (loop with start = 0
          for position = (search token text :start2 start)
          while position
          count (not (or (word-character-p (1- position))
                         (word-character-p (+ position (length token)))))
          do (setf start (1+ position)))))


;;; Expectation validation

(defparameter *expectation-keys*
  '(:exit :stdout :stdout-final-newline :stderr :stderr-final-newline
    :error :position :contains :absent :stdout-json))

(defun %plist-key-p (plist key)
  (loop for (candidate) on plist by #'cddr
        thereis (eq candidate key)))

(defun %string-list-p (value)
  (and (listp value) (every #'stringp value)))

(defun %non-empty-strings-p (value)
  (and value (%string-list-p value) (every #'plusp (mapcar #'length value))))

(defun %validate-expectation (expectation where)
  (unless (and (listp expectation) (evenp (length expectation)))
    (error "~a: an expectation must be a plist, got ~s" where expectation))
  (loop for (key) on expectation by #'cddr
        unless (member key *expectation-keys*)
          do (error "~a: unknown expectation key ~s" where key))
  (flet ((need (ok message &rest arguments)
           (unless ok
             (error "~a: ~?" where message arguments))))
    (need (integerp (getf expectation :exit)) ":exit must be an integer")
    (cond
      ((not (%plist-key-p expectation :stdout))
       (need (and (or (%plist-key-p expectation :error)
                      (%plist-key-p expectation :stdout-json))
                  (not (%plist-key-p expectation :stdout-final-newline)))
             ":stdout may be omitted only under :error or :stdout-json, without :stdout-final-newline"))
      ((%plist-key-p expectation :stdout-json)
       (need nil ":stdout-json replaces :stdout; give only one of them"))
      ((eq (getf expectation :stdout) :home)
       (need (not (%plist-key-p expectation :stdout-final-newline))
             ":stdout :home already fixes the final newline"))
      (t
       (need (and (%string-list-p (getf expectation :stdout))
                  (%plist-key-p expectation :stdout-final-newline)
                  (typep (getf expectation :stdout-final-newline) 'boolean))
             ":stdout needs a list of lines and a boolean :stdout-final-newline")))
    (if (%plist-key-p expectation :stderr)
        (need (and (%string-list-p (getf expectation :stderr))
                   (%plist-key-p expectation :stderr-final-newline)
                   (typep (getf expectation :stderr-final-newline) 'boolean))
              ":stderr needs a list of lines and a boolean :stderr-final-newline")
        (need (not (%plist-key-p expectation :stderr-final-newline))
              ":stderr-final-newline needs :stderr"))
    (when (%plist-key-p expectation :error)
      (let ((code (getf expectation :error)))
        (need (and (stringp code) (eql 0 (search "E_" code)))
              ":error must be an E_ code string")))
    (when (%plist-key-p expectation :position)
      (let ((position (getf expectation :position)))
        (need (and (listp position)
                   (= 2 (length position))
                   (every (lambda (n) (typep n '(integer 1))) position))
              ":position must be (LINE COL) with positive integers")))
    (when (%plist-key-p expectation :stdout-json)
      (let ((text (getf expectation :stdout-json)))
        (need (and (stringp text)
                   (handler-case (progn (%parse-json-text text) t)
                     (json-kit:json-kit-error () nil)))
              ":stdout-json must be a JSON text string")))
    (dolist (key '(:contains :absent))
      (when (%plist-key-p expectation key)
        (need (%non-empty-strings-p (getf expectation key))
              "~s must be a non-empty list of non-empty strings" key))))
  expectation)

(defun %validate-warning (warning where)
  (when warning
    (unless (and (listp warning) (evenp (length warning))
                 (loop for (key) on warning by #'cddr
                       always (member key '(:code :rewrite)))
                 (stringp (getf warning :code))
                 (eql 0 (search "W_" (getf warning :code)))
                 (typep (getf warning :rewrite) '(or null string)))
      (error "~a: :warning must be nil or (:code \"W_...\" :rewrite nil-or-string), got ~s"
             where warning)))
  warning)

;;; The v0.7.0 record as an expectation

(defparameter *argument-type-report-prefix* "source: $WORK/case.nsh: Command argument ")
(defparameter *argument-type-report-suffix*
  " is not a string, number, character, or non-nil symbol.")
(defparameter *v07-type-error-prefix* "source: $WORK/case.nsh: The value ")
(defparameter *v07-type-error-suffix*
  " is not of type (OR STRING CHARACTER NUMBER (AND SYMBOL (NOT (EQL NIL))))")
(defparameter *v07-signalled-line*
  "source: $WORK/case.nsh: Condition NSHELL.APPLICATION:COMMAND-ARGUMENT-TYPE-ERROR was signalled.")

(defun %suffix-p (suffix text)
  (let ((start (- (length text) (length suffix))))
    (and (>= start 0) (string= suffix text :start2 start))))

(defun %framed-value (text prefix suffix)
  (and (eql 0 (search prefix text))
       (%suffix-p suffix text)
       (<= (+ (length prefix) (length suffix)) (length text))
       (subseq text (length prefix) (- (length text) (length suffix)))))

(defun %v07-line-matches-p (expected actual)
  ;; The one named equivalence between the v0.7.0 record and later builds:
  ;; commit d17596f2 ("report script syntax and argument type errors without
  ;; crash logs") replaced SBCL's TYPE-ERROR text for a bad command argument
  ;; with the COMMAND-ARGUMENT-TYPE-ERROR report
  ;; (src/application/contracts/l06-value-conversion.lisp:13). The value must
  ;; stay the same when v0.7.0 recorded it; only the "was signalled." form,
  ;; which recorded no value, leaves it unchecked.
  (or (string= expected actual)
      (let ((actual-value (%framed-value actual *argument-type-report-prefix*
                                         *argument-type-report-suffix*)))
        (and actual-value
             (or (string= expected *v07-signalled-line*)
                 (equal actual-value
                        (%framed-value expected *v07-type-error-prefix*
                                       *v07-type-error-suffix*)))))))

(defun %v07-expectation (case)
  (let ((record (%v07-observation case)))
    (list :exit (getf record :exit)
          :stdout (getf (getf record :stdout) :lines)
          :stdout-final-newline (getf (getf record :stdout) :final-newline)
          :stderr (getf (getf record :stderr) :lines)
          :stderr-final-newline (getf (getf record :stderr) :final-newline))))

(defun %without-crash-log-lines (shape)
  ;; Crash-log presence is the *crash-probes* guard's job, not the baseline's.
  (let* ((lines (getf shape :lines))
         (kept (remove-if (lambda (line) (search *crash-log-marker* line)) lines)))
    (list :lines kept
          :final-newline (and kept
                              (or (getf shape :final-newline)
                                  (not (equal (car (last kept)) (car (last lines)))))))))

;;; The comparator

(defun %lines-match-p (expected actual line-test)
  (and (= (length expected) (length actual))
       (every line-test expected actual)))

(defun %stream-matches-p (expected actual line-test)
  (and (%lines-match-p (getf expected :lines) (getf actual :lines) line-test)
       (eq (getf expected :final-newline) (getf actual :final-newline))))

(defun %block-candidates (expected actual line-test)
  ;; Every way to read ACTUAL as A ++ W ++ B where A ++ B is EXPECTED and W is
  ;; one non-empty contiguous block of inserted lines.
  (let* ((expected-lines (getf expected :lines))
         (actual-lines (getf actual :lines))
         (size (- (length actual-lines) (length expected-lines))))
    (when (plusp size)
      (loop for start from 0 to (length expected-lines)
            when (and (%lines-match-p (subseq expected-lines 0 start)
                                      (subseq actual-lines 0 start)
                                      line-test)
                      (%lines-match-p (subseq expected-lines start)
                                      (subseq actual-lines (+ start size))
                                      line-test)
                      ;; The final newline belongs to the old output unless
                      ;; the block is the last thing in the stream.
                      (or (= start (length expected-lines))
                          (eq (getf expected :final-newline)
                              (getf actual :final-newline))))
              collect (subseq actual-lines start (+ start size))))))

(defun %expected-stream (expectation name run)
  (ecase name
    (:stdout
     (cond ((not (%plist-key-p expectation :stdout)) :uncompared)
           ((eq (getf expectation :stdout) :home)
            (list :lines (list (getf run :home)) :final-newline t))
           (t (list :lines (getf expectation :stdout)
                    :final-newline (getf expectation :stdout-final-newline)))))
    (:stderr
     (cond ((%plist-key-p expectation :stderr)
            (list :lines (getf expectation :stderr)
                  :final-newline (getf expectation :stderr-final-newline)))
           ((%plist-key-p expectation :error) :uncompared)
           (t (%stream-shape ""))))))

(defun %canonical-json (value)
  ;; Objects become (:object (key . value) ...) sorted by key, so member order
  ;; does not matter; arrays become (:array ...) and keep their order.
  (cond
    ((hash-table-p value)
     (cons :object
           (sort (loop for key being the hash-keys of value using (hash-value member)
                       collect (cons key (%canonical-json member)))
                 #'string< :key #'car)))
    ((listp value) (cons :array (mapcar #'%canonical-json value)))
    (t value)))

(defun %parse-json-text (text)
  ;; Hash-table objects keep objects and arrays apart, which an alist/list
  ;; reading cannot; JSON null and false become :null and :false.
  (%canonical-json
   (json-kit:parse text :object-type :hash-table :array-type :list
                        :duplicate-key-policy :error
                        :null-value :null :false-value :false)))

(defun %stdout-json-mismatches (expected-text run)
  ;; EXPECTED-TEXT is JSON text; json-kit ignores the trailing newline.
  (let ((expected (%parse-json-text expected-text))
        (text (getf run :stdout-text)))
    (handler-case
        (let ((actual (%parse-json-text text)))
          (unless (equal expected actual)
            (list (list :check :stdout-json :expected expected :actual actual))))
      (json-kit:json-kit-error (condition)
        (list (list :check :stdout-json :expected expected
                    :actual (list :unparsable text :reason (princ-to-string condition))))))))

(defun %count-mismatches (check needle expected-count actual-count)
  (unless (= expected-count actual-count)
    (list (list :check check :text needle
                :expected-count expected-count :actual-count actual-count))))

(defun %mismatches (expectation run &key warning (mode :none) v07-record)
  "Compare RUN with EXPECTATION, an EXPECTATION plist or :unsettled.
MODE :none forbids warnings, :optional allows one, :required demands one;
WARNING is the row's (:code :rewrite). V07-RECORD marks an expectation built
from the v0.7.0 JSON record."
  (unless (member mode '(:none :optional :required))
    (error "Unknown warning mode ~s" mode))
  (unless (eq expectation :unsettled)
    (%validate-expectation expectation "expectation"))
  (%validate-warning warning "warning")
  (when (and (not (eq mode :none)) (null warning))
    (error "Warning mode ~s needs a warning" mode))
  (let* ((code (getf warning :code))
         (rewrite (getf warning :rewrite))
         (text (getf run :text))
         (line-test (if v07-record #'%v07-line-matches-p #'string=))
         (mismatches nil)
         (blocks nil)
         (all-compared (not (eq expectation :unsettled))))
    (flet ((fail (&rest mismatch) (push mismatch mismatches)))
      (unless (eq expectation :unsettled)
        (unless (eql (getf expectation :exit) (getf run :exit))
          (fail :check :exit :expected (getf expectation :exit) :actual (getf run :exit)))
        (dolist (name '(:stdout :stderr))
          (let ((expected (%expected-stream expectation name run))
                (actual (if (and v07-record (eq name :stderr))
                            (%without-crash-log-lines (getf run name))
                            (getf run name))))
            (cond
              ((eq expected :uncompared) (setf all-compared nil))
              ((%stream-matches-p expected actual line-test))
              (t
               (let ((candidates (and (not (eq mode :none))
                                      (%block-candidates expected actual line-test))))
                 (if candidates
                     (push (cons name candidates) blocks)
                     (fail :check name :mode mode :expected expected :actual actual)))))))
        (when (%plist-key-p expectation :stdout-json)
          (setf mismatches (append (%stdout-json-mismatches
                                    (getf expectation :stdout-json) run)
                                   mismatches)))
        (when (%plist-key-p expectation :error)
          (let ((error-code (getf expectation :error)))
            (setf mismatches (append (%count-mismatches :error error-code 1
                                                        (%token-occurrences text error-code))
                                     mismatches))))
        (when (%plist-key-p expectation :position)
          (let ((token (format nil "case.nsh:~{~d:~d~}" (getf expectation :position))))
            (setf mismatches (append (%count-mismatches :position token 1
                                                        (%token-occurrences text token))
                                     mismatches))))
        (dolist (needle (getf expectation :contains))
          (setf mismatches (append (%count-mismatches :contains needle 1
                                                      (%substring-occurrences text needle))
                                   mismatches)))
        (dolist (needle (getf expectation :absent))
          (setf mismatches (append (%count-mismatches :absent needle 0
                                                      (%substring-occurrences text needle))
                                   mismatches))))
      (unless (eq mode :none)
        (when (> (length blocks) 1)
          (fail :check :warning-block :rule "one inserted block across both streams"
                :blocks blocks))
        (dolist (entry blocks)
          (unless (some (lambda (lines)
                          (let ((block-text (format nil "~{~a~%~}" lines)))
                            (and (plusp (%token-occurrences block-text code))
                                 (or (null rewrite) (search rewrite block-text)))))
                        (cdr entry))
            (fail :check (car entry) :mode mode
                  :rule "the inserted block must contain the code and :rewrite"
                  :code code :rewrite rewrite :blocks (cdr entry))))
        (when (or (eq mode :required) blocks)
          (setf mismatches (append (%count-mismatches :warning-code code 1
                                                      (%token-occurrences text code))
                                   mismatches))
          (when (and rewrite (not (search rewrite text)))
            (fail :check :warning-rewrite :expected rewrite :actual "absent")))
        (when (and (eq mode :required) all-compared (null blocks))
          (fail :check :warning-block :code code
                :expected "one inserted block" :actual "none"))))
    (nreverse mismatches)))

;;; Assertion

(defun %assert-no-mismatches (mismatches run)
  (expect (and mismatches
               (append mismatches
                       (list (list :normalized-actual
                                   :exit (getf run :exit)
                                   :stdout (getf run :stdout)
                                   :stderr (getf run :stderr)))))
          :to-equal nil))

;;; Row lookup and checks called by the generated tests

(defvar *l7-rows*)
(defvar *probe-changes*)
(defvar *crash-probes*)

(defun %l7-row (number)
  (or (find number *l7-rows* :key (lambda (row) (getf row :row)))
      (error "No L7.1 row ~a" number)))

(defun %v08-entry (designator)
  ;; An L7.1 row by its line number, or a *probe-changes* entry by probe id.
  (if (integerp designator)
      (%l7-row designator)
      (or (find designator *probe-changes*
                :key (lambda (entry) (getf entry :probe))
                :test #'string=)
          (error "No probe change ~a" designator))))

(defun %v07-row-for-probe (id)
  (find-if (lambda (row)
             (and (string= id (getf row :probe))
                  (eq :v07 (getf (getf row :v08) :expect))))
           *l7-rows*))

(defun %check-baseline (id)
  (let* ((case (%fixture-case id))
         (warning (getf (getf (%v07-row-for-probe id) :v08) :warning))
         (run (%run-probe nil case)))
    (%assert-no-mismatches
     (%mismatches (%v07-expectation case) run
                  :warning warning
                  :mode (if warning :optional :none)
                  :v07-record t)
     run)))

(defun %check-v08 (designator)
  (let* ((entry (%v08-entry designator))
         (case (%fixture-case (getf entry :probe)))
         (v08 (getf entry :v08))
         (expect (getf v08 :expect))
         (warning (getf v08 :warning))
         (run (%run-probe (getf entry :input) case)))
    (%assert-no-mismatches
     (if (eq expect :v07)
         (%mismatches (%v07-expectation case) run
                      :warning warning
                      :mode (if warning :required :none)
                      :v07-record t)
         (%mismatches expect run
                      :warning warning
                      :mode (if warning :required :none)))
     run)))

(defun %check-v09 (designator)
  (let* ((entry (%v08-entry designator))
         (v09 (or (getf entry :v09) (error "~a has no :v09" designator)))
         (run (%run-probe (getf v09 :input) (%fixture-case (getf entry :probe)))))
    (%assert-no-mismatches (%mismatches (getf v09 :expect) run) run)))

(defun %check-no-crash-log (id)
  (let* ((entry (or (find id *crash-probes*
                          :key (lambda (entry) (getf entry :probe))
                          :test #'string=)
                    (error "No crash probe ~a" id)))
         (run (%run-probe (getf entry :input) (%fixture-case id))))
    (expect (remove-if-not (lambda (line) (search *crash-log-marker* line))
                           (%output-lines (getf run :text)))
            :to-equal nil)))
