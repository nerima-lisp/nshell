(in-package #:nshell/test)

;;; The read_output machine method (task P1-4, ux/U6): reading a saved output
;;; by session id and byte offset, and refusing everything outside the
;;; private store. Every response is checked against the envelope schema with
;;; %MACHINE-PARSED of test-machine-methods.lisp.

(defmacro with-read-output-root ((root) &body body)
  "Bind ROOT to the namestring of <fresh temporary directory>/out/, which does
not exist yet; other names under the temporary directory lie outside ROOT."
  (let ((directory (gensym "DIRECTORY")))
    `(host-kit:with-temporary-directory (,directory)
       (let ((,root (concatenate 'string
                                 (string-right-trim
                                  "/" (sb-ext:native-namestring ,directory))
                                 "/out/")))
         ,@body))))

(defun %read-output (&rest keys)
  (%machine-parsed (apply #'nshell.feature.machine:read-output-envelope
                          :cwd "/tmp" keys)))

(defun %read-output-code (parsed)
  (expect (gethash "ok" parsed) :to-be json-kit:+json-false+)
  (gethash "code" (gethash "error" parsed)))

(defun %read-output-value (parsed)
  (expect (gethash "ok" parsed) :to-be t)
  (gethash "value" parsed))

(defun %read-output-all (&rest keys)
  "Read from offset 0 following next_offset until eof and return the
concatenated text and the number of calls. Each call must make progress."
  (let ((offset 0)
        (calls 0))
    (values
     (with-output-to-string (out)
       (loop
         (let ((value (%read-output-value
                       (apply #'%read-output :offset offset keys))))
           (incf calls)
           (expect (gethash "offset" value) :to-equal offset)
           (write-string (gethash "text" value) out)
           (when (eq t (gethash "eof" value))
             (expect (gethash "next_offset" value) :to-equal (gethash "bytes" value))
             (return))
           (expect (> (gethash "next_offset" value) offset) :to-be t)
           (setf offset (gethash "next_offset" value)))))
     calls)))

(defun %read-output-session (root files)
  "Create a session under ROOT holding FILES, a list of (NAME . TEXT), and
return its id and directory."
  (let ((session (nshell.feature.machine:open-output-session :root root)))
    (expect session :to-be-truthy)
    (loop for (name . text) in files
          do (expect (nshell.feature.machine:output-session-write session name text)
                     :to-be-truthy))
    (values (nshell.feature.machine:output-session-id session)
            (nshell.feature.machine:output-session-directory session))))

(defun %read-output-utf8-length (text)
  (length (sb-ext:string-to-octets text :external-format :utf-8)))

(describe "machine read_output"
  (it "reassembles the full output a --json run saved, in one or many calls"
    (with-json-cache-home (root)
      (let* ((envelope (json-command "seq 1 10000"))
             (session (json-at envelope "session"))
             (saved (uiop:read-file-string (format nil "~A~A/1.txt" root session)
                                           :external-format :utf-8))
             (expected (format nil "~{~D~%~}"
                               (loop for n from 1 to 10000 collect n))))
        (expect saved :to-equal expected)
        ;; The default root is the store --json wrote to.
        (multiple-value-bind (text calls) (%read-output-all :id session)
          (expect text :to-equal saved)
          (expect (> calls 1) :to-be t))
        (multiple-value-bind (text calls) (%read-output-all :id session :limit 1000)
          (expect text :to-equal saved)
          (expect calls :to-equal (ceiling (length saved) 1000)))
        (let ((value (%read-output-value (%read-output :id session :limit 1000))))
          (expect (gethash "id" value) :to-equal session)
          (expect (gethash "seq" value) :to-equal 1)
          (expect (gethash "stream" value) :to-equal "stdout")
          (expect (gethash "offset" value) :to-equal 0)
          (expect (gethash "next_offset" value) :to-equal 1000)
          (expect (gethash "bytes" value) :to-equal (json-at envelope "stdout" "bytes"))
          (expect (gethash "eof" value) :to-be json-kit:+json-false+)
          (expect (gethash "text" value) :to-equal (subseq saved 0 1000))))))

  (it "returns empty text and eof at the end of the file"
    (with-read-output-root (root)
      (let ((id (%read-output-session root '(("1.txt" . "abc")))))
        (let ((value (%read-output-value (%read-output :root root :id id :offset 3))))
          (expect (gethash "text" value) :to-equal "")
          (expect (gethash "next_offset" value) :to-equal 3)
          (expect (gethash "bytes" value) :to-equal 3)
          (expect (gethash "eof" value) :to-be t)))))

  (it "reads stderr and later seqs from their own files"
    (with-read-output-root (root)
      (let ((id (%read-output-session root '(("1.txt" . "out1")
                                              ("1.stderr.txt" . "err1")
                                              ("2.txt" . "out2")))))
        (expect (%read-output-all :root root :id id :stream "stderr") :to-equal "err1")
        (expect (%read-output-all :root root :id id :seq 2) :to-equal "out2")
        (expect (gethash "stream" (%read-output-value
                                   (%read-output :root root :id id :stream "stderr")))
                :to-equal "stderr")
        (expect (%read-output-code (%read-output :root root :id id :seq 2
                                                 :stream "stderr"))
                :to-equal "E_PERMISSION"))))

  (it "counts offsets in UTF-8 bytes and never splits a character"
    (with-read-output-root (root)
      (let* ((text (format nil "a~C~C~%~Cz" (code-char #x3042) (code-char #x3044)
                           (code-char #x1f600)))
             (id (%read-output-session root (list (cons "1.txt" text)))))
        (dolist (limit '(1 2 3 4 5 32768))
          (expect (list limit (%read-output-all :root root :id id :limit limit))
                  :to-equal (list limit text)))
        ;; limit 1 still returns the whole 3-byte character at offset 1.
        (let ((value (%read-output-value
                      (%read-output :root root :id id :offset 1 :limit 1))))
          (expect (gethash "text" value) :to-equal (string (code-char #x3042)))
          (expect (gethash "next_offset" value) :to-equal 4))
        ;; The chunk end moves back to the boundary before a cut character.
        (let ((value (%read-output-value
                      (%read-output :root root :id id :offset 0 :limit 5))))
          (expect (gethash "text" value) :to-equal (format nil "a~C" (code-char #x3042)))
          (expect (gethash "next_offset" value) :to-equal 4))
        (expect (gethash "bytes" (%read-output-value (%read-output :root root :id id)))
                :to-equal (%read-output-utf8-length text))
        (dolist (offset '(2 3 5 6 9 10 11))
          (expect (list offset (%read-output-code
                                (%read-output :root root :id id :offset offset)))
                  :to-equal (list offset "E_PROTOCOL")))))))

(describe "machine read_output rejects malformed requests"
  (it "takes the id only as a session name"
    (with-read-output-root (root)
      (let ((id (%read-output-session root '(("1.txt" . "x")))))
        (dolist (bad (list "../out" ".." (concatenate 'string root id)
                           (concatenate 'string id "/..") (format nil "~A/1" id)
                           (format nil "s_ab~Ccd" (code-char 0)) "" "s_abcd"
                           "s_abcdefg" (format nil "s_~C~Cabcd" (code-char #xff)
                                               (code-char #xff))
                           42 nil))
          (expect (list bad (%read-output-code (%read-output :root root :id bad)))
                  :to-equal (list bad "E_PROTOCOL"))))))

  (it "checks seq, stream, offset and limit"
    (with-read-output-root (root)
      (let ((id (%read-output-session root '(("1.txt" . "abc")))))
        (dolist (keys `((:seq 0) (:seq -1) (:seq 1.0) (:seq "1") (:seq nil)
                        (:stream "STDOUT") (:stream "both") (:stream :stdout)
                        (:offset -1) (:offset 1.5) (:offset "0") (:offset nil)
                        (:offset 4)
                        (:limit 0) (:limit 32769) (:limit -5) (:limit 1.0)))
          (expect (list keys (%read-output-code
                              (apply #'%read-output :root root :id id keys)))
                  :to-equal (list keys "E_PROTOCOL")))
        (expect (gethash "text" (%read-output-value
                                 (%read-output :root root :id id :limit 32768)))
                :to-equal "abc")))))

