;;; etaf-playground.el --- ETAF operations-console application pair -*- lexical-binding: t; -*-
;;; Commentary:
;; One reviewed pair: inert `.etaf' data plus an executable companion.
;;; Code:
(require 'cl-lib)
(require 'etaf)
(require 'etaf-ui)

(defconst etaf-playground-buffer-name "*ETAF Playground*")
(defconst etaf-playground-example-directory
  (expand-file-name "examples"
                    (file-name-directory (or load-file-name buffer-file-name))))
(defconst etaf-playground-scenario-manifest
  '((:pair "operations-console" :root-component etaf-operations-console-root
     :category "Complete application"
     :capabilities (view component reactivity context theme behavior events
                    actions data resource lifecycle etaf-ui)
     :refs (operations-console-alpha-increment operations-console-alpha-reset
            operations-console-beta-increment operations-console-beta-reset
            operations-console-nav-overview operations-console-nav-data
            operations-console-nav-resource operations-console-theme-toggle
            operations-console-local-callback operations-console-named-action
            operations-console-behavior-toggle operations-console-clear-selection
            operations-console-row-1 operations-console-row-2 operations-console-row-3
            operations-console-fail-next
            operations-console-resource-reload operations-console-error-boundary)
     :gui-checkpoints (compact fullscreen overview data resource theme focus)
     :performance (:warm-runs 10 :publication-per-event 1)))
  "The sole active Playground pair and its public review metadata.")
(defconst etaf-playground-example-names '("operations-console"))
(defvar-local etaf-playground-current-example nil)
(defconst etaf-playground--static-tags
  '(operations-console-shell header brand summary theme-control navigation tab
    main overview hero metric-strip metric workspace activity-panel
    capability-panel timeline data resource status
    column row text spacer panel label viewport-height stretch))

(defun etaf-playground-scenario (name)
  "Return the sole manifest entry named NAME."
  (or (and (equal name "operations-console")
           (car etaf-playground-scenario-manifest))
      (user-error "Unknown ETAF Playground pair: %s" name)))

(defun etaf-playground--pair-file (name suffix)
  "Return NAME pair path ending in SUFFIX."
  (expand-file-name (concat name suffix) etaf-playground-example-directory))

(defun etaf-playground--validate-static-node (node)
  "Validate inert static View NODE and return it."
  (cond
   ((or (null node) (stringp node) (numberp node) (keywordp node)
        (memq node '(t stretch viewport-height))) node)
   ((consp node)
    (unless (and (proper-list-p node) (symbolp (car node))
                 (memq (car node) etaf-playground--static-tags)
                 (not (string-prefix-p "etaf--" (symbol-name (car node))))
                 (not (string-prefix-p "ebox--" (symbol-name (car node)))))
      (error "Unsafe ETAF static View form: %S" node))
    (mapc #'etaf-playground--validate-static-node (cdr node))
    node)
   (t (error "Unsafe ETAF static View value: %S" node))))

(defun etaf-playground-read-static (name)
  "Read and validate NAME's single inert `.etaf' form."
  (with-temp-buffer
    (insert-file-contents (etaf-playground--pair-file name ".etaf"))
    (let ((read-eval nil)
          (form (read (current-buffer))))
      (ignore read-eval)
      (condition-case nil
          (progn (read (current-buffer))
                 (error "ETAF static file contains multiple forms"))
        (end-of-file nil))
      (etaf-playground--validate-static-node form))))

(defun etaf-playground-read-pair (name)
  "Read NAME data, load its companion, and return its root View."
  (let* ((scenario (etaf-playground-scenario name))
         (form (etaf-playground-read-static name))
         (root (plist-get scenario :root-component)))
    (unless (featurep 'etaf-operations-console)
      ;; Use Emacs's normal source/bytecode resolution.  `load-file' forced
      ;; the 39KB companion through the Lisp interpreter on every fresh
      ;; process, making the first retained render look like a layout
      ;; regression.  A compiled companion is the production path; source is
      ;; still the deterministic fallback when no `.elc' exists.
      (load (file-name-sans-extension
             (etaf-playground--pair-file name ".el"))
            nil nil nil))
    (unless (functionp root) (error "Missing root factory: %S" root))
    (funcall root form)))

(defun etaf-playground-mount-example (buffer-name name)
  "Mount pair NAME in BUFFER-NAME."
  (when-let ((runtime (etaf-runtime-for-buffer buffer-name)))
    (etaf-unmount runtime))
  (let ((buffer (etaf-mount buffer-name (etaf-playground-read-pair name))))
    (with-current-buffer buffer (setq etaf-playground-current-example name))
    buffer))

(defun etaf-playground--display-buffer (buffer)
  "Display BUFFER interactively and return it."
  (unless noninteractive (pop-to-buffer buffer))
  buffer)

;;;###autoload
(defun etaf-playground-open (&optional buffer-name)
  "Open the operations-console pair in BUFFER-NAME."
  (interactive)
  (etaf-playground--display-buffer
   (etaf-playground-mount-example
    (or buffer-name etaf-playground-buffer-name) "operations-console")))

;;;###autoload
(defun etaf-playground-open-example (name &optional buffer-name)
  "Open pair NAME in BUFFER-NAME."
  (etaf-playground--display-buffer
   (etaf-playground-mount-example
    (or buffer-name etaf-playground-buffer-name) name)))

;;;###autoload
(defun etaf-playground-reset (&optional buffer-name)
  "Remount the active pair in BUFFER-NAME."
  (interactive)
  (let ((name (or buffer-name etaf-playground-buffer-name)))
    (unless (get-buffer name) (user-error "No Playground pair is mounted"))
    (etaf-playground--display-buffer
     (etaf-playground-mount-example name "operations-console"))))

;;;###autoload
(defun etaf-playground-close (&optional buffer-name)
  "Unmount and kill the Playground BUFFER-NAME."
  (interactive)
  (let* ((name (or buffer-name etaf-playground-buffer-name))
         (buffer (get-buffer name)))
    (when-let ((runtime (and buffer (etaf-runtime-for-buffer buffer))))
      (etaf-unmount runtime))
    (when (buffer-live-p buffer) (kill-buffer buffer))
    buffer))

(provide 'etaf-playground)
;;; etaf-playground.el ends here
