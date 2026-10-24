(in-package #:nshell.domain.completion)

(defun completion-query-for (partial-input &optional filesystem &key home-directory)
  (let* ((context (%unwrap-completion-context
                   (completion-context-for partial-input)))
         (arg-prefix (completion-context-argument-prefix context))
         (filesystem-mode (completion-filesystem-mode context)))
    (%make-completion-query partial-input context
                            (completion-context-command context)
                            arg-prefix
                            (completion-context-argument-words context)
                            filesystem
                            (when filesystem-mode
                              (filesystem-candidates-for-mode filesystem-mode arg-prefix filesystem
                                                              :home-directory home-directory)))))


(defun complete (kb partial-input &key path filesystem alias-table function-table
                                        variable-names directory home-directory process-ids)
  (let ((query (completion-query-for partial-input filesystem :home-directory home-directory)))
    (%rank-candidates (%completion-ranking-prefix query)
                      (%completion-candidates kb query path alias-table function-table
                                              :variable-names variable-names
                                              :directory directory
                                              :home-directory home-directory
                                              :process-ids process-ids))))

(defun %completion-context-filesystem-candidates
    (context filesystem variable-names home-directory)
  (let ((mode (completion-filesystem-mode context))
        (prefix (completion-context-argument-prefix context)))
    (when mode
      (labels ((variable-expansion ()
                 (when (and (> (length prefix) 1)
                            (char= (char prefix 0) #\$))
                   (let* ((braced-p (and (> (length prefix) 1)
                                         (char= (char prefix 1) #\{)))
                          (name-start (if braced-p 2 1))
                          (name-end
                            (if braced-p
                                (position #\} prefix :start name-start)
                                (or (position-if-not
                                     (lambda (character)
                                       (or (alphanumericp character)
                                           (char= character #\_)))
                                     prefix
                                     :start name-start)
                                    (length prefix))))
                          (suffix-start
                            (and name-end
                                 (if braced-p (1+ name-end) name-end)))
                          (name (and name-end
                                     (> name-end name-start)
                                     (subseq prefix name-start name-end)))
                          (binding (and name
                                        (assoc name variable-names
                                               :key #'identity
                                               :test #'string=))))
                     (when (and binding
                                suffix-start
                                (position #\/ prefix :start suffix-start)
                                (stringp (cdr binding)))
                       (concatenate 'string
                                    (cdr binding)
                                    (subseq prefix suffix-start))))))
               (restore-prefix (candidates expanded-prefix)
                 (mapcar
                  (lambda (candidate)
                    (let ((text (candidate-text candidate)))
                      (if (and (>= (length text) (length expanded-prefix))
                               (string=
                                expanded-prefix
                                (subseq text 0 (length expanded-prefix))))
                          (make-candidate
                           (concatenate 'string
                                        prefix
                                        (subseq text (length expanded-prefix)))
                           :kind (candidate-kind candidate)
                           :description (candidate-description candidate)
                           :score (candidate-score candidate))
                          candidate)))
                  candidates))
               (cdpath-candidates ()
                 (let* ((binding (assoc "CDPATH" variable-names
                                        :key #'identity
                                        :test #'string=))
                        (cdpath (and binding (cdr binding))))
                   (when (and (string= (completion-context-command context) "cd")
                              (stringp cdpath)
                              (not (position-if #'%path-separator-p prefix)))
                     (loop with start = 0
                           for end = (position #\: cdpath :start start)
                           for directory = (subseq cdpath start
                                                   (or end (length cdpath)))
                           append
                           (unless (string= directory "")
                             (filesystem-candidates-for-mode
                              :directories
                              (concatenate
                               'string
                               directory
                               (if (and (plusp (length directory))
                                        (%path-separator-p
                                         (char directory (1- (length directory)))))
                                   ""
                                   "/")
                               prefix)
                              filesystem
                              :home-directory home-directory))
                           while end
                           do (setf start (1+ end)))))))
        (let* ((expanded-prefix (variable-expansion))
               (candidates
                 (filesystem-candidates-for-mode
                  mode
                  (or expanded-prefix prefix)
                  filesystem
                  :home-directory home-directory)))
          (when expanded-prefix
            (setf candidates (restore-prefix candidates expanded-prefix)))
          (%merge-candidates candidates (cdpath-candidates)))))))
(defun complete-in-context
    (kb partial-input context &key path filesystem alias-table function-table
                                    variable-names directory home-directory process-ids)
  (let* ((context (%unwrap-completion-context context))
         (arg-prefix (completion-context-argument-prefix context))
         (filesystem-candidates
           (%completion-context-filesystem-candidates
            context filesystem variable-names home-directory))
         (query
           (%make-completion-query
            partial-input
            context
            (completion-context-command context)
            arg-prefix
            (completion-context-argument-words context)
            filesystem
            filesystem-candidates)))
    (%rank-candidates
     (%completion-ranking-prefix query)
     (%completion-candidates kb query path alias-table function-table
                             :variable-names variable-names
                             :directory directory
                             :home-directory home-directory
                             :process-ids process-ids))))

