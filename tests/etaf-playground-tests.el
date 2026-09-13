;;; etaf-playground-tests.el --- Research Shelf pair contract -*- lexical-binding: t; -*-

;;; Commentary:
;; These tests exercise the generic pair boundary and one real application.
;; The framework tests never reach into the application's model; application
;; tests drive only public refs/events and observe the rendered surface.

;;; Code:
(require 'cl-lib)
(require 'ert)
(require 'package)
(require 'etaf-playground)
(require 'etaf)

(defconst etaf-playground-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Absolute ETAF Playground repository path used by subprocess gates.")

(defun etaf-playground-test--package-description (file)
  "Return the package description parsed from FILE."
  (with-temp-buffer
    (insert-file-contents file)
    (package-buffer-info)))

(defun etaf-playground-test--ensure-app-loaded ()
  "Load the same-basename Research Shelf companion for test setup."
  (unless (featurep 'etaf-research-shelf)
    (load-file (expand-file-name "examples/research-shelf.el"
                                default-directory))))

(ert-deftest etaf-playground-etaf-source-mode-clean-loads-without-runtime ()
  "Opening research-shelf.etaf must not eagerly load ETAF or TP."
  (let ((output (generate-new-buffer " *etaf-source-mode-clean-load*"))
        (program (expand-file-name invocation-name invocation-directory))
        (package-file
         (expand-file-name "etaf-playground.el" etaf-playground-test--root))
        (source-file
         (expand-file-name "examples/research-shelf.etaf"
                           etaf-playground-test--root)))
    (unwind-protect
        (let ((status
               (call-process
                program nil output nil "-Q" "--batch"
                "-L" etaf-playground-test--root
                "-l" package-file
                "--eval"
                (format
                 "(progn (find-file %S) (unless (eq major-mode 'etaf-playground-etaf-mode) (kill-emacs 11)) (when (featurep 'etaf) (kill-emacs 12)) (when (featurep 'tp) (kill-emacs 13)) (when (featurep 'tp-transaction) (kill-emacs 14)) (princ \"ETAF source mode clean-load OK\\n\"))"
                 source-file))))
          (unless (zerop status)
            (ert-fail
             (with-current-buffer output (buffer-string))))
          (with-current-buffer output
            (should (string-match-p "ETAF source mode clean-load OK"
                                    (buffer-string)))))
      (when (buffer-live-p output) (kill-buffer output)))))

(ert-deftest etaf-playground-package-closure-requires-transaction-tp ()
  "Package metadata must reject TP snapshots without tp-transaction.el."
  (let* ((workspace (file-name-directory
                     (directory-file-name etaf-playground-test--root)))
         (tp (etaf-playground-test--package-description
              (expand-file-name "tp/tp.el" workspace)))
         (ebox (etaf-playground-test--package-description
                (expand-file-name "ebox/ebox.el" workspace)))
         (etaf (etaf-playground-test--package-description
                (expand-file-name "etaf/etaf.el" workspace)))
         (playground (etaf-playground-test--package-description
                      (expand-file-name
                       "etaf-playground/etaf-playground.el" workspace))))
    (should (equal (package-desc-version tp) '(2 0 0)))
    (should (equal (package-desc-version ebox) '(3 0 0)))
    (should (member '(tp (1 0 1)) (package-desc-reqs ebox)))
    (should (equal (package-desc-version etaf) '(0 2 1)))
    (should (member '(ebox (3 0 0)) (package-desc-reqs etaf)))
    (should (member '(tp (2 0 0)) (package-desc-reqs etaf)))
    (should (equal (package-desc-version playground) '(0 2 2)))
    (should (member '(etaf (0 2 1)) (package-desc-reqs playground)))
    (should (member '(etaf-ui (0 1 0))
                    (package-desc-reqs playground)))
    (should (member '(etaf-sqlite (0 1 0))
                    (package-desc-reqs playground)))))

(ert-deftest etaf-playground-stale-tp-error-is-actionable ()
  "A stale TP install reports its required package instead of file-missing."
  (let ((original-require (symbol-function 'require)))
    (cl-letf (((symbol-function 'require)
               (lambda (feature &optional filename noerror)
                 (if (eq feature 'etaf)
                     (signal 'file-missing
                             '("Cannot open load file"
                               "No such file or directory"
                               "tp-transaction"))
                   (funcall original-require feature filename noerror)))))
      (let ((condition
             (should-error (etaf-playground--ensure-runtime)
                           :type 'etaf-playground-dependency-error)))
        (should (equal (plist-get (cdr condition) :required-package)
                       '(tp "2.0.0")))
        (should (eq (plist-get (cdr condition) :missing-feature)
                    'tp-transaction))))))

(ert-deftest etaf-playground-unrelated-file-missing-is-preserved ()
  "Runtime loading must not relabel an unrelated missing dependency as TP."
  (let ((original-require (symbol-function 'require))
        (injected
         '(file-missing "Cannot open load file"
                        "No such file or directory"
                        "unrelated-feature")))
    (cl-letf (((symbol-function 'require)
               (lambda (feature &optional filename noerror)
                 (if (eq feature 'etaf)
                     (signal (car injected) (cdr injected))
                   (funcall original-require feature filename noerror)))))
      (should (equal (should-error (etaf-playground--ensure-runtime)
                                   :type 'file-missing)
                     injected)))))

(ert-deftest etaf-playground-preview-suppresses-editor-redisplay-artifacts ()
  "Generated previews hide wrapping indicators that appear as edge blocks."
  (let ((buffer (generate-new-buffer " *etaf-preview-display-settings*"))
        (session (etaf-playground--session-create :name "display-settings")))
    (unwind-protect
        (progn
          (with-current-buffer buffer
            (etaf-playground-preview-mode)
            ;; Reused preview buffers may have settings changed by a caller;
            ;; session setup must restore the generated-canvas contract.
            (setq-local truncate-lines nil
                        auto-hscroll-mode nil
                        fringe-indicator-alist
                        '((truncation left-arrow right-arrow)
                          (continuation left-curly-arrow right-curly-arrow))
                        bidi-display-reordering t
                        bidi-paragraph-direction nil
                        bidi-inhibit-bpa nil))
          (etaf-playground--preview-mode-setup buffer session)
          (cl-letf (((symbol-function 'etaf-runtime-for-buffer)
                     (lambda (_buffer) nil))
                    ((symbol-function 'etaf-playground-read-pair)
                     (lambda (&rest _arguments) 'preview-view))
                    ((symbol-function 'etaf-mount)
                     (lambda (&rest _arguments)
                       ;; Model renderer publication restoring ordinary editor
                       ;; defaults after the preview mode was initialized.
                       (setq-local truncate-lines nil
                                   auto-hscroll-mode nil
                                   fringe-indicator-alist
                                   '((truncation left-arrow right-arrow)
                                     (continuation
                                      left-curly-arrow right-curly-arrow))
                                   bidi-display-reordering t
                                   bidi-paragraph-direction nil
                                   bidi-inhibit-bpa nil))))
            (etaf-playground--mount-example-now
             buffer "display-settings" session nil))
          (with-current-buffer buffer
            (should truncate-lines)
            (should auto-hscroll-mode)
            (should-not (assq 'truncation fringe-indicator-alist))
            (should-not (assq 'continuation fringe-indicator-alist))
            (should-not bidi-display-reordering)
            (should (eq bidi-paragraph-direction 'left-to-right))
            (should bidi-inhibit-bpa)))
      (when (buffer-live-p buffer) (kill-buffer buffer)))))

(defun etaf-playground-test--text (buffer)
  "Return BUFFER's plain rendered text."
  (with-current-buffer buffer
    (substring-no-properties (buffer-string))))

(defun etaf-playground-test--row-refs (runtime)
  "Return RUNTIME's visible Research Shelf row refs in stable order."
  (sort
   (delq nil
         (mapcar
          (lambda (entry)
            (let ((ref (car entry)))
              (and (symbolp ref)
                   (string-prefix-p "research-shelf-row-"
                                    (symbol-name ref))
                   ref)))
          (etaf-runtime-handler-entries runtime)))
   (lambda (left right)
     (string< (symbol-name left) (symbol-name right)))))

(defun etaf-playground-test--close (buffer)
  "Close BUFFER when it exists."
  (when (gethash "research-shelf" etaf-playground--sessions)
    (etaf-playground-close "research-shelf"))
  (when (get-buffer buffer)
    (etaf-playground-close buffer)))

(defmacro etaf-playground-test--with-app (variables &rest body)
  "Run BODY with VARIABLES.
VARIABLES is a `(BUFFER DATABASE)' list; the macro creates a temporary SQLite
database and mounts a test buffer before running BODY."
  (declare (indent 1))
  (let ((buffer (car variables))
        (database (cadr variables)))
    (unless (and (symbolp buffer) (symbolp database))
      (error "Expected (BUFFER DATABASE) variables, got %S" variables))
    `(let* ((,database (make-temp-file "etaf-research-shelf-" nil ".sqlite"))
            (,buffer " *etaf-research-shelf-test*"))
       (ignore ,database)
       (etaf-playground-test--ensure-app-loaded)
     (unwind-protect
         (let ((etaf-research-shelf-database-file ,database)
               (etaf-research-shelf-fixture-size 8)
               (etaf-research-shelf-page-size 4))
             (ignore etaf-research-shelf-fixture-size
                     etaf-research-shelf-page-size)
             (ignore etaf-research-shelf-database-file)
             ,@body)
         (etaf-playground-test--close ,buffer)
         (when (file-exists-p ,database)
           (delete-file ,database))))))

(defun etaf-playground-test--open (buffer)
  "Mount Research Shelf in BUFFER with a deterministic headless viewport.

Text assertions should not depend on whether batch Ebox has a selected
window.  GUI verification exercises responsive geometry separately on a real
frame."
  (etaf-playground-mount-example
   buffer "research-shelf" nil '(:viewport-width 1400 :viewport-height 80)))

(ert-deftest etaf-playground-framework-discovers-generic-file-triplets ()
  "Discover examples from files without a business catalog in the framework."
  (should (member "research-shelf" etaf-playground-example-names))
  (let ((entry (etaf-playground-scenario "research-shelf"))
        (framework (with-temp-buffer
                     (insert-file-contents "etaf-playground.el")
                     (buffer-string)))
        (makefile (with-temp-buffer
                    (insert-file-contents "Makefile")
                    (buffer-string)))
        (companion (with-temp-buffer
                     (insert-file-contents "examples/research-shelf.el")
                     (buffer-string))))
    (dolist (key '(:pair :directory :etaf-file :el-file :ecss-file
                   :root-component :companion-feature))
      (should (plist-member entry key)))
    (should (file-readable-p (plist-get entry :etaf-file)))
    (should (file-readable-p (plist-get entry :el-file)))
    (should (file-readable-p (plist-get entry :ecss-file)))
    (should (string-match-p "wildcard examples" makefile))
    (should-not (string-match-p "mindepth 2" makefile))
    (should-not (string-match-p "etaf-playground-catalog" framework))
    (should-not (string-match-p "research-shelf" framework))
    (should-not (string-match-p "operations-console" framework))
    (dolist (section '("DATA / SQLITE SOURCE"
                       "THEME / PALETTE CONTRACT"
                       "STATE / DATA CONTROLLER / ACTIONS"
                       "VIEW / COMPONENTS / COMPOSITION"
                       "ROOT / PLAYGROUND REGISTRATION"))
      (should (string-match-p (regexp-quote section) companion)))))

(ert-deftest etaf-playground-displays-before-responsive-mount ()
  "GUI entry points establish the containing window before Ebox mount."
  (let ((calls nil)
        (noninteractive nil))
    (cl-letf (((symbol-function 'switch-to-buffer)
               (lambda (buffer)
                 (push (list 'display (buffer-name buffer)) calls)
                 buffer))
              ((symbol-function 'etaf-playground-mount-example)
               (lambda (buffer name)
                 (push (list 'mount buffer name) calls)
                 buffer)))
      (etaf-playground--mount-for-display
       " *etaf-playground-display-order*" "research-shelf"))
    (should (equal '(display mount) (mapcar #'car (nreverse calls))))))

(ert-deftest etaf-playground-mount-owns-complete-render-burst ()
  "Source construction and ETAF mount share the host render transaction."
  (let ((buffer " *etaf-playground-burst-test*")
        (inside nil)
        calls)
    (unwind-protect
        (cl-letf (((symbol-function 'ebox-call-with-render-burst)
                   (lambda (function &rest arguments)
                     (push 'begin calls)
                     (setq inside t)
                     (unwind-protect
                         (prog1 (apply function arguments)
                           (push 'end calls))
                       (setq inside nil))))
                  ((symbol-function 'etaf-playground-read-pair)
                   (lambda (_name _session)
                     (should inside)
                     (push 'root calls)
                     'test-view))
                  ((symbol-function 'etaf-mount)
                   (lambda (target view options)
                     (should inside)
                     (should (equal view 'test-view))
                     (should (equal options '(:viewport-width 900)))
                     (push 'mount calls)
                     target)))
          (should (bufferp
                   (etaf-playground-mount-example
                    buffer "test" nil '(:viewport-width 900))))
          (should (equal '(begin root mount end) (nreverse calls))))
      (when (get-buffer buffer) (kill-buffer buffer)))))

(ert-deftest etaf-playground-compile-builds-the-dependency-graph ()
  "Integration builds must compile the framework's dependency graph first."
  (let ((makefile (with-temp-buffer
                    (insert-file-contents "Makefile")
                    (buffer-string))))
    (dolist (dependency '("$(MAKE) -C ../ecss compile"
                          "$(MAKE) -C ../tp compile"
                          "$(MAKE) -C ../ebox compile"
                          "$(MAKE) -C ../etaf compile"
                          "$(MAKE) -C ../etaf-ui compile"
                          "$(MAKE) -C ../etaf-db compile"))
      (should (string-match-p (regexp-quote dependency) makefile)))))

(ert-deftest etaf-playground-performance-gate-runs-before-regressions ()
  "Repeatable exclusive latency gates run before CPU-heavy regressions."
  (let* ((makefile (with-temp-buffer
                     (insert-file-contents "Makefile")
                     (buffer-string)))
         (target (string-match "^perf-check:" makefile))
         (repeatability
          (and target
               (string-match "$(MAKE) perf-repeatability " makefile target)))
         (regressions (and target
                           (string-match "perf-regressions" makefile target))))
    (should target)
    (should repeatability)
    (should regressions)
    (should (< repeatability regressions))
    (should (string-match-p "^perf-prepare: compile" makefile))
    (should (string-match-p "^perf-evaluator:" makefile))
    (should (string-match-p "^perf-repeatability: perf-prepare" makefile))
    (should (string-match-p "scripts/with-performance-lock.sh" makefile))
    (let* ((start (string-match "^perf-repeatability:" makefile))
           (end (string-match "^# Run package regressions" makefile start))
           (body (substring makefile start end))
           (offset 0)
           (count 0))
      (while (string-match "$(MAKE) perf-evaluator" body offset)
        (setq count (1+ count)
              offset (match-end 0)))
      (should (= count 3)))))

(ert-deftest etaf-playground-performance-lock-is-exclusive-and-stale-safe ()
  "The evaluator wrapper serializes runs and clears stale owner locks."
  (let ((script (with-temp-buffer
                  (insert-file-contents "scripts/with-performance-lock.sh")
                  (buffer-string))))
    (dolist (contract '("mkdir \"$PERF_LOCK_DIR\""
                        "kill -0 \"$PERF_LOCK_OWNER\""
                        "rmdir \"$PERF_LOCK_DIR\""
                        "performance evaluator waiting for exclusive host slot"))
      (should (string-match-p (regexp-quote contract) script)))
    (should-not (string-match-p "rm -rf" script))))

(ert-deftest etaf-playground-static-reader-is-inert-and-strict ()
  "Read pair structure as inert data and reject executable AST nodes."
  (let* ((form (etaf-playground-read-static "research-shelf"))
         (tags (plist-get (etaf-playground-scenario "research-shelf")
                          :static-tags)))
    (should (equal (car form) 'research-shelf-shell))
    (should (equal (plist-get (cdr form) :title) "Research Shelf"))
    (should (equal (mapcar #'car
                           (cl-remove-if-not #'consp (cdr form)))
                   '(research-shelf-header-spec
                     research-shelf-filter-specs
                     research-shelf-content-spec
                     research-shelf-footer-spec)))
    (let* ((filters (cl-find-if
                     (lambda (entry) (and (consp entry)
                                          (eq (car entry)
                                              'research-shelf-filter-specs)))
                     (cdr form)))
           (all-filter (cl-find-if
                        (lambda (entry) (and (consp entry)
                                             (eq (car entry)
                                                 'research-shelf-filter-spec)
                                             (eq (plist-get (cdr entry) :key)
                                                 'all)))
                        (cdr filters))))
      (should all-filter))
    (dolist (unsafe '((lambda () 1) (eval '(message "x"))
                      (etaf--private) (ebox--private) (shell-command "x")))
      (should-error (etaf-playground--validate-static-node unsafe tags)
                    :type 'error))))

(ert-deftest etaf-playground-research-shelf-uses-runtime-named-slots ()
  "The companion composes the Shell through ETAF's public named-slot API."
  (let ((source (with-temp-buffer
                  (insert-file-contents "examples/research-shelf.el")
                  (buffer-string))))
    (dolist (slot '("header" "filters" "library" "detail" "footer"))
      (should (string-match-p
               (format "(slot :name '%s" slot)
               source)))
    (should (string-match-p
             "(etaf-define-component etaf-research-shelf-shell ()"
             source))
    (should (string-match-p
             "(etaf-define-component etaf-research-shelf-app"
             source))))

(ert-deftest etaf-playground-ecss-reader-is-inert-and-usable ()
  "Read the optional style companion as validated static Component styles."
  (let ((form (etaf-playground-read-ecss "research-shelf")))
    (should (equal 'styles (car form)))
    (should (= 6 (length (cdr form))))
    (dolist (rule (cdr form))
      (should (stringp (car rule)))
      (should (cl-every #'keywordp
                        (cl-loop for (key _value) on (cdr rule) by #'cddr
                                 collect key))))))

(ert-deftest etaf-playground-workspace-switches-three-source-buffers ()
  "One session switches `.etaf', `.el', and `.ecss' beside one preview."
  (etaf-playground-test--with-app (buffer database)
    (ignore buffer)
    (let ((etaf-research-shelf-database-file database)
          (source (etaf-playground-open-example "research-shelf")))
      (ignore etaf-research-shelf-database-file)
      (let* ((session (buffer-local-value 'etaf-playground-session source))
             (preview (etaf-playground-session-preview-buffer session)))
        (should (etaf-playground-session-p session))
        (should (= 3 (length (etaf-playground-session-source-buffers session))))
        (should (equal ".etaf"
                       (etaf-playground-session-active-extension session)))
        (should (etaf-runtime-p (etaf-runtime-for-buffer preview)))
        (etaf-playground-show-el source)
        (should (equal ".el"
                       (etaf-playground-session-active-extension session)))
        (etaf-playground-show-ecss source)
        (should (equal ".ecss"
                       (etaf-playground-session-active-extension session)))
        (should (equal (etaf-playground-read-ecss "research-shelf" session)
                       (etaf-component-styles 'etaf-research-shelf-shell)))))))

(ert-deftest etaf-playground-show-session-uses-display-buffer-action ()
  "Workspace display delegates preview placement to standard `display-buffer'."
  (let* ((source (get-buffer-create " *etaf-display-source*"))
         (preview (get-buffer-create " *etaf-display-preview*"))
         (session
          (etaf-playground--session-create
           :name "display-test"
           :source-buffers (list (cons ".etaf" source))
           :preview-buffer preview
           :active-extension ".etaf"))
         (action '((display-buffer-in-side-window)
                   (side . right)
                   (window-width . 0.4)))
         calls)
    (unwind-protect
        (let ((noninteractive nil)
              (etaf-playground-display-action action))
          (cl-letf (((symbol-function 'current-window-configuration)
                     (lambda () 'saved-window-configuration))
                    ((symbol-function 'switch-to-buffer)
                     (lambda (buffer)
                       (push (list 'source buffer) calls)
                       buffer))
                    ((symbol-function 'display-buffer)
                     (lambda (buffer supplied-action)
                       (push (list 'preview buffer supplied-action) calls)
                       (selected-window)))
                    ((symbol-function 'delete-other-windows)
                     (lambda (&rest _)
                       (ert-fail "Workspace must not delete user windows")))
                    ((symbol-function 'split-window-right)
                     (lambda (&rest _)
                       (ert-fail "Workspace must not split windows directly")))
                    ((symbol-function 'split-window-below)
                     (lambda (&rest _)
                       (ert-fail "Workspace must not split windows directly"))))
            (should (windowp (etaf-playground--show-session session))))
          (should
           (equal
            (list (list 'source source) (list 'preview preview action))
            (nreverse calls)))
          (should (eq (etaf-playground-session-preview-window session)
                      (selected-window))))
      (when (buffer-live-p source) (kill-buffer source))
      (when (buffer-live-p preview) (kill-buffer preview)))))

(ert-deftest etaf-playground-source-tabs-have-buttons-and-shortcuts ()
  "Source tabs work through both header buttons and keyboard shortcuts."
  (etaf-playground-test--with-app (buffer database)
    (ignore buffer)
    (let ((etaf-research-shelf-database-file database)
          (source (etaf-playground-open-example "research-shelf")))
      (ignore etaf-research-shelf-database-file)
      (with-current-buffer source
        (should (eq #'etaf-playground-refresh
                    (key-binding (kbd "C-c C-c"))))
        (should (eq #'etaf-playground-show-etaf
                    (key-binding (kbd "C-c 1"))))
        (should (eq #'etaf-playground-show-el
                    (key-binding (kbd "C-c 2"))))
        (should (eq #'etaf-playground-show-ecss
                    (key-binding (kbd "C-c 3"))))
        (call-interactively (key-binding (kbd "C-c C-c")))
        (should (etaf-runtime-p
                 (etaf-runtime-for-buffer
                  (etaf-playground-session-preview-buffer
                   etaf-playground-session))))
        (let* ((header (etaf-playground--source-header))
               (position (string-match " EL" header)))
          (should position)
          (should (get-text-property position 'button header))
          (should (equal ".el"
                         (get-text-property position 'button-data header)))
          (etaf-playground--activate-source-tab
           (propertize " EL " 'etaf-playground-extension ".el"))
          (should (equal ".el"
                         (etaf-playground-session-active-extension
                          etaf-playground-session)))
          (should-not (string-match-p "Compile App" header)))))))

(ert-deftest etaf-playground-direct-etaf-c-c-c-opens-workspace ()
  "The source render command opens a workspace for a directly opened `.etaf'."
  (etaf-playground-test--with-app (buffer database)
    (ignore buffer)
    (let* ((etaf-research-shelf-database-file database)
           (source (find-file-noselect
                    (expand-file-name "examples/research-shelf.etaf"
                                      default-directory))))
      (ignore etaf-research-shelf-database-file)
      (unwind-protect
          (let ((mount-count 0)
                (original-mount
                 (symbol-function 'etaf-playground-mount-example)))
            (cl-letf (((symbol-function 'etaf-playground-mount-example)
                       (lambda (&rest arguments)
                         (cl-incf mount-count)
                         (apply original-mount arguments))))
              (with-current-buffer source
                (should (eq #'etaf-playground-refresh
                            (key-binding (kbd "C-c C-c"))))
                (should (etaf-playground-refresh source))
                (let ((session
                       (buffer-local-value 'etaf-playground-session source)))
                  (should (etaf-playground-session-p session))
                  (should (etaf-runtime-p
                           (etaf-runtime-for-buffer
                            (etaf-playground-session-preview-buffer session)))))))
            (should (= mount-count 1)))
        (when (buffer-live-p source)
          (etaf-playground-close source))))))

(ert-deftest etaf-playground-does-not-remap-source-buffer ()
  "The Research Shelf surface does not remap the source editor buffer."
  (etaf-playground-test--with-app (buffer database)
    (ignore buffer)
    (let ((etaf-research-shelf-database-file database))
      (ignore etaf-research-shelf-database-file)
      (let* ((source (etaf-playground-open-example "research-shelf"))
             (session (buffer-local-value 'etaf-playground-session source))
             (preview (etaf-playground-session-preview-buffer session)))
        (should (null (buffer-local-value 'face-remapping-alist source)))
        (should (etaf-runtime-p (etaf-runtime-for-buffer preview)))))))

(ert-deftest etaf-playground-refresh-uses-unsaved-etaf-source ()
  "Refreshing a workspace reads the current source buffer, not disk only."
  (etaf-playground-test--with-app (buffer database)
    (ignore buffer)
    (let ((etaf-research-shelf-database-file database)
          (source (etaf-playground-open-example "research-shelf")))
      (ignore etaf-research-shelf-database-file)
      (with-current-buffer source
        (goto-char (point-min))
        (search-forward ":title \"Research Shelf\"")
        (replace-match ":title \"Research Shelf (edited)\"" t t)
        (set-buffer-modified-p t))
      (should (etaf-playground-refresh source))
      (let* ((session (buffer-local-value 'etaf-playground-session source))
             (preview (etaf-playground-session-preview-buffer session))
             (form (etaf-playground-read-static "research-shelf" session)))
        (should (equal "Research Shelf (edited)"
                       (plist-get (cdr form) :title)))
        (should (string-match-p "edited"
                                (etaf-playground-test--text preview)))))))

(ert-deftest etaf-playground-refresh-reloads-unsaved-el-companion ()
  "Refreshing a dirty `.el' companion redefines its consumer intentionally."
  (etaf-playground-test--with-app (buffer database)
    (ignore buffer)
    (let ((etaf-research-shelf-database-file database)
          (source (etaf-playground-open-example "research-shelf")))
      (ignore etaf-research-shelf-database-file)
      (let* ((session (buffer-local-value 'etaf-playground-session source))
             (el (etaf-playground--source-buffer session ".el")))
        (with-current-buffer el
          (goto-char (point-max))
          (insert "\n;; dirty companion reload sentinel\n")
          (set-buffer-modified-p t))
        (should (etaf-playground-refresh source))
        (should-not (etaf-playground-session-companion-dirty-p session))
        (should (etaf-runtime-p
                 (etaf-runtime-for-buffer
                  (etaf-playground-session-preview-buffer session))))))))

(ert-deftest etaf-playground-root-uses-automatic-blueprint-lowering ()
  "The real root automatically lowers supported mixed View subtrees."
  (etaf-playground-test--with-app (buffer database)
    (etaf-compiler-clear-cache)
    (let* ((before (etaf-compiler-statistics))
           (instantiations (plist-get before :instantiations))
           (cache-entries (plist-get before :static-cache-entries)))
      (etaf-playground-test--open buffer)
      (let* ((after (etaf-compiler-statistics))
             (blueprint (plist-get after :last-blueprint)))
        (should (> (plist-get after :instantiations) instantiations))
        (should (> (plist-get after :static-cache-entries) cache-entries))
        (should (> (plist-get blueprint :dynamic-nodes) 0))
        (should (> (plist-get blueprint :hole-count) 0))))))

(ert-deftest etaf-playground-pair-mounts-sqlite-backed-surface ()
  "Mounting the pair initializes SQLite and renders the real app shell."
  (etaf-playground-test--with-app (buffer database)
    (etaf-playground-test--open buffer)
    (should (etaf-runtime-p (etaf-runtime-for-buffer buffer)))
    (should (file-exists-p database))
    (let ((text (etaf-playground-test--text buffer))
          (runtime (etaf-runtime-for-buffer buffer)))
      (should (string-match-p "Research Shelf" text))
      (should (string-match-p "8 items · SQLite-backed" text))
      (should (string-match-p "The Shape of Tools" text))
      (dolist (ref '(research-shelf-filter-all research-shelf-filter-reading
                     research-shelf-filter-unread research-shelf-filter-finished
                     research-shelf-filter-starred research-shelf-reload
                     research-shelf-page-size research-shelf-add
                     research-shelf-page-next
                     research-shelf-theme-toggle))
        (should (etaf-runtime-handler-for runtime ref))))))

(ert-deftest etaf-playground-research-shelf-uses-window-document-height ()
  "Research Shelf fills the viewport without creating a root scroll owner."
  (etaf-playground-test--with-app (buffer database)
    (etaf-playground-mount-example
     buffer "research-shelf" nil
     '(:viewport-width 900 :viewport-height 40))
    (let* ((state (ebox--buffer-render-state (get-buffer buffer)))
           (root (plist-get state :root-node)))
      (should (equal (plist-get root :height) '(viewport-height)))
      (should (= (plist-get root :min-height) 0))
      (should-not (plist-get state :scroll-region-ids)))))

(ert-deftest etaf-playground-fixture-supports-realistic-page-counts ()
  "The Playground can mount a larger deterministic fixture for pressure runs."
  (etaf-playground-test--ensure-app-loaded)
  (let ((database (make-temp-file "etaf-research-shelf-large-" nil ".sqlite"))
        (buffer " *etaf-research-shelf-large-test*"))
    (unwind-protect
        (let ((etaf-research-shelf-database-file database)
              (etaf-research-shelf-fixture-size 32)
              (etaf-research-shelf-page-size 8))
          (ignore etaf-research-shelf-database-file
                  etaf-research-shelf-fixture-size
                  etaf-research-shelf-page-size)
          (etaf-playground-mount-example buffer "research-shelf")
          (let ((text (etaf-playground-test--text buffer)))
            (should (string-match-p "32 items · SQLite-backed" text))
            (should (string-match-p "Page 1 / 4" text)))
          (should (file-exists-p database)))
      (etaf-playground-test--close buffer)
      (when (file-exists-p database)
        (delete-file database)))))

(ert-deftest etaf-playground-row-selection-is-repeatable ()
  "Repeated DataGrid row presses replace one selected identity."
  (etaf-playground-test--with-app (buffer database)
    (etaf-playground-test--open buffer)
    (let ((runtime (etaf-runtime-for-buffer buffer)))
      (dolist (entry '((research-shelf-row-1 research-shelf-row-2
                        "The best tools make attention feel larger")
                       (research-shelf-row-2 research-shelf-row-1
                        "Look again at the relationship between image and power")
                       (research-shelf-row-1 research-shelf-row-2
                        "The best tools make attention feel larger")
                       (research-shelf-row-2 research-shelf-row-1
                        "Look again at the relationship between image and power")))
        (let ((selected (nth 0 entry))
              (other (nth 1 entry))
              (detail (nth 2 entry)))
          (should (etaf-runtime-handler-for runtime selected))
          (etaf-focus runtime selected)
          (etaf-dispatch-event runtime selected 'press)
          (let ((text (etaf-playground-test--text buffer)))
            (should (string-match-p (regexp-quote detail) text)))
          (should (string-match-p
                   "selected"
                   (or (plist-get
                        (etaf-runtime-host-props-for runtime selected)
                        :class)
                       "")))
          (should-not
           (string-match-p
            "selected"
            (or (plist-get (etaf-runtime-host-props-for runtime other)
                           :class)
                ""))))))))

(ert-deftest etaf-playground-row-observer-on-off-is-exact ()
  "Observation preserves one real row mutation and its retained identity."
  (etaf-playground-test--with-app (buffer database)
    (etaf-playground-test--open buffer)
    (let* ((runtime (etaf-runtime-for-buffer buffer))
           (surface
            (lambda ()
              (with-current-buffer buffer
                (buffer-substring (point-min) (point-max))))))
      ;; Materialize the same lazy TP paint contribution before either side of
      ;; the equivalence comparison.  The observer remains detached here.
      (etaf-dispatch-event runtime 'research-shelf-row-2 'press)
      (etaf-dispatch-event runtime 'research-shelf-row-1 'press)
      (let* ((generation-before (etaf-runtime-generation runtime))
           (result-off
            (etaf-dispatch-event runtime 'research-shelf-row-2 'press))
           (generation-off (etaf-runtime-generation runtime))
           (output-off (funcall surface)))
        (should (= 1 (- generation-off generation-before)))
        (should (string-match-p
                 "selected"
                 (or (plist-get
                      (etaf-runtime-host-props-for
                       runtime 'research-shelf-row-2)
                      :class)
                     "")))
        (etaf-dispatch-event runtime 'research-shelf-row-1 'press)
        (etaf-performance-clear)
        (etaf-performance-start runtime)
        (let* ((generation-before-on (etaf-runtime-generation runtime))
               (result-on
                (etaf-dispatch-event runtime 'research-shelf-row-2 'press))
               (generation-on (etaf-runtime-generation runtime))
               (output-on (funcall surface))
               (operation (car (etaf-performance-records)))
               (providers
                (mapcar #'etaf-performance-stage-provider
                        (etaf-performance-operation-stages operation))))
          (should (equal result-off result-on))
          (should (= (- generation-off generation-before)
                     (- generation-on generation-before-on)))
          (should (equal-including-properties output-off output-on))
          (should (equal providers '(tp ebox etaf)))
          (should (string-match-p
                   "selected"
                   (or (plist-get
                        (etaf-runtime-host-props-for
                         runtime 'research-shelf-row-2)
                        :class)
                       ""))))
        (etaf-performance-stop runtime)))))

(ert-deftest etaf-playground-filters-and-pagination-reload-data ()
  "Filter and pager refs drive the SQLite-backed Data Controller."
  (etaf-playground-test--with-app (buffer database)
    (etaf-playground-test--open buffer)
    (let ((runtime (etaf-runtime-for-buffer buffer)))
      ;; Move the selected identity through the old page first.  The following
      ;; filter reorders keyed Range items; generated cell Host addresses must
      ;; remain scoped by item key rather than inheriting their new position.
      (dolist (ref (etaf-playground-test--row-refs runtime))
        (etaf-dispatch-event runtime ref 'press))
      (etaf-dispatch-event runtime 'research-shelf-filter-reading 'press)
      (dolist (ref (etaf-playground-test--row-refs runtime))
        (etaf-dispatch-event runtime ref 'press))
      (let ((text (etaf-playground-test--text buffer)))
        (should (string-match-p "Showing Reading" text))
        (should (string-match-p "Designing for Calm" text))
        (should-not (string-match-p "Ways of Seeing" text)))
      (etaf-dispatch-event runtime 'research-shelf-filter-all 'press)
      (let ((page-one (etaf-playground-test--text buffer)))
        (should (string-match-p "The Shape of Tools" page-one))
        (should-not (string-match-p "The Craftsman" page-one)))
      (etaf-dispatch-event runtime 'research-shelf-page-next 'press)
      (let ((page-two (etaf-playground-test--text buffer)))
        (should (string-match-p "Page 2 / 2" page-two))
        (should (string-match-p "The Craftsman" page-two))
        (should-not (string-match-p "The Shape of Tools" page-two)))
      (etaf-dispatch-event runtime 'research-shelf-page-previous 'press)
      (let ((page-one-again (etaf-playground-test--text buffer)))
        (should (string-match-p "Page 1 / 2" page-one-again))
        (should (string-match-p "The Shape of Tools" page-one-again)))
      (cl-letf (((symbol-function 'read-number)
                 (lambda (&rest _) 6)))
        (etaf-dispatch-event runtime 'research-shelf-page-size 'press))
      (should (string-match-p "Rows 6 ✎"
                              (etaf-playground-test--text buffer)))
      (should (string-match-p "Page 1 / 2"
                              (etaf-playground-test--text buffer)))
      (cl-letf (((symbol-function 'read-number)
                 (lambda (&rest _) 0)))
        (should-error
         (etaf-dispatch-event runtime 'research-shelf-page-size 'press)
         :type 'user-error)))))

(ert-deftest etaf-playground-workspace-reflows-at-responsive-widths ()
  "Workspace cards share a row when wide and wrap in document order."
  (etaf-playground-test--with-app (buffer database)
    (etaf-playground-test--open buffer)
    (cl-labels
        ((line-of (label)
           (with-current-buffer buffer
             (save-excursion
               (goto-char (point-min))
               (search-forward label)
               (line-number-at-pos (match-beginning 0)))))
         (layout-at (width)
           (ebox-surface-update-buffer-viewport (get-buffer buffer) width 80)
           (list (line-of "Library")
                 (line-of "Reading queue")
                 (line-of "Selected item"))))
      (pcase-let ((`(,filter-line ,list-line ,detail-line)
                   (layout-at 1600)))
        ;; Different child Components may start their first text baseline one
        ;; line apart while still sharing the same wide Flex row.
        (should (<= (abs (- filter-line list-line)) 1))
        (should (<= (- detail-line list-line) 1)))
      (pcase-let ((`(,filter-line ,list-line ,detail-line)
                   (layout-at 900)))
        (should (<= (abs (- filter-line list-line)) 1))
        (should (> detail-line list-line)))
      (pcase-let ((`(,filter-line ,list-line ,detail-line)
                   (layout-at 600)))
        (should (< filter-line list-line))
        (should (< list-line detail-line))))))

(ert-deftest etaf-playground-mutations-persist-and-refresh ()
  "Add and mutate actions persist through the SQLite source and refresh UI."
  (etaf-playground-test--with-app (buffer database)
    (etaf-playground-test--open buffer)
    (let ((runtime (etaf-runtime-for-buffer buffer)))
      (etaf-dispatch-event runtime 'research-shelf-row-1 'press)
      (etaf-dispatch-event runtime 'research-shelf-progress 'press)
      (should (string-match-p "Progress saved"
                              (etaf-playground-test--text buffer)))
      (etaf-dispatch-event runtime 'research-shelf-star 'press)
      (should (string-match-p "Removed star"
                              (etaf-playground-test--text buffer)))
      (etaf-dispatch-event runtime 'research-shelf-archive 'press)
      (should (equal t
                     (plist-get
                      (etaf-runtime-host-props-for runtime
                                                   'research-shelf-finish)
                      :disabled)))
      (etaf-dispatch-event runtime 'research-shelf-add 'press)
      (should (string-match-p "Added to your shelf"
                              (etaf-playground-test--text buffer)))
      (should (file-exists-p database)))))

(ert-deftest etaf-playground-theme-and-lifecycle-are-repeatable ()
  "Theme changes and reset/close do not leave a stale mounted runtime."
  (etaf-playground-test--with-app (buffer database)
    (etaf-playground-test--open buffer)
    (let ((runtime (etaf-runtime-for-buffer buffer)))
      (etaf-dispatch-event runtime 'research-shelf-row-1 'press)
      (let (dark-output light-output)
        (dotimes (cycle 2)
          (etaf-dispatch-event runtime 'research-shelf-theme-toggle 'press)
          (with-current-buffer buffer
            (let ((output (buffer-substring (point-min) (point-max))))
              (if (zerop cycle)
                  (setq dark-output output)
                (should (equal-including-properties output dark-output)))))
        (etaf-dispatch-event runtime 'research-shelf-theme-toggle 'press)
          (with-current-buffer buffer
            (let ((output (buffer-substring (point-min) (point-max))))
              (if (zerop cycle)
                  (setq light-output output)
                (should (equal-including-properties output light-output)))))))
      (should (string-match-p "The Shape of Tools"
                              (etaf-playground-test--text buffer)))
      (should (or (string-match-p "☑ Dark"
                                  (etaf-playground-test--text buffer))
                  (string-match-p "☐ Dark"
                                  (etaf-playground-test--text buffer))))
      ;; Theme-only Host reconstruction must preserve nested Component
      ;; backend anchors for the next unrelated interaction.
      (let ((generation (etaf-runtime-generation runtime)))
        (etaf-dispatch-event runtime 'research-shelf-filter-reading 'press)
        (should (= (etaf-runtime-generation runtime) (1+ generation)))
        (should (eq runtime (etaf-runtime-for-buffer buffer)))))
    (etaf-playground-reset buffer)
    (should (etaf-runtime-p (etaf-runtime-for-buffer buffer))))
  (should-not (get-buffer " *etaf-research-shelf-test*")))

(provide 'etaf-playground-tests)
;;; etaf-playground-tests.el ends here
