;;; etaf-playground-tests.el --- ETAF example tests -*- lexical-binding: t; -*-

(require 'ert)
(require 'etaf-playground)

(defun etaf-playground-test--layout-property (node key)
  "Return layout KEY from ordinary or Flex NODE."
  (if (plist-member node key)
      (plist-get node key)
    (plist-get (plist-get node :box) key)))

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
            (should (equal (plist-get root :bgcolor) "#F8F5EE"))
            (should-not (plist-member root :surface-properties))
            (should (equal (mapcar (lambda (node)
                                     (etaf-playground-test--layout-property
                                      node :bgcolor))
                                   children)
                           '("#FFFDF8" nil "#FFFDF8")))))
      (when-let ((runtime (etaf-runtime-for-buffer buffer-name)))
        (etaf-unmount runtime))
      (when-let ((buffer (get-buffer buffer-name)))
        (kill-buffer buffer)))))

(ert-deftest etaf-playground-showcase-delegates-viewport-width-to-host ()
  "Let the host own viewport width and stretch each shell section inside it."
  (let ((buffer-name " *etaf-playground-width-owner-test*")
        (ebox-viewport-width 900)
        (ebox-viewport-height 40))
    (unwind-protect
        (progn
          (etaf-mount buffer-name (etaf-playground-showcase-view))
          (let* ((runtime (etaf-runtime-for-buffer buffer-name))
                 (root (etaf-runtime-root-node runtime))
                 (layout (plist-get root :ebox-content-node))
                 (children (plist-get layout :children))
                 (main (nth 1 children)))
            (should (eq (plist-get root :width) 'stretch))
            (should (eq (plist-get main :ebox-type) 'box))
            (should (eq (plist-get (plist-get main :ebox-content-node)
                                   :ebox-type)
                        'stack))
            (should (cl-every
                     (lambda (node)
                       (eq (etaf-playground-test--layout-property node :width)
                           'stretch))
                     children))))
      (when-let ((runtime (etaf-runtime-for-buffer buffer-name)))
        (etaf-unmount runtime))
      (when-let ((buffer (get-buffer buffer-name)))
        (kill-buffer buffer)))))

(ert-deftest etaf-playground-showcase-syncs-to-window-body-width ()
  "Exclude fringes and other window chrome from the Ebox viewport width."
  (let (rerender-arguments)
    (cl-letf (((symbol-function 'get-buffer-window)
               (lambda (_buffer _all-frames) 'showcase-window))
              ((symbol-function 'window-pixel-width)
               (lambda (_window) 900))
              ((symbol-function 'window-body-width)
               (lambda (_window &optional pixelwise) (and pixelwise 880)))
              ((symbol-function 'window-body-height)
               (lambda (_window) 40))
              ((symbol-function 'window-frame)
               (lambda (_window) 'showcase-frame))
              ((symbol-function 'frame-char-width)
               (lambda (_frame) 8))
              ((symbol-function 'ebox-rerender-buffer-with-context)
               (lambda (&rest arguments)
                 (setq rerender-arguments arguments))))
      (etaf-playground--showcase-sync-viewport "*Showcase*")
      (should (equal rerender-arguments '("*Showcase*" 872 40))))))

(provide 'etaf-playground-tests)

;;; etaf-playground-tests.el ends here
