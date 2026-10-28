(cl:pushnew
  (cl:symbol-function
   (cl:find-symbol "MODULE-PROVIDE-CONTRIB" :sb-impl))
  sb-ext:*module-provider-functions*)
(cl:require :sb-sprof)
(cl:defparameter nshell.user::*nfr06-v2-command* __COMMAND__)
(cl:defparameter nshell.user::*nfr06-v2-control-dir* __CONTROL__)
(cl:defparameter nshell.user::*nfr06-v2-graph-path* __GRAPH__)
(cl:progn
  (cl:defparameter nshell.user::*nfr06-v2-target-graph-path* __TARGET_GRAPH__)
  (cl:defparameter nshell.user::*nfr06-v2-target-flat-path* __TARGET_FLAT__))
(cl:defparameter nshell.user::*nfr06-v2-flat-path* __FLAT__)
(cl:defparameter nshell.user::*nfr06-v2-metrics-path* __METRICS__)
(cl:defparameter nshell.user::*nfr06-v2-iterations* __ITERATIONS__)
(cl:defparameter nshell.user::*nfr06-v2-mode* __MODE__)
(cl:defparameter nshell.user::*nfr06-v2-main-thread* (sb-thread:main-thread))
(cl:defparameter nshell.user::*nfr06-v2-controller-thread* nil)
(cl:defparameter nshell.user::*nfr06-v2-window-threads* nil)
(cl:defparameter nshell.user::*nfr06-v2-profiled-workers* nil)
(cl:defparameter nshell.user::*nfr06-v2-thread-ids* (cl:make-hash-table :test 'cl:eq))
(cl:defparameter nshell.user::*nfr06-v2-next-thread-id* 0)
(cl:defparameter nshell.user::*nfr06-v2-render-done* (sb-thread:make-semaphore :name "nfr06 render done"))
(cl:defparameter nshell.user::*nfr06-v2-profile-active* nil)
(cl:defparameter nshell.user::*nfr06-v2-window-open* nil)
(cl:defparameter nshell.user::*nfr06-v2-window-index* nil)
(cl:defparameter nshell.user::*nfr06-v2-tab-count* 0)
(cl:defparameter nshell.user::*nfr06-v2-target-count* 0)
(cl:defparameter nshell.user::*nfr06-v2-tab-sequence* nil)
(cl:defparameter nshell.user::*nfr06-v2-target-sequence* nil)
(cl:defparameter nshell.user::*nfr06-v2-measurements* nil)

(cl:defun nshell.user::nfr06-v2-path (name)
  (cl:concatenate 'cl:string nshell.user::*nfr06-v2-control-dir* "/" name))

(cl:defun nshell.user::nfr06-v2-write-file (name text)
  (cl:with-open-file (stream (nshell.user::nfr06-v2-path name)
                             :direction :output :if-exists :supersede
                             :if-does-not-exist :create)
    (cl:write-line text stream)))

(cl:defun nshell.user::nfr06-v2-read-file (name)
  (cl:with-open-file (stream (nshell.user::nfr06-v2-path name) :direction :input)
    (cl:read-line stream nil "")))

(cl:defun nshell.user::nfr06-v2-worker-thread-p (thread)
  (cl:let ((name (sb-thread:thread-name thread))
           (prefix "nshell pipeline stage "))
    (cl:and (cl:stringp name)
            (cl:>= (cl:length name) (cl:length prefix))
            (cl:string= prefix name :end2 (cl:length prefix)))))

(cl:defun nshell.user::nfr06-v2-await-sampling-enabled (thread index)
  (cl:loop repeat 2000
           until (cl:= (sb-thread::%symbol-value-in-thread
                        'sb-thread::*sprof-enable* thread)
                       1)
           do (cl:sleep 0.001)
           finally (cl:when (cl:/= (sb-thread::%symbol-value-in-thread
                                    'sb-thread::*sprof-enable* thread)
                                   1)
                     (cl:error "thread ~A did not enable sampling at index ~D"
                               (sb-thread:thread-name thread) index))))

(cl:defun nshell.user::nfr06-v2-start-window-thread (thread index)
  (cl:unless (cl:member thread nshell.user::*nfr06-v2-window-threads* :test #'cl:eq)
    (sb-sprof:start-sampling thread)
    (nshell.user::nfr06-v2-await-sampling-enabled thread index)
    (cl:push thread nshell.user::*nfr06-v2-window-threads*)
    (cl:when (nshell.user::nfr06-v2-worker-thread-p thread)
      (cl:pushnew thread nshell.user::*nfr06-v2-profiled-workers* :test #'cl:eq)))
  thread)

(cl:defun nshell.user::nfr06-v2-discover-workers (index)
  (cl:dolist (thread (sb-thread:list-all-threads))
    (cl:when (cl:and (sb-thread:thread-alive-p thread)
                     (nshell.user::nfr06-v2-worker-thread-p thread))
      (nshell.user::nfr06-v2-start-window-thread thread index))))

(cl:defun nshell.user::nfr06-v2-stop-window-threads ()
  (cl:dolist (thread nshell.user::*nfr06-v2-window-threads*)
    (sb-sprof:stop-sampling thread))
  (cl:setf nshell.user::*nfr06-v2-window-threads* cl:nil))

(cl:defun nshell.user::nfr06-v2-thread-id (thread)
  (cl:or (cl:gethash thread nshell.user::*nfr06-v2-thread-ids*)
         (cl:setf (cl:gethash thread nshell.user::*nfr06-v2-thread-ids*)
                  (cl:incf nshell.user::*nfr06-v2-next-thread-id*))))

(cl:defun nshell.user::nfr06-v2-filter-samples (samples predicate)
  (cl:let ((selected cl:nil)
           (total-length 0)
           (trace-count 0))
    (sb-sprof:map-traces
     (cl:lambda (thread trace)
       (cl:when (cl:funcall predicate thread)
         (cl:destructuring-bind (source start end) trace
           (cl:push (cl:list thread source start end) selected)
           (cl:incf total-length (- end start))
           (cl:incf trace-count))))
     samples)
    (cl:let ((filtered (cl:copy-structure samples))
             (vector (cl:make-array total-length))
             (sampled-threads
               (cl:remove-if-not
                (cl:lambda (entry) (cl:funcall predicate (cl:first entry)))
                (sb-sprof::samples-sampled-threads samples)))
             (index 0))
      (cl:dolist (entry (cl:nreverse selected))
        (cl:destructuring-bind (thread source start end) entry
          (cl:let ((new-end (+ index (- end start))))
            (cl:setf (cl:aref vector index) (cl:cons 'sb-sprof::trace-start new-end)
                     (cl:aref vector (cl:1+ index)) thread)
            (cl:replace vector source :start1 (+ index 2) :start2 (+ start 2) :end2 end)
            (cl:setf index new-end))))
      (cl:setf (sb-sprof::samples-vector filtered) vector
               (sb-sprof::samples-trace-count filtered) trace-count
               (sb-sprof::samples-unique-trace-count filtered) trace-count
               (sb-sprof::samples-sampled-threads filtered) sampled-threads)
      filtered)))

(cl:defun nshell.user::nfr06-v2-vector-trace-count (samples)
  (cl:let* ((vector (sb-sprof::samples-vector samples))
            (vector-length (cl:length vector))
            (index 0)
            (count 0))
    (cl:loop while (cl:< index vector-length)
             do (cl:let ((marker (cl:aref vector index)))
                  (cl:unless (cl:and (cl:consp marker)
                                     (cl:eq (cl:car marker) 'sb-sprof::trace-start)
                                     (cl:integerp (cl:cdr marker))
                                     (cl:< index (cl:cdr marker))
                                     (cl:<= (cl:cdr marker) vector-length))
                    (cl:error "invalid raw sample trace marker at index ~D" index))
                  (cl:incf count)
                  (cl:setf index (cl:cdr marker))))
    count))

(cl:defun nshell.user::nfr06-v2-write-thread-counts ()
  (cl:let* ((counts (cl:make-hash-table :test 'cl:eq))
            (threads (cl:remove-duplicates
                      (cl:append (cl:list nshell.user::*nfr06-v2-main-thread*
                                           nshell.user::*nfr06-v2-controller-thread*)
                                 nshell.user::*nfr06-v2-profiled-workers*)
                      :test #'cl:eq))
            (samples (cl:symbol-value (cl:find-symbol "*SAMPLES*" :sb-sprof)))
            (vector (sb-sprof::samples-vector samples))
            (raw-vector-count
              (nshell.user::nfr06-v2-vector-trace-count samples))
            (map-trace-count 0))
    (sb-sprof:map-traces
     (cl:lambda (thread trace)
       (cl:declare (cl:ignore trace))
       (cl:pushnew thread threads :test #'cl:eq)
       (cl:incf map-trace-count)
       (cl:incf (cl:gethash thread counts 0)))
     samples)
    (cl:with-open-file (stream (cl:concatenate 'cl:string
                                                nshell.user::*nfr06-v2-control-dir*
                                                "/thread-counts.csv")
                               :direction :output :if-exists :supersede
                               :if-does-not-exist :create)
      (cl:write-line "thread_id,thread,role,samples" stream)
      (cl:dolist (thread threads)
        (cl:format stream "~D,~A,~A,~D~%"
                   (nshell.user::nfr06-v2-thread-id thread)
                   (sb-thread:thread-name thread)
                   (cl:cond ((cl:eq thread nshell.user::*nfr06-v2-main-thread*) "main")
                            ((cl:eq thread nshell.user::*nfr06-v2-controller-thread*) "controller")
                            ((nshell.user::nfr06-v2-worker-thread-p thread) "pipeline-worker")
                            (cl:t "other"))
                   (cl:gethash thread counts 0))))
    (nshell.user::nfr06-v2-write-file
     "sample-counts.txt"
     (cl:format cl:nil
                "sb_sprof_stop_counter=~D~%raw_vector_trace_count=~D~%map_traces_count=~D~%samples_vector_length=~D~%"
                (sb-sprof::samples-trace-count samples)
                raw-vector-count
                map-trace-count
                (cl:length vector)))))

(cl:defun nshell.user::nfr06-v2-write-metrics ()
  (cl:unless
      (cl:and
       (cl:= nshell.user::*nfr06-v2-tab-count*
             nshell.user::*nfr06-v2-iterations*)
       (cl:= nshell.user::*nfr06-v2-target-count*
             nshell.user::*nfr06-v2-iterations*)
       (cl:= (cl:length nshell.user::*nfr06-v2-measurements*)
             nshell.user::*nfr06-v2-iterations*))
    (cl:error "profile Tab counts mismatch: input=~D target=~D metrics=~D expected=~D"
              nshell.user::*nfr06-v2-tab-count*
              nshell.user::*nfr06-v2-target-count*
              (cl:length nshell.user::*nfr06-v2-measurements*)
              nshell.user::*nfr06-v2-iterations*))
  (cl:with-open-file (stream nshell.user::*nfr06-v2-metrics-path*
                             :direction :output :if-exists :supersede
                             :if-does-not-exist :create)
    (cl:format stream
               "# input_tab_count=~D~%# target_tab_count=~D~%# input_tab_sequence=~{~D~^,~}~%# target_tab_sequence=~{~D~^,~}~%"
               nshell.user::*nfr06-v2-tab-count*
               nshell.user::*nfr06-v2-target-count*
               (cl:nreverse nshell.user::*nfr06-v2-tab-sequence*)
               (cl:nreverse nshell.user::*nfr06-v2-target-sequence*))
    (cl:write-line "iteration,bytes_cons,gc_run_delta_ticks,cache_before,cache_after"
                   stream)
    (cl:dolist (row (cl:nreverse nshell.user::*nfr06-v2-measurements*))
      (cl:format stream "~D,~D,~D,~D,~D~%"
                 (cl:first row) (cl:second row) (cl:third row)
                 (cl:fourth row) (cl:fifth row)))))

(cl:defun nshell.user::nfr06-v2-start-profile ()
  (sb-ext:gc :full cl:t)
  (sb-sprof:reset)
  (sb-sprof:start-profiling __PROFILE_OPTIONS__ :threads :all)
  (cl:setf nshell.user::*nfr06-v2-profile-active* cl:t)
  (cl:dolist (thread (sb-thread:list-all-threads))
    (sb-sprof:stop-sampling thread))
  (nshell.user::nfr06-v2-write-file
   "start.ack"
   (cl:format cl:nil "started mode=~A profile-threads=all controller-thread=~A controller-is-main=~A target-thread=~A main-sampling=off worker-sampling=off"
              nshell.user::*nfr06-v2-mode*
              (sb-thread:thread-name sb-thread:*current-thread*)
              (cl:eq sb-thread:*current-thread* (sb-thread:main-thread))
               (sb-thread:thread-name nshell.user::*nfr06-v2-main-thread*))))

(cl:defun nshell.user::nfr06-v2-target-window (index)
  (cl:when nshell.user::*nfr06-v2-window-open*
    (cl:error "target window already open"))
  (cl:setf nshell.user::*nfr06-v2-window-index* index
           nshell.user::*nfr06-v2-window-open* cl:t
           nshell.user::*nfr06-v2-window-threads* cl:nil)
  (nshell.user::nfr06-v2-start-window-thread nshell.user::*nfr06-v2-main-thread* index)
  (nshell.user::nfr06-v2-discover-workers index)
  (cl:let ((sample-start-ticks (cl:get-internal-real-time)))
  (nshell.user::nfr06-v2-write-file
   "window-start.ack"
   (cl:format cl:nil "started index=~D sample-start-ticks=~D sampled-thread-count=~D sampled-workers=~{~A~^|~} controller-thread=~A controller-is-main=~A target-thread=~A"
              index
              sample-start-ticks
              (cl:length nshell.user::*nfr06-v2-window-threads*)
              (cl:mapcar #'sb-thread:thread-name
                         (cl:remove-if-not #'nshell.user::nfr06-v2-worker-thread-p
                                           nshell.user::*nfr06-v2-window-threads*))
              (sb-thread:thread-name sb-thread:*current-thread*)
              (cl:eq sb-thread:*current-thread* (sb-thread:main-thread))
              (sb-thread:thread-name nshell.user::*nfr06-v2-main-thread*)))
  (cl:let ((rendered
             (cl:let ((deadline (+ (cl:get-internal-real-time)
                                   (cl:floor (* __RENDER_TIMEOUT_SECONDS__ cl:internal-time-units-per-second)))))
               (cl:loop while (cl:< (cl:get-internal-real-time) deadline)
                        do (cl:when (sb-thread:wait-on-semaphore
                                     nshell.user::*nfr06-v2-render-done* :timeout 0.002)
                             (cl:return cl:t))
                           (nshell.user::nfr06-v2-discover-workers index)))))
  (cl:unless rendered
    (nshell.user::nfr06-v2-stop-window-threads)
    (cl:setf nshell.user::*nfr06-v2-window-open* cl:nil)
    (cl:error "completion render semaphore timed out at index ~D" index))
  (cl:let ((render-done-ticks (cl:get-internal-real-time))
           (window-thread-snapshot (cl:copy-list nshell.user::*nfr06-v2-window-threads*)))
  (nshell.user::nfr06-v2-stop-window-threads)
  (cl:setf nshell.user::*nfr06-v2-window-open* cl:nil)
  (cl:let ((sample-stop-ticks (cl:get-internal-real-time)))
  (nshell.user::nfr06-v2-write-file
   "window-stop.ack"
   (cl:format cl:nil "stopped index=~D sample-start-ticks=~D render-done-ticks=~D sample-stop-ticks=~D ticks-per-second=~D sampled-workers=~{~A~^|~} controller-thread=~A controller-is-main=~A target-thread=~A"
              index
              sample-start-ticks
              render-done-ticks
              sample-stop-ticks
              cl:internal-time-units-per-second
              (cl:mapcar #'sb-thread:thread-name
                         (cl:remove-if-not #'nshell.user::nfr06-v2-worker-thread-p
                                           window-thread-snapshot))
              (sb-thread:thread-name sb-thread:*current-thread*)
              (cl:eq sb-thread:*current-thread* (sb-thread:main-thread))
               (sb-thread:thread-name nshell.user::*nfr06-v2-main-thread*))))))))

(cl:defun nshell.user::nfr06-v2-stop-profile ()
  (cl:when nshell.user::*nfr06-v2-window-open*
    (cl:error "cannot stop profile while target window is open"))
  (sb-sprof:stop-profiling)
  (cl:let ((samples (cl:symbol-value (cl:find-symbol "*SAMPLES*" :sb-sprof))))
    (cl:unless (cl:plusp (cl:length (sb-sprof::samples-vector samples)))
      (cl:multiple-value-bind (vector unique-trace-count sampled-threads)
          (sb-sprof::convert-raw-data)
        (cl:setf (sb-sprof::samples-vector samples) vector
                 (sb-sprof::samples-unique-trace-count samples) unique-trace-count
                 (sb-sprof::samples-sampled-threads samples) sampled-threads)))
    (cl:let* ((raw-vector-count
                (nshell.user::nfr06-v2-vector-trace-count samples))
              (report-samples (cl:copy-structure samples)))
      (cl:setf (sb-sprof::samples-trace-count report-samples) raw-vector-count)
      (nshell.user::nfr06-v2-write-thread-counts)
      (cl:let ((call-graph
                 (sb-sprof::make-call-graph-1 report-samples most-positive-fixnum)))
        (cl:with-open-file (stream nshell.user::*nfr06-v2-graph-path*
                                   :direction :output :if-exists :supersede
                                   :if-does-not-exist :create)
          (sb-sprof:report :type :graph :call-graph call-graph :stream stream
                           :min-percent 0 :show-progress cl:nil))
        (cl:with-open-file (stream nshell.user::*nfr06-v2-flat-path*
                                   :direction :output :if-exists :supersede
                                   :if-does-not-exist :create)
          (sb-sprof:report :type :flat :call-graph call-graph :stream stream
                           :min-percent 0 :show-progress cl:nil)))))
  (cl:let* ((samples (cl:symbol-value (cl:find-symbol "*SAMPLES*" :sb-sprof)))
          (target-samples
            (nshell.user::nfr06-v2-filter-samples
             samples
             (cl:lambda (thread)
               (cl:or (cl:eq thread nshell.user::*nfr06-v2-main-thread*)
                      (nshell.user::nfr06-v2-worker-thread-p thread)))))
          (target-count (sb-sprof::samples-trace-count target-samples)))
  (cl:when (cl:plusp target-count)
    (cl:let ((target-graph
               (sb-sprof::make-call-graph-1 target-samples most-positive-fixnum)))
      (cl:progn
  (cl:with-open-file
      (stream nshell.user::*nfr06-v2-target-graph-path*
              :direction :output :if-exists :supersede :if-does-not-exist :create)
    (sb-sprof:report :type :graph :call-graph target-graph :stream stream
                     :min-percent 0 :show-progress cl:nil))
  (cl:with-open-file
      (stream nshell.user::*nfr06-v2-target-flat-path*
              :direction :output :if-exists :supersede :if-does-not-exist :create)
    (sb-sprof:report :type :flat :call-graph target-graph :stream stream
                     :min-percent 0 :show-progress cl:nil)))))
  (nshell.user::nfr06-v2-write-file
   "target-samples.ack"
   (cl:format cl:nil "target-samples=~D target-workers=~{~A~^|~}"
              target-count
              (cl:mapcar #'sb-thread:thread-name
                         (cl:remove-if-not #'nshell.user::nfr06-v2-worker-thread-p
                                           nshell.user::*nfr06-v2-profiled-workers*)))))
  (nshell.user::nfr06-v2-write-metrics)
  (cl:setf nshell.user::*nfr06-v2-profile-active* cl:nil)
  (nshell.user::nfr06-v2-write-file
   "stop.ack"
   (cl:format cl:nil "stopped controller-thread=~A controller-is-main=~A target-count=~D"
              (sb-thread:thread-name sb-thread:*current-thread*)
              (cl:eq sb-thread:*current-thread* (sb-thread:main-thread))
              nshell.user::*nfr06-v2-target-count*)))

(cl:defun nshell.user::nfr06-v2-controller ()
  (cl:handler-case
      (cl:progn
        (nshell.user::nfr06-v2-write-file
         "controller.ready"
         (cl:format cl:nil "ready controller-thread=~A controller-is-main=~A target-thread=~A"
                    (sb-thread:thread-name sb-thread:*current-thread*)
                    (cl:eq sb-thread:*current-thread* (sb-thread:main-thread))
                    (sb-thread:thread-name nshell.user::*nfr06-v2-main-thread*)))
        (cl:loop
          (cl:when (cl:probe-file (nshell.user::nfr06-v2-path "start.req"))
            (cl:delete-file (nshell.user::nfr06-v2-path "start.req"))
            (nshell.user::nfr06-v2-start-profile))
          (cl:when (cl:and nshell.user::*nfr06-v2-profile-active*
                           (cl:probe-file (nshell.user::nfr06-v2-path "window-start.req")))
            (cl:let ((index (cl:parse-integer
                             (nshell.user::nfr06-v2-read-file "window-start.req"))))
              (cl:delete-file (nshell.user::nfr06-v2-path "window-start.req"))
              (nshell.user::nfr06-v2-target-window index)))
          (cl:when (cl:and nshell.user::*nfr06-v2-profile-active*
                           (cl:probe-file (nshell.user::nfr06-v2-path "stop.req")))
            (cl:delete-file (nshell.user::nfr06-v2-path "stop.req"))
            (nshell.user::nfr06-v2-stop-profile))
          (cl:when (cl:probe-file (nshell.user::nfr06-v2-path "shutdown.req"))
            (cl:delete-file (nshell.user::nfr06-v2-path "shutdown.req"))
            (cl:return))
          (cl:sleep 0.002))
        (nshell.user::nfr06-v2-write-file
         "controller.stopped"
         (cl:format cl:nil "stopped controller-thread=~A controller-is-main=~A"
                    (sb-thread:thread-name sb-thread:*current-thread*)
                    (cl:eq sb-thread:*current-thread* (sb-thread:main-thread)))))
    (cl:error (condition)
      (cl:when nshell.user::*nfr06-v2-profile-active*
        (cl:ignore-errors
          (nshell.user::nfr06-v2-stop-window-threads)
          (cl:setf nshell.user::*nfr06-v2-window-open* cl:nil)
          (nshell.user::nfr06-v2-stop-profile)))
      (nshell.user::nfr06-v2-write-file
       "controller.error"
       (cl:format cl:nil "type=~A condition=~A" (cl:type-of condition) condition)))))



(cl:setf nshell.user::*nfr06-v2-controller-thread*
         (sb-thread:make-thread #'nshell.user::nfr06-v2-controller
                                :name "nfr06-v2-controller"))

(cl:let ((await-render cl:nil)
         (pending-index cl:nil)
         (pending-bytes-before cl:nil)
         (pending-gc-before cl:nil)
         (pending-cache-before cl:nil))
  (cl:let* ((package (cl:find-package "NSHELL.PRESENTATION"))
            (input-symbol (cl:find-symbol "%PROCESS-INPUT-EVENT" package))
            (input-original (cl:symbol-function input-symbol))
            (render-symbol (cl:find-symbol "RENDER-PROMPT-CONT" package))
            (render-original (cl:symbol-function render-symbol)))
    (cl:setf (cl:symbol-function input-symbol)
             (cl:lambda (event)
               (cl:let* ((tab-event
                           (cl:eq :tab (nshell.domain.input:key-event-type event)))
                         (target-tab
                           (cl:and tab-event
                                   (cl:string=
                                    (nshell.presentation::input-state-buffer
                                     nshell.presentation::*input-state*)
                                    nshell.user::*nfr06-v2-command*)))
                         (tab-index
                           (cl:when tab-event
                             (cl:incf nshell.user::*nfr06-v2-tab-count*)))
                         (target-index
                           (cl:when target-tab
                             (cl:incf nshell.user::*nfr06-v2-target-count*))))
                 (cl:when tab-event
                   (cl:push tab-index nshell.user::*nfr06-v2-tab-sequence*))
                 (cl:when target-tab
                   (cl:push target-index nshell.user::*nfr06-v2-target-sequence*)
                   (cl:unless
                       (cl:and nshell.user::*nfr06-v2-window-open*
                               (cl:= nshell.user::*nfr06-v2-window-index*
                                     (cl:1- target-index)))
                     (cl:error "target Tab outside its controller window: index=~D window=~S"
                               target-index nshell.user::*nfr06-v2-window-index*))
                   (cl:setf await-render cl:t
                            pending-index target-index
                            pending-bytes-before (sb-ext:get-bytes-consed)
                            pending-gc-before sb-ext:*gc-run-time*
                            pending-cache-before
                            (cl:not
                             (cl:null
                              (nshell.domain.completion::rule-knowledge-base-%rulebase-cache
                               nshell.presentation::*kb*)))))
                 (cl:funcall input-original event)))
    (cl:setf (cl:symbol-function render-symbol)
             (cl:lambda ()
               (cl:multiple-value-prog1
                   (cl:funcall render-original)
                 (cl:when await-render
                   (cl:setf await-render cl:nil)
                   (cl:let* ((bytes-cons
                               (- (sb-ext:get-bytes-consed) pending-bytes-before))
                             (gc-delta
                               (- sb-ext:*gc-run-time* pending-gc-before))
                             (cache-after
                               (cl:not
                                (cl:null
                                 (nshell.domain.completion::rule-knowledge-base-%rulebase-cache
                                  nshell.presentation::*kb*)))))
                     (cl:push
                      (cl:list pending-index bytes-cons gc-delta
                               (cl:if pending-cache-before 1 0)
                               (cl:if cache-after 1 0))
                      nshell.user::*nfr06-v2-measurements*))
                   (sb-thread:signal-semaphore
                    nshell.user::*nfr06-v2-render-done*))))))))

(nshell.user::nfr06-v2-write-file "init.ready" "completion wrapper installed")
(cl:format cl:*standard-output* "NFR06_V2_READY~%")
(cl:finish-output cl:*standard-output*)
