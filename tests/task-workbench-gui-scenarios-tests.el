;;; task-workbench-gui-scenarios-tests.el --- Workbench measurement order -*- lexical-binding: t; -*-

;;; Commentary:

;; Batch tests prove the adapter's message/paint/measurement ordering.  Actual
;; echo-area resizing and compositor geometry require the existing GUI run.

;;; Code:

(require 'cl-lib)
(require 'ert)
(add-to-list 'load-path (expand-file-name "../etaf/scripts" default-directory))
(add-to-list 'load-path (expand-file-name "../ebox-playground" default-directory))
(require 'task-workbench-gui-scenarios)

(ert-deftest wb-gui-preparation-preserves-focus-unless-requested ()
  "Preparation selects the target inside Emacs without activating the app."
  (let ((wb-gui--primary-name " *wb-gui-focus-fixture*")
        (wb-gui--secondary-name " *wb-gui-focus-secondary*")
        (wb-gui--prepared-buffer nil)
        (activations 0))
    (save-window-excursion
      (unwind-protect
          (cl-letf (((symbol-function 'display-graphic-p) (lambda (&rest _) t))
                    ((symbol-function 'wb-gui--configure-native) #'ignore)
                    ((symbol-function 'wb-gui--redisplay-for-geometry) #'ignore)
                    ((symbol-function 'select-frame-set-input-focus)
                     (lambda (&rest _) (cl-incf activations))))
            (dolist (foreground '(nil t))
              (let ((buffer (task-workbench-gui-prepare foreground)))
                (should (eq buffer (window-buffer (selected-window))))
                (should (= activations (if foreground 1 0)))
                (kill-buffer buffer))))
        (when (buffer-live-p wb-gui--prepared-buffer)
          (kill-buffer wb-gui--prepared-buffer))))))

(ert-deftest wb-gui-default-keeps-current-backend ()
  "An existing GUI without a native module remains a valid acceptance target."
  (let ((process-environment (copy-sequence process-environment))
        (ebox-native-reflow-module-path "/existing/module/location"))
    (setenv "EBOX_NATIVE_REFLOW_MODULE_PATH" nil)
    (cl-letf (((symbol-function 'ebox-native-reflow-runtime-report)
               (lambda () '(:layout-ready-p nil :load-error module-not-found))))
      (should (equal (wb-gui--configure-native)
                     '(:layout-ready-p nil :load-error module-not-found)))
      (should (equal ebox-native-reflow-module-path "/existing/module/location")))))

(ert-deftest wb-gui-explicit-native-request-remains-required ()
  "An explicit native request must not silently fall back or change modules."
  (let ((process-environment (copy-sequence process-environment))
        (ebox-native-reflow-module-path nil)
        (report '(:layout-ready-p nil :load-error module-not-found)))
    (setenv "EBOX_NATIVE_REFLOW_MODULE_PATH" "/requested/module")
    (cl-letf (((symbol-function 'file-readable-p) (lambda (_) t))
              ((symbol-function 'file-directory-p) (lambda (_) nil))
              ((symbol-function 'file-equal-p) #'equal)
              ((symbol-function 'ebox-native-reflow-runtime-report)
               (lambda () report)))
      (should-error (wb-gui--configure-native))
      (setq report '(:layout-ready-p t :loaded-module-path "/different/module"))
      (should-error (wb-gui--configure-native))
      (setq report '(:layout-ready-p t :loaded-module-path "/requested/module"))
      (should (equal report (wb-gui--configure-native))))))

(ert-deftest wb-gui-empty-native-request-is-invalid ()
  "An empty configured path is an error, rather than the default backend."
  (let ((process-environment (copy-sequence process-environment)))
    (setenv "EBOX_NATIVE_REFLOW_MODULE_PATH" "")
    (should-error (wb-gui--configure-native))))

(ert-deftest wb-gui-theme-baseline-clears-owned-message-before-paint ()
  "The first baseline measurement follows clearing and painting our diagnostic."
  (let ((context (etaf-gui-verifier--context-create))
        (echo-message (concat "Workbench GUI native module: " (make-string 300 ?x)))
        (bottom 797)
        trace)
    (cl-letf (((symbol-function 'current-message) (lambda () echo-message))
              ((symbol-function 'message)
               (lambda (format &rest _)
                 (should-not format)
                 (setq echo-message nil)
                 (push 'clear trace)))
              ((symbol-function 'redisplay)
               (lambda (&rest _)
                 (setq bottom (if echo-message 797 813))
                 (push 'paint trace)))
              ((symbol-function 'sit-for) (lambda (&rest _) (push 'wait trace)))
              ((symbol-function 'wb-gui--layout-snapshot)
               (lambda (_)
                 (push 'measure trace)
                 (list :viewport (list 0 0 991 bottom) :controls '((title 0 0))))))
      (wb-gui--capture-theme-baseline context)
      (should (equal '(clear paint measure wait paint measure) (nreverse trace)))
      (should (equal '(0 0 991 813)
                     (plist-get (etaf-gui-verifier-context-get context 'light-layout)
                                :viewport)))
      (should (wb-gui--theme-layout-preserved-p context))
      ;; Later viewport differences remain a failure, even with identical controls.
      (setq bottom 797)
      (should-not (wb-gui--theme-layout-preserved-p context)))))

(ert-deftest wb-gui-geometry-paint-preserves-unowned-messages ()
  "Geometry preparation clears only this adapter's own diagnostic."
  (let ((paints 0))
    (cl-letf (((symbol-function 'current-message) (lambda () "A user message"))
              ((symbol-function 'message)
               (lambda (&rest _) (ert-fail "Cleared an unrelated message")))
              ((symbol-function 'redisplay) (lambda (&rest _) (cl-incf paints))))
      (wb-gui--redisplay-for-geometry)
      (should (= paints 1)))))

(provide 'task-workbench-gui-scenarios-tests)
;;; task-workbench-gui-scenarios-tests.el ends here
