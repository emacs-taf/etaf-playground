;;; benchmark-research-shelf.el --- Research Shelf latency gate -*- lexical-binding: t; -*-

;;; Commentary:
;; Reproducible fullscreen-equivalent warm interaction benchmark.  The process
;; exits nonzero when the declared p50/max budgets are exceeded.

;;; Code:
(require 'cl-lib)
(require 'etaf-playground)

(defconst etaf-research-shelf-benchmark-row-p50-budget-ms 105.0)
(defconst etaf-research-shelf-benchmark-row-max-budget-ms 250.0)
(defconst etaf-research-shelf-benchmark-theme-p50-budget-ms 250.0)
(defconst etaf-research-shelf-benchmark-theme-max-budget-ms 500.0)

(defun etaf-research-shelf-benchmark--percentile (samples percentile)
  "Return PERCENTILE from numeric SAMPLES using nearest rank."
  (let* ((ordered (sort (copy-sequence samples) #'<))
         (index (min (1- (length ordered))
                     (floor (* percentile (length ordered))))))
    (nth index ordered)))

(defun etaf-research-shelf-benchmark--measure (runtime refs runs)
  "Measure warm press events through RUNTIME while cycling REFS.
The number of measured events is `RUNS'."
  (cl-loop for index below runs
           for ref = (nth (% index (length refs)) refs)
           collect
           (let ((started (float-time)))
             (etaf-dispatch-event runtime ref 'press)
             (* 1000.0 (- (float-time) started)))))

(defun etaf-research-shelf-benchmark--summary (label samples)
  "Print and return LABEL summary for SAMPLES."
  (let ((p50 (etaf-research-shelf-benchmark--percentile samples 0.5))
        (maximum (apply #'max samples)))
    (princ (format "%s p50=%.3fms max=%.3fms samples=%S\n"
                   label p50 maximum samples))
    (list :p50 p50 :max maximum)))

(defun etaf-research-shelf-benchmark-run ()
  "Run the Research Shelf evaluator and return non-nil on success."
  (load-file (expand-file-name "examples/research-shelf.el"
                              default-directory))
  (let ((database (make-temp-file "etaf-research-shelf-perf-" nil ".sqlite"))
        (buffer " *etaf-research-shelf-perf*"))
    (unwind-protect
        (let ((etaf-research-shelf-database-file database))
          (ignore etaf-research-shelf-database-file)
          (etaf-playground-open buffer)
          (ebox-surface-update-buffer-viewport (get-buffer buffer) 1413 62)
          (let ((runtime (etaf-runtime-for-buffer buffer)))
            ;; Prewarm both structural states before collecting evidence.
            (etaf-dispatch-event runtime 'research-shelf-row-1 'press)
            (etaf-dispatch-event runtime 'research-shelf-row-2 'press)
            (etaf-dispatch-event runtime 'research-shelf-theme-toggle 'press)
            (etaf-dispatch-event runtime 'research-shelf-theme-toggle 'press)
            (let* ((row (etaf-research-shelf-benchmark--summary
                         "row-selection"
                         (etaf-research-shelf-benchmark--measure
                          runtime '(research-shelf-row-1 research-shelf-row-2) 8)))
                   (theme (etaf-research-shelf-benchmark--summary
                           "theme-toggle"
                           (etaf-research-shelf-benchmark--measure
                            runtime '(research-shelf-theme-toggle) 8)))
                   (pass
                    (and (<= (plist-get row :p50)
                             etaf-research-shelf-benchmark-row-p50-budget-ms)
                         (<= (plist-get row :max)
                             etaf-research-shelf-benchmark-row-max-budget-ms)
                         (<= (plist-get theme :p50)
                             etaf-research-shelf-benchmark-theme-p50-budget-ms)
                         (<= (plist-get theme :max)
                             etaf-research-shelf-benchmark-theme-max-budget-ms))))
              (princ (format "research-shelf-perf %s\n"
                             (if pass "PASS" "FAIL")))
              (unless pass
                (error "Research Shelf interaction latency budget exceeded"))
              t)))
      (when (get-buffer buffer)
        (etaf-playground-close buffer))
      (when (file-exists-p database)
        (delete-file database)))))

(etaf-research-shelf-benchmark-run)

;;; benchmark-research-shelf.el ends here
