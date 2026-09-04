;;; benchmark-research-shelf-tests.el --- Performance evaluator tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'etaf-performance)
(load-file (expand-file-name "scripts/benchmark-research-shelf.el"
                            default-directory))

(declare-function etaf-performance-evaluator--percentile
                  "../scripts/benchmark-research-shelf")
(declare-function etaf-performance-evaluator--measure
                  "../scripts/benchmark-research-shelf")
(declare-function etaf-performance-evaluator--latency-failures
                  "../scripts/benchmark-research-shelf")
(declare-function etaf-performance-evaluator--trace-overhead-failures
                  "../scripts/benchmark-research-shelf")
(declare-function etaf-performance-evaluator--verify-runtime-accelerator
                  "../scripts/benchmark-research-shelf")
(declare-function etaf-performance-evaluator--verify-environment
                  "../scripts/benchmark-research-shelf")
(declare-function etaf-performance-evaluator--trace-scenario
                  "../scripts/benchmark-research-shelf")
(declare-function etaf-performance-evaluator--measure-overhead
                  "../scripts/benchmark-research-shelf")
(declare-function etaf-performance-evaluator--manifest-data
                  "../scripts/benchmark-research-shelf")
(declare-function etaf-performance-evaluator--write-manifest
                  "../scripts/benchmark-research-shelf")
(declare-function etaf-performance-evaluator--record-manifest-sample
                  "../scripts/benchmark-research-shelf")
(declare-function etaf-performance-evaluator-batch
                  "../scripts/benchmark-research-shelf")
(defvar etaf-performance-evaluator-warmup-count)
(defvar etaf-performance-evaluator-sample-count)
(defvar etaf-performance-evaluator--manifest-output)
(defvar etaf-performance-evaluator--manifest-scenarios)
(defvar etaf-performance-evaluator--manifest-run-id)

(ert-deftest etaf-performance-evaluator-uses-nearest-rank-percentiles ()
  "Return nearest-rank values for evaluator percentiles."
  (let ((samples (number-sequence 1 20)))
    (should (= 10 (etaf-performance-evaluator--percentile samples 0.50)))
    (should (= 19 (etaf-performance-evaluator--percentile samples 0.95)))))

