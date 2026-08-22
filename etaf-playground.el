;;; etaf-playground.el --- Generic ETAF pair playground framework -*- lexical-binding: t; -*-

;;; Commentary:
;; The Playground owns only pair registration, inert `.etaf' validation,
;; companion loading, mounting, and cleanup.  Applications belong in their
;; same-basename companion modules and never leak into this framework.

;;; Code:
(require 'cl-lib)
(require 'etaf)
(require 'etaf-playground-catalog)

;; `read' consults this dynamically scoped safety switch.  Declare it here
;; so the lexical-binding compiler does not mistake the protected binding for
;; an unused lexical local.
(defvar read-eval)

(defconst etaf-playground-buffer-name "*ETAF Playground*"
  "Default buffer used by the generic Playground launcher.")
(defconst etaf-playground-example-directory
  (expand-file-name "examples"
                    (file-name-directory (or load-file-name buffer-file-name)))
  "Directory containing same-basename `.etaf' and `.el' pairs.")
(defvar etaf-playground-default-pair
  (plist-get (car etaf-playground-catalog) :pair)
  "Pair opened by `etaf-playground-open'.")
(defvar etaf-playground-scenario-manifest
  (copy-tree etaf-playground-catalog)
  "Registered Playground pair specifications.

Each entry declares the pair name, companion feature, root factory, inert
static tags, public refs, and review metadata.  The framework does not inspect
or special-case the application's business model.")
(defvar etaf-playground-example-names
  (mapcar (lambda (entry) (plist-get entry :pair))
          etaf-playground-scenario-manifest)
  "Names of registered Playground pairs.")
(defvar-local etaf-playground-current-example nil)

(defun etaf-playground-register-pair (entry)
  "Register or replace a generic Playground pair ENTRY.

ENTRY must contain a string `:pair', symbol `:root-component', symbol
`:companion-feature', and a proper-list `:static-tags'."
  (let ((name (plist-get entry :pair)))
    (unless (and (stringp name) (symbolp (plist-get entry :root-component))
                 (symbolp (plist-get entry :companion-feature))
                 (proper-list-p (plist-get entry :static-tags)))
      (error "Invalid Playground pair manifest entry: %S" entry))
    (setq etaf-playground-scenario-manifest
          (cons entry
                (cl-remove name etaf-playground-scenario-manifest
                           :key (lambda (item) (plist-get item :pair))
                           :test #'equal)))
    (setq etaf-playground-example-names
          (mapcar (lambda (item) (plist-get item :pair))
                  etaf-playground-scenario-manifest))
    entry))

(defun etaf-playground-scenario (name)
  "Return the registered pair specification named NAME."
  (or (cl-find name etaf-playground-scenario-manifest
               :key (lambda (entry) (plist-get entry :pair))
               :test #'equal)
      (user-error "Unknown ETAF Playground pair: %s" name)))

(defun etaf-playground--pair-file (name suffix)
  "Return NAME pair path ending in SUFFIX."
  (expand-file-name (concat name suffix) etaf-playground-example-directory))

(defun etaf-playground--validate-static-node (node tags)
  "Validate inert static View NODE against allowlisted TAGS."
  (cond
   ((or (null node) (stringp node) (numberp node) (keywordp node)
        (memq node '(t stretch viewport-height))) node)
   ;; Symbols in a static pair are inert enum/data values.  They are not
   ;; evaluated because only proper-list nodes become View forms; reject
   ;; private runtime names while keeping the manifest format composable.
   ((symbolp node)
    (unless (or (string-prefix-p "etaf--" (symbol-name node))
                (string-prefix-p "ebox--" (symbol-name node)))
      node))
   ((consp node)
    (unless (and (proper-list-p node) (symbolp (car node))
                 (memq (car node) tags)
                 (not (string-prefix-p "etaf--" (symbol-name (car node))))
                 (not (string-prefix-p "ebox--" (symbol-name (car node)))))
      (error "Unsafe ETAF static View form: %S" node))
    (mapc (lambda (child) (etaf-playground--validate-static-node child tags))
          (cdr node))
    node)
   (t (error "Unsafe ETAF static View value: %S" node))))

(defun etaf-playground-read-static (name)
  "Read and validate NAME's single inert `.etaf' form."
  (let ((scenario (etaf-playground-scenario name)))
    (with-temp-buffer
      (insert-file-contents (etaf-playground--pair-file name ".etaf"))
      (let ((read-eval nil))
        (ignore read-eval)
        (let ((form (read (current-buffer))))
          (condition-case nil
              (progn (read (current-buffer))
                     (error "ETAF static file contains multiple forms"))
            (end-of-file nil))
          (etaf-playground--validate-static-node
           form (plist-get scenario :static-tags)))))))

(defun etaf-playground-read-pair (name)
  "Read NAME data, load its companion, and return its root View."
  (let* ((scenario (etaf-playground-scenario name))
         (form (etaf-playground-read-static name))
         (feature (plist-get scenario :companion-feature))
         (root (plist-get scenario :root-component)))
    (unless (featurep feature)
      (load (file-name-sans-extension
             (etaf-playground--pair-file name ".el")) nil nil nil))
    (unless (functionp root) (error "Missing root factory: %S" root))
    (funcall root form)))

(defun etaf-playground-mount-example (buffer-name name)
  "Mount registered pair NAME in BUFFER-NAME."
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
  "Open the registered default pair in BUFFER-NAME."
  (interactive)
  (etaf-playground--display-buffer
   (etaf-playground-mount-example
    (or buffer-name etaf-playground-buffer-name)
    etaf-playground-default-pair)))

;;;###autoload
(defun etaf-playground-open-example (name &optional buffer-name)
  "Open registered pair NAME in BUFFER-NAME."
  (interactive (list (completing-read "Pair: " etaf-playground-example-names)))
  (etaf-playground--display-buffer
   (etaf-playground-mount-example
    (or buffer-name etaf-playground-buffer-name) name)))

;;;###autoload
(defun etaf-playground-reset (&optional buffer-name)
  "Remount the current/default registered pair in BUFFER-NAME."
  (let* ((name (or buffer-name etaf-playground-buffer-name))
         (buffer (get-buffer name))
         (pair (or (and buffer
                        (buffer-local-value 'etaf-playground-current-example
                                            buffer))
                   etaf-playground-default-pair)))
    (unless buffer (user-error "No ETAF Playground pair is mounted"))
    (etaf-playground--display-buffer
     (etaf-playground-mount-example name pair))))

;;;###autoload
(defun etaf-playground-close (&optional buffer-name)
  "Unmount and kill the Playground BUFFER-NAME."
  (let* ((name (or buffer-name etaf-playground-buffer-name))
         (buffer (get-buffer name)))
    (when-let ((runtime (and buffer (etaf-runtime-for-buffer buffer))))
      (etaf-unmount runtime))
    (when (buffer-live-p buffer) (kill-buffer buffer))
    buffer))

(provide 'etaf-playground)
;;; etaf-playground.el ends here
