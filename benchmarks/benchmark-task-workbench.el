;;; benchmark-task-workbench.el --- Public Workbench latency samples -*- lexical-binding: t; -*-

;;; Commentary:
;; Batch feedback for the 100-task, 10-row Workbench.  This does not certify
;; foreground input-to-display latency.  Run after compilation has settled.

;;; Code:
(require 'cl-lib)
(require 'json)
(require 'etaf)
(require 'ebox)
(require 'task-workbench)

(defun etaf-workbench-benchmark--target (runtime label)
  "Find the first rendered RUNTIME control with aria LABEL."
  (let (targets)
    (dolist (entry (etaf-runtime-host-props-entries runtime))
      (when (equal label (plist-get (cdr entry) :aria-label))
        (when-let* ((bounds (etaf-host-ref-bounds runtime (car entry))))
          (push (cons (car bounds) (car entry)) targets))))
    (or (cdr (car (sort targets (lambda (a b) (< (car a) (car b))))))
        (error "Workbench has no rendered control: %s" label))))

(defun etaf-workbench-benchmark--checked-p (buffer runtime target)
  "Read BUFFER's committed checkbox mark for RUNTIME TARGET."
  (let ((bounds (etaf-host-ref-bounds runtime target)))
    (with-current-buffer buffer
      (let ((text (buffer-substring-no-properties (car bounds) (cdr bounds))))
        (unless (string-match-p "[☑☐]" text)
          (error "Workbench checkbox has no readable state"))
        (not (null (string-match-p "☑" text)))))))

(defun etaf-workbench-benchmark--wait (runtime)
  "Wait for RUNTIME's observable task request to settle, pumping native timers."
  (let* ((target (etaf-workbench-benchmark--target runtime "任务数据状态"))
         (deadline (+ (float-time) 10))
         (busy
          (lambda ()
            (unless (etaf-runtime-mounted-p runtime) (error "Workbench was unmounted"))
            (plist-get (etaf-runtime-host-props-for runtime target) :aria-busy))))
    (while (and (funcall busy) (< (float-time) deadline))
      (accept-process-output nil 0.01))
    (when (funcall busy) (error "Workbench task request did not settle"))))

(defun etaf-workbench-benchmark--dispatch (runtime target)
  "Activate TARGET and wait for all resulting task publications in RUNTIME."
  (etaf-dispatch-event runtime target 'press)
  (etaf-workbench-benchmark--wait runtime))

(defun etaf-workbench-benchmark--scenario
    (name label &optional call-operation sample-count)
  "Measure NAME's LABEL activation, checking each published result.
Diagnostic CALL-OPERATION receives BUFFER, RUNTIME and TARGET for each measured
action after the five warmups and must wait for asynchronous publication.
SAMPLE-COUNT defaults to 30.  Wall samples include provider waiting time."
  (let ((buffer (generate-new-buffer " *Workbench benchmark*"))
        runtime target samples)
    (unwind-protect
        (progn
          (etaf-mount buffer (etaf-view (wb-app))
                      '(:viewport-width 1413 :viewport-height 62))
          (setq runtime (etaf-runtime-for-buffer buffer))
          (etaf-workbench-benchmark--wait runtime)
          (unless (with-current-buffer buffer
                    (string-match-p (regexp-quote "共 100 条 · 当前页 10 条")
                                    (buffer-string)))
            (error "Workbench fixture must publish 100 tasks and 10 page rows"))
          (setq runtime (etaf-runtime-for-buffer buffer)
                target (etaf-workbench-benchmark--target runtime label))
          (dotimes (index (+ 5 (or sample-count 30)))
            ;; Every focus sample must move focus.  Reset outside both timing
            ;; and diagnostic recording; repeatedly focusing Add measures a no-op.
            (when (equal name "focus-add")
              (etaf-focus runtime (etaf-workbench-benchmark--target runtime "深色")))
            (let* ((checked (unless (equal name "focus-add")
                              (etaf-workbench-benchmark--checked-p buffer runtime target)))
                   (start (float-time)))
              (if (and call-operation (>= index 5))
                  (funcall call-operation buffer runtime target)
                (etaf-workbench-benchmark--dispatch runtime target))
              (let ((elapsed (* 1000.0 (- (float-time) start))))
                (when (>= index 5) (push elapsed samples)))
              (if (equal name "focus-add")
                  (unless (equal (etaf-focused-host-ref runtime)
                                 (etaf-workbench-benchmark--target runtime "新增任务"))
                    (error "Workbench did not focus its Add control"))
                (unless (eq (not checked)
                            (etaf-workbench-benchmark--checked-p buffer runtime target))
                  (error "Workbench did not publish the toggled value: %s" name)))))
          (let ((ordered (sort (copy-sequence samples) #'<)))
            (list :name name :samples_ms (vconcat (nreverse samples))
                  :p95_ms (nth (floor (* 0.95 (length ordered))) ordered)
                  :max_ms (car (last ordered)))))
      (when runtime (etaf-unmount runtime))
      (kill-buffer buffer))))

(defun etaf-workbench-benchmark--source-hash (function)
  "Return the source digest for the loaded benchmark or app FUNCTION."
  (with-temp-buffer
    (insert-file-contents
     (concat (file-name-sans-extension (symbol-file function 'defun)) ".el"))
    (secure-hash 'sha256 (current-buffer))))

(defun etaf-workbench-benchmark--write (output report)
  "Atomically publish REPORT at OUTPUT, including an unfinished run's state."
  (let ((temporary
         (make-temp-file
          (expand-file-name ".workbench-latency-"
                            (file-name-directory (expand-file-name output)))))
        (coding-system-for-write 'utf-8-unix))
    (unwind-protect
        (progn
          (with-temp-file temporary
            (insert (decode-coding-string
                     (json-serialize report :null-object nil :false-object :false)
                     'utf-8))
            (insert "\n"))
          (rename-file temporary output t)
          (setq temporary nil))
      (when temporary (delete-file temporary)))))

(defun etaf-workbench-benchmark-batch ()
  "Write public Workbench samples to ETAF_WORKBENCH_BENCHMARK_OUTPUT.
Without that environment variable, allocate a fresh JSON file outside Git.
Exit nonzero on an incorrect result or a p95/max exceeding 50 milliseconds."
  (let* ((output (or (getenv "ETAF_WORKBENCH_BENCHMARK_OUTPUT")
                     (make-temp-file "etaf-workbench-latency-" nil ".json")))
         (report
          (list :schema 1 :workload "task-workbench" :tasks 100 :page_size 10
                :viewport_width 1413 :viewport_height 62 :warmups 5 :samples 30
                :timing "batch-dispatch-to-async-settlement" :provider_wait_included t :emacs emacs-version
                :machine (system-name) :system system-configuration
                :evaluator_hash
                (etaf-workbench-benchmark--source-hash 'etaf-workbench-benchmark-batch)
                :app_hash (etaf-workbench-benchmark--source-hash 'wb-open)
                :app_compiled (if (byte-code-function-p (symbol-function 'wb-open))
                                  t :false)
                :runtime_compiled
                (if (byte-code-function-p (symbol-function 'etaf-mount)) t :false)
                :native (plist-get (ebox-native-reflow-runtime-report)
                                   :loaded-module-hash)))
         cases failure)
    (etaf-workbench-benchmark--write
     output (append report '(:status "running" :scenarios [] :error nil)))
    (condition-case problem
        (dolist (scenario '(("row-toggle" "完成") ("theme-toggle" "深色")
                            ("focus-add" "定位新增按钮")))
          (push (apply #'etaf-workbench-benchmark--scenario scenario) cases))
      (error (setq failure (error-message-string problem))))
    (setq cases (nreverse cases)
          report (append report
                         (list :scenarios (vconcat cases) :error failure
                               :status
                               (if (or failure
                                       (cl-some
                                        (lambda (entry)
                                          (> (plist-get entry :max_ms) 50.0))
                                        cases))
                                   "failed" "passed"))))
    (etaf-workbench-benchmark--write output report)
    (dolist (entry cases)
      (princ (format "%s p95=%.3fms max=%.3fms\n" (plist-get entry :name)
                     (plist-get entry :p95_ms) (plist-get entry :max_ms))))
    (when failure (princ (format "ERROR %s\n" failure)))
    (princ (format "%s %s\n" (upcase (plist-get report :status)) output))
    (unless (equal (plist-get report :status) "passed") (kill-emacs 1))))

(provide 'benchmark-task-workbench)
;;; benchmark-task-workbench.el ends here
