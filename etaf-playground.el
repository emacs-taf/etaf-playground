;;; etaf-playground.el --- Generic ETAF source and preview workspace -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;; Author: ETAF contributors
;; Version: 0.2.0
;; Package-Requires: ((emacs "29.1") (etaf "0.1.0"))
;; Keywords: tools, convenience, ui

;;; Commentary:

;; ETAF Playground is an authoring surface, not an application.  It discovers
;; same-basename example triplets, opens their `.etaf', `.el', and optional
;; `.ecss' sources on the left, and mounts the companion root in a preview
;; buffer on the right.  An example owns its Components, state, storage, and
;; root factory; this file owns only source navigation, inert data readers,
;; loading, window layout, and mount lifecycle.
;;
;; The file contract is deliberately small:
;;
;;   examples/NAME.etaf   one inert structural form
;;   examples/NAME.el     a companion which defines NAME's root factory
;;   examples/NAME.ecss   optional `(styles (SELECTOR PROPERTY VALUE ...))'
;;
;; The default root convention is `etaf-NAME-root'.  A companion may call
;; `etaf-playground-register-example' to provide a different root or feature.
;; Root factories receive the validated `.etaf' form and, when they accept a
;; second argument, the validated `.ecss' style form.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'button)
(require 'etaf)

(defgroup etaf-playground nil
  "Authoring workspaces for ETAF applications."
  :group 'etaf)

(defcustom etaf-playground-buffer-name "*ETAF Playground*"
  "Fallback name used by direct, non-workspace mounts."
  :type 'string
  :group 'etaf-playground)

(defcustom etaf-playground-example-directory
  (expand-file-name "examples"
                    (file-name-directory (or load-file-name buffer-file-name)))
  "Directory containing same-basename ETAF Playground examples."
  :type 'directory
  :group 'etaf-playground)

(defcustom etaf-playground-source-extensions
  '(".etaf" ".el" ".ecss")
  "Source extensions shown in a Playground workspace, in tab order."
  :type '(repeat string)
  :group 'etaf-playground)

(defcustom etaf-playground-preview-buffer-format
  "*ETAF Preview: %s*"
  "Format string used for a mounted example preview buffer."
  :type 'string
  :group 'etaf-playground)

(defcustom etaf-playground-refresh-on-save t
  "Whether saving a source buffer refreshes its paired preview."
  :type 'boolean
  :group 'etaf-playground)

(defcustom etaf-playground-display-action
  '((display-buffer-in-side-window)
    (side . right)
    (slot . 0)
    (window-width . 0.5))
  "Standard `display-buffer' action used for the preview buffer.
The default shows the preview in a right side window using half the frame.
Set `window-width' to a float for a ratio or an integer for a fixed column
count.  Use `display-buffer-pop-up-frame' to place the preview in its own
frame."
  :type 'sexp
  :group 'etaf-playground)

;; `read' consults this dynamically scoped safety switch.  Declaring it also
;; keeps byte compilation from treating the protected binding as lexical.
(defvar read-eval)

(cl-defstruct (etaf-playground-session
               (:constructor etaf-playground--session-create))
  "State shared by one source/preview workspace."
  name
  spec
  source-buffers
  preview-buffer
  preview-window
  source-frame
  active-extension
  owned-source-buffers
  companion-dirty-p
  previous-window-configuration)

(defvar etaf-playground--registrations (make-hash-table :test #'equal)
  "Companion-provided root and feature overrides, keyed by example name.")

(defvar etaf-playground--sessions (make-hash-table :test #'equal)
  "Live Playground sessions keyed by example name.")

(defvar etaf-playground-scenario-manifest nil
  "Discovered example specifications.

This compatibility variable is generated from the example directory.  It is
not a business catalog and contains no application metadata beyond file paths
and the root/feature naming convention.")

(defvar etaf-playground-example-names nil
  "Names discovered from `etaf-playground-example-directory'.")

(defvar etaf-playground-default-pair nil
  "Default discovered example opened by `etaf-playground-open'.")

(defvar-local etaf-playground-session nil
  "Session associated with the current source or preview buffer.")

(defvar-local etaf-playground-current-example nil
  "Example name associated with a direct mounted buffer.")

(defvar-local etaf-playground-source-extension nil
  "Extension represented by the current source buffer.")

(defvar-local etaf-playground-preview-p nil
  "Non-nil in a generated Playground preview buffer.")

(defvar-local etaf-playground-companion-dirty-p nil
  "Non-nil when the companion buffer needs an intentional reload.")

(defvar etaf-playground--current-example nil
  "Dynamically bound example name while a root factory is called.")
(defvar etaf-playground--current-static-form nil
  "Dynamically bound `.etaf' form while a root factory is called.")
(defvar etaf-playground--current-ecss nil
  "Dynamically bound `.ecss' form while a root factory is called.")

;;; Example discovery and registration

(defun etaf-playground-register-example
    (name &rest options)
  "Register companion overrides for example NAME.

OPTIONS accepts `:root' or `:root-component' and `:feature' or
`:companion-feature'.  `:reload-on-refresh' is useful for a companion that
must reload evaluated application behavior.  Registration
belongs in an example companion, not in the framework, and is optional when
the default `etaf-NAME-root' and `etaf-NAME' conventions are used."
  (unless (stringp name)
    (error "ETAF Playground example name must be a string: %S" name))
  (let ((root (or (plist-get options :root)
                  (plist-get options :root-component)))
        (feature (or (plist-get options :feature)
                     (plist-get options :companion-feature)))
        (reload-on-refresh (plist-get options :reload-on-refresh)))
    (when (and root (not (or (symbolp root) (functionp root))))
      (error "Invalid ETAF Playground root factory: %S" root))
    (when (and feature (not (symbolp feature)))
      (error "Invalid ETAF Playground companion feature: %S" feature))
    (puthash name (list :root-component root
                        :companion-feature feature
                        :reload-on-refresh reload-on-refresh)
             etaf-playground--registrations)
    name))

(defun etaf-playground--default-root-symbol (name)
  "Return the conventional root factory symbol for NAME."
  (intern (format "etaf-%s-root" name)))

(defun etaf-playground--default-feature-symbol (name)
  "Return the conventional companion feature symbol for NAME."
  (intern (format "etaf-%s" name)))

(defun etaf-playground--example-spec (name directory)
  "Build a generic file specification for NAME in DIRECTORY."
  (let* ((registration (gethash name etaf-playground--registrations))
         (etaf-file (expand-file-name (concat name ".etaf") directory))
         (el-file (expand-file-name (concat name ".el") directory))
         (ecss-file (expand-file-name (concat name ".ecss") directory)))
    (list :pair name
          :directory directory
          :etaf-file etaf-file
          :el-file el-file
          :ecss-file (and (file-readable-p ecss-file) ecss-file)
          :root-component (or (plist-get registration :root-component)
                              (etaf-playground--default-root-symbol name))
          :companion-feature
          (or (plist-get registration :companion-feature)
              (etaf-playground--default-feature-symbol name)))))

(defun etaf-playground-refresh-examples (&optional directory)
  "Discover valid `.etaf'/`.el' pairs in DIRECTORY.

An `.ecss' file is optional so an application can start with structure and
behavior only; when present it is included in the source tabs and passed to
the root factory."
  (let* ((directory (file-name-as-directory
                     (expand-file-name
                      (or directory etaf-playground-example-directory))))
         (names
          (when (file-directory-p directory)
            (cl-loop for file in (directory-files directory nil "\\.etaf\\'")
                     for name = (file-name-sans-extension file)
                     for el-file = (expand-file-name (concat name ".el") directory)
                     when (file-readable-p el-file)
                     collect name)))
         (specs (mapcar (lambda (name)
                          (etaf-playground--example-spec name directory))
                        (sort (delete-dups names) #'string<))))
    (setq etaf-playground-scenario-manifest specs
          etaf-playground-example-names (mapcar (lambda (spec)
                                                  (plist-get spec :pair))
                                                specs))
    (when (or (null etaf-playground-default-pair)
              (not (member etaf-playground-default-pair
                           etaf-playground-example-names)))
      (setq etaf-playground-default-pair
            (car etaf-playground-example-names)))
    etaf-playground-scenario-manifest))

(defun etaf-playground-scenario (name)
  "Return the discovered generic specification for NAME."
  (etaf-playground-refresh-examples)
  (or (cl-find name etaf-playground-scenario-manifest
               :key (lambda (spec) (plist-get spec :pair))
               :test #'equal)
      (user-error "Unknown ETAF Playground example: %s" name)))

(defun etaf-playground--pair-file (name suffix)
  "Return NAME's same-basename file ending in SUFFIX."
  (expand-file-name (concat name suffix)
                    (plist-get (etaf-playground-scenario name) :directory)))

(defun etaf-playground-example-files (name)
  "Return the source file plist for NAME."
  (let ((spec (etaf-playground-scenario name)))
    (list :etaf (plist-get spec :etaf-file)
          :el (plist-get spec :el-file)
          :ecss (plist-get spec :ecss-file))))

;;; Static form helpers

(defun etaf-playground-static-child (form tag)
  "Return the first static FORM child whose tag is TAG.

FORM is the inert structure passed to an example root.  Keeping this lookup
in the authoring layer prevents every consumer from reimplementing the same
raw `cl-find-if' traversal while leaving business-specific interpretation in
the consumer."
  (cl-find-if (lambda (entry)
                (and (consp entry) (eq (car entry) tag)))
              (cdr form)))

(defun etaf-playground-static-value (form key &optional default)
  "Return KEY from static FORM, or DEFAULT when FORM omits it."
  (or (plist-get (cdr form) key) default))

;;; Inert source readers

(defconst etaf-playground--forbidden-static-heads
  '(apply call-process call-process-region byte-code eval
    funcall function lambda load load-file message progn require
    shell-command start-process start-process-shell-command subprocess
    symbol-function setq setf psetq psetf)
  "Elisp heads which must never appear as executable static source.")

(defun etaf-playground--forbidden-static-head-p (head)
  "Return non-nil when HEAD is not allowed in inert source data."
  (and (symbolp head)
       (or (memq head etaf-playground--forbidden-static-heads)
           (string-prefix-p "etaf--" (symbol-name head))
           (string-prefix-p "ebox--" (symbol-name head)))))

(defun etaf-playground--validate-static-node (node &optional _tags)
  "Validate inert structural/data NODE.

The optional second argument is retained for compatibility with the former
catalog-based reader; structural tags are intentionally not allowlisted.  A
generic Playground must accept an application's own tags while still
rejecting executable forms and private runtime heads."
  (cond
   ((or (null node) (stringp node) (numberp node) (characterp node)
        (symbolp node) (keywordp node))
    (when (and (symbolp node)
               (string-prefix-p "#" (symbol-name node)))
      (error "Invalid ETAF static symbol: %S" node))
    node)
   ((vectorp node)
    (mapc #'etaf-playground--validate-static-node node)
    node)
   ((consp node)
    (unless (proper-list-p node)
      (error "ETAF static source must contain proper lists: %S" node))
    (when (etaf-playground--forbidden-static-head-p (car node))
      (error "Executable or private ETAF static form: %S" node))
    (mapc #'etaf-playground--validate-static-node node)
    node)
   (t
    (error "Unsupported ETAF static value: %S" node))))

(defun etaf-playground--read-single-form (content label)
  "Read one inert Lisp form from CONTENT labelled LABEL."
  (with-temp-buffer
    (insert content)
    (goto-char (point-min))
    (let ((read-eval nil)
          form)
      (setq form
            (condition-case nil
                (read (current-buffer))
              (end-of-file
               (error "ETAF Playground %s source is empty" label))))
      (condition-case nil
          (progn
            (read (current-buffer))
            (error "ETAF Playground %s source contains multiple forms"
                   label))
        (end-of-file nil))
      form)))

(defun etaf-playground--source-buffer (session extension)
  "Return SESSION's live source buffer for EXTENSION."
  (cdr (assoc extension
             (and (etaf-playground-session-p session)
                  (etaf-playground-session-source-buffers session)))))

(defun etaf-playground--file-content (file session extension)
  "Return FILE content, preferring SESSION's unsaved EXTENSION buffer."
  (if-let ((buffer (etaf-playground--source-buffer session extension)))
      (with-current-buffer buffer
        (buffer-substring-no-properties (point-min) (point-max)))
    (with-temp-buffer
      (insert-file-contents file)
      (buffer-string))))

(defun etaf-playground-read-static (name &optional session)
  "Read and validate NAME's single inert `.etaf' form.

When SESSION is supplied, unsaved buffer content is authoritative."
  (let* ((spec (etaf-playground-scenario name))
         (file (plist-get spec :etaf-file))
         (form (etaf-playground--read-single-form
                (etaf-playground--file-content file session ".etaf")
                ".etaf")))
    (etaf-playground--validate-static-node form)
    form))

(defun etaf-playground--validate-ecss-form (form)
  "Validate a static ETAF/ECSS style FORM and return it."
  (unless (and (consp form) (eq (car form) 'styles))
    (error "ETAF Playground `.ecss' must start with (styles ...)"))
  (dolist (rule (cdr form))
    (unless (and (consp rule) (stringp (car rule))
                 (proper-list-p rule))
      (error "Invalid ETAF Playground ECSS rule: %S" rule))
    (let ((properties (cdr rule)))
      (unless (zerop (% (length properties) 2))
        (error "ECSS rule has an incomplete property pair: %S" rule))
      (while properties
        (let ((key (pop properties))
              (value (pop properties)))
          (unless (keywordp key)
            (error "ECSS properties must be keywords: %S" key))
          (etaf-playground--validate-static-node value)))))
  form)

(defun etaf-playground-read-ecss (name &optional session)
  "Read and validate NAME's optional `.ecss' style form.

When SESSION is supplied, its unsaved source is authoritative.  Missing or
blank style files produce an empty `(styles)' form, so structure and
behavior-only examples remain valid consumers of the same framework."
  (let* ((spec (etaf-playground-scenario name))
         (file (plist-get spec :ecss-file)))
    (if (not file)
        '(styles)
      (let ((content (string-trim
                      (etaf-playground--file-content file session ".ecss"))))
        (if (string-empty-p content)
            '(styles)
          (etaf-playground--validate-ecss-form
           (etaf-playground--read-single-form content ".ecss")))))))

;;; Pair loading and mounting

(defun etaf-playground--registration (name)
  "Return companion registration for NAME, if any."
  (gethash name etaf-playground--registrations))

(defun etaf-playground--load-companion (spec &optional session)
  "Evaluate or load SPEC's `.el' companion.

An open source buffer is evaluated so unsaved editor changes participate in
the next preview refresh.  A direct mount without SESSION loads the file from
disk."
  (let* ((file (plist-get spec :el-file))
         (registration (etaf-playground--registration
                       (plist-get spec :pair)))
         (feature (or (plist-get registration :companion-feature)
                      (plist-get spec :companion-feature)))
         (buffer (and session
                      (etaf-playground--source-buffer session ".el"))))
    (let ((reload-buffer-p
           (and (buffer-live-p buffer)
                (or (buffer-modified-p buffer)
                    (etaf-playground-session-companion-dirty-p session)
                    (plist-get registration :reload-on-refresh))))
          (loaded-p (and (symbolp feature) (featurep feature))))
      (if reload-buffer-p
          (with-current-buffer buffer
            (save-restriction
              (widen)
              (etaf-component-redefine-run
               (lambda () (eval-buffer nil))))
            (setf (etaf-playground-session-companion-dirty-p session) nil)
            (setq-local etaf-playground-companion-dirty-p nil))
        (unless loaded-p
          (load (file-name-sans-extension file) nil nil nil))))
    spec))

(defun etaf-playground--root-factory (spec)
  "Return the loaded root factory for SPEC."
  (let* ((name (plist-get spec :pair))
         (registration (etaf-playground--registration name))
         (root (or (plist-get registration :root-component)
                   (plist-get spec :root-component))))
    (when (and (symbolp root) (not (fboundp root)))
      (error "Missing ETAF Playground root factory: %S" root))
    (unless (or (functionp root) (and (symbolp root) (fboundp root)))
      (error "Invalid ETAF Playground root factory: %S" root))
    root))

(defun etaf-playground--call-root (root name static-form ecss-form)
  "Call ROOT with NAME's STATIC-FORM and optional ECSS-FORM.

One-argument roots remain supported for small existing examples."
  (let ((etaf-playground--current-example name)
        (etaf-playground--current-static-form static-form)
        (etaf-playground--current-ecss ecss-form))
    (condition-case _err
        (funcall root static-form ecss-form)
      (wrong-number-of-arguments
       (funcall root static-form)))))

(defun etaf-playground-read-pair (name &optional session)
  "Load NAME's companion and return its root View value.

When SESSION is supplied, its current source buffers are authoritative.  The
`.etaf' and `.ecss' files are read as inert data.  The `.el' companion is the
only file evaluated by the framework."
  (let* ((spec (etaf-playground-scenario name))
         (static-form (etaf-playground-read-static name session))
         (ecss-form (etaf-playground-read-ecss name session)))
    (etaf-playground--load-companion spec session)
    (etaf-playground--call-root
     (etaf-playground--root-factory spec)
     name static-form ecss-form)))

(defun etaf-playground--preview-mode-setup (buffer session)
  "Prepare generated preview BUFFER for SESSION."
  (with-current-buffer buffer
    (unless (derived-mode-p 'etaf-playground-preview-mode)
      (etaf-playground-preview-mode))
    (setq-local etaf-playground-session session
                etaf-playground-current-example
                (etaf-playground-session-name session)
                etaf-playground-preview-p t
                header-line-format
                (format " ETAF Preview  %s  |  g refresh  q close"
                        (etaf-playground-session-name session)))
    (buffer-disable-undo)
    (setq-local truncate-lines nil))
  buffer)

(defun etaf-playground-mount-example
    (buffer-name name &optional session mount-options)
  "Mount example NAME into BUFFER-NAME and return its buffer.

This is the low-level consumer API.  `etaf-playground-open-example' adds the
source editors and side-by-side workspace around it.  MOUNT-OPTIONS is
forwarded to `etaf-mount', including an optional initial viewport."
  (let ((buffer (get-buffer-create buffer-name)))
    (when-let ((runtime (etaf-runtime-for-buffer buffer)))
      (with-current-buffer buffer
        (etaf-unmount runtime)))
    ;; Root factories and lifecycle callbacks are application code.  Run them
    ;; with the preview selected so a consumer using `face-remap' or another
    ;; buffer-local display API cannot accidentally style the source editor
    ;; which invoked `etaf-playground-refresh'.
    (with-current-buffer buffer
      (etaf-mount buffer (etaf-playground-read-pair name session)
                  mount-options))
    (with-current-buffer buffer
      (setq-local etaf-playground-current-example name))
    buffer))

(defun etaf-playground--render-error (session error-data)
  "Show ERROR-DATA in SESSION's preview buffer after a failed refresh."
  (let ((buffer (etaf-playground-session-preview-buffer session)))
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (let ((inhibit-read-only t))
          (erase-buffer)
          (insert (format "ETAF Playground could not render %s.\n\n%s\n"
                          (etaf-playground-session-name session)
                          (error-message-string error-data))))
        (setq-local buffer-read-only t)
        (setq-local header-line-format
                    (format " ETAF Preview  %s  |  ERROR  |  g retry  q close"
                            (etaf-playground-session-name session)))))))

(defun etaf-playground--refresh-session (session)
  "Refresh the single mounted preview owned by SESSION."
  (let ((preview (etaf-playground-session-preview-buffer session)))
    (condition-case err
        (progn
          (when-let ((runtime (etaf-runtime-for-buffer preview)))
            (with-current-buffer preview
              (etaf-unmount runtime)))
          (with-current-buffer preview
            (setq-local buffer-read-only nil))
          (etaf-playground-mount-example
           preview (etaf-playground-session-name session) session)
          (with-current-buffer preview
            (setq-local buffer-read-only t
                        header-line-format
                        (format " ETAF Preview  %s  |  g refresh  q close"
                                (etaf-playground-session-name session))))
          (force-mode-line-update t)
          preview)
      ((error quit)
       (etaf-playground--render-error session err)
       nil))))

(defun etaf-playground-refresh (&optional target)
  "Refresh the preview associated with TARGET or the current source buffer.

The current contents of all three source buffers are read on each refresh;
the companion `.el' is evaluated, the old runtime is unmounted, and the root
is mounted again from the Playground's perspective.  Errors stay visible in
the preview instead of destroying the source workspace."
  (interactive)
  (let ((session (etaf-playground--session-for-target target)))
    (if session
        (etaf-playground--refresh-session session)
      ;; Make `C-c C-c' useful when the user opened a source file directly.
      ;; `etaf-playground-open-example' creates, displays, and refreshes the
      ;; session once, so this outer entry only returns its mounted preview.
      (let* ((source (cond ((bufferp target) target)
                           ((and (stringp target) (get-buffer target))
                            (get-buffer target))
                           (t (current-buffer))))
             (name (etaf-playground--source-example-name source)))
        (unless name
          (user-error
           "No ETAF Playground workspace is associated with this buffer"))
        (etaf-playground-open-example name)
        (setq session (etaf-playground--session-for-target name))
        (and session (etaf-playground-session-preview-buffer session))))))

;;; Source modes and navigation

(defvar etaf-playground--tab-map
  (let ((map (make-sparse-keymap)))
    (define-key map [mouse-1] #'etaf-playground-click-source-tab)
    map)
  "Mouse map used by source tabs in the header line.")

(defvar etaf-playground-source-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-c") #'etaf-playground-refresh)
    (define-key map (kbd "C-c C-1") #'etaf-playground-show-etaf)
    (define-key map (kbd "C-c C-2") #'etaf-playground-show-el)
    (define-key map (kbd "C-c C-3") #'etaf-playground-show-ecss)
    (define-key map (kbd "C-c 1") #'etaf-playground-show-etaf)
    (define-key map (kbd "C-c 2") #'etaf-playground-show-el)
    (define-key map (kbd "C-c 3") #'etaf-playground-show-ecss)
    (define-key map (kbd "C-c C-n") #'etaf-playground-next-source)
    (define-key map (kbd "C-c C-p") #'etaf-playground-previous-source)
    (define-key map (kbd "C-c C-r") #'etaf-playground-refresh)
    (define-key map (kbd "q") #'etaf-playground-close)
    map)
  "Keymap used by source buffers in a Playground workspace.")

(define-minor-mode etaf-playground-source-mode
  "Minor mode shared by ETAF, Elisp, and ECSS Playground source buffers."
  :lighter " ETAF-Play"
  :keymap etaf-playground-source-mode-map
  (if etaf-playground-source-mode
      (progn
        (add-hook 'after-save-functions
                  #'etaf-playground--after-save nil t)
        (add-hook 'after-change-functions
                  #'etaf-playground--after-source-change nil t)
        (setq-local truncate-lines nil)
        (setq-local header-line-format
                    '(:eval (etaf-playground--source-header))))
    (remove-hook 'after-save-functions
                 #'etaf-playground--after-save t)
    (remove-hook 'after-change-functions
                 #'etaf-playground--after-source-change t)))

(define-derived-mode etaf-playground-etaf-mode emacs-lisp-mode "ETAF"
  "Major mode for inert ETAF structural source files."
  (etaf-playground-source-mode 1))

(define-derived-mode etaf-playground-ecss-mode emacs-lisp-mode "ECSS"
  "Major mode for inert ETAF ECSS style source files."
  (etaf-playground-source-mode 1))

(define-derived-mode etaf-playground-preview-mode special-mode "ETAF-Preview"
  "Read-only major mode for a mounted ETAF Playground preview."
  (setq-local truncate-lines nil)
  (setq-local buffer-read-only nil)
  (setq-local mode-line-process nil))

(add-to-list 'auto-mode-alist '("\\.etaf\\'" . etaf-playground-etaf-mode))
(add-to-list 'auto-mode-alist '("\\.ecss\\'" . etaf-playground-ecss-mode))

(defun etaf-playground--source-header ()
  "Return the button-based source tab header for the current buffer."
  (let ((session etaf-playground-session))
    (if (not (etaf-playground-session-p session))
        " ETAF Source"
      (concat
       " ETAF Source  "
       (mapconcat
        (lambda (extension)
          (when-let ((buffer (etaf-playground--source-buffer
                              session extension)))
            (let* ((active (equal extension
                                  (etaf-playground-session-active-extension
                                   session)))
                   (label (upcase (string-remove-prefix "." extension)))
                   (text (format " %s%s " label
                                 (if (buffer-modified-p buffer) "*" ""))))
              (make-text-button
               text nil
               'action #'etaf-playground--activate-source-tab
               'follow-link t
               'button-data extension
               'etaf-playground-extension extension
               'face (if active 'mode-line-emphasis
                       'mode-line-inactive)
               'mouse-face 'mode-line-highlight
               'help-echo (format "Switch to %s" extension)))))
        etaf-playground-source-extensions
        " | ")
       "  C-c C-c refresh"))))

(defun etaf-playground--activate-source-tab (button)
  "Activate source tab BUTTON from a header-line text button."
  (let ((extension
         (or (and (stringp button)
                  (get-text-property 0 'etaf-playground-extension button))
             (and (fboundp 'button-get)
                  (ignore-errors
                    (button-get button 'etaf-playground-extension)))
             (and (fboundp 'button-get)
                  (ignore-errors (button-get button 'button-data))))))
    (when extension
      (etaf-playground-switch-source extension))))

(defun etaf-playground--refresh-source-headers (session)
  "Refresh source tab headers for SESSION."
  (dolist (entry (etaf-playground-session-source-buffers session))
    (when (buffer-live-p (cdr entry))
      (with-current-buffer (cdr entry)
        (setq header-line-format '(:eval (etaf-playground--source-header)))
        (force-mode-line-update t)))))

(defun etaf-playground-click-source-tab (event)
  "Switch to the source tab under mouse EVENT."
  (interactive "e")
  (let* ((start (event-start event))
         (window (posn-window start))
         (position (posn-point start)))
    (when (and (window-live-p window) (integer-or-marker-p position))
      (with-current-buffer (window-buffer window)
        (when-let ((extension
                    (get-text-property position
                                       'etaf-playground-extension)))
          (etaf-playground-switch-source extension))))))

(defun etaf-playground--session-for-target (&optional target)
  "Return live session for TARGET, current buffer, or selected workspace."
  (cond
   ((etaf-playground-session-p target) target)
   ((bufferp target)
    (buffer-local-value 'etaf-playground-session target))
   ((stringp target)
    (or (gethash target etaf-playground--sessions)
        (and (get-buffer target)
             (buffer-local-value 'etaf-playground-session
                                 (get-buffer target)))))
   ((etaf-playground-session-p etaf-playground-session)
    etaf-playground-session)
   (t
    (let ((buffer (window-buffer (selected-window))))
      (and (buffer-live-p buffer)
           (buffer-local-value 'etaf-playground-session buffer))))))

(defun etaf-playground--source-example-name (&optional buffer)
  "Return the discovered example name owning BUFFER's source file."
  (when-let ((file (buffer-file-name (or buffer (current-buffer)))))
    (let ((file (file-truename file)))
      (cl-loop for spec in etaf-playground-scenario-manifest
               for name = (plist-get spec :pair)
               for source-files =
               (delq nil (list (plist-get spec :etaf-file)
                               (plist-get spec :el-file)
                               (plist-get spec :ecss-file)))
               when (cl-some (lambda (source-file)
                              (equal file (file-truename source-file)))
                             source-files)
               return name))))

(defun etaf-playground--source-window (session)
  "Return the visible source window for SESSION, if any."
  (cl-find-if
   (lambda (window)
     (memq (window-buffer window)
           (mapcar #'cdr (etaf-playground-session-source-buffers session))))
   (window-list nil 'no-minibuf)))

(defun etaf-playground-switch-source (extension &optional target)
  "Show EXTENSION in the left source window for TARGET's session."
  (interactive
   (list (completing-read
          "Source: "
          (mapcar (lambda (extension)
                    (cons (upcase (string-remove-prefix "." extension))
                          extension))
                  etaf-playground-source-extensions)
          nil t)))
  (let* ((session (etaf-playground--session-for-target target))
         (buffer (and session (etaf-playground--source-buffer
                               session extension))))
    (unless (and session (buffer-live-p buffer))
      (user-error "No live ETAF Playground source %s" extension))
    (setf (etaf-playground-session-active-extension session) extension)
    (etaf-playground--refresh-source-headers session)
    (when-let ((window (etaf-playground--source-window session)))
      (set-window-buffer window buffer)
      (select-window window))
    buffer))

(defun etaf-playground-next-source (&optional target)
  "Switch to the next available source for TARGET's session."
  (interactive)
  (let* ((session (etaf-playground--session-for-target target))
         (extensions
          (cl-remove-if-not
           (lambda (extension)
             (and session (etaf-playground--source-buffer session extension)))
           etaf-playground-source-extensions))
         (current (and session
                       (cl-position
                        (etaf-playground-session-active-extension session)
                        extensions :test #'equal))))
    (unless (and session extensions) (user-error "No ETAF source session"))
    (etaf-playground-switch-source
     (nth (mod (1+ (or current -1)) (length extensions)) extensions)
     session)))

(defun etaf-playground-previous-source (&optional target)
  "Switch to the previous available source for TARGET's session."
  (interactive)
  (let* ((session (etaf-playground--session-for-target target))
         (extensions
          (cl-remove-if-not
           (lambda (extension)
             (and session (etaf-playground--source-buffer session extension)))
           etaf-playground-source-extensions))
         (current (and session
                       (cl-position
                        (etaf-playground-session-active-extension session)
                        extensions :test #'equal))))
    (unless (and session extensions) (user-error "No ETAF source session"))
    (etaf-playground-switch-source
     (nth (mod (1- (or current 0)) (length extensions)) extensions)
     session)))

(defun etaf-playground-show-etaf (&optional target)
  "Show the `.etaf' source for TARGET's session."
  (interactive)
  (etaf-playground-switch-source ".etaf" target))

(defun etaf-playground-show-el (&optional target)
  "Show the `.el' source for TARGET's session."
  (interactive)
  (etaf-playground-switch-source ".el" target))

(defun etaf-playground-show-ecss (&optional target)
  "Show the `.ecss' source for TARGET's session."
  (interactive)
  (etaf-playground-switch-source ".ecss" target))

(defun etaf-playground--after-save ()
  "Refresh the current session after saving a source buffer."
  (when etaf-playground-refresh-on-save
    (etaf-playground-refresh (current-buffer))))

(defun etaf-playground--after-source-change (_beg _end _old-length)
  "Mark a companion as needing reload after an editor change."
  (when (and (equal etaf-playground-source-extension ".el")
             (etaf-playground-session-p etaf-playground-session))
    (setq-local etaf-playground-companion-dirty-p t)
    (setf (etaf-playground-session-companion-dirty-p
           etaf-playground-session)
          t)))

;;; Workspace layout and public entry points

(defun etaf-playground--session-preview-name (name)
  "Return the generated preview buffer name for NAME."
  (format etaf-playground-preview-buffer-format name))

(defun etaf-playground--setup-source-buffer (session extension buffer)
  "Prepare BUFFER as SESSION's EXTENSION source editor."
  (with-current-buffer buffer
    (pcase extension
      (".etaf" (unless (derived-mode-p 'etaf-playground-etaf-mode)
                  (etaf-playground-etaf-mode)))
      (".ecss" (unless (derived-mode-p 'etaf-playground-ecss-mode)
                  (etaf-playground-ecss-mode)))
      (".el" (unless (derived-mode-p 'emacs-lisp-mode)
                (emacs-lisp-mode))))
    (setq-local etaf-playground-session session
                etaf-playground-source-extension extension
                etaf-playground-current-example
                (etaf-playground-session-name session)
                header-line-format '(:eval (etaf-playground--source-header)))
    (etaf-playground-source-mode 1))
  buffer)

(defun etaf-playground--make-session (name)
  "Create or reuse the source/preview session for NAME."
  (or (gethash name etaf-playground--sessions)
      (let* ((spec (etaf-playground-scenario name))
             (source-buffers nil)
             (owned nil))
        (dolist (extension etaf-playground-source-extensions)
          (let* ((file (pcase extension
                         (".etaf" (plist-get spec :etaf-file))
                         (".el" (plist-get spec :el-file))
                         (".ecss" (plist-get spec :ecss-file))))
                 (existing (and file (get-file-buffer file)))
                 (buffer (and file (or existing (find-file-noselect file)))))
            (when buffer
              (push (cons extension buffer) source-buffers)
              (unless existing (push buffer owned)))))
        (setq source-buffers (nreverse source-buffers))
        (let* ((session (etaf-playground--session-create
                         :name name :spec spec
                         :source-buffers source-buffers
                         :active-extension (caar source-buffers)
                         :owned-source-buffers owned))
               (preview (get-buffer-create
                         (etaf-playground--session-preview-name name))))
          (setf (etaf-playground-session-preview-buffer session) preview)
          (puthash name session etaf-playground--sessions)
          (dolist (entry source-buffers)
            (etaf-playground--setup-source-buffer
             session (car entry) (cdr entry)))
          (etaf-playground--preview-mode-setup preview session)
          session))))

(defun etaf-playground--show-session (session)
  "Display SESSION through standard `display-buffer' policy."
  (unless noninteractive
    (unless (etaf-playground-session-previous-window-configuration session)
      (setf (etaf-playground-session-previous-window-configuration session)
            (current-window-configuration)))
    (setf (etaf-playground-session-source-frame session) (selected-frame))
    (let* ((source (etaf-playground--source-buffer
                    session
                    (etaf-playground-session-active-extension session)))
           (preview (etaf-playground-session-preview-buffer session)))
      (switch-to-buffer source)
      (let ((window (display-buffer preview etaf-playground-display-action)))
        (unless (window-live-p window)
          (error "ETAF Playground display action did not return a live window"))
        (setf (etaf-playground-session-preview-window session) window)
        window))))

(defun etaf-playground--active-source-buffer (session)
  "Return SESSION's active source buffer."
  (etaf-playground--source-buffer
   session (etaf-playground-session-active-extension session)))

(defun etaf-playground-open-example (name &optional buffer-name)
  "Open example NAME as a source/preview workspace.

When BUFFER-NAME is supplied, retain the low-level direct-mount behavior for
batch tests and callers which do not need editor windows."
  (interactive
   (list (completing-read "ETAF example: "
                         (progn (etaf-playground-refresh-examples)
                                etaf-playground-example-names)
                         nil t)))
  (if buffer-name
      (etaf-playground--mount-for-display buffer-name name)
    (let ((session (etaf-playground--make-session name)))
      (etaf-playground--show-session session)
      (etaf-playground-refresh session)
      (etaf-playground--refresh-source-headers session)
      (etaf-playground--active-source-buffer session))))

(defun etaf-playground--mount-for-display (buffer-name name)
  "Display BUFFER-NAME before mounting NAME in its containing window."
  (unless noninteractive
    (switch-to-buffer (get-buffer-create buffer-name)))
  (etaf-playground-mount-example buffer-name name))

;;;###autoload
(defun etaf-playground-open (&optional target)
  "Open the default or selected generic ETAF Playground.

With a known example name, TARGET selects that workspace.  A target beginning
with `*' is treated as a legacy direct preview buffer name and mounts the
default example there."
  (interactive)
  (etaf-playground-refresh-examples)
  (cond
   ((null target)
    (etaf-playground-open-example etaf-playground-default-pair))
   ((member target etaf-playground-example-names)
    (etaf-playground-open-example target))
   ((string-match-p "\\`[[:space:]]*\\*" target)
    (etaf-playground--mount-for-display
     target etaf-playground-default-pair))
   (t
    (user-error "Unknown ETAF Playground target: %s" target))))

;;;###autoload
(defun etaf-playground-reset (&optional target)
  "Refresh TARGET's workspace or remount its direct preview."
  (interactive)
  (if-let ((session (etaf-playground--session-for-target target)))
      (etaf-playground-refresh session)
    (let* ((buffer (cond ((bufferp target) target)
                         ((stringp target) (get-buffer target))
                         (t (current-buffer))))
           (name (and (buffer-live-p buffer)
                      (buffer-local-value 'etaf-playground-current-example
                                          buffer))))
      (unless (and buffer name)
        (user-error "No ETAF Playground session is mounted"))
      (etaf-playground-mount-example (buffer-name buffer) name))))

;;;###autoload
(defun etaf-playground-close (&optional target)
  "Close TARGET's workspace, or unmount and kill a direct preview buffer."
  (interactive)
  (if-let ((session (etaf-playground--session-for-target target)))
      (let* ((preview (etaf-playground-session-preview-buffer session))
             (preview-window
              (etaf-playground-session-preview-window session))
             (source-frame
              (etaf-playground-session-source-frame session))
             (preview-frame
              (and (window-live-p preview-window)
                   (window-frame preview-window)))
             (configuration
              (etaf-playground-session-previous-window-configuration session)))
        (when-let ((runtime (and (buffer-live-p preview)
                                 (etaf-runtime-for-buffer preview))))
          (with-current-buffer preview
            (etaf-unmount runtime)))
        (remhash (etaf-playground-session-name session)
                 etaf-playground--sessions)
        (dolist (entry (etaf-playground-session-source-buffers session))
          (when (buffer-live-p (cdr entry))
            (with-current-buffer (cdr entry)
              (setq-local etaf-playground-session nil
                          etaf-playground-source-extension nil))))
        (dolist (buffer (etaf-playground-session-owned-source-buffers session))
          (when (buffer-live-p buffer) (kill-buffer buffer)))
        (when (window-live-p preview-window)
          (if (and (frame-live-p preview-frame)
                   (frame-live-p source-frame)
                   (not (eq preview-frame source-frame))
                   (= (length (window-list preview-frame 'no-minibuf)) 1))
              (delete-frame preview-frame)
            (quit-window nil preview-window)))
        (when (buffer-live-p preview)
          (kill-buffer preview))
        (when (and configuration (window-configuration-p configuration))
          (set-window-configuration configuration))
        session)
    (let* ((buffer (cond ((bufferp target) target)
                         ((and (stringp target) (get-buffer target))
                          (get-buffer target))
                         ((null target) (current-buffer))))
           (runtime (and (buffer-live-p buffer)
                         (etaf-runtime-for-buffer buffer))))
      (when runtime
        (with-current-buffer buffer
          (etaf-unmount runtime)))
      (when (buffer-live-p buffer) (kill-buffer buffer))
      buffer)))

(etaf-playground-refresh-examples)

(provide 'etaf-playground)
;;; etaf-playground.el ends here
