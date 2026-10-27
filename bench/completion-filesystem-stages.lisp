(require :asdf)
(progn
  (load #P"scripts/asdf-runtime.lisp")
  (defparameter +stages-asdf-output-root+
    (nshell-configure-writable-asdf-output))
  (format t "~&asdf_output_root=~A~%"
          (truename +stages-asdf-output-root+))
  (asdf:load-system :cl-host-kit))
(progn
  (asdf:load-system :nshell :force t)
  (let* ((source
           (truename (asdf:system-source-file (asdf:find-system "nshell"))))
         (expected-source (truename #P"./nshell.asd"))
         (component-source
           (truename #P"./src/domain/completion/filesystem-file-completion.lisp"))
         (translated-output
           (asdf:apply-output-translations
            (compile-file-pathname component-source)))
         (output-root
           (namestring
            (uiop:ensure-directory-pathname
             (truename +stages-asdf-output-root+))))
         (output-path (truename translated-output))
         (output-name (namestring output-path)))
    (unless (equal source expected-source)
      (error "ASDF resolved nshell outside this worktree: ~A" source))
    (unless (and (> (length output-name) (length output-root))
                 (string= output-root output-name :end2 (length output-root)))
      (error "ASDF FASL output is outside configured root: ~A" output-path))
    (format t
            "~&asdf_source=~A~%asdf_fasl_output=~A~%asdf_output_path_assertion=passed~%"
            source output-path)))
(progn
  (defparameter +stages-fixture-entries+ 20000)
  (defparameter +stages-default-warmup-pairs+ 3)
  (defparameter +stages-default-sample-pairs+ 30)
  (defparameter +stages-minimum-sample-pairs+ 20)

  (defun %stages-environment-integer (name default)
    (let ((value (host-kit:getenv name)))
      (if value
          (let ((parsed (parse-integer value :junk-allowed nil)))
            (unless (plusp parsed)
              (error "~A must be positive, got ~S" name value))
            parsed)
          default)))

  (defun %stages-output-signature (output candidate-output-p)
    (if candidate-output-p
        (mapcar
         (lambda (candidate)
           (list
            (nshell.domain.completion::candidate-text candidate)
            (nshell.domain.completion::candidate-kind candidate)
            (nshell.domain.completion::candidate-description candidate)
            (nshell.domain.completion::candidate-score candidate)))
         output)
      (mapcar
       (lambda (entry)
         (cond
          ((pathnamep entry) (namestring entry))
          ((stringp entry) entry)
          (t
           (list
            (nshell.domain.filesystem:filesystem-completion-entry-name entry)
            (nshell.domain.filesystem:filesystem-completion-entry-kind entry)
            (nshell.domain.filesystem:filesystem-completion-entry-target-kind
             entry)))))
       output)))

  (defun %stages-signature-hash (signature)
    (let ((hash #xcbf29ce484222325))
      (loop for character across (prin1-to-string signature)
            do (setf hash
                     (logand #xffffffffffffffff
                             (* (logxor hash (char-code character))
                                #x100000001b3))))
      (format nil "~16,'0X" hash)))

  (defun %stages-assert-output (name output candidate-output-p
                                expected-signature expected-hash)
    (let* ((signature (%stages-output-signature output candidate-output-p))
           (hash (%stages-signature-hash signature)))
      (unless (equal expected-signature signature)
        (error "~A ordered output signature changed" name))
      (unless (string= expected-hash hash)
        (error "~A output hash changed: expected ~A, got ~A"
               name expected-hash hash))
      (values signature hash)))

  (progn
  (defun %stages-convert-entries (entries query)
    (let ((candidate-set
            (nshell.domain.completion::%make-empty-filesystem-candidate-set)))
      (setf candidate-set
            (nshell.domain.completion::%add-file-completion-entries
             entries :file query candidate-set))
      (nshell.domain.completion::%filesystem-candidate-set-candidates
       candidate-set)))

  (defun %stages-convert-completion-entries (entries query)
    (let ((candidate-set
            (nshell.domain.completion::%make-empty-filesystem-candidate-set)))
      (setf candidate-set
            (nshell.domain.completion::%add-file-completion-port-entries
             entries query candidate-set))
      (nshell.domain.completion::%filesystem-candidate-set-candidates
       candidate-set))))

  (defun %stages-prepare-cache (cache-state thunk)
    (ecase cache-state
      (:application-cold
       (nshell.infrastructure.acl:clear-directory-listing-cache))
      (:application-warm
       (nshell.infrastructure.acl:clear-directory-listing-cache)
       (funcall thunk))
      (:memory
       (values))))

  (defun %stages-timed-arm (name arm thunk cache-state candidate-output-p
                            expected-signature expected-hash)
    (%stages-prepare-cache cache-state thunk)
    (sb-ext:gc :full t)
    (let* ((start (get-internal-real-time))
           (output (funcall thunk))
           (elapsed
             (/ (* 1000.0d0 (- (get-internal-real-time) start))
                internal-time-units-per-second)))
      (multiple-value-bind (signature hash)
          (%stages-assert-output
           (format nil "~A arm ~A" name arm)
           output candidate-output-p expected-signature expected-hash)
        (values elapsed signature hash))))

  (defun %stages-paired-run (name thunk-a thunk-b cache-state candidate-output-p
                           expected-signature expected-hash a-first-p)
    (if a-first-p
        (multiple-value-bind (a-time a-signature a-hash)
            (%stages-timed-arm name :a thunk-a cache-state candidate-output-p
                               expected-signature expected-hash)
          (multiple-value-bind (b-time b-signature b-hash)
              (%stages-timed-arm name :b thunk-b cache-state candidate-output-p
                                 expected-signature expected-hash)
            (unless (and (equal a-signature b-signature)
                         (string= a-hash b-hash))
              (error "~A paired arms differ: signatures or hashes" name))
            (values a-time b-time)))
        (multiple-value-bind (b-time b-signature b-hash)
            (%stages-timed-arm name :b thunk-b cache-state candidate-output-p
                               expected-signature expected-hash)
          (multiple-value-bind (a-time a-signature a-hash)
              (%stages-timed-arm name :a thunk-a cache-state candidate-output-p
                                 expected-signature expected-hash)
            (unless (and (equal a-signature b-signature)
                         (string= a-hash b-hash))
              (error "~A paired arms differ: signatures or hashes" name))
            (values a-time b-time)))))

  (defun %stages-percentile (sorted-samples fraction)
    (nth (max 0 (1- (ceiling (* fraction (length sorted-samples)))))
         sorted-samples))

  (defun %stages-statistics (samples)
    (let* ((sorted (sort (copy-list samples) #'<))
           (p50 (%stages-percentile sorted 0.50d0))
           (deviations
             (sort (mapcar (lambda (sample) (abs (- sample p50))) samples)
                   #'<)))
      (list :p05 (%stages-percentile sorted 0.05d0)
            :p50 p50
            :p95 (%stages-percentile sorted 0.95d0)
            :mad (%stages-percentile deviations 0.50d0))))

  (defun %stages-run-paired (name cache-state thunk candidate-output-p
                           expected-signature expected-hash warmup-pairs sample-pairs
                           &optional (thunk-b thunk) (arm-a-label "A")
                             (arm-b-label "B")
                             (interpretation "identical_code_noise_floor"))
    (let ((arm-a-samples nil)
          (arm-b-samples nil)
          (paired-differences nil))
      (dotimes (index warmup-pairs)
        (%stages-paired-run name thunk thunk-b cache-state candidate-output-p
                            expected-signature expected-hash (evenp index)))
      (dotimes (index sample-pairs)
        (multiple-value-bind (a-time b-time)
            (%stages-paired-run name thunk thunk-b cache-state candidate-output-p
                                expected-signature expected-hash (evenp index))
          (push a-time arm-a-samples)
          (push b-time arm-b-samples)
          (push (- a-time b-time) paired-differences)))
      (setf arm-a-samples (nreverse arm-a-samples)
            arm-b-samples (nreverse arm-b-samples)
            paired-differences (nreverse paired-differences))
      (let ((a-stats (%stages-statistics arm-a-samples))
            (b-stats (%stages-statistics arm-b-samples))
            (difference-stats (%stages-statistics paired-differences)))
        (format t
                "~&phase=~A cache_state=~A warmup_pairs=~D excluded=true measured_pairs=~D order=alternating_AB_BA arm_a_label=~A arm_b_label=~A same_process=true same_thunk=~A~%"
                name cache-state warmup-pairs sample-pairs arm-a-label arm-b-label
                (if (eq thunk thunk-b) "true" "false"))
        (format t
                "  arm_a_ms_p05=~,3F arm_a_ms_p50=~,3F arm_a_ms_p95=~,3F arm_a_ms_mad=~,3F~%"
                (getf a-stats :p05) (getf a-stats :p50)
                (getf a-stats :p95) (getf a-stats :mad))
        (format t
                "  arm_b_ms_p05=~,3F arm_b_ms_p50=~,3F arm_b_ms_p95=~,3F arm_b_ms_mad=~,3F~%"
                (getf b-stats :p05) (getf b-stats :p50)
                (getf b-stats :p95) (getf b-stats :mad))
        (format t
                "  paired_diff_a_minus_b_ms_p05=~,3F paired_diff_a_minus_b_ms_p50=~,3F paired_diff_a_minus_b_ms_p95=~,3F paired_diff_a_minus_b_ms_mad=~,3F~%"
                (getf difference-stats :p05) (getf difference-stats :p50)
                (getf difference-stats :p95) (getf difference-stats :mad))
        (format t
                "  arm_a_faster_pairs=~D arm_b_faster_pairs=~D ties=~D interpretation=~A~%"
                (count-if #'minusp paired-differences)
                (count-if #'plusp paired-differences)
                (count-if #'zerop paired-differences)
                interpretation)
        (format t "  arm_a_raw_ms=~S~%" arm-a-samples)
        (format t "  arm_b_raw_ms=~S~%" arm-b-samples)
        (format t "  paired_diff_a_minus_b_raw_ms=~S~%" paired-differences))))

  (defun run-completion-filesystem-stages ()
    (let* ((fixture-argument (car (last sb-ext:*posix-argv*)))
           (fixture-directory
             (and fixture-argument
                  (host-kit:ensure-directory-pathname
                   (pathname fixture-argument))))
           (filesystem
             (nshell.infrastructure.acl:make-host-filesystem))
           (directory-files-function
             (nshell.domain.filesystem:filesystem-directory-files filesystem))
           (completion-entries-function
             (nshell.domain.filesystem:filesystem-completion-entries filesystem))
           (enumeration-thunk
             (lambda ()
               (funcall completion-entries-function fixture-directory)))
           (prefix
             (and fixture-directory
                  (format nil "~Aitem-" (namestring fixture-directory))))
           (warmup-pairs
             (%stages-environment-integer
              "NSHELL_FS_STAGES_WARMUP_PAIRS"
              +stages-default-warmup-pairs+))
           (sample-pairs
             (%stages-environment-integer
              "NSHELL_FS_STAGES_SAMPLES"
              +stages-default-sample-pairs+)))
      (unless (and fixture-directory
                   (functionp directory-files-function)
                   (functionp completion-entries-function))
        (error "Expected fixture directory and both filesystem callbacks"))
      (unless (>= sample-pairs +stages-minimum-sample-pairs+)
        (error "At least ~D measured pairs are required"
               +stages-minimum-sample-pairs+))
      (let* ((legacy-paths
               (progn
                 (nshell.infrastructure.acl:clear-directory-listing-cache)
                 (funcall directory-files-function fixture-directory)))
             (completion-entries
               (progn
                 (nshell.infrastructure.acl:clear-directory-listing-cache)
                 (funcall completion-entries-function fixture-directory)))
             (legacy-path-count (length legacy-paths))
             (legacy-pathname-count (count-if (function pathnamep) legacy-paths))
             (completion-entry-count (length completion-entries))
             (query
               (nshell.domain.completion::%file-completion-query-from-prefix
                prefix t t))
             (legacy-candidates (%stages-convert-entries legacy-paths query))
             (entry-candidates
               (%stages-convert-completion-entries completion-entries query))
             (production-candidates
               (nshell.domain.completion::filesystem-candidates-for-mode
                :files-and-directories prefix filesystem))
             (ranked
               (nshell.domain.completion::%rank-candidates
                prefix entry-candidates))
             (production-ranked
               (nshell.domain.completion::%rank-candidates
                prefix production-candidates))
             (completion-entry-signature
               (%stages-output-signature completion-entries nil))
             (completion-entry-hash
               (%stages-signature-hash completion-entry-signature))
             (legacy-signature
               (%stages-output-signature legacy-candidates t))
             (legacy-hash (%stages-signature-hash legacy-signature))
             (entry-signature
               (%stages-output-signature entry-candidates t))
             (entry-hash (%stages-signature-hash entry-signature))
             (production-signature
               (%stages-output-signature production-candidates t))
             (production-hash (%stages-signature-hash production-signature))
             (ranking-signature (%stages-output-signature ranked t))
             (ranking-hash (%stages-signature-hash ranking-signature))
             (production-ranking-signature
               (%stages-output-signature production-ranked t))
             (production-ranking-hash
               (%stages-signature-hash production-ranking-signature)))
        (unless (= legacy-path-count +stages-fixture-entries+)
          (error "Expected ~D legacy paths, got ~D"
                 +stages-fixture-entries+ legacy-path-count))
        (unless (= legacy-pathname-count +stages-fixture-entries+)
          (error "Expected ~D legacy pathnames, got ~D"
                 +stages-fixture-entries+ legacy-pathname-count))
        (unless (= completion-entry-count +stages-fixture-entries+)
          (error "Expected ~D completion entries, got ~D"
                 +stages-fixture-entries+ completion-entry-count))
        (unless (and (= (length legacy-candidates) +stages-fixture-entries+)
                     (= (length entry-candidates) +stages-fixture-entries+)
                     (= (length ranked) +stages-fixture-entries+))
          (error "Expected ~D candidates, got legacy=~D entry=~D ranking=~D"
                 +stages-fixture-entries+
                 (length legacy-candidates)
                 (length entry-candidates)
                 (length ranked)))
        (unless (and (equal legacy-signature entry-signature)
                     (string= legacy-hash entry-hash))
          (error "Legacy and completion-entry candidate outputs differ"))
        (unless (and (equal entry-signature production-signature)
                     (string= entry-hash production-hash))
          (error "Completion-entry conversion differs from production API"))
        (unless (and (equal ranking-signature production-ranking-signature)
                     (string= ranking-hash production-ranking-hash))
          (error "Staged ranking differs from full filesystem candidate output"))
        (format t
                "~&fixture_entries=~D legacy_paths=~D legacy_pathnames=~D completion_entries=~D legacy_candidates=~D entry_candidates=~D ranked_candidate_count=~D~%"
                legacy-path-count legacy-path-count legacy-pathname-count
                completion-entry-count (length legacy-candidates)
                (length entry-candidates) (length ranked))
        (format t
                "candidate_legacy_path_conversion_hash_fnv1a64=~A candidate_completion_entry_conversion_hash_fnv1a64=~A candidate_output_hash_fnv1a64=~A structural_equal=true~%"
                legacy-hash entry-hash ranking-hash)
        (format t
                "timer=get-internal-real-time units_per_second=~D full_gc_before_each_timed_arm=true~%"
                internal-time-units-per-second)
        (%stages-run-paired
         "enumeration" :application-cold enumeration-thunk nil
         completion-entry-signature completion-entry-hash
         warmup-pairs sample-pairs)
        (%stages-run-paired
         "enumeration" :application-warm enumeration-thunk nil
         completion-entry-signature completion-entry-hash
         warmup-pairs sample-pairs)
        (%stages-run-paired
         "entry-conversion" :memory
         (lambda () (%stages-convert-entries legacy-paths query))
         t legacy-signature legacy-hash warmup-pairs sample-pairs
         (lambda () (%stages-convert-completion-entries completion-entries query))
         "legacy-path-to-name" "completion-entry-name+kind"
         "legacy_vs_completion_entry")
        (%stages-run-paired
         "ranking" :memory
         (lambda ()
           (nshell.domain.completion::%rank-candidates prefix entry-candidates))
         t ranking-signature ranking-hash warmup-pairs sample-pairs)
        (format t "~&focused_benchmark=passed~%"))))

  (handler-case
      (progn
        (run-completion-filesystem-stages)
        (sb-ext:exit :code 0))
    (error (condition)
      (format *error-output* "~&completion filesystem stages failed: ~A~%"
              condition)
      (sb-ext:exit :code 1))))
