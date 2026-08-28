;;; benchmark-research-shelf.el --- Cross-package ETAF latency gate -*- lexical-binding: t; -*-

;;; Commentary:
;; Generic evaluator primitives exercised with Research Shelf as one fixed,
;; deterministic, real cross-package workload.  Trace assertions consume only
;; public `etaf-performance' records; application concepts stay out of the
;; recorder itself.

;;; Code:
(require 'cl-lib)
(require 'seq)
(require 'etaf-playground)
(require 'etaf-performance)
(require 'ebox-native-reflow)

(defvar etaf-research-shelf-database-file)
(defvar etaf-research-shelf-fixture-size)
(defvar etaf-research-shelf-page-size)
(declare-function etaf-research-shelf--ensure-database
                  "../examples/research-shelf")

(defconst etaf-performance-evaluator-warmup-count 5)
(defconst etaf-performance-evaluator-sample-count 30)
(defconst etaf-performance-evaluator-latency-budget-ms 50.0)
(defconst etaf-performance-evaluator-overhead-budget-ms 2.0)
(defconst etaf-performance-evaluator-fixture-size 256)
(defconst etaf-performance-evaluator-page-size 12)
(defconst etaf-performance-evaluator-viewport-width 1413)
(defconst etaf-performance-evaluator-viewport-height 62)

(defun etaf-performance-evaluator--percentile (samples percentile)
  "Return nearest-rank PERCENTILE from non-empty numeric SAMPLES."
  (unless samples (error "Cannot summarize an empty performance sample"))
  (let* ((ordered (sort (copy-sequence samples) #'<))
         (rank (max 1 (ceiling (* percentile (length ordered))))))
    (nth (1- rank) ordered)))

(defun etaf-performance-evaluator--statistics (samples)
  "Return min, p50, p95, and max statistics for SAMPLES."
  (list :count (length samples) :min (apply #'min samples)
        :p50 (etaf-performance-evaluator--percentile samples 0.50)
        :p95 (etaf-performance-evaluator--percentile samples 0.95)
        :max (apply #'max samples)))

(defun etaf-performance-evaluator--print-statistics (label statistics)
  "Print LABEL and STATISTICS in stable machine-readable form."
  (princ (format (concat "perf-scenario=%s samples=%d min=%.3fms "
                         "p50=%.3fms p95=%.3fms max=%.3fms\n")
                 label (plist-get statistics :count)
                 (plist-get statistics :min) (plist-get statistics :p50)
                 (plist-get statistics :p95) (plist-get statistics :max))))

(defun etaf-performance-evaluator--timed-call (function)
  "Call FUNCTION and return `(ELAPSED-MS . RESULT)'."
  (let ((started (float-time)) result)
    (setq result (funcall function))
    (cons (* 1000.0 (- (float-time) started)) result)))

