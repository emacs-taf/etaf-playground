;;; performance-scenarios.el --- Search laboratory interaction workloads -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Public application input and observable outcomes for the shared driver.
;; Sampling, profiling, deadlines and source freshness belong to the workspace.

;;; Code:
(require 'cl-lib)
(require 'etaf-playground)
(require 'etaf)
(declare-function taf-benchmark-register "performance-driver" (id &rest properties))

(defun pf-benchmark--setup (mode keyboard)
  "Prepare one retained search board for MODE; KEYBOARD selects real RET input."
  (let* ((buffer (generate-new-buffer " *Pathfinding benchmark*"))
         (runtime nil) (before 0) (before-text nil) (ready nil))
    (etaf-playground-mount-example
     (buffer-name buffer) "pathfinding" nil
     (list :viewport-width (* 100 (frame-char-width)) :viewport-height 50))
    (setq runtime (etaf-runtime-for-buffer buffer))
    (list
     :buffer buffer
     :ready (lambda ()
              (unless ready
                (when (eq mode 'gui) (etaf-refit runtime (selected-window)))
                (setq ready t))
              t)
     :prepare
     (lambda ()
       (when (with-current-buffer buffer
               (string-match-p "已找到\\|不可达"
                               (buffer-substring-no-properties (point-min) (point-max))))
         (etaf-dispatch-event runtime 'pf-reset 'press))
       (when keyboard (etaf-focus runtime 'pf-step))
       (setq before (etaf-runtime-generation runtime)
             before-text (with-current-buffer buffer
                           (buffer-substring-no-properties (point-min) (point-max)))))
     :invoke (lambda (_sample)
               (if keyboard (execute-kbd-macro (kbd "RET"))
                 (etaf-dispatch-event runtime 'pf-step 'press)))
     :verify (lambda ()
               (and (> (etaf-runtime-generation runtime) before)
                    (etaf-host-ref-bounds runtime 'pf-cell-2-2)
                    (not (equal before-text
                                (with-current-buffer buffer
                                  (buffer-substring-no-properties (point-min) (point-max)))))))
     :outcome
     (lambda ()
       (let ((bounds (etaf-host-ref-bounds runtime 'pf-summary)))
         (list :generation (etaf-runtime-generation runtime)
               :summary (with-current-buffer buffer
                          (buffer-substring-no-properties (car bounds) (cdr bounds))))))
     :observe
     (lambda (sink)
       (etaf-performance-start runtime)
       (let ((before-ids (mapcar (lambda (record)
                                  (cons (plist-get record :runtime-id) (plist-get record :id)))
                                (plist-get (etaf-performance-report-data) :operations))))
         (lambda ()
           (etaf-performance-stop runtime)
           (dolist (operation (plist-get (etaf-performance-report-data) :operations))
             (when (and (equal (plist-get operation :buffer-name) (buffer-name buffer))
                        (not (member (cons (plist-get operation :runtime-id)
                                           (plist-get operation :id)) before-ids)))
               (dolist (stage (plist-get operation :stages))
                 (funcall sink
                          (append (list :provider (plist-get stage :provider)
                                        :stage (plist-get stage :stage)
                                        :duration-ms (plist-get stage :duration-ms))
                                  (plist-get stage :metadata)))))))))
     :cleanup (lambda ()
                (when-let* ((live (etaf-runtime-for-buffer buffer))) (etaf-unmount live))
                (when (buffer-live-p buffer) (kill-buffer buffer))))))

(taf-benchmark-register
 "pathfinding.step.callback" :version 1 :modes '(batch gui) :isolation 'series
 :required-providers '(ebox)
 :budget-ms 100 :impact 'local
 :description "One real search/route animation step on the retained 24x14 board"
 :setup (lambda (mode) (pf-benchmark--setup mode nil)))
(taf-benchmark-register
 "pathfinding.step.keyboard" :version 1 :modes '(gui) :isolation 'series
 :required-providers '(ebox)
 :budget-ms 100 :impact 'local
 :description "RET on the focused Single Step control through the command loop"
 :setup (lambda (mode) (pf-benchmark--setup mode t)))

(provide 'pathfinding-performance-scenarios)
;;; performance-scenarios.el ends here
