;;; profile-task-workbench.el --- Workbench operation diagnostics -*- lexical-binding: t; -*-

;;; Commentary:
;; Separate public stage recording and CPU sampling passes of the same checked
;; workload.  These instrumented passes never serve as latency acceptance data.

;;; Code:
(require 'profiler)
(require 'benchmark-task-workbench)

(defun etaf-workbench-profile--operation (operation)
  "Convert public OPERATION timing facts to JSON-compatible data."
  (list :id (etaf-performance-operation-id operation)
        :kind (symbol-name (etaf-performance-operation-kind operation))
        :status (symbol-name (etaf-performance-operation-status operation))
        :elapsed_ms (etaf-performance-operation-elapsed operation)
        :gc_count (etaf-performance-operation-gc-count operation)
        :gc_ms (etaf-performance-operation-gc-elapsed operation)
        :stages
        (vconcat
         (mapcar
          (lambda (stage)
            (list :provider (format "%s" (etaf-performance-stage-provider stage))
                  :category (format "%s" (etaf-performance-stage-category stage))
                  :name (format "%s" (etaf-performance-stage-name stage))
                  :status (format "%s" (etaf-performance-stage-status stage))
                  :elapsed_ms (etaf-performance-stage-duration stage)))
          (etaf-performance-operation-stages operation)))))

(defun etaf-workbench-profile--frame-name (frame)
  "Describe a sampled FRAME without traversing captured application state."
  (cond ((symbolp frame) (symbol-name frame))
        ((byte-code-function-p frame) "<byte-code>")
        ((functionp frame) "<closure>")
        (t (format "<%s>" (type-of frame)))))

(defun etaf-workbench-profile--git (directory &rest arguments)
  "Read Git ARGUMENTS in DIRECTORY, returning nil when unavailable."
  (with-temp-buffer
    (when (eq 0 (apply #'process-file "git" nil t nil "-C" directory arguments))
      (string-trim-right (buffer-string)))))

(defun etaf-workbench-profile--sources ()
  "Identify the loaded workspace package roots and local source state."
  (vconcat
   (mapcar
    (lambda (feature)
      (let* ((entry (locate-library (symbol-name feature)))
             (directory (and entry (file-name-directory entry))))
        (list :package (symbol-name feature) :entry entry
              :revision (and directory
                             (etaf-workbench-profile--git directory "rev-parse" "HEAD"))
              :status (and directory
                           (etaf-workbench-profile--git directory "status" "--short"))
              :diff_hash
              (and directory
                   (secure-hash
                    'sha256
                    (or (etaf-workbench-profile--git directory "diff" "HEAD" "--") ""))))))
    '(ecss tp ebox etaf etaf-ui etaf-playground))))

(defun etaf-workbench-profile--print-stages (operations)
  "Print mean per-action stage totals from OPERATIONS, retaining overlap."
  (let ((totals (make-hash-table :test #'equal)) rows)
    (dolist (operation operations)
      (seq-doseq (stage (plist-get operation :stages))
        (let ((key (format "%s/%s" (plist-get stage :provider)
                           (plist-get stage :name))))
          (puthash key (+ (gethash key totals 0) (plist-get stage :elapsed_ms)) totals))))
    (maphash (lambda (key value) (push (cons key value) rows)) totals)
    (princ "Stage means per action (overlapping, instrumented):\n")
    (dolist (row (seq-take (sort rows (lambda (a b) (> (cdr a) (cdr b)))) 8))
      (princ (format "  %8.3f ms  %s\n" (/ (cdr row) (float (length operations)))
                     (car row))))))

(defun etaf-workbench-profile-batch ()
  "Diagnose the Workbench scenario selected by environment variables.
ETAF_WORKBENCH_PROFILE_SCENARIO defaults to row-toggle; theme-toggle and
focus-add are also supported.  ETAF_WORKBENCH_PROFILE_SAMPLES defaults to 10.
ETAF_WORKBENCH_PROFILE_OUTPUT selects an atomic JSON report outside Git."
  (let* ((scenario (or (getenv "ETAF_WORKBENCH_PROFILE_SCENARIO") "row-toggle"))
         (label (cdr (assoc scenario '(("row-toggle" . "完成")
                                       ("theme-toggle" . "深色")
                                       ("focus-add" . "定位新增按钮")))))
         (count-text (or (getenv "ETAF_WORKBENCH_PROFILE_SAMPLES") "10"))
         (count (string-to-number count-text))
         (output (or (getenv "ETAF_WORKBENCH_PROFILE_OUTPUT")
                     (make-temp-file "etaf-workbench-profile-" nil ".json")))
         (report (list :schema 1 :purpose "diagnostic-only"
                       :status "running" :scenario scenario
                       :tasks 100 :page_size 10 :viewport_width 1413 :viewport_height 62
                       :warmups 5 :samples_per_pass count
                       :cpu_units "profiler sample weights"
                       :stack_order "leaf-first"
                       :sampling_interval_ns profiler-sampling-interval
                       :emacs emacs-version :machine (system-name)
                       :system system-configuration
                       :app_compiled (if (byte-code-function-p (symbol-function 'wb-open))
                                         t :false)
                       :runtime_compiled
                       (if (byte-code-function-p (symbol-function 'etaf-mount)) t :false)
                       :native (plist-get (ebox-native-reflow-runtime-report)
                                          :loaded-module-hash)
                       :sources (etaf-workbench-profile--sources)
                       :profile_hash (etaf-workbench-benchmark--source-hash
                                      'etaf-workbench-profile-batch)
                       :workload_hash (etaf-workbench-benchmark--source-hash
                                       'etaf-workbench-benchmark-batch)
                       :app_hash (etaf-workbench-benchmark--source-hash 'wb-open)))
         operations profiles (total 0)
         (inclusive (make-hash-table :test #'eq))
         (self (make-hash-table :test #'eq))
         functions)
    (condition-case problem
        (progn
          (unless label (error "Unknown Workbench scenario: %s" scenario))
          (unless (and (string-match-p "\\`[0-9]+\\'" count-text) (<= 1 count 100))
            (error "Profile samples must be an integer from 1 to 100"))
          (etaf-workbench-benchmark--write output report)
          ;; These two fresh mounts share the acceptance workload and checks.
          ;; Stage tracing never runs concurrently with CPU sampling.
          (etaf-workbench-benchmark--scenario
           scenario label
           (lambda (buffer runtime target)
             (with-current-buffer buffer
               (etaf-performance-mode 1)
               (etaf-performance-clear)
               (unwind-protect
                   (progn
                     (etaf-dispatch-event runtime target 'press)
                     (let ((records (etaf-performance-records)))
                       (unless (= 1 (length records))
                         (error "Expected one complete operation per action"))
                       (push (etaf-workbench-profile--operation (car records)) operations)))
                 (etaf-performance-mode -1))))
           count)
          (etaf-workbench-benchmark--scenario
           scenario label
           (lambda (_buffer runtime target)
             (profiler-reset)
             (profiler-start 'cpu)
             (unwind-protect (etaf-dispatch-event runtime target 'press)
               (profiler-stop))
             (let (stacks)
               (maphash
                (lambda (stack samples)
                  (cl-incf total samples)
                  (push (list :frames (vconcat (mapcar #'etaf-workbench-profile--frame-name
                                                     (append stack nil)))
                              :samples samples) stacks)
                  (when (and (> (length stack) 0) (symbolp (aref stack 0)))
                    (let ((name (aref stack 0)))
                      (puthash name (+ samples (gethash name self 0)) self)))
                  (dolist (name (delete-dups
                                 (cl-remove-if-not #'symbolp (append stack nil))))
                    (when name
                      (puthash name (+ samples (gethash name inclusive 0)) inclusive))))
                (profiler-profile-log (profiler-cpu-profile)))
               (push (vconcat stacks) profiles)))
           count)
          (unless (> total 0) (error "No CPU samples captured; increase profile samples"))
          (maphash
           (lambda (name samples)
             (let* ((file (symbol-file name 'defun))
                    (source (and file (string-suffix-p ".elc" file)
                                 (substring file 0 -1))))
               (push (list :function (symbol-name name)
                           :self_samples (gethash name self 0) :inclusive_samples samples
                           :inclusive_percent (* 100.0 (/ (float samples) total))
                           :file (if (and source (file-exists-p source)) source file))
                     functions)))
           inclusive)
          (setq functions (sort functions (lambda (a b)
                                            (> (plist-get a :inclusive_samples)
                                               (plist-get b :inclusive_samples)))))
          (setq report (plist-put report :status "completed"))
          (etaf-workbench-profile--print-stages operations)
          (princ (format "CPU sample weight: %d; inclusive counts overlap, not elapsed time\n" total))
          (dolist (row (seq-take functions 15))
            (princ (format "  %6.1f%%  self=%-5d %s\n"
                           (plist-get row :inclusive_percent)
                           (plist-get row :self_samples) (plist-get row :function)))))
      (error
       (setq report (plist-put report :status "failed"))
       (setq report (plist-put report :error
                               (let ((print-level 3) (print-length 8) (print-circle t))
                                 (error-message-string problem))))
       (princ (format "FAILED %s\n" (plist-get report :error)))))
    (setq report (plist-put report :operations (vconcat (nreverse operations)))
          report (plist-put report :cpu_samples total)
          report (plist-put report :cpu_profiles (vconcat (nreverse profiles)))
          report (plist-put report :functions (vconcat functions)))
    (etaf-workbench-benchmark--write output report)
    (princ (format "diagnostic=%s report=%s\n" (plist-get report :status) output))
    (kill-emacs (if (equal (plist-get report :status) "completed") 0 1))))

(provide 'profile-task-workbench)
;;; profile-task-workbench.el ends here
