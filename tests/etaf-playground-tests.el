;;; etaf-playground-tests.el --- ETAF example tests -*- lexical-binding: t; -*-

(require 'ert)
(require 'etaf-playground)

(ert-deftest etaf-playground-mounts-and-dispatches-core-example ()
  "Mount the public playground and update its retained counter."
  (let ((buffer-name " *etaf-playground-test*"))
    (unwind-protect
        (progn
          (etaf-mount buffer-name (etaf-playground-view))
          (with-current-buffer buffer-name
            (should (string-match-p "ETAF Playground" (buffer-string)))
            (should (string-match-p "Count: 0" (buffer-string))))
          (etaf-dispatch-event (etaf-runtime-for-buffer buffer-name)
                               'increment 'press)
          (with-current-buffer buffer-name
            (should (string-match-p "Count: 1" (buffer-string)))))
      (when-let ((runtime (etaf-runtime-for-buffer buffer-name)))
        (etaf-unmount runtime))
      (when-let ((buffer (get-buffer buffer-name)))
        (kill-buffer buffer)))))

(ert-deftest etaf-playground-ui-entry-keeps-catalog-optional ()
  "Load the catalog only through the optional UI entry point."
  (require 'etaf-ui)
  (let ((buffer-name " *etaf-playground-ui-test*"))
    (unwind-protect
        (progn
          (etaf-mount buffer-name (etaf-playground-ui-view))
          (with-current-buffer buffer-name
            (should (string-match-p "Official Components" (buffer-string)))
            (should (string-match-p "Controlled checkbox" (buffer-string)))))
      (when-let ((runtime (etaf-runtime-for-buffer buffer-name)))
        (etaf-unmount runtime))
      (when-let ((buffer (get-buffer buffer-name)))
        (kill-buffer buffer)))))

(provide 'etaf-playground-tests)

;;; etaf-playground-tests.el ends here