(cl-defun etaf-performance-evaluator--measure
    (label action verify &key setup cleanup
           (warmups etaf-performance-evaluator-warmup-count)
           (samples etaf-performance-evaluator-sample-count))
  "Warm, then measure ACTION under LABEL and verify every result.
ACTION, VERIFY, SETUP, and CLEANUP receive an index.  WARMUPS use negative
indices and are never included in SAMPLES.  ACTION's result is passed to
VERIFY and CLEANUP."
  (let (durations)
    ;; Batch Emacs does not run the interactive 0.2s deferred-GC timer between
    ;; synthetic inputs.  Settle that idle work before, never inside, samples.
    (garbage-collect)
    (dotimes (offset warmups)
      (let ((index (- offset warmups)))
        (when setup (funcall setup index))
        (let ((result (funcall action index)))
          (funcall verify result index)
          (when cleanup (funcall cleanup result index)))))
    (dotimes (index samples)
      (when setup (funcall setup index))
      (garbage-collect)
      (let (timed)
        ;; Interactive Ebox render bursts postpone GC until after visible
        ;; completion.  A batch burst restores the process threshold
        ;; synchronously, which can make the harness collect before its Lisp
        ;; caller returns.  Stop the timer before restoring that batch-only
        ;; threshold; the explicit collection above still settles every run.
        (let ((gc-cons-threshold most-positive-fixnum)
              (gc-cons-percentage 1.0))
          (setq timed
                (etaf-performance-evaluator--timed-call
                 (lambda () (funcall action index)))))
        (pcase-let ((`(,elapsed . ,result) timed))
          (funcall verify result index)
          (when cleanup (funcall cleanup result index))
          (push elapsed durations))))
    (let ((statistics
           (etaf-performance-evaluator--statistics (nreverse durations))))
      (etaf-performance-evaluator--print-statistics label statistics)
      (cons label statistics))))

(defun etaf-performance-evaluator--text (buffer)
  "Return BUFFER's rendered text without properties."
  (with-current-buffer buffer
    (substring-no-properties (buffer-string))))

(defun etaf-performance-evaluator--surface-invariant (runtime buffer label)
  "Assert committed RUNTIME/publication invariants in BUFFER for LABEL."
  (unless (and (buffer-live-p (get-buffer buffer))
               (eq runtime (etaf-runtime-for-buffer buffer)))
    (error "%s: mounted Runtime/buffer invariant failed" label))
  (let ((generation (etaf-runtime-current-generation runtime)))
    (unless (and (etaf-generation-p generation)
                 (integerp (etaf-runtime-generation runtime))
                 (> (etaf-runtime-generation runtime) 0)
                 (integerp (etaf-generation-root-semantic-id generation))
                 (etaf-runtime-handler-entries runtime)
                 (etaf-runtime-host-props-entries runtime))
      (error "%s: committed generation/publication structure is incomplete"
             label)))
  (unless (> (buffer-size (get-buffer buffer)) 0)
    (error "%s: publication produced an empty visible buffer" label))
  t)

(defun etaf-performance-evaluator--load-workload ()
  "Load the deterministic integration workload companion."
  (let* ((source (expand-file-name "examples/research-shelf.el"
                                   default-directory))
         (compiled (concat (file-name-sans-extension source) ".elc")))
    (load (if (and (file-readable-p compiled)
                   (not (file-newer-than-file-p source compiled)))
              compiled source)
          nil nil t)))

(defun etaf-performance-evaluator--prepare-database (database)
  "Prepare DATABASE outside the measured mount operation."
  (let ((etaf-research-shelf-database-file database)
        (etaf-research-shelf-fixture-size
         etaf-performance-evaluator-fixture-size)
        (etaf-research-shelf-page-size etaf-performance-evaluator-page-size))
    (etaf-research-shelf--ensure-database))
  (unless (and (file-exists-p database)
               (> (file-attribute-size (file-attributes database)) 0))
    (error "Prepared SQLite fixture was not created: %s" database)))

(defun etaf-performance-evaluator--verify-runtime-accelerator ()
  "Require the optional Ebox native runtime accelerator."
  (unless (and (require 'ebox-native-reflow nil t)
               (ebox-native-reflow-layout-ready-p))
    (error "Performance evaluator requires the Ebox native runtime"))
  (princ "perf-runtime-accelerator=ready\n")
  t)

(defun etaf-performance-evaluator--verify-environment (environment)
  "Require ENVIRONMENT to be suitable for an absolute latency gate."
  (let* ((power (plist-get environment :power-state))
         (source (or (plist-get power :source) 'unknown))
         (low-power (or (plist-get power :low-power-mode) 'unknown))
         (native-jit (plist-get environment :native-comp-jit-compilation))
         (load (plist-get environment :load-average)))
    (princ
     (format
      "perf-environment power-source=%s low-power-mode=%s native-jit=%S load=%S\n"
      source low-power native-jit load))
    (when (eq low-power 'on)
      (error (concat "Performance evaluator requires low-power mode off; "
                     "current source=%s")
             source))
    (when native-jit
      (error "Performance evaluator requires native-comp JIT disabled")))
  environment)

(defun etaf-performance-evaluator--mount (buffer)
  "Mount the fixed workload in BUFFER at the fixed viewport."
  (etaf-playground-mount-example
   buffer "research-shelf" nil
   (list :viewport-width etaf-performance-evaluator-viewport-width
         :viewport-height etaf-performance-evaluator-viewport-height))
  (etaf-runtime-for-buffer buffer))

(defun etaf-performance-evaluator--close-buffer (buffer)
  "Unmount and close BUFFER when it is live."
  (when (get-buffer buffer) (etaf-playground-close buffer)))

(defun etaf-performance-evaluator--visible-match-p (buffer regexp)
  "Return non-nil when BUFFER's visible text matches REGEXP."
  (string-match-p regexp (etaf-performance-evaluator--text buffer)))

(defun etaf-performance-evaluator--trace-categories (records)
  "Return unique stage categories present in performance RECORDS."
  (let (categories)
    (dolist (operation records)
      (dolist (stage (etaf-performance-operation-stages operation))
        (cl-pushnew (etaf-performance-stage-category stage) categories)))
    categories))

(defun etaf-performance-evaluator--verify-trace-records (records)
  "Verify generic cross-package RECORDS are successful and complete."
  (unless records (error "Trace-on run produced no etaf-performance records"))
  (dolist (operation records)
    (unless (eq (etaf-performance-operation-status operation) 'success)
      (error "Trace operation %s (%s) finished with status %s"
             (etaf-performance-operation-id operation)
             (etaf-performance-operation-label operation)
             (etaf-performance-operation-status operation)))
    (dolist (stage (etaf-performance-operation-stages operation))
      (unless (eq (etaf-performance-stage-status stage) 'success)
        (error "Trace stage %s/%s finished with status %s"
               (etaf-performance-stage-category stage)
               (etaf-performance-stage-name stage)
               (etaf-performance-stage-status stage)))))
  (let ((categories (etaf-performance-evaluator--trace-categories records)))
    (dolist (required '(runtime ebox tp sqlite))
      (unless (memq required categories)
        (error "Trace records lack required %s stage; present=%S"
               required categories)))
    (setq categories
          (sort categories (lambda (left right)
                             (string< (symbol-name left)
                                      (symbol-name right)))))
    (princ (format "perf-trace records=%d categories=%S status=success\n"
                   (length records) categories))))

(defun etaf-performance-evaluator--print-slowest-records (records)
  "Print the two slowest generic operation RECORDS per kind/label."
  (let ((groups (make-hash-table :test #'equal)) selected)
    (dolist (operation records)
      (let ((key (cons (etaf-performance-operation-kind operation)
                       (etaf-performance-operation-label operation))))
        (puthash key (cons operation (gethash key groups)) groups)))
    (maphash
     (lambda (_key operations)
       (setq selected
             (append
              (seq-take
               (sort operations
                     (lambda (left right)
                       (> (etaf-performance-operation-elapsed left)
                          (etaf-performance-operation-elapsed right))))
               2)
              selected)))
     groups)
    (dolist
        (operation
         (sort selected
               (lambda (left right)
                 (> (etaf-performance-operation-elapsed left)
                    (etaf-performance-operation-elapsed right)))))
    (let* ((gc-count (etaf-performance-operation-gc-count operation))
           (gc-ms (etaf-performance-operation-gc-elapsed operation))
           (stages
            (mapcar
             (lambda (entry)
               (cons (plist-get entry :category)
                     (plist-get entry :duration-ms)))
             (etaf-performance-operation-stage-summary operation))))
      (princ
       (format (concat "perf-slowest id=%d kind=%s label=%S elapsed=%.3fms "
                       "gc=%d/%.3fms stages=%S\n")
               (etaf-performance-operation-id operation)
               (etaf-performance-operation-kind operation)
               (etaf-performance-operation-label operation)
               (etaf-performance-operation-elapsed operation)
               gc-count gc-ms stages))
      (dolist (stage (etaf-performance-operation-stages operation))
        (princ
         (format
          "perf-stage id=%d provider=%s name=%s duration=%.3fms metadata=%S\n"
          (etaf-performance-operation-id operation)
          (etaf-performance-stage-provider stage)
          (etaf-performance-stage-name stage)
          (etaf-performance-stage-duration stage)
          (etaf-performance-stage-metadata stage))))))))

(defun etaf-performance-evaluator--select-ref (runtime ref)
  "Select workload row REF through RUNTIME's public event path."
  (etaf-dispatch-event runtime ref 'press)
  ref)

(defun etaf-performance-evaluator--measure-overhead
    (runtime buffer &optional reset-ref)
  "Measure trace overhead for RUNTIME with visible state in BUFFER.
RESET-REF defaults to the first Research Shelf row."
  (let ((reset-ref (or reset-ref 'research-shelf-row-1))
        signed-deltas absolute-deltas traced-samples plain-samples)
    (dotimes (index etaf-performance-evaluator-sample-count)
      (let ((order (if (zerop (% index 2)) '(nil t) '(t nil))) plain traced)
        (dolist (trace-p order)
          (if trace-p
              (etaf-performance-start runtime)
            (etaf-performance-stop runtime))
          ;; Restore equivalent state outside the timed region; AB/BA order
          ;; cancels drift without retries or skipped real work.
          (garbage-collect)
          (etaf-focus runtime reset-ref)
          (when trace-p (etaf-performance-clear))
          (let ((before (etaf-focused-host-ref runtime))
                (elapsed
                 (let ((gc-cons-threshold most-positive-fixnum)
                       (gc-cons-percentage 1.0))
                   (car (etaf-performance-evaluator--timed-call
                         (if trace-p
                             (lambda ()
                               (etaf-performance-call-operation
                                runtime 'overhead "focus navigation"
                                (lambda () (etaf-focus-next runtime))))
                           (lambda () (etaf-focus-next runtime))))))))
            (unless (and (buffer-live-p (get-buffer buffer))
                         (not (equal before
                                     (etaf-focused-host-ref runtime))))
              (error "Trace-overhead: equivalent focus-navigation work failed"))
            (if trace-p
                (progn (setq traced elapsed)
                       (unless (etaf-performance-records)
                         (error "Trace-overhead: trace-on sample recorded nothing")))
              (setq plain elapsed))))
        (push plain plain-samples)
        (push traced traced-samples)
        (push (- traced plain) signed-deltas)
        (push (abs (- traced plain)) absolute-deltas)))
    (etaf-performance-stop runtime)
    (let ((signed
           (etaf-performance-evaluator--statistics (nreverse signed-deltas)))
          (jitter
           (etaf-performance-evaluator--statistics
            (nreverse absolute-deltas))))
      (princ (format (concat "perf-trace-overhead pairs=%d off-p50=%.3fms "
                             "on-p50=%.3fms signed-p50=%.3fms "
                             "signed-p95=%.3fms jitter-p50=%.3fms "
                             "budget=%.3fms\n")
                     etaf-performance-evaluator-sample-count
                     (etaf-performance-evaluator--percentile plain-samples .5)
                     (etaf-performance-evaluator--percentile traced-samples .5)
                     (plist-get signed :p50) (plist-get signed :p95)
                     (plist-get jitter :p50)
                     etaf-performance-evaluator-overhead-budget-ms))
      (list :signed signed :jitter jitter))))

(defun etaf-performance-evaluator--latency-failures (results)
  "Return hard latency budget failures from scenario RESULTS."
  (cl-loop for (label . statistics) in results append
           (let (failures)
             (when (> (plist-get statistics :p95)
                      etaf-performance-evaluator-latency-budget-ms)
               (push (format "%s p95 %.3fms > %.3fms" label
                             (plist-get statistics :p95)
                             etaf-performance-evaluator-latency-budget-ms)
                     failures))
             (when (> (plist-get statistics :max)
                      etaf-performance-evaluator-latency-budget-ms)
               (push (format "%s max %.3fms > %.3fms" label
                             (plist-get statistics :max)
                             etaf-performance-evaluator-latency-budget-ms)
                     failures))
             (nreverse failures))))

(defun etaf-performance-evaluator--trace-scenario
    (runtime label function &optional verify)
  "Run FUNCTION and return the one new operation for LABEL.
RUNTIME owns the observation boundary.  When VERIFY is non-nil, call it with
FUNCTION's exact result."
  (let* ((before (etaf-performance-records))
         (before-count (length before))
         (before-id (and before
                         (etaf-performance-operation-id (car before))))
         (result
          (etaf-performance-call-operation
           runtime 'trace label function))
         (after (etaf-performance-records))
         (operation (car after)))
    (unless (and operation
                 (= (length after) (1+ before-count))
                 (not (equal before-id
                             (etaf-performance-operation-id operation)))
                 (eq 'trace (etaf-performance-operation-kind operation))
                 (equal label
                        (etaf-performance-operation-label operation))
                 (eq (etaf-performance-operation-status operation) 'success))
      (error "Trace scenario %s did not produce one successful operation"
             label))
    (when verify
      (funcall verify result))
    (list label operation result)))

(defun etaf-performance-evaluator--visible-item-count (buffer)
  "Return the item count rendered in BUFFER, or nil."
  (let ((text (etaf-performance-evaluator--text buffer)))
    (when (string-match "\\([0-9]+\\) items" text)
      (string-to-number (match-string 1 text)))))

(defun etaf-performance-evaluator--visible-page (buffer)
  "Return BUFFER's rendered `(CURRENT . TOTAL)' page pair, or nil."
  (let ((text (etaf-performance-evaluator--text buffer)))
    (when (string-match "Page \\([0-9]+\\) / \\([0-9]+\\)" text)
      (cons (string-to-number (match-string 1 text))
            (string-to-number (match-string 2 text))))))

(cl-defun etaf-performance-evaluator--measure-event
    (label runtime buffer action verify &key setup)
  "Measure one public event ACTION under LABEL and run VERIFY.
ACTION and VERIFY receive the sample index.  Every sample must advance the
ETAF generation and preserve RUNTIME's mounted surface in BUFFER."
  (etaf-performance-evaluator--measure
   label
   (lambda (index)
     (let ((before (etaf-runtime-generation runtime)))
       (list before
             (progn (funcall action index)
                    (etaf-runtime-generation runtime)))))
   (lambda (result index)
     (unless (> (car result) -1)
       (error "%s: invalid source generation" label))
     (unless (> (cadr result) (car result))
       (error "%s: event did not advance the generation" label))
     (funcall verify index)
     (etaf-performance-evaluator--surface-invariant runtime buffer label))
   :setup setup))

(defun etaf-performance-evaluator--measure-add
    (label runtime buffer)
  "Measure RUNTIME's public Add action under LABEL in BUFFER."
  (let (before-count)
    (etaf-performance-evaluator--measure-event
     label runtime buffer
     (lambda (_index)
       (setq before-count
             (etaf-performance-evaluator--visible-item-count buffer))
       (etaf-dispatch-event runtime 'research-shelf-add 'press))
     (lambda (_index)
       (unless (and before-count
                    (= (1+ before-count)
                       (etaf-performance-evaluator--visible-item-count buffer))
                    (etaf-performance-evaluator--visible-match-p
                     buffer "Added to your shelf"))
         (error "%s: insertion/count/toast invariant failed" label))))))

(defun etaf-performance-evaluator--measure-reload
    (label runtime buffer)
  "Measure RUNTIME's public Reload action under LABEL in BUFFER."
  (etaf-performance-evaluator--measure-event
   label runtime buffer
   (lambda (_index)
     (etaf-dispatch-event runtime 'research-shelf-reload 'press))
   (lambda (_index)
     (unless (etaf-performance-evaluator--visible-match-p
              buffer "Library reloaded")
       (error "%s: reload toast invariant failed" label)))))

(defun etaf-performance-evaluator--measure-viewport-resize
    (runtime buffer)
  "Measure RUNTIME's alternating viewport publications for BUFFER."
  (let ((target-buffer (get-buffer buffer)))
    (unless (buffer-live-p target-buffer)
      (error "Viewport-resize: target buffer is not live"))
    (etaf-performance-evaluator--measure
     "viewport-resize"
     (lambda (index)
       (let* ((target (if (zerop (% (1+ index) 2)) 720 1413))
              (report
               (ebox-rerender-buffer-with-context target-buffer target 62)))
         (list target report)))
     (lambda (result _index)
       (let* ((target (car result))
              (report (cadr result)))
         (unless (and (= (plist-get report :target-viewport-width) target)
                      (eq (plist-get report :projection-kind) 'native-frame)
                      (plist-get report :runtime-published)
                      (not (plist-get report :tp-full-root))
                      (not (plist-get report :tp-scope-fallback)))
           (error "Viewport-resize: retained native publication failed"))
         (etaf-performance-evaluator--surface-invariant
          runtime buffer "viewport-resize"))))))

(defun etaf-performance-evaluator--measure-post-resize-events
    (runtime buffer)
  "Return RUNTIME's post-resize interaction measurements for BUFFER."
  (let (results)
    (push
     (etaf-performance-evaluator--measure-event
      "post-resize-row-selection" runtime buffer
      (lambda (index)
        (etaf-performance-evaluator--select-ref
         runtime (if (zerop (% (1+ index) 2))
                     'research-shelf-row-1
                   'research-shelf-row-2)))
      (lambda (index)
        (let ((ref (if (zerop (% (1+ index) 2))
                       'research-shelf-row-1
                     'research-shelf-row-2)))
          (unless (string-match-p
                   "selected"
                   (or (plist-get
                        (etaf-runtime-host-props-for runtime ref) :class)
                       ""))
            (error "Post-resize row selection invariant failed")))))
     results)
    (push
     (etaf-performance-evaluator--measure-event
      "post-resize-theme-toggle" runtime buffer
      (lambda (_index)
        (etaf-dispatch-event runtime 'research-shelf-theme-toggle 'press))
      (lambda (_index)
        (unless (etaf-performance-evaluator--visible-match-p
                 buffer "\\(Dark theme\\|Light theme\\)")
          (error "Post-resize theme invariant failed"))))
     results)
    (push
     (etaf-performance-evaluator--measure-event
      "post-resize-filter-query" runtime buffer
      (lambda (index)
        (etaf-dispatch-event
         runtime
         (if (zerop (% (1+ index) 2))
             'research-shelf-filter-reading
           'research-shelf-filter-all)
         'press))
      (lambda (index)
        (unless (etaf-performance-evaluator--visible-match-p
                 buffer
                 (if (zerop (% (1+ index) 2))
                     "Showing Reading"
                   "Showing All"))
          (error "Post-resize filter invariant failed"))))
     results)
    (etaf-dispatch-event runtime 'research-shelf-filter-all 'press)
    (push
     (etaf-performance-evaluator--measure-event
      "post-resize-pagination" runtime buffer
      (lambda (_index)
        (pcase-let ((`(,current . ,_total)
                     (etaf-performance-evaluator--visible-page buffer)))
          (etaf-dispatch-event
           runtime
           (if (= current 1)
               'research-shelf-page-next
             'research-shelf-page-previous)
           'press)))
      (lambda (_index)
        (unless (etaf-performance-evaluator--visible-page buffer)
          (error "Post-resize pagination invariant failed"))))
     results)
    (when-let* ((page (etaf-performance-evaluator--visible-page buffer)))
      (unless (= (car page) 1)
        (etaf-dispatch-event runtime 'research-shelf-page-previous 'press)))
    (push (etaf-performance-evaluator--measure-add
           "post-resize-add-reading" runtime buffer)
          results)
    (push (etaf-performance-evaluator--measure-reload
           "post-resize-reload" runtime buffer)
          results)
    (nreverse results)))

(defun etaf-performance-evaluator-run ()
  "Run the fixed cross-package evaluator and return non-nil on success."
  (etaf-performance-evaluator--load-workload)
  (etaf-performance-evaluator--verify-environment
   (etaf-performance-environment-data))
  (let* ((database (make-temp-file "etaf-perf-fixture-" nil ".sqlite"))
         (buffer " *etaf-cross-package-perf*")
         (mount-buffer " *etaf-cross-package-mount-perf*")
         (etaf-research-shelf-database-file database)
         (etaf-research-shelf-fixture-size
          etaf-performance-evaluator-fixture-size)
         (etaf-research-shelf-page-size etaf-performance-evaluator-page-size)
         (etaf-performance-max-records 10000)
         results runtime trace-records trace-scenarios overhead failures)
    (unwind-protect
        (progn
          (etaf-performance-evaluator--prepare-database database)
          (etaf-performance-evaluator--verify-runtime-accelerator)
          ;; Latency samples measure the product path without observer work.
          ;; Trace behavior and overhead have separate, explicit gates below.
          (etaf-performance-clear)
          (push
           (etaf-performance-evaluator--measure
            "prepared-database-mount"
            (lambda (_index)
              (etaf-performance-evaluator--mount mount-buffer))
            (lambda (mounted _index)
              (etaf-performance-evaluator--surface-invariant
               mounted mount-buffer "prepared-database-mount")
              (let ((text (etaf-performance-evaluator--text mount-buffer)))
                (unless (and (string-match-p "256 items · SQLite-backed" text)
                             (string-match-p "Page 1 / 22" text))
                  (error "Prepared-database-mount: fixture/page invariant failed"))))
            :cleanup (lambda (_result _index)
                       (etaf-performance-evaluator--close-buffer mount-buffer)))
           results)
          (setq runtime (etaf-performance-evaluator--mount buffer))
          (etaf-performance-evaluator--surface-invariant runtime buffer "setup")

          (push
           (etaf-performance-evaluator--measure
            "row-selection"
            (lambda (index)
              (let* ((ref (if (zerop (% (1+ index) 2))
                              'research-shelf-row-1 'research-shelf-row-2))
                     (before (etaf-runtime-generation runtime)))
                (etaf-performance-evaluator--select-ref runtime ref)
                (list ref before (etaf-runtime-generation runtime))))
            (lambda (result _index)
              (pcase-let ((`(,ref ,before ,after) result))
                (unless (and (>= after before)
                             (string-match-p
                              "selected"
                              (or (plist-get
                                   (etaf-runtime-host-props-for runtime ref)
                                   :class) "")))
                  (error "Row-selection: selection/generation invariant failed")))
              (etaf-performance-evaluator--surface-invariant
               runtime buffer "row-selection")))
           results)

          (push
           (etaf-performance-evaluator--measure
            "theme-toggle"
            (lambda (_index)
              (let ((before (etaf-runtime-generation runtime)))
                (etaf-dispatch-event runtime 'research-shelf-theme-toggle 'press)
                (list before (etaf-runtime-generation runtime))))
            (lambda (result _index)
              (unless (and (> (cadr result) (car result))
                           (etaf-performance-evaluator--visible-match-p
                            buffer "\\(Dark theme\\|Light theme\\)"))
                (error "Theme-toggle: theme/generation invariant failed"))
              (etaf-performance-evaluator--surface-invariant
               runtime buffer "theme-toggle")))
           results)

          (push
           (etaf-performance-evaluator--measure
            "filter-query"
            (lambda (index)
              (let* ((reading-p (zerop (% (1+ index) 2)))
                     (ref (if reading-p 'research-shelf-filter-reading
                            'research-shelf-filter-all))
                     (before (etaf-runtime-generation runtime)))
                (etaf-dispatch-event runtime ref 'press)
                (list reading-p before (etaf-runtime-generation runtime))))
            (lambda (result _index)
              (unless (and (> (nth 2 result) (nth 1 result))
                           (etaf-performance-evaluator--visible-match-p
                            buffer (if (car result) "Showing Reading"
                                     "Showing All")))
                (error "Filter-query: query/generation invariant failed"))
              (etaf-performance-evaluator--surface-invariant
               runtime buffer "filter-query")))
           results)

          (etaf-dispatch-event runtime 'research-shelf-filter-all 'press)
          (push
           (etaf-performance-evaluator--measure
            "pagination"
            (lambda (_index)
              (let* ((on-first (etaf-performance-evaluator--visible-match-p
                                buffer "Page 1 / 22"))
                     (ref (if on-first 'research-shelf-page-next
                            'research-shelf-page-previous))
                     (before (etaf-runtime-generation runtime)))
                (etaf-dispatch-event runtime ref 'press)
                (list (if on-first 2 1) before
                      (etaf-runtime-generation runtime))))
            (lambda (result _index)
              (unless (and (> (nth 2 result) (nth 1 result))
                           (etaf-performance-evaluator--visible-match-p
                            buffer (format "Page %d / 22" (car result))))
                (error "Pagination: page/generation invariant failed"))
              (etaf-performance-evaluator--surface-invariant
               runtime buffer "pagination")))
           results)

          (unless (etaf-performance-evaluator--visible-match-p
                   buffer "Page 1 / 22")
            (etaf-dispatch-event runtime 'research-shelf-page-previous 'press))
          (let ((refs '(research-shelf-row-2 research-shelf-row-4
                        research-shelf-row-5 research-shelf-row-8
                        research-shelf-row-9 research-shelf-row-10)))
            (push
             (etaf-performance-evaluator--measure
              "progress-mutation"
              (lambda (_index)
                (let ((before (etaf-runtime-generation runtime)))
                  (etaf-dispatch-event runtime 'research-shelf-progress 'press)
                  (list before (etaf-runtime-generation runtime))))
              (lambda (result _index)
                (unless (and (> (cadr result) (car result))
                             (etaf-performance-evaluator--visible-match-p
                              buffer "Progress saved"))
                  (error "Progress-mutation: persistence invariant failed"))
                (etaf-performance-evaluator--surface-invariant
                 runtime buffer "progress-mutation"))
              :setup (lambda (index)
                       (etaf-performance-evaluator--select-ref
                        runtime (nth (% (1+ index) (length refs)) refs))))
             results))

          (push
           (etaf-performance-evaluator--measure
            "focus-navigation"
            (lambda (_index)
              (let ((before (etaf-focused-host-ref runtime)))
                (etaf-focus-next runtime)
                (list before (etaf-focused-host-ref runtime))))
            (lambda (result _index)
              (unless (and (cadr result)
                           (not (equal (car result) (cadr result))))
                (error "Focus-navigation: focus did not advance"))
              (etaf-performance-evaluator--surface-invariant
               runtime buffer "focus-navigation")))
           results)

          (push
           (etaf-performance-evaluator--measure-add
            "add-reading" runtime buffer)
           results)
          (push
           (etaf-performance-evaluator--measure-reload
            "reload" runtime buffer)
           results)
          (push
           (etaf-performance-evaluator--measure-viewport-resize
            runtime buffer)
           results)
          (dolist (result
                   (etaf-performance-evaluator--measure-post-resize-events
                    runtime buffer))
            (push result results))

          ;; Capture one representative cross-package trace after the latency
          ;; samples.  This validates coverage without folding observer work
          ;; into the product latency distribution.
          (etaf-performance-start runtime)
          (etaf-performance-clear)
          (push
           (etaf-performance-evaluator--trace-scenario
            runtime "row-selection"
            (lambda ()
              (etaf-performance-evaluator--select-ref
               runtime 'research-shelf-row-2))
            (lambda (ref)
              (unless (string-match-p
                       "selected"
                       (or (plist-get
                            (etaf-runtime-host-props-for runtime ref) :class)
                           ""))
                (error "Trace row-selection product invariant failed"))))
           trace-scenarios)
          (push
           (etaf-performance-evaluator--trace-scenario
            runtime "theme-toggle"
            (lambda ()
              (etaf-dispatch-event
               runtime 'research-shelf-theme-toggle 'press))
            (lambda (_result)
              (unless (etaf-performance-evaluator--visible-match-p
                       buffer "\\(Dark theme\\|Light theme\\)")
                (error "Trace theme-toggle product invariant failed"))))
           trace-scenarios)
          (push
           (etaf-performance-evaluator--trace-scenario
            runtime "reload"
            (lambda ()
              (etaf-dispatch-event runtime 'research-shelf-reload 'press))
            (lambda (_result)
              (unless (etaf-performance-evaluator--visible-match-p
                       buffer "Library reloaded")
                (error "Trace reload product invariant failed"))))
           trace-scenarios)
          (let* ((previous (ebox-buffer-update-report (get-buffer buffer)))
                 (target
                  (if (= (or (plist-get previous :target-viewport-width) 720)
                         720)
                      1413
                    720)))
            (push
             (etaf-performance-evaluator--trace-scenario
              runtime "viewport-resize"
              (lambda ()
                (list target
                      (ebox-rerender-buffer-with-context
                       (get-buffer buffer) target 62)))
              (lambda (result)
                (let ((report (cadr result)))
                  (unless (and (= (plist-get report :target-viewport-width)
                                  (car result))
                               (plist-get report :runtime-published))
                    (error
                     "Trace viewport-resize product invariant failed")))))
             trace-scenarios))
          (push
           (etaf-performance-evaluator--trace-scenario
            runtime "post-resize-row-selection"
            (lambda ()
              (etaf-performance-evaluator--select-ref
               runtime 'research-shelf-row-1))
            (lambda (ref)
              (unless (string-match-p
                       "selected"
                       (or (plist-get
                            (etaf-runtime-host-props-for runtime ref) :class)
                           ""))
                (error "Trace post-resize action invariant failed"))))
           trace-scenarios)
          (push
           (etaf-performance-evaluator--trace-scenario
            runtime "progress-mutation"
            (lambda ()
              (etaf-dispatch-event
               runtime 'research-shelf-progress 'press))
            (lambda (_result)
              (unless (etaf-performance-evaluator--visible-match-p
                       buffer "Progress saved")
                (error "Trace progress mutation invariant failed"))))
           trace-scenarios)
          (push
           (etaf-performance-evaluator--trace-scenario
            runtime "filter-query"
            (lambda ()
              (etaf-dispatch-event
               runtime 'research-shelf-filter-reading 'press))
            (lambda (_result)
              (unless (etaf-performance-evaluator--visible-match-p
                       buffer "Showing Reading")
                (error "Trace filter query invariant failed"))))
           trace-scenarios)
          (push
           (etaf-performance-evaluator--trace-scenario
            runtime "pagination"
            (lambda ()
              (etaf-dispatch-event
               runtime 'research-shelf-page-next 'press))
            (lambda (_result)
              (unless (equal (car (etaf-performance-evaluator--visible-page
                                   buffer))
                             2)
                (error "Trace pagination invariant failed"))))
           trace-scenarios)
          (dolist (scenario trace-scenarios)
            (unless (etaf-performance-operation-p (cadr scenario))
              (error "Trace scenario %s lacks a retained operation"
                     (car scenario))))
          (let* ((row-operation
                  (cadr (assoc "row-selection" trace-scenarios)))
                 (reload-operation
                  (cadr (assoc "reload" trace-scenarios)))
                 (row-providers
                  (mapcar #'etaf-performance-stage-provider
                          (etaf-performance-operation-stages row-operation)))
                 (reload-providers
                  (mapcar #'etaf-performance-stage-provider
                          (etaf-performance-operation-stages reload-operation))))
            (unless (equal row-providers '(tp ebox etaf))
              (error "Trace row-selection providers are %S" row-providers))
            (unless (memq 'sqlite reload-providers)
              (error "Trace reload lacks SQLite attribution")))
          (setq results (nreverse results)
                trace-records (etaf-performance-records))
          (etaf-performance-evaluator--verify-trace-records trace-records)
          (etaf-performance-evaluator--print-slowest-records trace-records)
          (etaf-performance-stop runtime)
          (etaf-dispatch-event
           runtime 'research-shelf-filter-all 'press)
          (when-let* ((page (etaf-performance-evaluator--visible-page buffer)))
            (unless (= (car page) 1)
              (etaf-dispatch-event
               runtime 'research-shelf-page-previous 'press)))
          (setq overhead
                (etaf-performance-evaluator--measure-overhead runtime buffer)
                failures (etaf-performance-evaluator--latency-failures results))
          (when (> (abs (plist-get (plist-get overhead :signed) :p50))
                   etaf-performance-evaluator-overhead-budget-ms)
            (push (format "trace signed |p50| %.3fms > %.3fms"
                          (abs (plist-get (plist-get overhead :signed) :p50))
                          etaf-performance-evaluator-overhead-budget-ms)
                  failures))
          (if failures
              (let ((failure-count (length failures)))
                (princ "etaf-cross-package-perf FAIL\n")
                (dolist (failure (reverse failures))
                  (princ (format "PERF-GATE-FAIL: %s\n" failure)))
                (error "Cross-package performance gate failed (%d conditions)"
                       failure-count))
            (princ "etaf-cross-package-perf PASS\n") t))
      (when runtime
        (etaf-performance-stop runtime))
      (etaf-performance-evaluator--close-buffer mount-buffer)
      (etaf-performance-evaluator--close-buffer buffer)
      (when (file-exists-p database) (delete-file database)))))

(defun etaf-performance-evaluator-batch ()
  "Batch entry point for the cross-package performance evaluator."
  (condition-case condition
      (progn (etaf-performance-evaluator-run) (kill-emacs 0))
    (error
     (princ (format "PERF-EVALUATOR-ERROR: %s\n"
                    (error-message-string condition)))
     (kill-emacs 1))))

(provide 'benchmark-research-shelf)
;;; benchmark-research-shelf.el ends here
