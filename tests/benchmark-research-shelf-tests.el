;;; benchmark-research-shelf-tests.el --- Performance evaluator tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(load-file (expand-file-name "scripts/benchmark-research-shelf.el"
                            default-directory))

(declare-function etaf-performance-evaluator--percentile
                  "../scripts/benchmark-research-shelf")
(declare-function etaf-performance-evaluator--measure
                  "../scripts/benchmark-research-shelf")
(declare-function etaf-performance-evaluator--latency-failures
                  "../scripts/benchmark-research-shelf")
(declare-function etaf-performance-evaluator--verify-compiled-runtime
                  "../scripts/benchmark-research-shelf")
(declare-function etaf-performance-evaluator--verify-environment
                  "../scripts/benchmark-research-shelf")

(ert-deftest etaf-performance-evaluator-uses-nearest-rank-percentiles ()
  "Return nearest-rank values for evaluator percentiles."
  (let ((samples (number-sequence 1 20)))
    (should (= 10 (etaf-performance-evaluator--percentile samples 0.50)))
    (should (= 19 (etaf-performance-evaluator--percentile samples 0.95)))))

(ert-deftest etaf-performance-evaluator-warms-before-exact-sample-count ()
  "Execute one unmeasured warmup before the requested measured samples."
  (let (actions verifications)
    (let ((result
           (etaf-performance-evaluator--measure
            "unit-workload"
            (lambda (index) (push index actions) index)
            (lambda (value index)
              (should (= value index))
              (push index verifications))
            :samples 3)))
      (should (equal '(-1 0 1 2) (nreverse actions)))
      (should (equal '(-1 0 1 2) (nreverse verifications)))
      (should (= 3 (plist-get (cdr result) :count))))))

(ert-deftest etaf-performance-evaluator-reports-both-hard-budget-failures ()
  "Report p95 and max independently when both exceed the hard budget."
  (let ((failures
         (etaf-performance-evaluator--latency-failures
          '((slow :count 20 :min 1.0 :p50 2.0 :p95 51.0 :max 60.0)))))
    (should (= 2 (length failures)))
    (should (string-match-p "slow p95" (car failures)))
    (should (string-match-p "slow max" (cadr failures)))))

(ert-deftest etaf-performance-evaluator-uses-approved-theme-budget ()
  "Accept the approved 90ms Theme budget without relaxing other scenarios."
  (should-not
   (etaf-performance-evaluator--latency-failures
    '(("theme-toggle" :count 20 :min 80.0 :p50 84.0
                      :p95 86.0 :max 99.0))))
  (should (= 2
             (length
              (etaf-performance-evaluator--latency-failures
               '(("theme-toggle" :count 20 :min 80.0 :p50 84.0
                                 :p95 91.0 :max 111.0)))))))

(ert-deftest etaf-performance-evaluator-requires-native-compiled-runtime ()
  "Never report fallback-renderer latency as the optimized product gate."
  (cl-letf (((symbol-function 'princ) #'ignore))
    (should
     (equal
      (etaf-performance-evaluator--verify-compiled-runtime
       '(:status current :runtime-accelerator ready))
      '(:status current :runtime-accelerator ready))))
  (should-error
   (etaf-performance-evaluator--verify-compiled-runtime
    '(:status current :runtime-accelerator unavailable)))
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
        :load-average (1.0))))))

(provide 'benchmark-research-shelf-tests)
;;; benchmark-research-shelf-tests.el ends here
