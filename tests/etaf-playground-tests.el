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

(provide 'etaf-playground-tests)
;;; etaf-playground-tests.el ends here
