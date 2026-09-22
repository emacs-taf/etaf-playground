;;; desktop-gui-scenarios.el --- ETAF Desktop GUI acceptance adapter -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; This adapter drives a real mounted `etaf-desktop' surface in the existing
;; graphical Emacs server.  It deliberately uses the public desktop APIs for
;; state assertions and the rendered Host positions for input.  The generic
;; `emacs-gui-verifier' owns ordered checkpoints, window-only screenshots and
;; manifest/result evidence; this file owns only the Desktop fixture and its
;; observable actions.
;;
;; The scenario is fail-closed.  If an expected title bar, resize handle,
;; launcher or tiling splitter is absent, it records a failed action instead
;; of replacing the real GUI path with a direct state mutation.  Direct API
;; calls are used only to prepare an app manifest or to inspect detached state.

;;; Code:

(require 'cl-lib)
(require 'emacs-gui-verifier)
(require 'etaf)
(require 'etaf-desktop)
(require 'etaf-ui)
(require 'etaf-desktop-layout nil t)

(declare-function ebox-viewport-window-width "ebox-viewport" (window))

(defconst etaf-desktop-gui--buffer "*ETAF Desktop GUI Acceptance*"
  "Dedicated target buffer used by the Desktop GUI scenario.")

(defconst etaf-desktop-gui--notes-app 'etaf-desktop-gui-notes
  "Fixture application ID for the Notes window.")
(defconst etaf-desktop-gui--files-app 'etaf-desktop-gui-files
  "Fixture application ID for the Files window.")
(defconst etaf-desktop-gui--chat-app 'etaf-desktop-gui-chat
  "Fixture application ID for the Chat window.")
(defconst etaf-desktop-gui--broken-app 'etaf-desktop-gui-broken
  "Fixture application ID whose launch callback fails deliberately.")

(defvar etaf-desktop-gui--desktop nil
  "Desktop controller retained for one GUI scenario run.")
(defvar etaf-desktop-gui--run-directory nil
  "Evidence directory for the currently scheduled run.")
(defvar etaf-desktop-gui--notes-window nil
  "Window ID belonging to the Notes fixture instance.")
(defvar etaf-desktop-gui--files-window nil
  "Window ID belonging to the Files fixture instance.")
(defvar etaf-desktop-gui--chat-window nil
  "Window ID belonging to the Chat fixture instance.")
(defvar etaf-desktop-gui--notes-instance nil
  "Instance ID belonging to the Notes fixture app.")

(defun etaf-desktop-gui--view (text)
  "Return an ETAF View containing literal TEXT for the fixture." 
  (etaf-view (expr (etaf-node 'text nil (list text)))))

(defun etaf-desktop-gui--app-open (title text workspace)
  "Return an app callback producing one fixture window." 
  (lambda (_context)
    (list :windows
          (list (list :id "main" :title title :view (etaf-desktop-gui--view text)
                      :workspace workspace
                      :x (cond ((eq workspace 'dev) 430)
                               ((equal title "Files") 430)
                               (t 24))
                      :y (if (eq workspace 'dev) 5 3)
                      :width 300 :height 8 :min-width 160 :min-height 4)))))

(defun etaf-desktop-gui--register-apps ()
  "Install unique fixture manifests for one scenario." 
  (dolist (id (list etaf-desktop-gui--notes-app etaf-desktop-gui--files-app
                    etaf-desktop-gui--chat-app etaf-desktop-gui--broken-app))
    (when (etaf-desktop-app-registered-p id)
      (ignore-errors (etaf-desktop-unregister-app id t))))
  (etaf-desktop-register-app
   etaf-desktop-gui--notes-app :title "Notes"
   :open (etaf-desktop-gui--app-open
          "Notes" "ETAF Notes application" 'main)
   :capabilities '(multiple-instances resizable) :replace t)
  (etaf-desktop-register-app
   etaf-desktop-gui--files-app :title "Files"
   :open (etaf-desktop-gui--app-open
          "Files" "ETAF Files application" 'main)
   :capabilities '(resizable) :replace t)
  (etaf-desktop-register-app
   etaf-desktop-gui--chat-app :title "Chat"
   :open (etaf-desktop-gui--app-open
          "Chat" "ETAF Chat application" 'dev)
   :capabilities '(resizable) :replace t)
  (etaf-desktop-register-app
   etaf-desktop-gui--broken-app :title "Broken app"
   :open (lambda (_context) (error "intentional Desktop GUI launch failure"))
   :replace t))

(defun etaf-desktop-gui--prepare ()
  "Create a fresh Desktop fixture without mounting it." 
  (unless (display-graphic-p)
    (user-error "ETAF Desktop GUI acceptance requires a graphical Emacs frame"))
  (when-let* ((old (get-buffer etaf-desktop-gui--buffer)))
    (when-let* ((runtime (etaf-runtime-for-buffer old)))
      (etaf-unmount runtime))
    (kill-buffer old))
  (etaf-desktop-gui--register-apps)
  (setq etaf-desktop-gui--desktop
        (etaf-desktop-create :name etaf-desktop-gui--buffer
                             :workspaces '(main dev)))
  (let* ((notes (etaf-desktop-launch etaf-desktop-gui--desktop
                                     etaf-desktop-gui--notes-app
                                     :instance-id "desktop-notes-1"
                                     :options '(:workspace main)
                                     :workspace 'main))
         (files (etaf-desktop-launch etaf-desktop-gui--desktop
                                     etaf-desktop-gui--files-app
                                     :instance-id "desktop-files-1"
                                     :options '(:workspace main)
                                     :workspace 'main))
         (chat (etaf-desktop-launch etaf-desktop-gui--desktop
                                    etaf-desktop-gui--chat-app
                                    :instance-id "desktop-chat-1"
                                    :options '(:workspace dev)
                                    :workspace 'dev)))
    (setq etaf-desktop-gui--notes-instance (plist-get notes :id)
          etaf-desktop-gui--notes-window (car (plist-get notes :windows))
          etaf-desktop-gui--files-window (car (plist-get files :windows))
          etaf-desktop-gui--chat-window (car (plist-get chat :windows)))
    (etaf-desktop-switch-workspace etaf-desktop-gui--desktop 'main))
  etaf-desktop-gui--desktop)

(defun etaf-desktop-gui--runtime (context)
  "Return CONTEXT's live Runtime or signal a descriptive failure." 
  (or (etaf-runtime-for-buffer
       (etaf-gui-verifier-context-target-buffer context))
      (error "ETAF Desktop Runtime is not mounted")))

(defun etaf-desktop-gui--props-entries (context)
  "Return public Host property entries for CONTEXT's Runtime." 
  (etaf-runtime-host-props-entries (etaf-desktop-gui--runtime context)))

(defun etaf-desktop-gui--class-p (props class)
  "Return non-nil when PROPS has CLASS in its public class value." 
  (let ((value (plist-get props :class)))
    (cond
     ((stringp value) (member class (split-string value)))
     ((listp value) (member class value))
     (t nil))))

(defun etaf-desktop-gui--find-ref (context predicate description)
  "Return first public Host reference satisfying PREDICATE.
Signal an error mentioning DESCRIPTION when no displayed target exists." 
  (let ((entry (cl-find-if (lambda (entry) (funcall predicate (cdr entry)))
                           (etaf-desktop-gui--props-entries context))))
    (or (car entry) (error "Missing rendered Desktop target: %s" description))))

(defun etaf-desktop-gui--ref-by-symbol (context symbol)
  "Return the rendered Host reference named SYMBOL.

Labels are ambiguous across the shell: a launcher entry and a taskbar entry
can share an application title, so the launcher action addresses the
application's own launcher reference instead of the first matching label."
  (let ((entry (cl-find symbol (etaf-desktop-gui--props-entries context)
                        :key #'car :test #'equal)))
    (or (car entry)
        (error "Missing rendered Desktop target: %s" symbol))))

(defun etaf-desktop-gui--ref-by-label (context label)
  "Find a rendered Host with accessible LABEL." 
  (etaf-desktop-gui--find-ref
   context (lambda (props)
             (or (equal label (plist-get props :aria-label))
                 (equal label (plist-get props :label))
                 (equal label (plist-get props :text))))
   label))

(defun etaf-desktop-gui--ref-by-class (context class)
  "Find a rendered Host by exact public CLASS." 
  (etaf-desktop-gui--find-ref
   context (lambda (props)
             (if (string-match-p " " class)
                 (cl-every (lambda (token)
                            (etaf-desktop-gui--class-p props token))
                           (split-string class))
               (etaf-desktop-gui--class-p props class))) class))

(defun etaf-desktop-gui--mouse-data (position)
  "Return displayed mouse event data at buffer POSITION." 
  (redisplay t)
  (let ((data (posn-at-point position (selected-window))))
    (unless (and data (pos-visible-in-window-p position))
      (error "Desktop mouse target is not visible: %S" position))
    data))

(defun etaf-desktop-gui--click-ref (context ref)
  "Send a native mouse click to rendered Host REF." 
  (let* ((runtime (etaf-desktop-gui--runtime context))
         (position (etaf-host-ref-position runtime ref)))
    (unless position (error "Desktop Host has no rendered position: %S" ref))
    (let ((data (etaf-desktop-gui--mouse-data position)))
      (execute-kbd-macro (vector (list 'down-mouse-1 data)
                                 (list 'mouse-1 data))))))

(defun etaf-desktop-gui--drag-ref (context ref dx dy)
  "Send a native drag from Host REF by pixel DX and DY.
The Ebox/ETAF gesture adapter converts DY to text rows at the product boundary;
this helper intentionally retains the physical pixel event." 
  (let* ((runtime (etaf-desktop-gui--runtime context))
         (position (etaf-host-ref-position runtime ref))
         (data (and position (etaf-desktop-gui--mouse-data position))))
    (unless data (error "Desktop drag target is not visible: %S" ref))
    (let* ((xy (nth 2 data))
           (end-data (list (nth 0 data) (nth 1 data)
                           (cons (+ (car xy) dx) (+ (cdr xy) dy))
                           (or (nth 3 data) 1)))
           (press (list 'down-mouse-1 data))
           (events (list (list 'mouse-movement end-data)
                         (list 'drag-mouse-1 (event-start press) end-data)))
           (command (key-binding (vector press) nil nil position)))
      (unless (commandp command)
        (error "No drag command is bound at Desktop Host %S" ref))
      (cl-letf (((symbol-function 'read-event)
                 (lambda (&rest _)
                   (or (pop events) (error "Desktop drag ended without release")))))
        (funcall command press)))))

(defun etaf-desktop-gui--window-state (id)
  "Return public state of fixture window ID." 
  (etaf-desktop-window-state etaf-desktop-gui--desktop id))

(defun etaf-desktop-gui--ref-by-label-within (context label window-ref)
  "Find the rendered Host labelled LABEL inside WINDOW-REF's bounds.

Shell labels repeat across windows, so a window action addresses the button
that is rendered inside that window's own visible range."
  (let* ((runtime (etaf-desktop-gui--runtime context))
         (buffer (etaf-runtime-buffer runtime))
         (outer (ignore-errors (ebox-host-ref-bounds buffer window-ref))))
    (unless outer
      (error "Desktop window is not rendered: %s" window-ref))
    (or (cl-loop for (ref . props) in (etaf-desktop-gui--props-entries context)
                 when (and (or (equal label (plist-get props :aria-label))
                               (equal label (plist-get props :label))
                               (equal label (plist-get props :text)))
                           (let ((bounds (ignore-errors
                                          (ebox-host-ref-bounds buffer ref))))
                             (and bounds
                                  (<= (car outer) (car bounds))
                                  (<= (cdr bounds) (cdr outer)))))
                 return ref)
        (error "Desktop window %s has no visible %s control"
               window-ref label))))

(defun etaf-desktop-gui--title-ref (context title)
  "Find the title-bar Host for TITLE using its rendered label text." 
  (let ((runtime (etaf-desktop-gui--runtime context)))
    (or (cl-loop for (ref . props) in (etaf-runtime-host-props-entries runtime)
                 when (and (equal title (plist-get props :text))
                           (etaf-desktop-gui--class-p props "etaf-window-chrome"))
                 return ref)
        ;; The title text may be represented by a Label Host in older ETAF UI
        ;; revisions; keep the fallback constrained to the visible title text.
        (let ((position (save-excursion
                          (goto-char (point-min))
                          (and (search-forward title nil t)
                               (- (point) (length title))))))
          (unless position (error "Rendered Desktop title is missing: %s" title))
          ;; A title click must still use a public Host position.  Resolve the
          ;; smallest visible Host covering that point rather than a private
          ;; node; the title text itself owns no reference.
          (or (car (car (sort
                         (cl-loop for (ref . _props) in
                                  (etaf-runtime-host-props-entries runtime)
                                  for bounds = (ignore-errors
                                                (ebox-host-ref-bounds
                                                 (etaf-runtime-buffer runtime) ref))
                                  when (and bounds
                                            (<= (car bounds) position)
                                            (< position (cdr bounds)))
                                  collect (cons ref (- (cdr bounds) (car bounds))))
                         (lambda (a b) (< (cdr a) (cdr b))))))
              (error "Rendered Desktop title has no public Host: %s" title))))))

(defun etaf-desktop-gui--mounted-p (context)
  "Return non-nil when CONTEXT is mounted, selected and visibly rendered." 
  (let ((buffer (etaf-gui-verifier-context-target-buffer context)))
    (and (buffer-live-p buffer)
         (eq (window-buffer (selected-window)) buffer)
         (etaf-runtime-for-buffer buffer)
         (string-match-p "Notes\\|Files\\|Chat"
                         (buffer-substring-no-properties (point-min) (point-max))))))

(defun etaf-desktop-gui--fills-window-p ()
  "Return non-nil when the default canvas owns the visible target window.

The controller reports the safe Ebox viewport width and the number of canvas
rows between the one-row workspace bar and one-row taskbar.  Comparing those
public dimensions with the mounted window catches a regression where a fixed
demo canvas is rendered in the upper-left corner instead of following its host.
"
  (let* ((window (selected-window))
         (state (etaf-desktop-state etaf-desktop-gui--desktop))
         (width (ebox-viewport-window-width window))
         (height (window-body-height window))
         ;; A one-pixel border/rounding difference is host-window chrome, not
         ;; an upper-left-canvas regression.  The desktop's text-row height
         ;; remains exact because its two shell rows are logical units.
         (canvas-width (plist-get state :canvas-width)))
    (and (numberp width)
         (<= (abs (- canvas-width width)) 1)
         (= (+ 2 (plist-get state :canvas-height)) height))))

(defun etaf-desktop-gui--invariants (context)
  "Return generic Desktop invariants for each verifier checkpoint." 
  (let ((mounted (etaf-gui-verifier-context-get context 'expects-mounted)))
    (list
   (etaf-gui-verifier-assert "desktop-mounted"
                             (or (not mounted)
                                 (etaf-desktop-gui--mounted-p context)))
   (etaf-gui-verifier-assert
    "desktop-buffer-selected"
    (eq (window-buffer (selected-window))
        (etaf-gui-verifier-context-target-buffer context)))
   (etaf-gui-verifier-assert
    "desktop-no-render-error"
    (or (not mounted)
        (not (string-match-p "could not render\\|runtime error\\|Wrong type argument"
                             (buffer-substring-no-properties (point-min) (point-max)))))))))

(defun etaf-desktop-gui--adapter (_context)
  "Return JSON-safe public state facts for CONTEXT." 
  (let ((desktop etaf-desktop-gui--desktop))
    (list
     (cons 'active_workspace
           (format "%s" (etaf-desktop-active-workspace desktop)))
     (cons 'active_window
           (format "%s" (or (etaf-desktop-active-window desktop) "")))
     (cons 'layout_mode
           (if (fboundp 'etaf-desktop-layout-mode)
               (format "%s" (etaf-desktop-layout-mode desktop))
             "floating"))
     (cons 'windows
           (vconcat
            (mapcar (lambda (window)
                      (let ((id (plist-get window :id)))
                        (list (cons 'id (format "%s" id))
                              (cons 'x (plist-get window :x))
                              (cons 'y (plist-get window :y))
                              (cons 'width (plist-get window :width))
                              (cons 'height (plist-get window :height))
                              (cons 'visible (and (plist-get window :visible) t))
                              (cons 'minimized (and (plist-get window :minimized) t))
                              (cons 'maximized (and (plist-get window :maximized) t)))))
                    (etaf-desktop-windows desktop))))
     (cons 'instances
           (vconcat
            (mapcar (lambda (instance)
                      (list (cons 'id (format "%s" (plist-get instance :id)))
                            (cons 'app_id (format "%s" (plist-get instance :app-id)))
                            (cons 'status (format "%s" (plist-get instance :status)))
                            (cons 'error (or (plist-get instance :error) ""))))
                    (etaf-desktop-instances desktop)))))))

(defun etaf-desktop-gui--action (id execute predicate)
  "Build a screenshot action ID with settled PREDICATE." 
  (etaf-gui-verifier-action-create
   :id id :execute execute :screenshot t
   :settled-p (lambda (context)
                (and (etaf-desktop-gui--mounted-p context)
                     (funcall predicate context)))
   :assertions (lambda (context)
                 (list (etaf-gui-verifier-assert id (funcall predicate context))))))

(defun etaf-desktop-gui--scenario ()
  "Return the complete ETAF Desktop GUI scenario." 
  (etaf-gui-verifier-scenario-create
   :name "etaf-desktop"
   :claim "ETAF Desktop floating, tiling, app lifecycle and workspace GUI"
   :initialize
   (lambda (context)
     (let ((desktop (etaf-desktop-gui--prepare)))
       (etaf-gui-verifier-context-put context 'desktop desktop)
       (etaf-gui-verifier-context-put context 'expects-mounted nil)
       ;; Generic verifier assertions require a selected target even before
       ;; the first mount action.  This is an intentionally unmounted, empty
       ;; buffer; the action below mounts the prepared desktop into it.
       (etaf-gui-verifier-context-select-buffer
        context (get-buffer-create etaf-desktop-gui--buffer))))
   :invariants #'etaf-desktop-gui--invariants
   :adapter #'etaf-desktop-gui--adapter
   :actions
   (list
    (etaf-desktop-gui--action
     "mount"
     (lambda (context)
       (let ((buffer (etaf-desktop-mount etaf-desktop-gui--desktop
                                         etaf-desktop-gui--buffer)))
         (etaf-gui-verifier-context-select-buffer context buffer)))
     (lambda (context)
       (and (etaf-desktop-gui--mounted-p context)
            (etaf-desktop-gui--fills-window-p)
            (string-match-p "Notes" (buffer-string))
            (string-match-p "Files" (buffer-string))
            (etaf-gui-verifier-context-put context 'expects-mounted t))))
    (etaf-desktop-gui--action
     "settings-modal-overlays-desktop"
     (lambda (context)
       (etaf-desktop-gui--click-ref
        context (etaf-desktop-gui--ref-by-symbol
                 context 'etaf-workspace-settings)))
     (lambda (_context)
       (and (etaf-desktop-settings-open-p etaf-desktop-gui--desktop)
            (string-match-p "Desktop Settings" (buffer-string))
            (string-match-p "Notes\\|Files" (buffer-string)))))
    (etaf-desktop-gui--action
     "settings-modal-closes-and-restores-surface"
     (lambda (context)
       (etaf-desktop-gui--click-ref
        context (etaf-desktop-gui--ref-by-label context "Done")))
     (lambda (_context)
       (and (not (etaf-desktop-settings-open-p etaf-desktop-gui--desktop))
            (string-match-p "Notes\\|Files" (buffer-string)))))
    (etaf-desktop-gui--action
     "launcher-focuses-running-files"
     (lambda (context)
       (etaf-gui-verifier-context-put
        context 'instances-before (length (etaf-desktop-instances
                                           etaf-desktop-gui--desktop)))
       (etaf-desktop-gui--click-ref
        context (etaf-desktop-gui--ref-by-label context "Applications"))
       (redisplay t)
       (etaf-desktop-gui--click-ref
        context (etaf-desktop-gui--ref-by-symbol
                 context (intern (format "etaf-desktop-launcher-%s"
                                         etaf-desktop-gui--files-app)))))
     (lambda (context)
       (and (= (length (etaf-desktop-instances etaf-desktop-gui--desktop))
               (etaf-gui-verifier-context-get context 'instances-before))
            (equal (etaf-desktop-active-window etaf-desktop-gui--desktop)
                   etaf-desktop-gui--files-window))))
    (etaf-desktop-gui--action
     "focus-files-by-title-click"
     (lambda (context)
       (etaf-desktop-gui--click-ref
        context (etaf-desktop-gui--title-ref context "Files")))
     (lambda (_context)
       (equal (etaf-desktop-active-window etaf-desktop-gui--desktop)
              etaf-desktop-gui--files-window)))
    (etaf-desktop-gui--action
     "drag-notes-title"
     (lambda (context)
       (let ((before (etaf-desktop-gui--window-state etaf-desktop-gui--notes-window)))
         (etaf-gui-verifier-context-put context 'drag-before before)
         (etaf-desktop-gui--drag-ref
          context (etaf-desktop-gui--title-ref context "Notes") 48
          (* 2 (max 1 (frame-char-height))))))
     (lambda (context)
       (let ((before (etaf-gui-verifier-context-get context 'drag-before))
             (after (etaf-desktop-gui--window-state etaf-desktop-gui--notes-window)))
         (and (> (plist-get after :x) (plist-get before :x))
              (= (plist-get after :y) (+ (plist-get before :y) 2))))))
    (etaf-desktop-gui--action
     "resize-notes-right-handle"
     (lambda (context)
       (let ((before (etaf-desktop-gui--window-state etaf-desktop-gui--notes-window)))
         (etaf-gui-verifier-context-put context 'resize-before before)
         (etaf-desktop-gui--drag-ref
          context (etaf-desktop-gui--ref-by-symbol
                   context (intern (format "etaf-desktop-resize-%s-right"
                                           etaf-desktop-gui--notes-window)))
          48 0)))
     (lambda (context)
       (> (plist-get (etaf-desktop-gui--window-state etaf-desktop-gui--notes-window)
                     :width)
          (plist-get (etaf-gui-verifier-context-get context 'resize-before) :width))))
    (etaf-desktop-gui--action
     "resize-notes-all-edges-and-corners"
     (lambda (context)
       (let ((id etaf-desktop-gui--notes-window))
         (cl-labels
             ((drag-edge
               (edge dx dy check)
               (let* ((before (etaf-desktop-gui--window-state id))
                      (ref (etaf-desktop-gui--ref-by-symbol
                            context
                            (intern (format "etaf-desktop-resize-%s-%s"
                                            id edge)))))
                 (etaf-desktop-gui--drag-ref context ref dx dy)
                 (redisplay t)
                 (let ((after (etaf-desktop-gui--window-state id)))
                   (unless (funcall check before after)
                     (error "Desktop %s resize did not update geometry: %S -> %S"
                            edge before after))))))
           (drag-edge 'left 12 0
                      (lambda (before after)
                        (and (> (plist-get after :x) (plist-get before :x))
                             (< (plist-get after :width)
                                (plist-get before :width)))))
           (drag-edge 'right 12 0
                      (lambda (before after)
                        (> (plist-get after :width)
                           (plist-get before :width))))
           (drag-edge 'top 0 (* 2 (max 1 (frame-char-height)))
                      (lambda (before after)
                        (and (> (plist-get after :y) (plist-get before :y))
                             (< (plist-get after :height)
                                (plist-get before :height)))))
           (drag-edge 'bottom 0 (* 2 (max 1 (frame-char-height)))
                      (lambda (before after)
                        (> (plist-get after :height)
                           (plist-get before :height))))
           (drag-edge 'top-left 8 (max 1 (frame-char-height))
                      (lambda (before after)
                        (and (> (plist-get after :x) (plist-get before :x))
                             (> (plist-get after :y) (plist-get before :y))
                             (< (plist-get after :width)
                                (plist-get before :width))
                             (< (plist-get after :height)
                                (plist-get before :height)))))
           (drag-edge 'top-right 8 (max 1 (frame-char-height))
                      (lambda (before after)
                        (and (> (plist-get after :y) (plist-get before :y))
                             (> (plist-get after :width)
                                (plist-get before :width))
                             (< (plist-get after :height)
                                (plist-get before :height)))))
           (drag-edge 'bottom-left 8 (max 1 (frame-char-height))
                      (lambda (before after)
                        (and (> (plist-get after :x) (plist-get before :x))
                             (< (plist-get after :width)
                                (plist-get before :width))
                             (> (plist-get after :height)
                                (plist-get before :height)))))
           (drag-edge 'bottom-right 8 (max 1 (frame-char-height))
                      (lambda (before after)
                        (and (> (plist-get after :width)
                                (plist-get before :width))
                             (> (plist-get after :height)
                                (plist-get before :height))))))))
     (lambda (_context) t))
    (etaf-desktop-gui--action
     "maximize-notes"
     (lambda (context)
       (etaf-desktop-gui--click-ref
        context (etaf-desktop-gui--ref-by-label-within
                 context "Maximize"
                 (intern (format "etaf-desktop-window-%s"
                                 etaf-desktop-gui--notes-window)))))
     (lambda (_context)
       (plist-get (etaf-desktop-gui--window-state etaf-desktop-gui--notes-window)
                  :maximized)))
    (etaf-desktop-gui--action
     "minimize-notes"
     (lambda (context)
       (etaf-desktop-gui--click-ref
        context (etaf-desktop-gui--ref-by-label-within
                 context "Minimize"
                 (intern (format "etaf-desktop-window-%s"
                                 etaf-desktop-gui--notes-window)))))
     (lambda (_context)
       (plist-get (etaf-desktop-gui--window-state etaf-desktop-gui--notes-window)
                  :minimized)))
    (etaf-desktop-gui--action
     "restore-notes-from-taskbar"
     (lambda (context)
       (etaf-desktop-gui--click-ref
        context (etaf-desktop-gui--ref-by-label context "Notes")))
     (lambda (_context)
       ;; A minimized maximized window returns maximized, exactly as the
       ;; taskbar restore contract promises.
       (let ((state (etaf-desktop-gui--window-state etaf-desktop-gui--notes-window)))
         (and (plist-get state :visible)
              (not (plist-get state :minimized))
              (plist-get state :maximized)))))
    (etaf-desktop-gui--action
     "workspace-switch"
     (lambda (context)
       (etaf-desktop-gui--click-ref context (etaf-desktop-gui--ref-by-label context "dev")))
     (lambda (_context)
       (eq (etaf-desktop-active-workspace etaf-desktop-gui--desktop) 'dev)))
    (etaf-desktop-gui--action
     "app-error-isolation"
     (lambda (context)
       (let ((instance (etaf-desktop-launch etaf-desktop-gui--desktop
                                             etaf-desktop-gui--broken-app
                                             :instance-id "desktop-broken-1")))
         (etaf-gui-verifier-context-put context 'broken-instance
                                        (plist-get instance :id))))
     (lambda (context)
       (let ((instance (etaf-desktop-instance
                        etaf-desktop-gui--desktop
                        (etaf-gui-verifier-context-get context 'broken-instance))))
         (and (eq (plist-get instance :status) 'error)
              (plist-get instance :error)
              (string-match-p "intentional Desktop GUI" (buffer-string))))))
    (etaf-desktop-gui--action
     "tiling-layout-and-splitter"
     (lambda (context)
       (unless (fboundp 'etaf-desktop-set-layout-mode)
         (error "Desktop tiling API is unavailable"))
       (etaf-desktop-switch-workspace etaf-desktop-gui--desktop 'main)
       (etaf-desktop-set-layout-mode etaf-desktop-gui--desktop 'tiling 'main)
       (redisplay t)
       (unless (fboundp 'etaf-desktop-layout-resize-split)
         (error "Desktop split resize API is unavailable"))
       (etaf-gui-verifier-context-put
        context 'tiling-tree-before
        (etaf-desktop-layout-tree etaf-desktop-gui--desktop 'main))
       (etaf-desktop-gui--drag-ref
        context (etaf-desktop-gui--ref-by-class context "etaf-splitter-divider")
        0 (* 2 (max 1 (frame-char-height)))))
     (lambda (context)
       (and (eq (etaf-desktop-layout-mode etaf-desktop-gui--desktop 'main) 'tiling)
            (let ((tree (etaf-desktop-layout-tree etaf-desktop-gui--desktop 'main)))
              (and tree (eq (car tree) :split)
                   (not (equal tree
                               (etaf-gui-verifier-context-get
                                context 'tiling-tree-before))))))))))
  )

(defun etaf-desktop-gui-run (run-directory)
  "Run Desktop GUI scenario asynchronously into RUN-DIRECTORY." 
  (interactive "DDesktop GUI evidence directory: ")
  (setq etaf-desktop-gui--run-directory (expand-file-name run-directory))
  (setenv "ETAF_GUI_CAPTURE_PID" (number-to-string (emacs-pid)))
  (run-at-time 0.1 nil
               (lambda ()
                 (etaf-gui-verifier-run
                  (etaf-desktop-gui--scenario)
                  etaf-desktop-gui--run-directory)))
  'scheduled)

(provide 'desktop-gui-scenarios)
;;; desktop-gui-scenarios.el ends here
