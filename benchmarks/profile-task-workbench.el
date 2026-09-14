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

(defun etaf-workbench-profile--print-stages (operations action-count)
  "Print per-action stage totals from OPERATIONS for ACTION-COUNT activations."
  (let ((totals (make-hash-table :test #'equal)) rows)
    (dolist (operation operations)
      (seq-doseq (stage (plist-get operation :stages))
        (let ((key (format "%s/%s" (plist-get stage :provider)
                           (plist-get stage :name))))
          (puthash key (+ (gethash key totals 0) (plist-get stage :elapsed_ms)) totals))))
    (maphash (lambda (key value) (push (cons key value) rows)) totals)
    (princ "Stage means per action (overlapping, instrumented):\n")
    (dolist (row (seq-take (sort rows (lambda (a b) (> (cdr a) (cdr b)))) 8))
      (princ (format "  %8.3f ms  %s\n" (/ (cdr row) (float action-count))
                     (car row))))))

(defun etaf-workbench-profile-batch ()
  "Diagnose the Workbench scenario selected by environment variables.
ETAF_WORKBENCH_PROFILE_SCENARIO defaults to row-toggle; theme-toggle and
focus-add are also supported.  ETAF_WORKBENCH_PROFILE_SAMPLES defaults to 10.
ETAF_WORKBENCH_PROFILE_STACK_DEPTH defaults to 256 frames (16 through 1024).
ETAF_WORKBENCH_PROFILE_OUTPUT selects an atomic JSON report outside Git."
  (let* ((scenario (or (getenv "ETAF_WORKBENCH_PROFILE_SCENARIO") "row-toggle"))
         (label (cdr (assoc scenario '(("row-toggle" . "完成")
                                       ("theme-toggle" . "深色")
                                       ("focus-add" . "定位新增按钮")))))
         (count-text (or (getenv "ETAF_WORKBENCH_PROFILE_SAMPLES") "10"))
         (count (string-to-number count-text))
         (depth-text (or (getenv "ETAF_WORKBENCH_PROFILE_STACK_DEPTH") "256"))
         (profiler-max-stack-depth (string-to-number depth-text))
         (output (or (getenv "ETAF_WORKBENCH_PROFILE_OUTPUT")
                     (make-temp-file "etaf-workbench-profile-" nil ".json")))
         (report (list :schema 1 :purpose "diagnostic-only"
                       :status "running" :scenario scenario
                       :tasks 100 :page_size 10 :viewport_width 1413 :viewport_height 62
                       :warmups 5 :samples_per_pass count
                       :cpu_units "profiler sample weights"
                       :stack_order "leaf-first"
                       :max_stack_depth profiler-max-stack-depth
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
         operations profiles (action-index 0) (total 0) (depth-limit-samples 0)
         (inclusive (make-hash-table :test #'eq))
         (self (make-hash-table :test #'eq))
         (nearest-callers (make-hash-table :test #'eq))
         functions caller-rows)
    (condition-case problem
        (progn
          (unless label (error "Unknown Workbench scenario: %s" scenario))
          (unless (and (string-match-p "\\`[0-9]+\\'" count-text) (<= 1 count 100))
            (error "Profile samples must be an integer from 1 to 100"))
          (unless (and (string-match-p "\\`[0-9]+\\'" depth-text)
                       (<= 16 profiler-max-stack-depth 1024))
            (error "Profile stack depth must be an integer from 16 to 1024"))
          (etaf-workbench-benchmark--write output report)
          ;; These two fresh mounts share the acceptance workload and checks.
          ;; Stage tracing never runs concurrently with CPU sampling.
          (etaf-workbench-benchmark--scenario
           scenario label
           (lambda (buffer runtime target)
             (cl-incf action-index)
             (with-current-buffer buffer
               (etaf-performance-mode 1)
               (etaf-performance-clear)
               (unwind-protect
                   (progn
                     (etaf-workbench-benchmark--dispatch runtime target)
                     (let ((records (etaf-performance-records)))
                       (unless records (error "No completed operation was recorded"))
                       (dolist (record records)
                         (push (append (list :action_index action-index)
                                       (etaf-workbench-profile--operation record)) operations))))
                 (etaf-performance-mode -1))))
           count)
          (etaf-workbench-benchmark--scenario
           scenario label
           (lambda (_buffer runtime target)
             (profiler-reset)
             (profiler-start 'cpu)
             (unwind-protect (etaf-workbench-benchmark--dispatch runtime target)
               (profiler-stop))
             (let (stacks)
               (maphash
                (lambda (raw-stack samples)
                  ;; Emacs pads normal sample vectors with nil.  Only occupied
                  ;; frames count toward the depth limit; GC has its own short
                  ;; vector.  Do not label padding as a truncated call chain.
                  (let* ((last-frame (cl-position-if #'identity raw-stack :from-end t))
                         (stack (seq-subseq raw-stack 0 (if last-frame (1+ last-frame) 0)))
                         (caller
                          (seq-find
                           (lambda (frame)
                             (and (symbolp frame)
                                  (string-match-p
                                   "\\`\\(?:ebox\\|ecss\\|tp\\|etaf\\|wb\\)-"
                                   (symbol-name frame))))
                           stack)))
                    (cl-incf total samples)
                    (when caller
                      (puthash caller (+ samples (gethash caller nearest-callers 0))
                               nearest-callers))
                    (when (>= (length stack) profiler-max-stack-depth)
                      (cl-incf depth-limit-samples samples))
                    (push (list :frames (vconcat (mapcar #'etaf-workbench-profile--frame-name
                                                       (append stack nil)))
                                :at_depth_limit (if (>= (length stack) profiler-max-stack-depth)
                                                    t :false)
                                :samples samples) stacks)
                    (when (and (> (length stack) 0) (symbolp (aref stack 0)))
                      (let ((name (aref stack 0)))
                        (puthash name (+ samples (gethash name self 0)) self)))
                    (dolist (name (delete-dups
                                   (cl-remove-if-not #'symbolp (append stack nil))))
                      (when name
                        (puthash name (+ samples (gethash name inclusive 0)) inclusive)))))
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
          (maphash
           (lambda (name samples)
             (push (list :function (symbol-name name) :samples samples
                         :percent (* 100.0 (/ (float samples) total)))
                   caller-rows))
           nearest-callers)
          (setq caller-rows (sort caller-rows (lambda (a b)
                                              (> (plist-get a :samples)
                                                 (plist-get b :samples)))))
          (setq report (plist-put report :status "completed"))
          (etaf-workbench-profile--print-stages operations count)
          (princ (format "CPU sample weight: %d; inclusive counts overlap, not elapsed time\n" total))
          (princ (format "Stack depth: %d; depth-limit sample weight: %d (%.1f%%)\n"
                         profiler-max-stack-depth depth-limit-samples
                         (* 100.0 (/ (float depth-limit-samples) total))))
          (when (> depth-limit-samples 0)
            (princ "Depth limit reached: omitted callers can be undercounted; increase stack depth.\n"))
          (princ "Nearest named package callers (disjoint sample attribution):\n")
          (dolist (row (seq-take caller-rows 12))
            (princ (format "  %6.1f%%  samples=%-5d %s\n"
                           (plist-get row :percent)
                           (plist-get row :samples) (plist-get row :function)))))
      (error
       (setq report (plist-put report :status "failed"))
       (setq report (plist-put report :error
                               (let ((print-level 3) (print-length 8) (print-circle t))
                                 (error-message-string problem))))
       (princ (format "FAILED %s\n" (plist-get report :error)))))
    (setq report (plist-put report :operations (vconcat (nreverse operations)))
          report (plist-put report :cpu_samples total)
          report (plist-put report :depth_limit_samples depth-limit-samples)
          report (plist-put report :depth_limit_percent
                            (if (> total 0)
                                (* 100.0 (/ (float depth-limit-samples) total))
                              0.0))
          report (plist-put report :cpu_profiles (vconcat (nreverse profiles)))
          report (plist-put report :functions (vconcat functions)))
    (setq report (plist-put report :nearest_package_callers (vconcat caller-rows)))
    (etaf-workbench-benchmark--write output report)
    (princ (format "diagnostic=%s report=%s\n" (plist-get report :status) output))
    (kill-emacs (if (equal (plist-get report :status) "completed") 0 1))))

(provide 'profile-task-workbench)
;;; profile-task-workbench.el ends here
