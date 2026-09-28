;;; etaf-playground-tests.el --- Public API acceptance -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Verify failure behavior through the supported mount API.

;;; Code:
(require 'ert)
(require 'etaf-playground)

(ert-deftest etaf-playground-mount-rejects-unknown-example ()
  "An unknown example fails explicitly without publishing preview content."
  (let ((buffer (generate-new-buffer " *playground-public-acceptance*")))
    (unwind-protect
        (progn
          (should-error
           (etaf-playground-mount-example
            (buffer-name buffer) "missing-public-acceptance-example")
           :type 'user-error)
          (with-current-buffer buffer
            (should (= (buffer-size) 0))))
      (when (buffer-live-p buffer) (kill-buffer buffer)))))

(ert-deftest etaf-playground-mounts-preloaded-research-companion ()
  "A directly loaded companion keeps its Actions usable across preview mounts."
  (let* ((user-emacs-directory (make-temp-file "preloaded-preview-" t))
         (root (file-name-directory (locate-library "etaf-playground")))
         (buffer (generate-new-buffer " *preloaded-preview*")))
    (unwind-protect
        (progn
          ;; Use the same source/compiled selection as an ordinary application
          ;; preload.  The package check compiles the shipped companion first.
          (load (expand-file-name "examples/research-shelf" root) nil t)
          (dotimes (_ 2)
            (etaf-playground-mount-example (buffer-name buffer) "research-shelf")
            (let ((runtime (etaf-runtime-for-buffer buffer)))
              (should (not (null runtime)))
              (etaf-dispatch-event runtime 'research-shelf-reload 'press)
              (with-current-buffer buffer
                (let ((text (buffer-substring-no-properties (point-min) (point-max))))
                  (should (string-match-p "256 items · SQLite-backed" text))
                  (should (string-match-p "Library reloaded" text)))))))
      (when-let* ((runtime (etaf-runtime-for-buffer buffer)))
        (etaf-unmount runtime))
      (when (buffer-live-p buffer) (kill-buffer buffer))
      (delete-directory user-emacs-directory t))))

(ert-deftest etaf-playground-mounts-static-rule-companion-in-fresh-emacs ()
  "The shipped app mounts, filters, paginates and switches themes in a fresh process."
  (let* ((workspace (file-name-directory
                     (directory-file-name
                      (file-name-directory (locate-library "etaf-playground")))))
         (paths (apply #'append
                       (mapcar (lambda (name) (list "-L" (expand-file-name name workspace)))
                               '("ecss" "ebox" "etaf" "etaf-ui" "etaf-db"
                                 "etaf-playground"))))
         (log (generate-new-buffer " *playground-rule-check*")))
    (unwind-protect
        (let ((status
               (apply
                #'call-process (expand-file-name invocation-name invocation-directory)
                nil log nil
                (append
                 '("-Q" "--batch") paths
                 (list "--eval" "(setq load-prefer-newer t)"
                       "--eval"
                       (prin1-to-string
                        '(let ((user-emacs-directory (make-temp-file "rules-preview-" t))
                               (buffer (generate-new-buffer " *rules-preview*")))
                           (unwind-protect
                               (progn
                                 (require 'etaf-playground)
                                 (etaf-playground-mount-example
                                  (buffer-name buffer) "research-shelf")
                                 (unless (with-current-buffer buffer
                                           (string-match-p "Research Shelf" (buffer-string)))
                                   (error "Missing Research Shelf preview"))
                                 (let ((runtime (etaf-runtime-for-buffer buffer)))
                                   (dolist (step
                                            '((research-shelf-filter-reading . "Showing Reading")
                                              (research-shelf-filter-all . "Showing All")
                                              (research-shelf-page-next . "Page 2 / 22")
                                              (research-shelf-page-previous . "Page 1 / 22")
                                              (research-shelf-theme-toggle . "Dark theme")
                                              (research-shelf-theme-toggle . "Light theme")))
                                     (let ((generation (etaf-runtime-generation runtime)))
                                       (etaf-dispatch-event runtime (car step) 'press)
                                       (unless (and (> (etaf-runtime-generation runtime) generation)
                                                    (with-current-buffer buffer
                                                      (string-match-p (cdr step) (buffer-string))))
                                         (error "Research Shelf did not publish %S" (car step)))))))
                             (when-let* ((runtime (etaf-runtime-for-buffer buffer)))
                               (etaf-unmount runtime))
                             (kill-buffer buffer)
                             (delete-directory user-emacs-directory t)))))))))
          (ert-info ((with-current-buffer log (buffer-string)))
            (should (equal status 0))))
      (kill-buffer log))))

(provide 'etaf-playground-tests)
;;; etaf-playground-tests.el ends here