(ert-deftest etaf-performance-evaluator-warms-before-exact-sample-count ()
  "Execute five unmeasured warmups before the measured samples."
  (let (actions verifications)
    (let ((result
           (etaf-performance-evaluator--measure
            "unit-workload"
            (lambda (index) (push index actions) index)
            (lambda (value index)
              (should (= value index))
              (push index verifications))
            :samples 3)))
      (should (equal '(-5 -4 -3 -2 -1 0 1 2) (nreverse actions)))
      (should (equal '(-5 -4 -3 -2 -1 0 1 2)
                     (nreverse verifications)))
      (should (= 3 (plist-get (cdr result) :count))))))

(ert-deftest etaf-performance-evaluator-defaults-to-stable-sample-volume ()
  "Use at least five warmups and thirty samples for every fixed scenario."
  (should (>= etaf-performance-evaluator-warmup-count 5))
  (should (>= etaf-performance-evaluator-sample-count 30)))

(ert-deftest etaf-performance-evaluator-models-visible-gc-boundary ()
  "Measured actions defer GC like an interactive Ebox render burst."
  (let ((gc-cons-threshold 1000)
        (gc-cons-percentage 0.1)
        observed)
    (etaf-performance-evaluator--measure
     "visible-gc-boundary"
     (lambda (_index)
       (push (list gc-cons-threshold gc-cons-percentage) observed)
       t)
     (lambda (result _index) (should result))
     :samples 1)
    ;; Warmups are intentionally outside the timed visible transaction; the
    ;; measured sample owns the raised threshold and caller settings restore.
    (should (equal (car observed) (list most-positive-fixnum 1.0)))
    (should (= gc-cons-threshold 1000))
    (should (= gc-cons-percentage 0.1))))

(ert-deftest etaf-performance-evaluator-manifest-preserves-raw-samples ()
  "Write exact post-timing samples and statistics to the optional manifest."
  (let* ((output (make-temp-file "etaf-perf-manifest-" nil ".json"))
         (etaf-performance-evaluator--manifest-output output)
         (etaf-performance-evaluator--manifest-scenarios
          (make-hash-table :test #'equal))
         (etaf-performance-evaluator--manifest-run-id "unit-run")
         (process-environment
          (append '("INCREMENTAL_SET_INDEX=2"
                    "INCREMENTAL_SOURCE_IDENTITY=source-id"
                    "INCREMENTAL_EVALUATOR_IDENTITY=evaluator-id")
                  process-environment))
         (durations '(1.25 2.5 3.75)))
    (unwind-protect
        (progn
          (cl-letf (((symbol-function 'etaf-performance-evaluator--timed-call)
                     (lambda (function)
                       (cons (pop durations) (funcall function))))
                    ((symbol-function 'princ) #'ignore))
            (etaf-performance-evaluator--measure
             "row-selection" (lambda (_index) 'ok)
             (lambda (result _index) (should (eq result 'ok)))
             :warmups 0 :samples 3))
          (etaf-performance-evaluator--write-manifest)
          (let* ((json-object-type 'hash-table)
                 (json-array-type 'list)
                 (manifest (json-read-file output))
                 (scenario (gethash "row-selection"
                                    (gethash "scenarios" manifest))))
            (should (equal '(1.25 2.5 3.75)
                           (gethash "samples_ms" scenario)))
            (should (= 3.75 (gethash "p95_ms" scenario)))
            (should (= 3.75 (gethash "max_ms" scenario)))
            (should (= 2 (gethash "set_index" manifest)))
            (should (equal "source-id" (gethash "source_identity" manifest)))
            (should (equal "evaluator-id"
                           (gethash "evaluator_identity" manifest)))))
      (when (file-exists-p output) (delete-file output)))))

(ert-deftest etaf-performance-evaluator-manifest-retains-failed-prefix ()
  "Keep only real samples captured before a scenario verification failure."
  (let ((etaf-performance-evaluator--manifest-scenarios
         (make-hash-table :test #'equal))
        (durations '(4.0 5.0 6.0)))
    (cl-letf (((symbol-function 'etaf-performance-evaluator--timed-call)
               (lambda (function)
                 (cons (pop durations) (funcall function))))
              ((symbol-function 'princ) #'ignore))
      (should-error
       (etaf-performance-evaluator--measure
        "pagination" (lambda (_index) 'ok)
        (lambda (_result index)
          (when (= index 1) (error "Fixture failure")))
        :warmups 0 :samples 3)))
    (should (equal '(5.0 4.0)
                   (gethash "pagination"
                            etaf-performance-evaluator--manifest-scenarios)))))

(ert-deftest etaf-performance-evaluator-batch-writes-manifest-on-failure ()
  "Write the actually captured prefix before returning a failing batch status."
  (let* ((output (make-temp-file "etaf-failed-perf-manifest-" nil ".json"))
         (process-environment
          (append (list (concat "INCREMENTAL_PERF_MANIFEST=" output)
                        "INCREMENTAL_SET_INDEX=1"
                        "INCREMENTAL_SOURCE_IDENTITY=source-id"
                        "INCREMENTAL_EVALUATOR_IDENTITY=evaluator-id")
                  process-environment))
         exit-status)
    (unwind-protect
        (progn
          (cl-letf (((symbol-function 'etaf-performance-evaluator-run)
                     (lambda ()
                       (etaf-performance-evaluator--record-manifest-sample
                        "filter-query" 8.5)
                       (error "Fixture failure")))
                    ((symbol-function 'kill-emacs)
                     (lambda (status) (setq exit-status status)))
                    ((symbol-function 'princ) #'ignore))
            (etaf-performance-evaluator-batch))
          (let* ((json-object-type 'hash-table)
                 (json-array-type 'list)
                 (manifest (json-read-file output))
                 (scenario (gethash "filter-query"
                                    (gethash "scenarios" manifest))))
            (should (= 1 exit-status))
            (should (equal '(8.5) (gethash "samples_ms" scenario)))
            (should (= 8.5 (gethash "p95_ms" scenario)))
            (should (= 8.5 (gethash "max_ms" scenario)))))
      (when (file-exists-p output) (delete-file output)))))

(ert-deftest etaf-performance-evaluator-no-manifest-env-keeps-normal-path ()
  "Do not create evidence or change measurement results without the env opt-in."
  (let ((etaf-performance-evaluator--manifest-output nil)
        (etaf-performance-evaluator--manifest-scenarios nil))
    (cl-letf (((symbol-function 'princ) #'ignore))
      (let ((result
             (etaf-performance-evaluator--measure
              "row-selection" (lambda (_index) 'ok)
              (lambda (value _index) (should (eq value 'ok)))
              :warmups 0 :samples 1)))
        (should (= 1 (plist-get (cdr result) :count)))))
    (should-not (etaf-performance-evaluator--write-manifest))))

(ert-deftest etaf-performance-evaluator-reports-both-hard-budget-failures ()
  "Report p95 and max independently when both exceed the hard budget."
  (let ((failures
         (etaf-performance-evaluator--latency-failures
          '((slow :count 20 :min 1.0 :p50 2.0 :p95 51.0 :max 60.0)))))
    (should (= 2 (length failures)))
    (should (string-match-p "slow p95" (car failures)))
    (should (string-match-p "slow max" (cadr failures)))))

(ert-deftest etaf-performance-evaluator-applies-one-budget-to-theme ()
  "Theme and post-resize Theme obey the same 50ms p95/max gate."
  (let ((failures
         (etaf-performance-evaluator--latency-failures
          '(("theme-toggle" :count 30 :min 40.0 :p50 45.0
                            :p95 51.0 :max 52.0)
            ("post-resize-theme-toggle" :count 30 :min 40.0 :p50 45.0
                                        :p95 49.0 :max 51.0)))))
    (should (= 3 (length failures)))
    (dolist (failure failures)
      (should (string-match-p "> 50.000ms" failure)))))

(ert-deftest etaf-performance-evaluator-gates-trace-overhead-p95 ()
  "Apply the 2ms trace budget to signed p95 as well as median bias."
  (let ((failures
         (etaf-performance-evaluator--trace-overhead-failures
          '(:signed (:p50 0.4 :p95 2.5)))))
    (should (= 1 (length failures)))
    (should (string-match-p "p95 2.500ms > 2.000ms" (car failures))))
  (let ((failures
         (etaf-performance-evaluator--trace-overhead-failures
          '(:signed (:p50 -2.5 :p95 1.9)))))
    (should (= 1 (length failures)))
    (should (string-match-p "|p50| 2.500ms > 2.000ms" (car failures))))
  (should-not
   (etaf-performance-evaluator--trace-overhead-failures
    '(:signed (:p50 0.4 :p95 1.9)))))

(ert-deftest etaf-performance-evaluator-trace-scenario-retains-one-operation ()
  "The trace driver uses the public Runtime recorder and preserves results."
  (let ((buffer-name (generate-new-buffer-name " *etaf-driver-trace-test*"))
        runtime verified)
    (unwind-protect
        (progn
          (etaf-mount buffer-name (etaf-view (box "Trace")))
          (setq runtime (etaf-runtime-for-buffer buffer-name))
          (etaf-performance-start runtime)
          (etaf-performance-clear)
          (let ((scenario
                 (etaf-performance-evaluator--trace-scenario
                  runtime "fixture"
                  (lambda () 'exact-result)
                  (lambda (result) (setq verified result)))))
            (should (equal '("fixture") (list (car scenario))))
            (should (etaf-performance-operation-p (cadr scenario)))
            (should (eq 'exact-result (caddr scenario)))
            (should (eq 'exact-result verified))
            (should (= 1 (length (etaf-performance-records))))))
      (when runtime
        (etaf-performance-stop runtime)
        (etaf-unmount runtime))
      (when-let* ((buffer (get-buffer buffer-name)))
        (kill-buffer buffer)))))

(ert-deftest etaf-performance-evaluator-overhead-uses-explicit-operation ()
  "Trace-on focus work enters the public Runtime operation boundary."
  (let ((buffer-name (generate-new-buffer-name " *etaf-driver-overhead-test*"))
        (etaf-performance-evaluator-sample-count 2)
        runtime)
    (unwind-protect
        (progn
          (etaf-mount
           buffer-name
           (etaf-view
            (column
              (box :ref 'first :tab-index 0 "First")
              (box :ref 'second :tab-index 1 "Second"))))
          (setq runtime (etaf-runtime-for-buffer buffer-name))
          (cl-letf (((symbol-function 'princ) #'ignore))
            (let ((result
                   (etaf-performance-evaluator--measure-overhead
                    runtime buffer-name 'first)))
              (should (numberp (plist-get (plist-get result :signed) :p50)))
              (should (= 1 (length (etaf-performance-records)))))))
      (when runtime
        (etaf-performance-stop runtime)
        (etaf-unmount runtime))
      (when-let* ((buffer (get-buffer buffer-name)))
        (kill-buffer buffer)))))

(ert-deftest etaf-performance-evaluator-requires-native-runtime ()
  "Never report fallback-renderer latency as the optimized product gate."
  (cl-letf (((symbol-function 'princ) #'ignore)
            ((symbol-function 'ebox-native-reflow-layout-ready-p)
             (lambda () t)))
    (should (etaf-performance-evaluator--verify-runtime-accelerator)))
  (cl-letf (((symbol-function 'ebox-native-reflow-layout-ready-p)
             (lambda () nil)))
    (should-error
     (etaf-performance-evaluator--verify-runtime-accelerator)))
  (let ((makefile (with-temp-buffer
                    (insert-file-contents "Makefile")
                    (buffer-string))))
    (should (string-match-p "native-build" makefile))
    (should (string-match-p "EBOX_NATIVE_REFLOW_MODULE_PATH" makefile))))

(ert-deftest etaf-performance-evaluator-rejects-low-power-baselines ()
  "Absolute latency gates fail closed when macOS throttles the CPU."
  (cl-letf (((symbol-function 'princ) #'ignore))
    (should
     (equal
      '(:power-state (:source ac :low-power-mode off) :load-average (1.0))
      (etaf-performance-evaluator--verify-environment
       '(:power-state (:source ac :low-power-mode off)
         :load-average (1.0)))))
    (should-error
     (etaf-performance-evaluator--verify-environment
      '(:power-state (:source battery :low-power-mode on)
        :load-average (1.0))))
    (should-error
     (etaf-performance-evaluator--verify-environment
      '(:power-state (:source ac :low-power-mode off)
        :native-comp-jit-compilation t
        :load-average (1.0))))))

(ert-deftest etaf-performance-evaluator-uses-only-recorder-v2-public-api ()
  "The driver contains no v1 recorder fields or implicit global tracing."
  (let ((source
         (with-temp-buffer
           (insert-file-contents "scripts/benchmark-research-shelf.el")
           (buffer-string))))
    (dolist (obsolete
             '("etaf-performance-mode"
               "etaf-performance-stage-function"
               "etaf-performance-stage-exclusive"
               "etaf-performance-operation-gc-count-before"
               "etaf-performance-operation-gc-count-after"
               "etaf-performance-operation-gc-elapsed-before"
               "etaf-performance-operation-gc-elapsed-after"
               "etaf-performance-register-stage"
               "etaf-performance--installed-advices"
               "etaf-runtime-mount-epoch"
               "etaf-runtime-mounted-p"))
      (should-not (string-match-p (regexp-quote obsolete) source)))
    (dolist (required '("etaf-performance-start"
                        "etaf-performance-stop"
                        "etaf-performance-stage-name"
                        "etaf-performance-operation-gc-count"
                        "etaf-performance-operation-gc-elapsed"))
      (should (string-match-p (regexp-quote required) source)))))

(provide 'benchmark-research-shelf-tests)
;;; benchmark-research-shelf-tests.el ends here
