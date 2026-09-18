;;; playground-gui-scenarios.el --- Playground GUI verifier adapters -*- lexical-binding: t; -*-

;;; Commentary:

;; Concrete Research Shelf and Ebox reference adapters for the generic
;; `emacs-gui-verifier' engine.  Process, recording, checkpoint ordering, and
;; evidence lifecycle remain outside this file.

;;; Code:

(require 'emacs-gui-verifier)
(require 'ebox-playground)
(require 'etaf-playground)
(require 'benchmark-research-shelf)
(require 'ebox)

(defvar etaf-research-shelf-database-file)
(defvar etaf-research-shelf-fixture-size)
(defvar etaf-research-shelf-page-size)

(defun etaf-playground-gui-scenarios--report (context)
  "Return CONTEXT target's public Ebox report, or nil before mount."
  (let ((buffer (etaf-gui-verifier-context-target-buffer context)))
    (when (and (buffer-live-p buffer)
               (ebox-surface-buffer-mounted-p buffer))
      (ebox-buffer-update-report buffer))))

(defun etaf-playground-gui-scenarios--visible-window-content-p (context)
  "Return non-nil when CONTEXT's selected window shows nonblank text."
  (let* ((buffer (etaf-gui-verifier-context-target-buffer context))
         (window (selected-window)))
    (and (buffer-live-p buffer)
         (window-live-p window)
         (eq (window-buffer window) buffer)
         (let ((start (window-start window))
               (end (window-end window t)))
           (and (integer-or-marker-p start)
                (integer-or-marker-p end)
                (< start end)
                (with-current-buffer buffer
                  (string-match-p
                   "[^[:space:]]"
                   (buffer-substring-no-properties start end))))))))

(defun etaf-playground-gui-scenarios--buffer-text (context)
  "Return CONTEXT target's complete plain buffer text."
  (let ((buffer (etaf-gui-verifier-context-target-buffer context)))
    (and (buffer-live-p buffer)
         (with-current-buffer buffer
           (buffer-substring-no-properties (point-min) (point-max))))))

(defun etaf-playground-gui-scenarios--mounted-settled-p (context)
  "Return non-nil when CONTEXT has a mounted, visibly rendered surface."
  (let ((buffer (etaf-gui-verifier-context-target-buffer context)))
    (and (buffer-live-p buffer)
         (ebox-surface-buffer-mounted-p buffer)
         (eq (frame-parameter nil 'fullscreen)
             (etaf-gui-verifier-context-get context 'target-fullscreen))
         (etaf-playground-gui-scenarios--visible-window-content-p context))))

(defun etaf-playground-gui-scenarios--begin-viewport-change
    (context fullscreen &optional width height)
  "Record CONTEXT state before targeting FULLSCREEN, WIDTH, and HEIGHT."
  (when (ebox-transaction-active-p)
    (error "Cannot observe committed viewport geometry inside a TP transaction"))
  (let* ((buffer (etaf-gui-verifier-context-target-buffer context))
         (revision (ebox-surface-buffer-revision buffer))
         (unchanged (and (eq (frame-parameter nil 'fullscreen) fullscreen)
                         (or (not (numberp width)) (= (frame-text-width) width))
                         (or (not (numberp height)) (= (frame-text-height) height)))))
    (etaf-gui-verifier-context-put
     context 'viewport-revision-before
     ;; A frame already at the requested geometry has no resize to publish.
     ;; Real geometry changes still require a new committed revision.
     (unless unchanged revision))
    (etaf-gui-verifier-context-put
     context 'viewport-noop-before
     (when unchanged
       (list :window (selected-window)
             :width (ebox-viewport-window-width (selected-window))
             :height (window-body-height (selected-window))
             :frame-width (frame-text-width) :frame-height (frame-text-height)
             :revision revision)))
    (etaf-gui-verifier-context-put context 'target-fullscreen fullscreen)
    (etaf-gui-verifier-context-put context 'target-frame-width width)
    (etaf-gui-verifier-context-put context 'target-frame-height height)))

(defun etaf-playground-gui-scenarios--frame-target-settled-p (context)
  "Return non-nil when the selected frame reached CONTEXT's target geometry."
  (let ((fullscreen
         (etaf-gui-verifier-context-get context 'target-fullscreen))
        (width (etaf-gui-verifier-context-get context 'target-frame-width))
        (height (etaf-gui-verifier-context-get context 'target-frame-height)))
    (and (eq (frame-parameter nil 'fullscreen) fullscreen)
         (or (not (numberp width)) (= (frame-text-width) width))
         (or (not (numberp height)) (= (frame-text-height) height)))))

(defun etaf-playground-gui-scenarios--viewport-unchanged-p (context before)
  "Prove CONTEXT's window geometry and committed revision match BEFORE.
This proves an unchanged action, not a new viewport publication."
  (let ((buffer (etaf-gui-verifier-context-target-buffer context)))
    (and (not (ebox-transaction-active-p))
         (buffer-live-p buffer)
         (ebox-surface-buffer-mounted-p buffer)
         (eq (selected-window) (plist-get before :window))
         (numberp (plist-get before :width))
         (equal (ebox-viewport-window-width (selected-window))
                (plist-get before :width))
         (equal (window-body-height (selected-window)) (plist-get before :height))
         (equal (frame-text-width) (plist-get before :frame-width))
         (equal (frame-text-height) (plist-get before :frame-height))
         (numberp (plist-get before :revision))
         (> (plist-get before :revision) 0)
         (= (ebox-surface-buffer-revision buffer) (plist-get before :revision)))))

(defun etaf-playground-gui-scenarios--viewport-settled-p (context)
  "Return non-nil when CONTEXT's resize published or its no-op stayed unchanged."
  (let* ((before (etaf-gui-verifier-context-get context 'viewport-noop-before))
         (report (unless before (etaf-playground-gui-scenarios--report context)))
         (buffer (etaf-gui-verifier-context-target-buffer context))
         (actual (ebox-viewport-window-width (selected-window)))
         (published (or (plist-get report :target-viewport-width)
                        (plist-get report :viewport-width)))
         (published-height (plist-get report :target-viewport-height))
         ;; The public buffer revision is TP's committed surface revision.
         ;; Ebox's runtime revision is a different, possibly lagging counter.
         (revision (plist-get report :surface-revision))
         (previous
          (etaf-gui-verifier-context-get
           context 'viewport-revision-before)))
    (and (if before
             (etaf-playground-gui-scenarios--viewport-unchanged-p context before)
           (and (not (ebox-transaction-active-p))
                (buffer-live-p buffer)
                (ebox-surface-buffer-mounted-p buffer)
                (numberp actual)
                (numberp published)
                (= actual published)
                (numberp published-height)
                (= (window-body-height (selected-window)) published-height)
                (integerp revision)
                (integerp previous)
                (> revision previous)
                (= revision (ebox-surface-buffer-revision buffer))
                (plist-get report :runtime-published)
                (not (plist-get report :publication-scope-fallback))))
         (etaf-playground-gui-scenarios--frame-target-settled-p context)
         (etaf-playground-gui-scenarios--visible-window-content-p context))))

(cl-defun etaf-playground-gui-scenarios--invariants
    (context &optional (preview-p t))
  "Return shared Ebox/ETAF publication invariants for CONTEXT.
PREVIEW-P additionally requires the display settings owned by Playground."
  (let* ((buffer (etaf-gui-verifier-context-target-buffer context))
         (mounted (and (buffer-live-p buffer)
                       (ebox-surface-buffer-mounted-p buffer)))
         (canvas-settings
          (and mounted preview-p
               (with-current-buffer buffer
                 (list truncate-lines fringe-indicator-alist))))
         (text (and mounted
                    (with-current-buffer buffer
                      (buffer-substring-no-properties
                       (point-min) (point-max))))))
    (when (etaf-gui-verifier-context-get context 'expects-mounted)
      (append
       (list
       (etaf-gui-verifier-assert "surface-mounted" mounted)
       (etaf-gui-verifier-assert
        "rendered-output-nonempty" (and text (> (length text) 0)))
       (etaf-gui-verifier-assert
        "visible-output-nonempty"
        (etaf-playground-gui-scenarios--visible-window-content-p context))
       (etaf-gui-verifier-assert
        "no-render-error"
        (and text
             (not (string-match-p
                   "could not render\\|runtime error\\|Wrong type argument"
                   text)))))
       ;; Preview chrome is owned by Playground's preview mode.  A standalone
       ;; App mounted with `etaf-mount' has no preview-mode contract.
       (when preview-p
         (list
          (etaf-gui-verifier-assert
           "generated-canvas-truncates-editor-lines" (car canvas-settings))
          (etaf-gui-verifier-assert
           "generated-canvas-hides-editor-edge-indicators"
           (and (not (assq 'truncation (cadr canvas-settings)))
                (not (assq 'continuation (cadr canvas-settings)))))))))))

(defun etaf-playground-gui-scenarios--adapter (context)
  "Return Playground-specific JSON data for CONTEXT."
  (let* ((report (etaf-playground-gui-scenarios--report context))
         (buffer (etaf-gui-verifier-context-target-buffer context))
         (runtime (and (buffer-live-p buffer)
                       (etaf-runtime-for-buffer buffer)))
         (stage (plist-get report :stage)))
    (list
     (cons 'generation (if runtime (etaf-runtime-generation runtime) 0))
     (cons 'viewport_width
           (or (plist-get report :target-viewport-width)
               (plist-get report :viewport-width)
               0))
     (cons 'frame_text_width (frame-text-width))
     (cons 'frame_text_height (frame-text-height))
     (cons 'fullscreen
           (format "%s" (frame-parameter nil 'fullscreen)))
     (cons 'target_frame_width
           (or (etaf-gui-verifier-context-get
                context 'target-frame-width)
               0))
     (cons 'target_frame_height
           (or (etaf-gui-verifier-context-get
                context 'target-frame-height)
               0))
     (cons 'stage (if stage (symbol-name stage) "none")))))

(defun etaf-playground-gui-scenarios--resize (context width height)
  "Resize CONTEXT's selected frame to pixel WIDTH and HEIGHT."
  (etaf-playground-gui-scenarios--begin-viewport-change
   context nil width height)
  (let ((frame-resize-pixelwise t))
    (set-frame-size nil width height t)))

(defun etaf-playground-gui-scenarios--windowed-action ()
  "Return an action that leaves fullscreen and publishes its viewport."
  (etaf-gui-verifier-action-create
   :id "leave-fullscreen"
   :execute
   (lambda (context)
     (etaf-playground-gui-scenarios--begin-viewport-change context nil)
     (set-frame-parameter nil 'fullscreen nil))
   :settled-p #'etaf-playground-gui-scenarios--viewport-settled-p
   :assertions #'etaf-playground-gui-scenarios--resize-assertions))

(defun etaf-playground-gui-scenarios--resize-assertions (context)
  "Return exact viewport publication or unchanged-action assertions for CONTEXT."
  (if (etaf-gui-verifier-context-get context 'viewport-noop-before)
      (list (etaf-gui-verifier-assert
             "viewport-unchanged"
             (etaf-playground-gui-scenarios--viewport-settled-p context)))
    (let ((report (etaf-playground-gui-scenarios--report context)))
      (list
       (etaf-gui-verifier-assert
        "viewport-published"
        (etaf-playground-gui-scenarios--viewport-settled-p context))
       (etaf-gui-verifier-assert
        "resize-not-scope-fallback"
        (not (plist-get report :publication-scope-fallback)))))))

(defun etaf-playground-gui-scenarios--resize-action (id width height)
  "Return resize action ID for pixel WIDTH and HEIGHT."
  (etaf-gui-verifier-action-create
   :id id
   :execute (lambda (context)
              (etaf-playground-gui-scenarios--resize
               context width height))
   :settled-p #'etaf-playground-gui-scenarios--viewport-settled-p
   :assertions #'etaf-playground-gui-scenarios--resize-assertions
   :screenshot t))

(defun etaf-playground-gui-scenarios--maximize-action ()
  "Return a stable full-workarea viewport publication action."
  (etaf-gui-verifier-action-create
   :id "maximize-frame"
   :execute
   (lambda (context)
     (etaf-playground-gui-scenarios--begin-viewport-change
      context 'maximized)
     (set-frame-parameter nil 'fullscreen 'maximized))
   :settled-p #'etaf-playground-gui-scenarios--viewport-settled-p
   :assertions #'etaf-playground-gui-scenarios--resize-assertions
   :screenshot t))

(defun etaf-playground-gui-scenarios--scroll-progressed-p (context)
  "Return non-nil when CONTEXT's pending scroll changed visible state."
  (or
   (/= (etaf-gui-verifier-context-get
        context 'scroll-window-start (window-start))
       (window-start))
   (not
    (equal
     (etaf-gui-verifier-context-get context 'scroll-report)
     (etaf-playground-gui-scenarios--report context)))))

(defun etaf-playground-gui-scenarios--scroll-settled-p (context)
  "Return non-nil when CONTEXT's scroll progressed to visible content."
  (and (etaf-playground-gui-scenarios--scroll-progressed-p context)
       (etaf-playground-gui-scenarios--visible-window-content-p context)))

(defun etaf-playground-gui-scenarios--scroll-action (id command)
  "Return Ebox page-scroll action ID using public COMMAND."
  (etaf-gui-verifier-action-create
   :id id
   :execute
   (lambda (context)
     (etaf-gui-verifier-context-put context 'scroll-window-start
                                    (window-start))
     (etaf-gui-verifier-context-put
     context 'scroll-report
      (etaf-playground-gui-scenarios--report context))
     (with-current-buffer (etaf-gui-verifier-context-target-buffer context)
       (goto-char (window-start)))
     (funcall command))
   :settled-p #'etaf-playground-gui-scenarios--scroll-settled-p
   :assertions
   (lambda (context)
     (list
      (etaf-gui-verifier-assert
       "scroll-progressed"
       (etaf-playground-gui-scenarios--scroll-progressed-p context))))
   :screenshot t))

(defun etaf-playground-gui-scenarios--reset-scroll-action ()
  "Return an action that restores the outer Emacs window to its top."
  (etaf-gui-verifier-action-create
   :id "reset-scroll"
   :execute
   (lambda (_context)
     (set-window-start (selected-window) (point-min))
     (goto-char (point-min)))
   :settled-p
   (lambda (context)
     (and (= (window-start) (point-min))
          (etaf-playground-gui-scenarios--visible-window-content-p context)))
   :assertions
   (lambda (_context)
     (list
      (etaf-gui-verifier-assert
       "scroll-reset" (= (window-start) (point-min)))))))

(defun etaf-playground-gui-scenarios--research-event-action
    (id reference postcondition &optional screenshot assertion-name)
  "Return Research action ID for REFERENCE and POSTCONDITION.
When non-nil, SCREENSHOT requests visual evidence and ASSERTION-NAME names the
product-specific postcondition in the evidence stream."
  (etaf-gui-verifier-action-create
   :id id
   :execute
   (lambda (context)
     (let ((runtime
            (etaf-runtime-for-buffer
             (etaf-gui-verifier-context-target-buffer context))))
       (etaf-gui-verifier-context-put
        context (intern (concat id "-generation"))
        (etaf-runtime-generation runtime))
       (with-current-buffer
           (etaf-gui-verifier-context-target-buffer context)
         (etaf-focus runtime reference)
         (execute-kbd-macro (kbd "RET")))))
   :settled-p
   (lambda (context)
     (let ((runtime
            (etaf-runtime-for-buffer
             (etaf-gui-verifier-context-target-buffer context))))
       (and runtime
            (> (etaf-runtime-generation runtime)
               (etaf-gui-verifier-context-get
                context (intern (concat id "-generation")) -1))
            (funcall postcondition context)
            (etaf-playground-gui-scenarios--visible-window-content-p
             context))))
   :assertions
   (lambda (context)
     (let ((runtime
            (etaf-runtime-for-buffer
             (etaf-gui-verifier-context-target-buffer context))))
       (list
        (etaf-gui-verifier-assert
         "generation-advanced"
         (> (etaf-runtime-generation runtime)
            (etaf-gui-verifier-context-get
             context (intern (concat id "-generation")) -1)))
        (etaf-gui-verifier-assert
         "activated-host-focused"
         (equal reference (etaf-focused-host-ref runtime)))
        (etaf-gui-verifier-assert
         (or assertion-name "product-postcondition")
         (funcall postcondition context)))))
   :screenshot screenshot))

(defun etaf-playground-gui-scenarios-research ()
  "Return the Research Shelf GUI scenario adapter."
  (etaf-gui-verifier-scenario-create
     :name "research-shelf"
     :claim "Research Shelf renders, handles interactions, and persists SQLite writes"
     :initialize
     (lambda (context)
       (etaf-gui-verifier-context-select-buffer
        context (get-buffer-create "*ETAF GUI Research Shelf*")))
     :invariants #'etaf-playground-gui-scenarios--invariants
     :adapter #'etaf-playground-gui-scenarios--adapter
     :actions
     (list
      (etaf-gui-verifier-action-create
       :id "mount"
       :execute
       (lambda (context)
         (etaf-gui-verifier-context-put context 'target-fullscreen 'maximized)
         (set-frame-parameter nil 'fullscreen 'maximized)
         (etaf-playground-refresh-examples)
         (etaf-gui-verifier-context-select-buffer
          context
          (etaf-playground-open-example
           "research-shelf" "*ETAF GUI Research Shelf*"))
         (etaf-gui-verifier-context-put context 'expects-mounted t))
       :settled-p #'etaf-playground-gui-scenarios--mounted-settled-p
       :assertions
       (lambda (context)
         (list
          (etaf-gui-verifier-assert
           "runtime-mounted"
           (etaf-runtime-for-buffer
            (etaf-gui-verifier-context-target-buffer context)))))
       :screenshot t)
      (etaf-playground-gui-scenarios--windowed-action)
      (etaf-playground-gui-scenarios--resize-action
       "resize-narrow" 900 500)
      (etaf-playground-gui-scenarios--resize-action
       "resize-compact" 700 500)
      (etaf-playground-gui-scenarios--scroll-action
       "scroll-down" #'ebox-scroll-page-down)
      (etaf-playground-gui-scenarios--reset-scroll-action)
      (etaf-playground-gui-scenarios--resize-action
       "resize-wide" 1300 750)
      (etaf-playground-gui-scenarios--research-event-action
       "row-select" 'research-shelf-row-2
       (lambda (context)
         (string-match-p
          "John Berger · Book"
          (etaf-playground-gui-scenarios--buffer-text context))))
      (etaf-playground-gui-scenarios--research-event-action
       "data-mutation" 'research-shelf-progress
       (lambda (context)
         (let ((text
                (etaf-playground-gui-scenarios--buffer-text context)))
           (and (string-match-p "Progress saved" text)
                (string-match-p "10%" text))))
       t "progress-persisted")
      (etaf-playground-gui-scenarios--research-event-action
       "filter-reading" 'research-shelf-filter-reading
       (lambda (context)
         (let ((text
                (etaf-playground-gui-scenarios--buffer-text context)))
           (and (string-match-p "Showing Reading" text)
                (string-match-p "Ways of Seeing" text))))
       t "reading-filter-applied")
      (etaf-playground-gui-scenarios--research-event-action
       "theme-toggle" 'research-shelf-theme-toggle
       (lambda (context)
         (string-match-p
          "Dark theme"
          (etaf-playground-gui-scenarios--buffer-text context)))
       t)
      (etaf-playground-gui-scenarios--research-event-action
       "pagination" 'research-shelf-page-next
       (lambda (context)
         (let ((text
                (etaf-playground-gui-scenarios--buffer-text context)))
           (and (string-match-p "Page 2 /" text)
                (string-match-p "13–24 of" text))))
       t)
      (etaf-playground-gui-scenarios--maximize-action)
      (etaf-gui-verifier-action-create
       :id "reopen-database"
       :execute
       (lambda (context)
         (let* ((buffer (etaf-gui-verifier-context-target-buffer context))
                (name (buffer-name buffer))
                (runtime (etaf-runtime-for-buffer buffer)))
           (etaf-gui-verifier-context-put context 'closed-runtime runtime)
           (etaf-gui-verifier-context-put context 'closed-buffer buffer)
           (etaf-unmount runtime)
           (kill-buffer buffer)
           (etaf-gui-verifier-context-select-buffer
            context (etaf-playground-mount-example name "research-shelf"))))
       :settled-p
       (lambda (context)
         (and (etaf-playground-gui-scenarios--mounted-settled-p context)
              (not (buffer-live-p
                    (etaf-gui-verifier-context-get context 'closed-buffer)))
              (not (etaf-runtime-mounted-p
                    (etaf-gui-verifier-context-get context 'closed-runtime)))
              (string-match-p "256 items"
                              (etaf-playground-gui-scenarios--buffer-text context))))
       :screenshot t)
      (etaf-playground-gui-scenarios--research-event-action
       "persisted-row-select" 'research-shelf-row-2
       (lambda (context)
         (let ((text (etaf-playground-gui-scenarios--buffer-text context)))
           (and (string-match-p "John Berger · Book" text)
                (string-match-p "Progress  10%" text)
                (string-match-p "256 items" text))))
       t "progress-survives-reopen")
      (etaf-playground-gui-scenarios--research-event-action
       "reload-persisted-record" 'research-shelf-reload
       (lambda (context)
         (let ((text (etaf-playground-gui-scenarios--buffer-text context)))
           (and (string-match-p "Library reloaded" text)
                (string-match-p "Progress  10%" text)
                (string-match-p "256 items" text))))
       t "reload-does-not-repeat-write"))
     :completion
     (lambda (context)
       (= (etaf-gui-verifier-context-action-count context) 16))))

(defun etaf-playground-gui-scenarios-ebox (scenario fixture)
  "Return one Ebox SCENARIO adapter for FIXTURE."
  (etaf-gui-verifier-scenario-create
     :name scenario
     :claim "Ebox reference mounts, follows frame resize, and scrolls"
     :initialize
     (lambda (context)
       (let ((source (find-file fixture)))
         (ebox-playground-mode)
         (etaf-gui-verifier-context-select-buffer context source)))
     :invariants #'etaf-playground-gui-scenarios--invariants
     :adapter #'etaf-playground-gui-scenarios--adapter
     :actions
     (list
      (etaf-gui-verifier-action-create
       :id "mount"
       :execute
       (lambda (context)
         (etaf-gui-verifier-context-put context 'target-fullscreen 'maximized)
         (set-frame-parameter nil 'fullscreen 'maximized)
         (etaf-gui-verifier-context-select-buffer context (ebox-playground-render))
         (etaf-gui-verifier-context-put context 'expects-mounted t))
       :settled-p #'etaf-playground-gui-scenarios--mounted-settled-p
       :assertions
       (lambda (context)
         (let ((preview (etaf-gui-verifier-context-target-buffer context)))
           (list
            (etaf-gui-verifier-assert
             "preview-mounted"
             (and (buffer-live-p preview)
                  (ebox-surface-buffer-mounted-p preview))))))
       :screenshot t)
      (etaf-playground-gui-scenarios--windowed-action)
      (etaf-playground-gui-scenarios--resize-action
       "resize-narrow" 900 500)
      (etaf-playground-gui-scenarios--scroll-action
       "scroll-down" #'ebox-scroll-page-down)
      (etaf-playground-gui-scenarios--reset-scroll-action)
      (etaf-playground-gui-scenarios--resize-action
       "resize-wide" 1300 750)
      (etaf-playground-gui-scenarios--maximize-action))
     :completion
     (lambda (context)
       (= (etaf-gui-verifier-context-action-count context) 7))))

;;;###autoload
(defun etaf-playground-gui-scenarios-run-from-environment ()
  "Build one concrete adapter from environment and run the generic engine."
  (unless (plist-get (ebox-native-reflow-runtime-report) :layout-ready-p)
    (error "Prepared Ebox native module is unavailable"))
  (let* ((scenario (or (getenv "ETAF_GUI_SCENARIO")
                       (error "ETAF_GUI_SCENARIO is not configured")))
         (run-directory (or (getenv "ETAF_GUI_RUN_DIR")
                            (error "ETAF_GUI_RUN_DIR is not configured")))
         (fixture (getenv "ETAF_GUI_FIXTURE"))
         (_research-fixture
          (when (equal scenario "research-shelf")
            (setq etaf-research-shelf-database-file
                  (expand-file-name "research-shelf.sqlite" run-directory)
                  etaf-research-shelf-fixture-size 256
                  etaf-research-shelf-page-size 12)
            (when (file-exists-p etaf-research-shelf-database-file)
              (delete-file etaf-research-shelf-database-file))))
         (adapter
          (pcase scenario
            ("research-shelf"
             (etaf-playground-gui-scenarios-research))
            ((or "flex-reference" "grid-reference")
             (unless (and fixture (file-readable-p fixture))
               (error "ETAF_GUI_FIXTURE is not readable"))
             (etaf-playground-gui-scenarios-ebox scenario fixture))
            (_ (error "Unknown Playground GUI scenario: %s" scenario)))))
    (etaf-gui-verifier-run adapter run-directory)))

(provide 'playground-gui-scenarios)
;;; playground-gui-scenarios.el ends here
