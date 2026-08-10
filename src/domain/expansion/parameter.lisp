(in-package #:nshell.domain.expansion)

(defun expand-variables (input env)
  "Expand $VAR and ${VAR} occurrences in INPUT using ENV. Also expands the
fish-style argument list $argv and indexed $argv[N] from *POSITIONAL-ARGS*
\(bare $argv joins with spaces here; a bare unquoted $argv is split into separate
words by the argument expander). POSIX positional $1..$9 are NOT special and stay
literal, matching fish. Undefined variables expand to the empty string."
  (with-output-to-string (out)
    (loop with len = (length input)
          for i from 0 below len
          for ch = (char input i)
          do (cond
               ((char/= ch #\$) (write-char ch out))
               ((>= (1+ i) len) (write-char ch out))
               ((char= (char input (1+ i)) #\{)
                (let ((end (position #\} input :start (+ i 2))))
                  (if end
                      (progn
                        (write-string
                         (%expand-braced-parameter (subseq input (+ i 2) end) env)
                         out)
                        (setf i end))
                      (write-char ch out))))
               ((char= (char input (1+ i)) #\?)
                (write-string
                 (or (nshell.domain.environment:env-get env "?") "0")
                 out)
                (incf i))
               ((char= (char input (1+ i)) #\!)
                (write-string
                 (or (nshell.domain.environment:env-get env "!") "")
                 out)
                (incf i))
               ((variable-name-start-p (char input (1+ i)))
                (multiple-value-bind (element next)
                    (%expand-variable-reference input i len env)
                  (if element
                      (progn
                        (write-string element out)
                        (setf i (1- next)))
                      (write-char ch out))))
               (t (write-char ch out))))))
