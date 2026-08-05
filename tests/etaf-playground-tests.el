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

(ert-deftest etaf-playground-showcase-covers-public-interaction-path ()
  "Mount the Showcase and exercise its navigation, data, and theme events."
  (let ((buffer-name " *etaf-playground-showcase-test*"))
    (unwind-protect
        (progn
          (etaf-mount buffer-name (etaf-playground-showcase-view))
          (with-current-buffer buffer-name
            (should (string-match-p "ETAF Showcase" (buffer-string)))
            (should (string-match-p "VISIBLE WORK ITEMS" (buffer-string)))
            (should (string-match-p "4" (buffer-string))))
          (let ((runtime (etaf-runtime-for-buffer buffer-name)))
            (etaf-dispatch-event runtime 'showcase-open-work-items 'press)
            (with-current-buffer buffer-name
              (should (string-match-p "Work items" (buffer-string)))
              (should (string-match-p "T-101" (buffer-string))))
            (etaf-dispatch-event runtime 'showcase-task-T-101 'press)
            (with-current-buffer buffer-name
              (should (string-match-p "Selected T-101" (buffer-string))))
            (etaf-dispatch-event runtime 'showcase-add-task 'press)
            (with-current-buffer buffer-name
              (should (string-match-p "T-107" (buffer-string))))
            (etaf-dispatch-event runtime 'showcase-nav-theme 'press)
            (with-current-buffer buffer-name
              (should (string-match-p "Theme and semantics" (buffer-string))))
            (etaf-dispatch-event runtime 'showcase-theme-toggle 'press)
            (with-current-buffer buffer-name
              (should (string-match-p "Dark theme" (buffer-string)))
              (should (string-match-p "Dark semantic surface" (buffer-string))))
            (etaf-dispatch-event runtime 'showcase-nav-overview 'press)
            (with-current-buffer buffer-name
              (should (string-match-p "Overview" (buffer-string)))
              (should (string-match-p "Dark semantic surface" (buffer-string))))))
      (when-let ((runtime (etaf-runtime-for-buffer buffer-name)))
        (etaf-unmount runtime))
      (when-let ((buffer (get-buffer buffer-name)))
        (kill-buffer buffer)))))

(ert-deftest etaf-playground-showcase-keeps-backgrounds-layered ()
  "Keep the root canvas background separate from semantic surface boxes."
  (let ((buffer-name " *etaf-playground-showcase-layering-test*"))
    (unwind-protect
        (progn
          (etaf-mount buffer-name (etaf-playground-showcase-view))
          (let* ((runtime (etaf-runtime-for-buffer buffer-name))
                 (root (etaf-runtime-root-node runtime))
                 (layout (plist-get root :ebox-content-node))
                 (children (plist-get layout :children)))
            (should (equal (plist-get root :bgcolor) "#F4F6FB"))
            (should-not (plist-member root :surface-properties))
            (should (equal (mapcar (lambda (node) (plist-get node :bgcolor))
                                   children)
                           '("#FFFFFF" nil "#FFFFFF")))))
      (when-let ((runtime (etaf-runtime-for-buffer buffer-name)))
        (etaf-unmount runtime))
      (when-let ((buffer (get-buffer buffer-name)))
        (kill-buffer buffer)))))

(provide 'etaf-playground-tests)

;;; etaf-playground-tests.el ends here
