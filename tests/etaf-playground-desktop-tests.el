;;; etaf-playground-desktop-tests.el --- Desktop consumer integration -*- lexical-binding: t; -*-

(require 'ert)
(require 'etaf)
(require 'etaf-playground)

(ert-deftest etaf-playground-consumes-etaf-desktop-application ()
  "The Playground mounts and releases the independent desktop application."
  (let ((buffer-name "*ETAF Playground Desktop Test*"))
    (unwind-protect
        (let ((buffer (etaf-playground-mount-example buffer-name "desktop")))
          (should (buffer-live-p buffer))
          (with-current-buffer buffer
            (should (string-match-p "Notes" (buffer-string)))
            (should (string-match-p "Signal" (buffer-string))))
          (should (stringp (buffer-name buffer))))
      (when-let* ((buffer (get-buffer buffer-name))
                  (runtime (etaf-runtime-for-buffer buffer)))
        (etaf-unmount runtime))
      (when-let* ((buffer (get-buffer buffer-name)))
        (kill-buffer buffer)))))

(provide 'etaf-playground-desktop-tests)
;;; etaf-playground-desktop-tests.el ends here