(describe "machine read_output refuses the store"
  (it "refuses a missing root, session or file"
    (with-read-output-root (root)
      (expect (%read-output-code (%read-output :root root :id "s_abcdef"))
              :to-equal "E_PERMISSION")
      (%read-output-session root '(("1.txt" . "x")))
      (expect (%read-output-code (%read-output :root root :id "s_abcdef"))
              :to-equal "E_PERMISSION")))

  (it "refuses after a --private run, which saved nothing"
    (with-json-cache-home (root)
      (let ((envelope (json-command "seq 1 10000" :private t)))
        (expect (json-at envelope "session") :to-be-null)
        (expect (probe-file root) :to-be-null)
        (expect (%read-output-code (%read-output :id "s_abcdef"))
                :to-equal "E_PERMISSION"))))

  (it "refuses a root that is a symlink"
    (with-read-output-root (root)
      (let ((id (%read-output-session root '(("1.txt" . "x"))))
            (link (concatenate 'string (string-right-trim "/" root) "-link")))
        (sb-posix:symlink (string-right-trim "/" root) link)
        (expect (%read-output-all :root root :id id) :to-equal "x")
        (expect (%read-output-code (%read-output :root (concatenate 'string link "/")
                                                 :id id))
                :to-equal "E_PERMISSION"))))

  (it "refuses a session directory that is a symlink out of the root"
    (with-read-output-root (root)
      (let ((outside (concatenate 'string (string-right-trim "/" root) "-outside/")))
        (multiple-value-bind (id directory)
            (%read-output-session outside '(("1.txt" . "secret")))
          (%read-output-session root '(("1.txt" . "x")))
          (expect (%read-output-all :root outside :id id) :to-equal "secret")
          (sb-posix:symlink (string-right-trim "/" directory)
                            (concatenate 'string root "s_link00"))
          (expect (%read-output-code (%read-output :root root :id "s_link00"))
                  :to-equal "E_PERMISSION")))))

  (it "refuses a file that is a symlink out of the session"
    (with-read-output-root (root)
      (let ((outside (concatenate 'string (string-right-trim "/" root) "-secret.txt")))
        (with-open-file (out outside :direction :output)
          (write-string "secret" out))
        (sb-posix:chmod outside #o600)
        (multiple-value-bind (id directory) (%read-output-session root '())
          (sb-posix:symlink outside (concatenate 'string directory "1.txt"))
          (expect (%read-output-code (%read-output :root root :id id))
                  :to-equal "E_PERMISSION")))))

  (it "refuses a root, session or file that group or other can access"
    (with-read-output-root (root)
      (multiple-value-bind (id directory) (%read-output-session root '(("1.txt" . "x")))
        (let ((file (concatenate 'string directory "1.txt"))
              (session (string-right-trim "/" directory))
              (root-directory (string-right-trim "/" root)))
          (expect (%read-output-all :root root :id id) :to-equal "x")
          (sb-posix:chmod file #o644)
          (expect (%read-output-code (%read-output :root root :id id))
                  :to-equal "E_PERMISSION")
          (sb-posix:chmod file #o600)
          (sb-posix:chmod session #o755)
          (expect (%read-output-code (%read-output :root root :id id))
                  :to-equal "E_PERMISSION")
          (sb-posix:chmod session #o700)
          (sb-posix:chmod root-directory #o755)
          (expect (%read-output-code (%read-output :root root :id id))
                  :to-equal "E_PERMISSION")
          (sb-posix:chmod root-directory #o700)
          (expect (%read-output-all :root root :id id) :to-equal "x")))))

  (it "refuses a session that is not a directory and a file that is not regular"
    (with-read-output-root (root)
      (multiple-value-bind (id directory) (%read-output-session root '())
        (with-open-file (out (concatenate 'string root "s_plain0") :direction :output)
          (write-string "x" out))
        (sb-posix:chmod (concatenate 'string root "s_plain0") #o600)
        (expect (%read-output-code (%read-output :root root :id "s_plain0"))
                :to-equal "E_PERMISSION")
        ;; A FIFO is opened without blocking and refused.
        (sb-posix:mkfifo (concatenate 'string directory "1.txt") #o600)
        (expect (%read-output-code (%read-output :root root :id id))
                :to-equal "E_PERMISSION")
        (sb-posix:mkdir (concatenate 'string directory "2.txt") #o700)
        (expect (%read-output-code (%read-output :root root :id id :seq 2))
                :to-equal "E_PERMISSION")))))
