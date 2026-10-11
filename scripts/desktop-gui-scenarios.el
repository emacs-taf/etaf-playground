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

(declare-function ebox-viewport-window-width "ebox" (window))

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
  "Return an ETAF View containing literal TEXT for the fixture.

The desktop frame is seamless: its resize strips cover the outermost body row
and columns, so the fixture keeps that margin cell clear of its content."
  (etaf-view (box :width 'stretch :height 'stretch
                  :padding '((lh 0) (ch 2) (lh 1) (ch 2))
               (text (expr text)))))

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
  (let ((entry (cl-find-if
                (lambda (entry)
                  (and (funcall predicate (cdr entry))
                       (etaf-host-ref-position (etaf-desktop-gui--runtime context) (car entry))))
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

(defun etaf-desktop-gui--enter-number (context label value)
  "Activate LABEL and type integer VALUE through CONTEXT's real minibuffer."
  (let ((text (number-to-string value)) received)
    (let ((minibuffer-exit-hook
           (cons (lambda ()
                   (setq received (minibuffer-contents-no-properties)))
                 minibuffer-exit-hook)))
      (minibuffer-with-setup-hook
          (lambda ()
            (delete-minibuffer-contents)
            (setq unread-command-events
                  (append (listify-key-sequence (vconcat text (kbd "RET")))
                          unread-command-events)))
        (etaf-desktop-gui--click-ref
         context (etaf-desktop-gui--ref-by-label context label))))
    (unless (equal text received)
      (error "Desktop %s input did not receive %s" label text))))

(defun etaf-desktop-gui--face-paint (position)
  "Return native face paint at POSITION without generated face identities."
  (let ((faces (get-char-property position 'face)))
    (cl-labels
        ((paint (face &optional seen)
           (cond
            ((null face) nil)
            ((and (listp face) (keywordp (car face))) face)
            ((listp face) (mapcar (lambda (item) (paint item seen)) face))
            ((and (not (memq face seen)) (assq face face-remapping-alist))
             (mapcar (lambda (item) (paint item (cons face seen)))
                     (cdr (assq face face-remapping-alist))))
            ((facep face)
             (mapcar (lambda (attribute)
                       (cons attribute (face-attribute face attribute nil t)))
                     '(:background :foreground :height :family))))))
      (paint faces))))

(defun etaf-desktop-gui--canvas-margin (context)
  "Observe the unobscured left canvas margin's pixels and paint in CONTEXT.
The top workspace bar and bottom taskbar contain focusable controls, so they
are excluded.  A centered modal leaves this margin visible on every row."
  (redisplay t)
  (with-current-buffer (etaf-gui-verifier-context-target-buffer context)
    (let ((window (selected-window)) rows)
      (save-excursion
        (goto-char (point-min))
        (forward-line 1)
        (dotimes (_ (plist-get (etaf-desktop-state etaf-desktop-gui--desktop)
                              :canvas-height))
          (let* ((position (line-beginning-position))
                 (data (and (pos-visible-in-window-p position window)
                            (posn-at-point position window))))
            (unless data (error "Desktop canvas margin is clipped"))
            (push (list (posn-x-y data)
                        (etaf-desktop-gui--face-paint position)) rows))
          (forward-line 1)))
      (list :start (window-start window) :hscroll (window-hscroll window)
            :rows (nreverse rows)))))

(defun etaf-desktop-gui--settings-background-stable-p (context)
  "Require CONTEXT's desktop geometry to stay fixed and its paint to return.
An open modal intentionally dims the shell.  Closing it must restore the
original paint; opening it must not move the surface or stretch any row."
  (let ((before (etaf-gui-verifier-context-get context 'settings-canvas-before))
        (after (etaf-desktop-gui--canvas-margin context)))
    (if (etaf-desktop-settings-open-p etaf-desktop-gui--desktop)
        (and (equal (plist-get before :start) (plist-get after :start))
             (equal (plist-get before :hscroll) (plist-get after :hscroll))
             (equal (mapcar #'car (plist-get before :rows))
                    (mapcar #'car (plist-get after :rows)))
             (not (cl-some
                   (lambda (entry)
                     (etaf-desktop-gui--class-p (cdr entry) "etaf-modal-backdrop"))
                   (etaf-desktop-gui--props-entries context))))
      (equal before after))))

(defun etaf-desktop-gui--settings-geometry (context)
  "Observe CONTEXT's settings panel dimensions and displayed coordinates."
  (redisplay t)
  (let* ((runtime (etaf-desktop-gui--runtime context))
         (ref (etaf-desktop-gui--find-ref
               context (lambda (props)
                         (and (eq (plist-get props :role) 'dialog)
                              (equal (plist-get props :aria-label) "Desktop Settings")
                              (etaf-desktop-gui--class-p props "etaf-floating-panel")))
               "Desktop Settings dialog"))
         (props (etaf-runtime-host-props-for runtime ref))
         (bounds (etaf-host-ref-bounds runtime ref))
         (start (and bounds (car bounds)))
         (end (and bounds (1- (cdr bounds))))
         (window (selected-window))
         (first (and start (pos-visible-in-window-p start window)
                     (posn-at-point start window)))
         (last (and end (pos-visible-in-window-p end window)
                    (posn-at-point end window)))
         (title-bounds
          (and bounds
               (save-excursion
                 (goto-char start)
                 (when (search-forward "Desktop Settings" (cdr bounds) t)
                   (cons (- (point) (length "Desktop Settings")) (point)))))))
    (unless (and first last title-bounds)
      (error "Desktop settings panel or title is clipped"))
    (let ((section
           (cl-find-if
            (lambda (name)
              (etaf-desktop-gui--class-p
               (etaf-runtime-host-props-for
                runtime (intern (format "settings-tab-%s" name))) "secondary"))
            '(appearance layout behavior shortcuts))))
      (unless section (error "Settings has no selected tab"))
      (list :section section
          :width (plist-get props :width) :height (plist-get props :height)
          :gap (plist-get props :item-gap) :padding (plist-get props :padding)
          :first (posn-x-y first) :last (posn-x-y last)
          :rows (1+ (- (line-number-at-pos end) (line-number-at-pos start)))
          :title-rows (1+ (- (line-number-at-pos (1- (cdr title-bounds)))
                            (line-number-at-pos (car title-bounds))))))))

(defun etaf-desktop-gui--settings-compact-p (context)
  "Require the current centered card, with a height fitting its selected tab.
The maintained appearance and layout forms request 18 and 14 rows; the
visible viewport bounds either request without changing the one-row title."
  (let* ((geometry (etaf-desktop-gui--settings-geometry context))
         (window (selected-window))
         (char-width (max 1 (frame-char-width)))
         (line-height (max 1 (frame-char-height)))
         (viewport-width (ebox-viewport-window-width window))
         (viewport-height (window-body-height window))
         (width (min (* 76 char-width) (max 1 (- viewport-width (* 2 char-width)))))
         (requested-height (pcase (plist-get geometry :section)
                             ('appearance 18) ('layout 14) ('behavior 16) ('shortcuts 20)
                             (_ (error "Settings geometry section is not covered"))))
         (height (min requested-height (max 1 (- viewport-height 4))))
         (left (floor (/ (- viewport-width width) 2)))
         (top (* line-height (floor (/ (- viewport-height height) 2))))
         (first (plist-get geometry :first))
         (last (plist-get geometry :last)))
    (etaf-gui-verifier-context-put context 'settings-geometry geometry)
    (and (equal (list 'px width) (plist-get geometry :width))
         (equal (list 'lh height) (plist-get geometry :height))
         (equal '(lh 0) (plist-get geometry :gap))
         (equal '((lh 0) (ch 0)) (plist-get geometry :padding))
         (= height (plist-get geometry :rows))
         (= 1 (plist-get geometry :title-rows))
         (<= (abs (- (car first) left)) char-width)
         (<= (abs (- (cdr first) top)) line-height)
         (<= (abs (- (- (cdr last) (cdr first))
                     (* (1- height) line-height))) line-height)
         (etaf-desktop-gui--settings-background-stable-p context))))

(defun etaf-desktop-gui--settings-gaps-p (context outer inner)
  "Require OUTER and INNER in public settings and CONTEXT's rendered controls."
  (let ((settings (etaf-desktop-settings etaf-desktop-gui--desktop))
        (runtime (etaf-desktop-gui--runtime context)))
    (and (= outer (plist-get settings :tile-outer-gap))
         (= inner (plist-get settings :tile-inner-gap))
         (cl-every
          (lambda (entry)
            (let* ((label (car entry))
                   (ref (etaf-desktop-gui--ref-by-label context label))
                   (bounds (etaf-host-ref-bounds runtime ref))
                   (position (etaf-host-ref-position runtime ref)))
              (and position (pos-visible-in-window-p position)
                   bounds
                   (string-search label (etaf-desktop-gui--text context))
                   (equal (number-to-string (cdr entry))
                          (string-trim (buffer-substring-no-properties
                                        (car bounds) (cdr bounds)))))))
          (list (cons "Outer gap" outer) (cons "Inner gap" inner)))
         (etaf-desktop-gui--settings-compact-p context))))

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
           ;; An empty nonblocking read lets the motion publish before release.
           (events (list (list 'mouse-movement end-data)
                         nil
                         (list 'drag-mouse-1 (event-start press) end-data)))
           ;; Native motion draining may put a boundary event back.  Keep this
           ;; fixture queue separate from unrelated pending command input.
           (unread-command-events nil)
           (command (key-binding (vector press) nil nil position)))
      (unless (commandp command)
        (error "No drag command is bound at Desktop Host %S" ref))
      (cl-letf (((symbol-function 'read-event)
                 (lambda (&optional _prompt _inherit seconds)
                   (cond
                    (unread-command-events (pop unread-command-events))
                    (events (pop events))
                    ((equal seconds 0) nil)
                    (t (error "Desktop drag ended without release"))))))
        (funcall command press))
      (when (or events unread-command-events)
        (error "Desktop drag returned before consuming release")))))

(defun etaf-desktop-gui--window-state (id)
  "Return public state of fixture window ID." 
  (etaf-desktop-window-state etaf-desktop-gui--desktop id))

(defun etaf-desktop-gui--ref-within (context window-ref predicate description)
  "Find a visible semantic descendant of WINDOW-REF matching PREDICATE.
Absolute windows have interleaved buffer ranges, so bounds containment alone
cannot establish ownership of a repeated control label."
  (let* ((runtime (etaf-desktop-gui--runtime context))
         (candidates (cl-remove-if-not
                      (lambda (entry) (funcall predicate (cdr entry)))
                      (etaf-desktop-gui--props-entries context)))
         (ancestries (etaf-runtime-host-ancestries
                      runtime (cons window-ref (mapcar #'car candidates))))
         (owner (car (gethash window-ref ancestries))))
    (unless owner (error "Desktop window Host is absent: %s" window-ref))
    (or (cl-loop for (ref . _props) in candidates
                 when (and (member owner (gethash ref ancestries))
                           (etaf-host-ref-position runtime ref)) return ref)
        (error "Desktop window %s has no visible %s" window-ref description))))

(defun etaf-desktop-gui--ref-by-label-within (context label window-ref)
  "Find the visible Host labelled LABEL inside WINDOW-REF's semantic subtree."
  (etaf-desktop-gui--ref-within
   context window-ref
   (lambda (props)
     (or (equal label (plist-get props :aria-label))
         (equal label (plist-get props :label))
         (equal label (plist-get props :text))))
   label))

(defun etaf-desktop-gui--title-ref (context title)
  "Find TITLE's visible chrome through its owning window's semantic subtree.
The workspace status and taskbar repeat window titles.  Text search cannot
identify a title bar, and the chrome Host has no `:text' property of its own."
  (let* ((desktop etaf-desktop-gui--desktop)
         (active (etaf-desktop-active-window desktop))
         (windows (cl-remove-if-not
                   (lambda (window) (equal title (plist-get window :title)))
                   (etaf-desktop-windows desktop)))
         (window (or (cl-find active windows
                              :key (lambda (item) (plist-get item :id)) :test #'equal)
                     (cl-find-if
                      (lambda (item)
                        (and (plist-get item :visible)
                             (not (plist-get item :minimized))
                             (equal (plist-get item :workspace)
                                    (etaf-desktop-active-workspace desktop))))
                      windows))))
    (unless window (error "No visible Desktop window has title: %s" title))
    (etaf-desktop-gui--ref-within
     context (intern (format "etaf-desktop-window-%s" (plist-get window :id)))
     (lambda (props)
       (etaf-desktop-gui--class-p props "etaf-window-chrome"))
     (format "%s title bar" title))))

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

(defun etaf-desktop-gui--line-height-baseline (context)
  "Measure ordinary host text in CONTEXT before mounting any Desktop content.
Use the actual frame, buffer faces and user line spacing.  No font, spacing,
animation or GC setting is changed to establish the reference."
  (let ((buffer (etaf-gui-verifier-context-target-buffer context))
        (window (selected-window)))
    (when-let* ((runtime (etaf-runtime-for-buffer buffer)))
      (etaf-unmount runtime))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert "Agpq 0123456789\nAgpq 0123456789\nAgpq 0123456789\n")
        (goto-char (point-min))
        (set-window-start window (point-min))
        (redisplay t)
        (let ((line (window-line-height 1 window)))
          (unless (and line (> (car line) 0) (= (nth 3 line) 0))
            (error "Cannot observe a complete standard Emacs text row"))
          (etaf-gui-verifier-context-put context 'standard-line-height (car line))
          (etaf-gui-verifier-context-put context 'standard-line-spacing line-spacing))
        (erase-buffer)
        (set-buffer-modified-p nil)))))

(defun etaf-desktop-gui--physical-rows-standard-p (context)
  "Require every visible physical row to fit CONTEXT's standard Emacs row.
Dedicated thin border rows may be shorter; they never raise the text-row
limit.  Include off-window pixels when a row is clipped at a viewport edge."
  (let ((baseline (etaf-gui-verifier-context-get context 'standard-line-height))
        (window (selected-window)) heights)
    (unless (and baseline
                 (eq (window-buffer window)
                     (etaf-gui-verifier-context-target-buffer context)))
      (error "Physical row acceptance has no matching native text baseline"))
    (redisplay t)
    (dotimes (index (window-body-height window))
      (when-let* ((line (window-line-height index window)))
        (let ((height (+ (car line) (nth 3 line) (max 0 (- (nth 2 line))))))
          (push height heights)
          (when (> height baseline)
            (error "Desktop physical row %d is %d px; standard text with user spacing is %d px"
                   index height baseline)))))
    (unless heights (error "No physical Desktop rows could be measured"))
    (etaf-gui-verifier-context-put context 'physical-row-count (length heights))
    (etaf-gui-verifier-context-put context 'physical-row-heights
                                   (sort (delete-dups heights) #'<))
    t))

(defun etaf-desktop-gui--window-anchor-y (context)
  "Record visible window chrome Hosts in CONTEXT using physical pixel Y.
Store both the semantic Host cell and its physical line start, independently
of application x/y fields and of serialized buffer positions."
  (let ((runtime (etaf-desktop-gui--runtime context))
        (window (selected-window)) anchors)
    (redisplay t)
    (with-current-buffer (etaf-gui-verifier-context-target-buffer context)
      (dolist (entry (etaf-desktop-gui--props-entries context))
        (when (etaf-desktop-gui--class-p (cdr entry) "etaf-window-chrome")
          (when-let* ((position (etaf-host-ref-position runtime (car entry)))
                      ((pos-visible-in-window-p position window))
                      (cell (posn-at-point position window))
                      (row (save-excursion
                             (goto-char position)
                             (posn-at-point (line-beginning-position) window))))
            (push (list (car entry) :host-y (cdr (posn-x-y cell))
                        :row-y (cdr (posn-x-y row))) anchors)))))
    anchors))

(defun etaf-desktop-gui--anchor-y-unchanged-p (context before minimum)
  "Check physical pixel Y of BEFORE's still-visible Hosts in CONTEXT.
Require at least MINIMUM independent anchors, so complete occlusion cannot
silently pass the stationary-neighbor check."
  (let ((after (etaf-desktop-gui--window-anchor-y context)) (count 0))
    (dolist (old before)
      (when-let* ((current (assoc (car old) after)))
        (unless (equal (cdr old) (cdr current))
          (error "Unmoved Desktop Host %s jumped in pixels: %s -> %s"
                 (car old) (cdr old) (cdr current)))
        (cl-incf count)))
    (unless (>= count minimum)
      (error "Stationary-neighbor check needs %d visible Hosts; observed %d" minimum count))
    (etaf-gui-verifier-context-put context 'stable-host-y-count count)
    (etaf-desktop-gui--physical-rows-standard-p context)))

(defun etaf-desktop-gui--settings-tabs-keep-native-rows (context)
  "Exercise every Settings tab while checking native rows and neighbor Y."
  (let ((anchors (etaf-desktop-gui--window-anchor-y context)))
    (etaf-desktop-gui--click-ref
     context (etaf-desktop-gui--ref-by-symbol context 'etaf-workspace-settings))
    (dolist (section '(appearance layout behavior shortcuts appearance))
      (etaf-desktop-gui--click-ref
       context (etaf-desktop-gui--ref-by-symbol
                context (intern (format "settings-tab-%s" section))))
      (unless (etaf-desktop-settings-open-p etaf-desktop-gui--desktop)
        (error "Settings closed while selecting tab %s" section))
      (etaf-desktop-gui--anchor-y-unchanged-p context anchors 1)
      (let ((geometry (etaf-desktop-gui--settings-geometry context)))
        (unless (and (eq (plist-get geometry :section) section)
                     (= (plist-get geometry :title-rows) 1))
          (error "Settings tab %s lost its selection or single-row title" section))))
    (etaf-desktop-gui--click-ref
     context (etaf-desktop-gui--ref-by-label context "Done"))
    (etaf-desktop-gui--anchor-y-unchanged-p context anchors 1)))

(defun etaf-desktop-gui--invariants (context)
  "Return generic Desktop invariants for each verifier checkpoint." 
  (let ((mounted (etaf-gui-verifier-context-get context 'expects-mounted)))
    (list
   (etaf-gui-verifier-assert "desktop-no-asynchronous-errors"
                             (etaf-desktop-gui--messages-clean-p context))
   (etaf-gui-verifier-assert "desktop-standard-physical-line-height"
                             (or (not mounted)
                                 (etaf-desktop-gui--physical-rows-standard-p context)))
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

(defun etaf-desktop-gui--adapter (context)
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
     (cons 'standard_line_height_px
           (etaf-gui-verifier-context-get context 'standard-line-height))
     (cons 'standard_line_spacing
           (etaf-gui-verifier-context-get context 'standard-line-spacing))
     (cons 'physical_row_count
           (etaf-gui-verifier-context-get context 'physical-row-count))
     (cons 'physical_row_heights_px
           (vconcat (etaf-gui-verifier-context-get context 'physical-row-heights)))
     (cons 'stable_host_y_count
           (etaf-gui-verifier-context-get context 'stable-host-y-count))
     (cons 'settings_open (and (etaf-desktop-settings-open-p desktop) t))
     (cons 'tile_outer_gap (plist-get (etaf-desktop-settings desktop) :tile-outer-gap))
     (cons 'tile_inner_gap (plist-get (etaf-desktop-settings desktop) :tile-inner-gap))
     (cons 'settings_geometry
           (when-let* ((geometry (etaf-gui-verifier-context-get
                                  context 'settings-geometry)))
             (list (cons 'width (format "%S" (plist-get geometry :width)))
                   (cons 'height (format "%S" (plist-get geometry :height)))
                   (cons 'first (vconcat (list (car (plist-get geometry :first))
                                              (cdr (plist-get geometry :first)))))
                   (cons 'last (vconcat (list (car (plist-get geometry :last))
                                             (cdr (plist-get geometry :last)))))
                   (cons 'rows (plist-get geometry :rows))
                   (cons 'title_rows (plist-get geometry :title-rows)))))
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
     (etaf-desktop-gui--messages-start context)
     (let ((desktop (etaf-desktop-gui--prepare)))
       (etaf-gui-verifier-context-put context 'desktop desktop)
       (etaf-gui-verifier-context-put context 'expects-mounted nil)
       ;; Generic verifier assertions require a selected target even before
       ;; the first mount action.  This is an intentionally unmounted, empty
       ;; buffer; the action below mounts the prepared desktop into it.
       (etaf-gui-verifier-context-select-buffer
        context (get-buffer-create etaf-desktop-gui--buffer))
       (etaf-desktop-gui--line-height-baseline context)))
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
     "settings-modal-is-compact-and-preserves-desktop"
     (lambda (context)
       (etaf-gui-verifier-context-put
        context 'settings-canvas-before (etaf-desktop-gui--canvas-margin context))
       (etaf-desktop-gui--click-ref
        context (etaf-desktop-gui--ref-by-symbol
                 context 'etaf-workspace-settings)))
     (lambda (context)
       (and (etaf-desktop-settings-open-p etaf-desktop-gui--desktop)
            (string-match-p "Desktop Settings" (buffer-string))
            (string-match-p "Notes\\|Files" (buffer-string))
            (etaf-desktop-gui--settings-compact-p context))))
    (etaf-desktop-gui--action
     "settings-layout-tab-shows-default-gaps"
     (lambda (context)
       (etaf-desktop-gui--click-ref
        context (etaf-desktop-gui--ref-by-symbol context 'settings-tab-layout)))
     (lambda (context) (etaf-desktop-gui--settings-gaps-p context 1 1)))
    (etaf-desktop-gui--action
     "settings-gaps-accept-minimum-native-input"
     (lambda (context)
       (etaf-desktop-gui--enter-number context "Outer gap" 0)
       (etaf-desktop-gui--enter-number context "Inner gap" 1))
     (lambda (context) (etaf-desktop-gui--settings-gaps-p context 0 1)))
    (etaf-desktop-gui--action
     "settings-gaps-accept-maximum-native-input"
     (lambda (context)
       (etaf-desktop-gui--enter-number context "Outer gap" 4)
       (etaf-desktop-gui--enter-number context "Inner gap" 4))
     (lambda (context) (etaf-desktop-gui--settings-gaps-p context 4 4)))
    (etaf-desktop-gui--action
     "settings-modal-closes-and-restores-surface"
     (lambda (context)
       (etaf-desktop-gui--click-ref
        context (etaf-desktop-gui--ref-by-label context "Done")))
     (lambda (context)
       (and (not (etaf-desktop-settings-open-p etaf-desktop-gui--desktop))
            (string-match-p "Notes\\|Files" (buffer-string))
            (etaf-desktop-gui--settings-background-stable-p context))))
    (etaf-desktop-gui--action
     "settings-gaps-persist-when-reopened"
     (lambda (context)
       (etaf-desktop-gui--click-ref
        context (etaf-desktop-gui--ref-by-symbol context 'etaf-workspace-settings))
       (etaf-desktop-gui--click-ref
        context (etaf-desktop-gui--ref-by-symbol context 'settings-tab-layout)))
     (lambda (context) (etaf-desktop-gui--settings-gaps-p context 4 4)))
    (etaf-desktop-gui--action
     "settings-reset-restores-default-gaps"
     (lambda (context)
       (etaf-desktop-gui--click-ref
        context (etaf-desktop-gui--ref-by-label context "Reset settings")))
     (lambda (context) (etaf-desktop-gui--settings-gaps-p context 1 1)))
    (etaf-desktop-gui--action
     "settings-dismiss-returns-focus-and-preserves-desktop"
     (lambda (_context) (execute-kbd-macro (kbd "<escape>")))
     (lambda (context)
       (and (not (etaf-desktop-settings-open-p etaf-desktop-gui--desktop))
            (equal 'etaf-workspace-settings
                   (etaf-focused-host-ref (etaf-desktop-gui--runtime context)))
            (etaf-desktop-gui--settings-background-stable-p context))))
    (etaf-desktop-gui--action
     "settings-all-tabs-preserve-native-rows-and-neighbor-y"
     #'etaf-desktop-gui--settings-tabs-keep-native-rows
     (lambda (context)
       (and (not (etaf-desktop-settings-open-p etaf-desktop-gui--desktop))
            (etaf-desktop-gui--physical-rows-standard-p context))))
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
                 context "Zoom"
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
            (not (etaf-desktop-window-maximized-p
                  etaf-desktop-gui--desktop etaf-desktop-gui--notes-window))
            (with-current-buffer (etaf-gui-verifier-context-target-buffer context)
              (and (string-match-p "ETAF Notes application" (buffer-string))
                   (string-match-p "ETAF Files application" (buffer-string))))
            (let ((tree (etaf-desktop-layout-tree etaf-desktop-gui--desktop 'main)))
              (and tree (eq (car tree) :split)
                   (not (equal tree
                               (etaf-gui-verifier-context-get
                                context 'tiling-tree-before))))))))
    (etaf-desktop-gui--action
     "focus-files-tile-by-title"
     (lambda (context)
       (etaf-desktop-gui--click-ref
        context (etaf-desktop-gui--title-ref context "Files")))
     (lambda (_context)
       (equal etaf-desktop-gui--files-window
              (etaf-desktop-active-window etaf-desktop-gui--desktop))))
    (etaf-desktop-gui--action
     "layout-control-roundtrip"
     (lambda (context)
       (etaf-desktop-gui--click-ref
        context (etaf-desktop-gui--ref-by-symbol context 'etaf-workspace-layout))
       (unless (eq 'floating
                   (etaf-desktop-layout-mode etaf-desktop-gui--desktop 'main))
         (error "Desktop layout control did not switch to floating"))
       (etaf-desktop-gui--click-ref
        context (etaf-desktop-gui--ref-by-symbol context 'etaf-workspace-layout)))
     (lambda (context)
       (and (eq 'tiling (etaf-desktop-layout-mode etaf-desktop-gui--desktop 'main))
            (with-current-buffer (etaf-gui-verifier-context-target-buffer context)
              (and (string-match-p "ETAF Notes application" (buffer-string))
                   (string-match-p "ETAF Files application" (buffer-string)))))))
    (etaf-desktop-gui--action
     "close-notes-and-focus-files"
     (lambda (context)
       (etaf-desktop-gui--click-ref
        context (etaf-desktop-gui--title-ref context "Notes"))
       (etaf-desktop-gui--click-ref
        context (etaf-desktop-gui--ref-by-label-within
                 context "Close"
                 (intern (format "etaf-desktop-window-%s"
                                 etaf-desktop-gui--notes-window)))))
     (lambda (context)
       (and (equal etaf-desktop-gui--files-window
                   (etaf-desktop-active-window etaf-desktop-gui--desktop))
            (not (cl-find etaf-desktop-gui--notes-window
                          (etaf-desktop-windows etaf-desktop-gui--desktop)
                          :key (lambda (window) (plist-get window :id))
                          :test #'equal))
            (with-current-buffer (etaf-gui-verifier-context-target-buffer context)
              (string-match-p "ETAF Files application" (buffer-string))))))
    (etaf-desktop-gui--action
     "post-close-workspace-isolation"
     (lambda (context)
       (etaf-gui-verifier-context-put context 'post-close-ready nil)
       (run-at-time
        1 nil
        (lambda ()
          (etaf-gui-verifier-context-put context 'post-close-ready t))))
     (lambda (context)
       (and (etaf-gui-verifier-context-get context 'post-close-ready)
            (eq 'main (etaf-desktop-active-workspace etaf-desktop-gui--desktop))
            (let* ((instance (etaf-desktop-instance
                              etaf-desktop-gui--desktop
                              (etaf-gui-verifier-context-get context 'broken-instance)))
                   (error-window (car (plist-get instance :windows))))
              (eq 'dev (plist-get
                        (etaf-desktop-window-state
                         etaf-desktop-gui--desktop error-window)
                        :workspace)))
            (with-current-buffer (etaf-gui-verifier-context-target-buffer context)
              (and (string-match-p "ETAF Files application" (buffer-string))
                   (not (string-match-p "intentional Desktop GUI launch failure"
                                        (buffer-string)))
                   (not (string-match-p "ETAF app error" (buffer-string))))))))
    (etaf-desktop-gui--action
     "error-window-joins-tiling-with-title"
     (lambda (context)
       (let* ((instance (etaf-desktop-launch
                         etaf-desktop-gui--desktop etaf-desktop-gui--broken-app))
              (id (car (plist-get instance :windows)))
              (runtime (etaf-desktop-gui--runtime context))
              (chrome (intern (format "etaf-desktop-chrome-%s" id)))
              (position (etaf-host-ref-position runtime chrome)))
         (etaf-gui-verifier-context-put context 'new-error-window id)
         (unless (and position
                      (with-current-buffer
                          (etaf-gui-verifier-context-target-buffer context)
                        (save-excursion
                          (goto-char position)
                          (string-match-p
                           "ETAF app error"
                           (buffer-substring-no-properties
                            (line-beginning-position) (line-end-position))))))
           (error "Tiled error window title row is covered"))
         (etaf-desktop-focus-window
          etaf-desktop-gui--desktop etaf-desktop-gui--files-window)
         (etaf-desktop-gui--click-ref
          context
          (etaf-desktop-gui--title-ref
           context "ETAF app error: etaf-desktop-gui-broken"))))
     (lambda (context)
       (let* ((id (etaf-gui-verifier-context-get context 'new-error-window))
              (files (etaf-desktop-gui--window-state
                      etaf-desktop-gui--files-window))
              (error-window (etaf-desktop-gui--window-state id)))
         (and (eq 'main (etaf-desktop-active-workspace
                         etaf-desktop-gui--desktop))
              (equal id (etaf-desktop-active-window
                         etaf-desktop-gui--desktop))
              (= (1+ (+ (plist-get files :y) (plist-get files :height)))
                 (plist-get error-window :y))
              (with-current-buffer
                  (etaf-gui-verifier-context-target-buffer context)
                (and (string-match-p "ETAF Files application" (buffer-string))
                     (string-match-p "intentional Desktop GUI launch failure"
                                     (buffer-string))))))))
)))

(defconst etaf-desktop-gui--demo-titles
  '("Notes" "Tasks" "Clock" "Chat" "Monitor" "Calculator")
  "Real applications required by the demo acceptance scenario.")

(defun etaf-desktop-gui--messages-start (context)
  "Start observing new asynchronous errors for CONTEXT."
  (etaf-gui-verifier-context-put
   context 'messages-start
   (with-current-buffer (get-buffer-create "*Messages*")
     (copy-marker (point-max)))))

(defun etaf-desktop-gui--messages-clean-p (context)
  "Reject new timer and rendering errors, including errors outside the surface."
  (let ((marker (etaf-gui-verifier-context-get context 'messages-start)))
    (when (and (markerp marker) (marker-buffer marker))
      (with-current-buffer (marker-buffer marker)
        (save-excursion
          (goto-char marker)
          (when (re-search-forward
                 "Error running timer\\|Error during redisplay\\|could not render\\|runtime error\\|Wrong type argument\\|Lisp nesting exceeds\\|Variable binding depth exceeds"
                 nil t)
            (error "Desktop asynchronous error: %s"
                   (buffer-substring-no-properties
                    (line-beginning-position)
                    (min (line-end-position) (+ (line-beginning-position) 400))))))))
    t))

(defun etaf-desktop-gui--text (context)
  "Return CONTEXT's displayed text without cyclic ownership properties."
  (with-current-buffer (etaf-gui-verifier-context-target-buffer context)
    (buffer-substring-no-properties (point-min) (point-max))))

(defun etaf-desktop-gui--demo-window (title)
  "Find the live demo window with TITLE through the public window snapshot."
  (or (cl-find title (etaf-desktop-windows etaf-desktop-gui--desktop)
               :key (lambda (window) (plist-get window :title)) :test #'equal)
      (error "Demo application window is missing: %s" title)))

(defun etaf-desktop-gui--demo-ref (title)
  "Return the public window Host reference for TITLE."
  (intern (format "etaf-desktop-window-%s"
                  (plist-get (etaf-desktop-gui--demo-window title) :id))))

(defun etaf-desktop-gui--demo-taskbar (context title)
  "Activate TITLE's actual taskbar control, including cross-workspace restore."
  (etaf-desktop-gui--click-ref
   context
   (etaf-desktop-gui--find-ref
    context (lambda (props)
              (and (equal title (plist-get props :aria-label))
                   (etaf-desktop-gui--class-p props "etaf-taskbar-item"))) title))
  (unless (equal (plist-get (etaf-desktop-gui--demo-window title) :id)
                 (etaf-desktop-active-window etaf-desktop-gui--desktop))
    (error "Taskbar did not activate %s" title)))

(defun etaf-desktop-gui--demo-click (context title label)
  "Press the real LABEL control in the currently visible TITLE window."
  (etaf-desktop-gui--click-ref
   context (etaf-desktop-gui--ref-by-label-within
            context label (etaf-desktop-gui--demo-ref title))))

(defun etaf-desktop-gui--demo-full (context title)
  "Focus TITLE and maximize through its chrome to expose application controls."
  (etaf-desktop-gui--demo-taskbar context title)
  (unless (plist-get (etaf-desktop-gui--demo-window title) :maximized)
    (etaf-desktop-gui--demo-click context title "Zoom")))

(defun etaf-desktop-gui--demo-input (context title label text)
  "Type TEXT into TITLE's LABEL control through its native minibuffer."
  (let (received)
    (let ((minibuffer-exit-hook
           (cons (lambda () (setq received (minibuffer-contents-no-properties)))
                 minibuffer-exit-hook)))
      (minibuffer-with-setup-hook
          (lambda ()
            (delete-minibuffer-contents)
            (setq unread-command-events
                  (append (listify-key-sequence (vconcat text (kbd "RET")))
                          unread-command-events)))
        (etaf-desktop-gui--demo-click context title label)))
    (unless (equal received text)
      (error "Demo %s input did not receive its text" label))))

(defun etaf-desktop-gui--require-text (context text &optional absent)
  "Require displayed TEXT in CONTEXT, or its absence when ABSENT is non-nil."
  (unless (eq (not (null (string-search text (etaf-desktop-gui--text context))))
              (not absent))
    (error "Demo text %s: %s" (if absent "unexpected" "missing") text)))

(defun etaf-desktop-gui--demo-rectangle (title)
  "Return TITLE's observable rectangle."
  (let ((state (etaf-desktop-gui--demo-window title)))
    (mapcar (lambda (key) (plist-get state key)) '(:x :y :width :height))))

(defun etaf-desktop-gui--demo-launch (context title app)
  "Launch APP from its real launcher control and require TITLE to exist."
  (etaf-desktop-gui--click-ref
   context (etaf-desktop-gui--ref-by-symbol context 'etaf-taskbar-launcher))
  (etaf-desktop-gui--click-ref
   context (etaf-desktop-gui--ref-by-symbol
            context (intern (format "etaf-desktop-launcher-%s" app))))
  (etaf-desktop-gui--demo-window title))

(defun etaf-desktop-gui--demo-lifecycle (context title)
  "Exercise TITLE's chrome, taskbar and launcher across one complete lifecycle."
  (etaf-desktop-gui--demo-taskbar context title)
  (when (plist-get (etaf-desktop-gui--demo-window title) :maximized)
    (etaf-desktop-gui--demo-click context title "Zoom"))
  (let* ((window (etaf-desktop-gui--demo-window title))
         (id (plist-get window :id))
         (rect (etaf-desktop-gui--demo-rectangle title))
         (instance (cl-find-if
                    (lambda (item) (member id (plist-get item :windows)))
                    (etaf-desktop-instances etaf-desktop-gui--desktop)))
         (app (plist-get instance :app-id)))
    (etaf-desktop-gui--demo-click context title "Minimize")
    (unless (and (plist-get (etaf-desktop-gui--demo-window title) :minimized)
                 (not (equal id (etaf-desktop-active-window etaf-desktop-gui--desktop))))
      (error "%s did not minimize and release focus" title))
    (etaf-desktop-gui--demo-taskbar context title)
    (unless (equal rect (etaf-desktop-gui--demo-rectangle title))
      (error "%s did not restore its normal rectangle" title))
    (etaf-desktop-gui--demo-click context title "Zoom")
    (unless (plist-get (etaf-desktop-gui--demo-window title) :maximized)
      (error "%s did not maximize" title))
    (etaf-desktop-gui--demo-click context title "Minimize")
    (etaf-desktop-gui--click-ref
     context (etaf-desktop-gui--ref-by-symbol
              context (if (eq (plist-get window :workspace) 'main)
                          'etaf-workspace-work 'etaf-workspace-main)))
    (etaf-desktop-gui--demo-taskbar context title)
    (unless (and (plist-get (etaf-desktop-gui--demo-window title) :maximized)
                 (eq (plist-get window :workspace)
                     (etaf-desktop-active-workspace etaf-desktop-gui--desktop)))
      (error "%s lost maximization on cross-workspace restore" title))
    (etaf-desktop-gui--demo-click context title "Zoom")
    (unless (equal rect (etaf-desktop-gui--demo-rectangle title))
      (error "%s lost its normal rectangle after maximization" title))
    (etaf-desktop-gui--demo-click context title "Close")
    (when (cl-find id (etaf-desktop-windows etaf-desktop-gui--desktop)
                   :key (lambda (item) (plist-get item :id)) :test #'equal)
      (error "%s did not close" title))
    (etaf-desktop-gui--demo-launch context title app)
    (unless (= 6 (length (etaf-desktop-windows etaf-desktop-gui--desktop)))
      (error "Closing and reopening %s changed demo membership" title))))

(defun etaf-desktop-gui--demo-class-ref (context title class)
  "Find visible CLASS inside TITLE through public semantic Host ancestry."
  (etaf-desktop-gui--ref-within
   context (etaf-desktop-gui--demo-ref title)
   (lambda (props) (etaf-desktop-gui--class-p props class)) class))

(defun etaf-desktop-gui--ref-text (context ref)
  "Return the displayed text belonging to public Host REF in CONTEXT."
  (let ((bounds (etaf-host-ref-bounds (etaf-desktop-gui--runtime context) ref)))
    (unless bounds (error "Demo Host is not rendered: %s" ref))
    (with-current-buffer (etaf-gui-verifier-context-target-buffer context)
      (buffer-substring-no-properties (car bounds) (cdr bounds)))))

(defun etaf-desktop-gui--demo-clock-text (context)
  "Return the displayed Clock time without inspecting Component state."
  (let ((text (etaf-desktop-gui--ref-text
               context (etaf-desktop-gui--demo-class-ref
                        context "Clock" "etaf-window-content"))))
    (when (string-match "\\b[0-2][0-9]:[0-5][0-9]:[0-5][0-9]\\b" text)
      (match-string 0 text))))

(defun etaf-desktop-gui--demo-wait-action (id prepare verify)
  "Wait across real periodic callbacks after PREPARE, then VERIFY once settled."
  (etaf-desktop-gui--action
   id
   (lambda (context)
     (funcall prepare context)
     (etaf-gui-verifier-context-put context 'demo-wait-until (+ (float-time) 2.2)))
   (lambda (context)
     (and (etaf-desktop-gui--messages-clean-p context)
          (>= (float-time) (etaf-gui-verifier-context-get context 'demo-wait-until))
          (funcall verify context)))))

(defun etaf-desktop-gui--demo-open (context)
  "Mount the real public demo and bind CONTEXT to its fresh dedicated buffer."
  (setq etaf-desktop-gui--desktop (etaf-desktop-demo-open etaf-desktop-gui--buffer))
  (etaf-gui-verifier-context-select-buffer context (get-buffer etaf-desktop-gui--buffer))
  (etaf-gui-verifier-context-put context 'desktop etaf-desktop-gui--desktop)
  (etaf-gui-verifier-context-put context 'expects-mounted t)
  (setq etaf-desktop-gui--notes-window
        (plist-get (etaf-desktop-gui--demo-window "Notes") :id)))

(defun etaf-desktop-gui--key (keys)
  "Exercise KEYS through the selected Desktop buffer's actual command map."
  (execute-kbd-macro (kbd keys)))

(defun etaf-desktop-gui--demo-two-panes (context)
  "Prepare Notes and Tasks as the only visible main-workspace panes.
All windows remain mounted; notably the hidden Clock keeps its real timer."
  (dolist (title '("Clock" "Chat"))
    (etaf-desktop-gui--demo-taskbar context title)
    (etaf-desktop-gui--key "i")
    (unless (plist-get (etaf-desktop-gui--demo-window title) :minimized)
      (error "Shortcut i did not minimize %s" title)))
  (dolist (title '("Tasks" "Notes"))
    (etaf-desktop-gui--demo-taskbar context title)
    (etaf-desktop-gui--key "r"))
  (let ((first (plist-get (etaf-desktop-gui--demo-window "Notes") :id))
        (second (plist-get (etaf-desktop-gui--demo-window "Tasks") :id)))
    (etaf-desktop-set-layout-mode etaf-desktop-gui--desktop 'floating)
    ;; Make s observably replace a vertical split with a horizontal split.
    ;; These public APIs prepare input; s itself must traverse the buffer map.
    (etaf-desktop-layout-set-tree
     etaf-desktop-gui--desktop
     (list :split 'vertical 0.4 (list :leaf first) (list :leaf second)))
    (etaf-desktop-gui--key "s")
    (unless (equal (list :split 'horizontal 0.5
                        (list :leaf first) (list :leaf second))
                   (etaf-desktop-layout-tree etaf-desktop-gui--desktop))
      (error "Shortcut s did not split the two visible panes; hidden windows must be excluded"))
    (unless (eq 'tiling (etaf-desktop-layout-mode etaf-desktop-gui--desktop))
      (error "Shortcut s did not enter tiling"))))

(defvar etaf-desktop-gui--last-drag-evidence nil
  "Bounded native event facts from the latest GUI drag, without event objects.")

(defun etaf-desktop-gui--native-motion-sequence (context ref offsets observe)
  "Drag actual Host REF over pixel OFFSETS, checking every published motion.
OBSERVE receives each offset after a separate event/redisplay turn.  Nil reads
separate native motion batches; no direct drag callback or layout setter is
used for the tested motion, and release comes through the native drag keymap."
  (let* ((runtime (etaf-desktop-gui--runtime context))
         (position (etaf-host-ref-position runtime ref))
         (data (etaf-desktop-gui--mouse-data position))
         (xy (posn-x-y data))
         (press (list 'down-mouse-1 data))
         (command (key-binding (vector press) nil nil position))
         (active (etaf-desktop-active-window etaf-desktop-gui--desktop))
         (native-read-event (symbol-function 'read-event))
         (unread-command-events nil)
         queue reads observed)
    (setq etaf-desktop-gui--last-drag-evidence nil)
    (unless (commandp command) (error "Splitter has no native drag binding"))
    (dolist (offset offsets)
      (let ((target (list (posn-window data) (posn-point data)
                          (cons (+ (car xy) (car offset))
                                (+ (cdr xy) (cdr offset)))
                          1)))
        (setq queue (append queue (list (list 'mouse-movement target)
                                        nil (cons 'checkpoint offset))))))
    (let* ((last (car (last offsets)))
           (end (list (posn-window data) (posn-point data)
                      (cons (+ (car xy) (car last)) (+ (cdr xy) (cdr last))) 1)))
      (setq queue (append queue (list (list 'drag-mouse-1 data end)))))
    (cl-letf (((symbol-function 'read-event)
               (lambda (&optional _prompt _inherit seconds)
                 (when (eq (car-safe (car queue)) 'checkpoint)
                   (let ((offset (cdr (pop queue))))
                     ;; `sit-for' itself calls `read-event' in a graphical
                     ;; Emacs.  Its wait must use the native reader; otherwise
                     ;; it consumes the next scripted motion and requeues `t'.
                     (cl-letf (((symbol-function 'read-event) native-read-event))
                       (sit-for 0.02)
                       (redisplay t))
                     (push offset observed)
                     (funcall observe offset)))
                 (let ((next
                        (cond (unread-command-events (pop unread-command-events))
                              (queue (pop queue))
                              ((equal seconds 0) nil)
                              (t (error "Splitter gesture exhausted its native events")))))
                   (push (list seconds (and next (event-basic-type next))
                               (and (mouse-event-p next) (posn-x-y (event-start next)))
                               (window-start (selected-window))
                               (etaf-host-ref-position runtime ref)) reads)
                   next))))
      (unwind-protect
          (funcall command press)
        (setq etaf-desktop-gui--last-drag-evidence
              (list :reads (nreverse reads) :observed (nreverse observed)
                    :remaining (mapcar (lambda (item) (if (consp item) (car item) item)) queue)
                    :unread (mapcar #'event-basic-type unread-command-events)
                    :target-position (etaf-host-ref-position runtime ref)
                    :tree (etaf-desktop-layout-tree etaf-desktop-gui--desktop)))))
    (when (or queue unread-command-events)
      (error "Splitter did not consume its release: %S" etaf-desktop-gui--last-drag-evidence))
    (funcall observe (car (last offsets)))
    (unless (equal active (etaf-desktop-active-window etaf-desktop-gui--desktop))
      (error "Splitter gesture changed the active application"))
    (when (ebox-selector-query-buffer (etaf-runtime-buffer runtime) ":active")
      (error "Splitter release left an active input target"))))

(defun etaf-desktop-gui--splitter-check (orientation before ratio offset bounded)
  "Check both pane geometries after one native split OFFSET from BEFORE.
RATIO is the starting split ratio.  BOUNDED permits minimum-size clamping
while still requiring the ratio policy and the shared pane edges to agree."
  (let* ((horizontal (eq orientation 'horizontal))
         (axis (if horizontal :x :y))
         (size (if horizontal :width :height))
         (cross (if horizontal :y :x))
         (cross-size (if horizontal :height :width))
         (a (etaf-desktop-gui--demo-window "Notes"))
         (b (etaf-desktop-gui--demo-window "Tasks"))
         (old-a (car before)) (old-b (cadr before))
         (span (+ (plist-get old-a size) (plist-get old-b size)))
         (delta (if horizontal (round (car offset))
                  (round (/ (cdr offset) (float (frame-char-height))))))
         (requested (* ratio span))
         ;; Ordinary allocation rounds at most half a layout unit.  A size
         ;; constraint instead makes the actually displayed edge the origin
         ;; of the next gesture, as the Desktop interaction contract specifies.
         (origin (if (<= (abs (- (plist-get old-a size) requested)) 0.500001)
                     requested (plist-get old-a size)))
         (expected (if (zerop delta) ratio
                     (/ (float (max 1 (min (1- span) (+ origin delta)))) span)))
         (tree (etaf-desktop-layout-tree etaf-desktop-gui--desktop))
         (gap (- (plist-get old-b axis) (plist-get old-a axis) (plist-get old-a size))))
    (unless (and (eq (nth 1 tree) orientation)
                 (< (abs (- (nth 2 tree) expected)) 0.000001)
                 (equal (nth 3 tree) (list :leaf (plist-get a :id)))
                 (equal (nth 4 tree) (list :leaf (plist-get b :id)))
                 (= (plist-get a axis) (plist-get old-a axis))
                 (= (+ (plist-get a size) (plist-get b size)) span)
                 (= (- (plist-get b axis) (plist-get a axis) (plist-get a size)) gap)
                 (= (+ (plist-get b axis) (plist-get b size))
                    (+ (plist-get old-b axis) (plist-get old-b size)))
                 (= (plist-get a cross) (plist-get old-a cross))
                 (= (plist-get b cross) (plist-get old-b cross))
                 (= (plist-get a cross-size) (plist-get old-a cross-size))
                 (= (plist-get b cross-size) (plist-get old-b cross-size))
                 (>= (plist-get a size) (plist-get a (if horizontal :min-width :min-height)))
                 (>= (plist-get b size) (plist-get b (if horizontal :min-width :min-height)))
                 (or bounded
                     (and (<= (abs (- (plist-get a size) (plist-get old-a size) delta)) 1)
                          (<= (abs (- (plist-get b axis) (plist-get old-b axis) delta)) 1))))
      (error "Native %s splitter failed at %s: ratio expected %.9f observed %.9f; panes %s/%s -> %s/%s"
             orientation offset expected (nth 2 tree)
             (mapcar (lambda (key) (plist-get old-a key)) '(:x :y :width :height))
             (mapcar (lambda (key) (plist-get old-b key)) '(:x :y :width :height))
             (mapcar (lambda (key) (plist-get a key)) '(:x :y :width :height))
             (mapcar (lambda (key) (plist-get b key)) '(:x :y :width :height))))))

(defun etaf-desktop-gui--demo-splitter (context orientation)
  "Exercise slow, reversed and limited native splitter gestures on real apps."
  (let* ((first (plist-get (etaf-desktop-gui--demo-window "Notes") :id))
         (second (plist-get (etaf-desktop-gui--demo-window "Tasks") :id))
         (label (if (eq orientation 'horizontal) "Resize columns" "Resize rows"))
         (horizontal (eq orientation 'horizontal))
         (step (if horizontal 4 (frame-char-height))))
    (etaf-desktop-layout-set-tree
     etaf-desktop-gui--desktop
     (list :split orientation 0.5 (list :leaf first) (list :leaf second)))
    (dolist (direction '(1 -1))
      (let* ((before (list (etaf-desktop-gui--demo-window "Notes")
                           (etaf-desktop-gui--demo-window "Tasks")))
             (ratio (nth 2 (etaf-desktop-layout-tree etaf-desktop-gui--desktop)))
             (offsets (mapcar (lambda (n)
                               (if horizontal (cons (* direction n step) 0)
                                 (cons 0 (* direction n step)))) '(1 2 3 4))))
        (etaf-desktop-gui--native-motion-sequence
         context (etaf-desktop-gui--ref-by-label context label) offsets
         (lambda (offset) (etaf-desktop-gui--splitter-check orientation before ratio offset nil)))))
    (dolist (direction '(1 -1))
      (let* ((before (list (etaf-desktop-gui--demo-window "Notes")
                           (etaf-desktop-gui--demo-window "Tasks")))
             (ratio (nth 2 (etaf-desktop-layout-tree etaf-desktop-gui--desktop)))
             (size (if horizontal :width :height))
             (minimum (if horizontal :min-width :min-height))
             (ref (etaf-desktop-gui--ref-by-label context label))
             (position (etaf-host-ref-position (etaf-desktop-gui--runtime context) ref))
             (data (etaf-desktop-gui--mouse-data position))
             (xy (posn-x-y data))
             (edges (window-inside-pixel-edges (selected-window)))
             (coordinate (if horizontal (car xy) (cdr xy)))
             (extent (if horizontal (- (nth 2 edges) (nth 0 edges))
                       (- (nth 3 edges) (nth 1 edges))))
             ;; Moving outside the Emacs text window correctly cancels a
             ;; native gesture; it cannot test the Desktop's size limits.
             (distance (if (> direction 0) (- extent 1 coordinate) (- coordinate)))
             (offsets (mapcar (lambda (n)
                               (let ((delta (round (* n distance))))
                                 (if horizontal (cons delta 0) (cons 0 delta))))
                             '(0.5 1.0))))
        (etaf-desktop-gui--native-motion-sequence
         context ref offsets
         (lambda (offset) (etaf-desktop-gui--splitter-check orientation before ratio offset t)))
        (let* ((constrained-title (if (> direction 0) "Tasks" "Notes"))
               (constrained (etaf-desktop-gui--demo-window constrained-title)))
          (unless (= (plist-get constrained size) (plist-get constrained minimum))
            (error "Native %s drag to the window edge did not reach %s's minimum %s"
                   orientation constrained-title (plist-get constrained minimum))))))
    ;; Preserve the ratio produced by the last actual drag across policy
    ;; changes, before preparing a separate comfortable content/hit case.
    (let ((saved (etaf-desktop-layout-tree etaf-desktop-gui--desktop)))
      (etaf-desktop-gui--key "l")
      (unless (eq 'floating (etaf-desktop-layout-mode etaf-desktop-gui--desktop))
        (error "Shortcut l did not leave tiling"))
      (etaf-desktop-gui--key "l")
      (unless (and (eq 'tiling (etaf-desktop-layout-mode etaf-desktop-gui--desktop))
                   (equal saved (etaf-desktop-layout-tree etaf-desktop-gui--desktop)))
        (error "Floating/tiling roundtrip lost the splitter ratio")))
    (etaf-desktop-layout-resize-split etaf-desktop-gui--desktop nil 0.43)
    (etaf-desktop-gui--demo-taskbar context "Notes")
    (etaf-desktop-gui--demo-input context "Notes" "Title" (format "%s divider accepted" orientation))
    (etaf-desktop-gui--require-text context (format "%s divider accepted" orientation))
    (etaf-desktop-gui--demo-taskbar context "Tasks")
    (etaf-desktop-gui--demo-click context "Tasks" "Review the tiled layout")
    (etaf-desktop-gui--require-text context "0 of 4 done")
    (etaf-desktop-gui--demo-click context "Tasks" "Review the tiled layout")
    (etaf-desktop-gui--require-text context "1 of 4 done")
    (etaf-desktop-gui--demo-taskbar context "Notes")))

(defun etaf-desktop-gui--demo-tiled-swap (context)
  "Require shortcut x to exchange tile occupants while preserving their state."
  (etaf-desktop-gui--demo-taskbar context "Notes")
  (let* ((tree (etaf-desktop-layout-tree etaf-desktop-gui--desktop))
         (first (etaf-desktop-gui--demo-rectangle "Notes"))
         (second (etaf-desktop-gui--demo-rectangle "Tasks"))
         (active (etaf-desktop-active-window etaf-desktop-gui--desktop))
         (expected (list :split (nth 1 tree) (nth 2 tree) (nth 4 tree) (nth 3 tree))))
    (etaf-desktop-gui--key "x")
    (unless (and (equal expected (etaf-desktop-layout-tree etaf-desktop-gui--desktop))
                 (equal first (etaf-desktop-gui--demo-rectangle "Tasks"))
                 (equal second (etaf-desktop-gui--demo-rectangle "Notes"))
                 (equal active (etaf-desktop-active-window etaf-desktop-gui--desktop)))
      (error "Shortcut x did not exchange the two visible tiles atomically"))
    (etaf-desktop-gui--key "x")
    (unless (and (equal tree (etaf-desktop-layout-tree etaf-desktop-gui--desktop))
                 (equal first (etaf-desktop-gui--demo-rectangle "Notes"))
                 (equal second (etaf-desktop-gui--demo-rectangle "Tasks")))
      (error "Second shortcut x did not restore both tile slots"))))

(defun etaf-desktop-gui--demo-shortcut-lifecycle (context)
  "Use m/r/i/q through the default buffer map and validate visible lifecycle."
  (etaf-desktop-gui--demo-taskbar context "Notes")
  (let* ((before (etaf-desktop-gui--demo-rectangle "Notes"))
         (id (plist-get (etaf-desktop-gui--demo-window "Notes") :id))
         (instance (cl-find-if (lambda (entry) (member id (plist-get entry :windows)))
                               (etaf-desktop-instances etaf-desktop-gui--desktop)))
         (app (plist-get instance :app-id)))
    (etaf-desktop-gui--key "m")
    (unless (plist-get (etaf-desktop-gui--demo-window "Notes") :maximized)
      (error "Shortcut m did not maximize Notes"))
    (etaf-desktop-gui--key "r")
    (unless (and (not (plist-get (etaf-desktop-gui--demo-window "Notes") :maximized))
                 (equal before (etaf-desktop-gui--demo-rectangle "Notes")))
      (error "Shortcut r did not restore the tiled rectangle"))
    (etaf-desktop-gui--key "i")
    (unless (and (plist-get (etaf-desktop-gui--demo-window "Notes") :minimized)
                 (equal (plist-get (etaf-desktop-gui--demo-window "Tasks") :id)
                        (etaf-desktop-active-window etaf-desktop-gui--desktop)))
      (error "Shortcut i did not retire Notes and focus the visible tile"))
    (etaf-desktop-gui--demo-taskbar context "Notes")
    (etaf-desktop-gui--key "q")
    (when (cl-find id (etaf-desktop-windows etaf-desktop-gui--desktop)
                   :key (lambda (window) (plist-get window :id)) :test #'equal)
      (error "Shortcut q did not close Notes"))
    (etaf-desktop-gui--demo-launch context "Notes" app)
    (etaf-desktop-gui--key "l")
    (unless (eq 'floating (etaf-desktop-layout-mode etaf-desktop-gui--desktop))
      (error "Shortcut l did not restore floating mode after close/reopen"))
    (dolist (title '("Clock" "Chat")) (etaf-desktop-gui--demo-taskbar context title))))

(defun etaf-desktop-gui--demo-scroll-target (context title)
  "Find TITLE's overflowing body and an actual visible descendant content cell.
The author selector yields the scrolling Ebox node; semantic Host ancestry
selects a cell inside that body's content rather than window padding.  The
scroll range is read by clamping a maximal offset and restoring the original."
  (let* ((runtime (etaf-desktop-gui--runtime context))
         (buffer (etaf-runtime-buffer runtime))
         (window (etaf-desktop-gui--demo-window title))
         (body (etaf-desktop-gui--demo-class-ref context title "etaf-desktop-demo-app-body"))
         (matches (ebox-selector-query-buffer
                   buffer (format "[id=%S] .etaf-desktop-demo-app-body"
                                  (format "%s" (plist-get window :id)))))
         (owner (and (= (length matches) 1) (car matches)))
         (offset (and owner (ebox-node-scroll-offset owner)))
         (maximum (and owner
                       (prog1 (ebox-node-set-scroll owner most-positive-fixnum)
                         (ebox-node-set-scroll owner offset))))
         (target (etaf-desktop-gui--ref-within
                  context body
                  (lambda (props) (etaf-desktop-gui--class-p props "etaf-label"))
                  "visible scroll content label")))
    (unless (and maximum (> maximum 0))
      (error "%s has no overflowing scroll owner: matches=%d maximum=%s"
             title (length matches) maximum))
    (list :owner owner :target target :offset offset :maximum maximum)))

(defun etaf-desktop-gui--demo-wheel (context direction)
  "Send DIRECTION to the actual native keymap at the stored body content cell."
  (let* ((target (etaf-gui-verifier-context-get context 'demo-scroll-target))
         (position (etaf-host-ref-position (etaf-desktop-gui--runtime context)
                                           (plist-get target :target))))
    (unless position
      ;; The first label may have scrolled out.  Resolve another visible label
      ;; through the same semantic body, retaining the original owner/offset.
      (setq position
            (etaf-host-ref-position
             (etaf-desktop-gui--runtime context)
             (plist-get (etaf-desktop-gui--demo-scroll-target context "Notes") :target))))
    (etaf-gui-verifier-context-put context 'demo-scroll-quiet-offset nil)
    (execute-kbd-macro
     (vector (list direction (etaf-desktop-gui--mouse-data position))))))

(defun etaf-desktop-gui--demo-scroll-settled-p (context reverse)
  "Require changed or restored public scroll state and a quiet animation turn.
REVERSE requires the original offset.  Smooth wheel delivery must finish;
returning from a wheel callback alone is not evidence that pixels settled."
  (let* ((target (etaf-gui-verifier-context-get context 'demo-scroll-target))
         (owner (plist-get target :owner))
         (offset (and (ebox-node-buffer owner) (ebox-node-scroll-offset owner)))
         (last (etaf-gui-verifier-context-get context 'demo-scroll-quiet-offset)))
    (unless (integerp offset)
      (error "The real demo scroll owner disappeared during wheel delivery"))
    (unless (equal last offset)
      (etaf-gui-verifier-context-put context 'demo-scroll-quiet-offset offset)
      (etaf-gui-verifier-context-put context 'demo-scroll-quiet-since (float-time)))
    (and (if reverse (= offset (plist-get target :offset))
           (and (> offset (plist-get target :offset))
                (<= offset (plist-get target :maximum))))
         (>= (- (float-time)
                (etaf-gui-verifier-context-get context 'demo-scroll-quiet-since)) 0.1))))

(defun etaf-desktop-gui--demo-scenario ()
  "Return actual six-application GUI coverage, sharing the shell verifier."
  (let ((shell-actions (etaf-gui-verifier-scenario-actions (etaf-desktop-gui--scenario))))
    (etaf-gui-verifier-scenario-create
     :name "etaf-desktop-demo"
     :claim "Real six-app Desktop inputs, lifecycle, periodic updates and native controls"
     :initialize
     (lambda (context)
       (unless (display-graphic-p)
         (user-error "Desktop demo acceptance requires a graphical frame"))
       (etaf-desktop-gui--messages-start context)
       (etaf-gui-verifier-context-select-buffer
        context (get-buffer-create etaf-desktop-gui--buffer))
       (etaf-desktop-gui--line-height-baseline context))
     :invariants #'etaf-desktop-gui--invariants
     :adapter (lambda (context)
                (when (etaf-gui-verifier-context-get context 'expects-mounted)
                  (etaf-desktop-gui--adapter context)))
     :actions
     (append
      (list
       (etaf-desktop-gui--action
        "demo-mount-six-applications"
        #'etaf-desktop-gui--demo-open
        (lambda (_context)
          (and (= 6 (length (etaf-desktop-windows etaf-desktop-gui--desktop)))
               (cl-every #'etaf-desktop-gui--demo-window etaf-desktop-gui--demo-titles))))
       (etaf-desktop-gui--action
        "demo-focus-keeps-neighbor-physical-row-y"
        (lambda (context)
          (let ((anchors (etaf-desktop-gui--window-anchor-y context)))
            (dolist (title '("Notes" "Tasks" "Notes"))
              (etaf-desktop-gui--click-ref
               context (etaf-desktop-gui--title-ref context title))
              (unless (equal (etaf-desktop-active-window etaf-desktop-gui--desktop)
                             (plist-get (etaf-desktop-gui--demo-window title) :id))
                (error "Physical row focus check did not activate %s" title))
              (etaf-desktop-gui--anchor-y-unchanged-p context anchors 2))))
        (lambda (context) (etaf-desktop-gui--physical-rows-standard-p context)))
       (etaf-desktop-gui--demo-wait-action
        "demo-clock-visible-ticks"
        (lambda (context)
          (etaf-desktop-gui--demo-full context "Clock")
          (etaf-gui-verifier-context-put context 'clock-before
                                         (etaf-desktop-gui--demo-clock-text context)))
        (lambda (context)
          (let ((now (etaf-desktop-gui--demo-clock-text context)))
            (and now (not (equal now (etaf-gui-verifier-context-get context 'clock-before)))))))
       (etaf-desktop-gui--demo-wait-action
        "demo-clock-minimized-with-live-notes"
        (lambda (context)
          (etaf-desktop-gui--demo-click context "Clock" "Minimize")
          (etaf-desktop-gui--demo-full context "Notes")
          (etaf-desktop-gui--demo-click context "Notes" "Add line"))
        (lambda (context)
          (and (plist-get (etaf-desktop-gui--demo-window "Clock") :minimized)
               (string-search "line 4 written" (etaf-desktop-gui--text context)))))
       (etaf-desktop-gui--action
        "demo-clock-restores-current-time"
        (lambda (context) (etaf-desktop-gui--demo-taskbar context "Clock"))
        (lambda (context)
          (member (etaf-desktop-gui--demo-clock-text context)
                  (list (format-time-string "%H:%M:%S")
                        (format-time-string "%H:%M:%S" (time-subtract nil 1))))))
       (etaf-desktop-gui--demo-wait-action
        "demo-clock-inactive-workspace-with-live-monitor"
        (lambda (context)
          (etaf-desktop-gui--click-ref context (etaf-desktop-gui--ref-by-symbol context 'etaf-workspace-work))
          (etaf-desktop-gui--demo-full context "Monitor")
          (etaf-desktop-gui--demo-click context "Monitor" "Refresh"))
        (lambda (_context) (eq 'work (etaf-desktop-active-workspace etaf-desktop-gui--desktop))))
       (etaf-desktop-gui--action
        "demo-clock-cross-workspace-restore"
        (lambda (context) (etaf-desktop-gui--demo-taskbar context "Clock"))
        (lambda (context)
          (and (eq 'main (etaf-desktop-active-workspace etaf-desktop-gui--desktop))
               (member (etaf-desktop-gui--demo-clock-text context)
                       (list (format-time-string "%H:%M:%S")
                             (format-time-string "%H:%M:%S" (time-subtract nil 1)))))))
       (etaf-desktop-gui--action
        "demo-notes-input-buttons-and-keyboard"
        (lambda (context)
          (etaf-desktop-gui--demo-full context "Notes")
          (etaf-desktop-gui--demo-input context "Notes" "Title" "Native mnpiq title")
          (etaf-desktop-gui--require-text context "Native mnpiq title")
          (etaf-desktop-gui--demo-click context "Notes" "Clear")
          (etaf-desktop-gui--require-text context "Empty note")
          (etaf-desktop-gui--demo-click context "Notes" "Add line")
          (etaf-desktop-gui--require-text context "line 1 written")
          (etaf-focus (etaf-desktop-gui--runtime context)
                      (etaf-desktop-gui--ref-by-label-within context "Add line"
                                                           (etaf-desktop-gui--demo-ref "Notes")))
          (execute-kbd-macro (kbd "RET")))
        (lambda (context) (string-search "line 2 written" (etaf-desktop-gui--text context))))
       (etaf-desktop-gui--action
        "demo-tasks-checkbox-add-clear-and-empty-recovery"
        (lambda (context)
          (etaf-desktop-gui--demo-full context "Tasks")
          (etaf-desktop-gui--demo-click context "Tasks" "Review the tiled layout")
          (etaf-desktop-gui--require-text context "0 of 4 done")
          (dolist (label '("Review the tiled layout" "Drag a window past the canvas edge"
                           "Open Settings and switch the theme" "Launch a second Notes window"))
            (etaf-desktop-gui--demo-click context "Tasks" label))
          (etaf-desktop-gui--require-text context "4 of 4 done")
          (etaf-desktop-gui--demo-click context "Tasks" "Clear done")
          (etaf-desktop-gui--require-text context "All clear")
          (etaf-desktop-gui--demo-click context "Tasks" "Add task"))
        (lambda (context) (and (string-search "Task 5" (etaf-desktop-gui--text context))
                               (string-search "0 of 1 done" (etaf-desktop-gui--text context)))))
       (etaf-desktop-gui--action
        "demo-chat-native-input-send-and-retained-history"
        (lambda (context)
          (etaf-desktop-gui--demo-full context "Chat")
          (etaf-desktop-gui--demo-input context "Chat" "Message" "Hello native input")
          (etaf-desktop-gui--demo-click context "Chat" "Send")
          (etaf-desktop-gui--require-text context "Hello native input")
          (etaf-desktop-gui--require-text context "4 messages")
          (etaf-desktop-gui--demo-click context "Chat" "Send")
          (etaf-desktop-gui--require-text context "Message 5")
          (etaf-desktop-gui--demo-click context "Chat" "Send")
          (etaf-desktop-gui--require-text context "Welcome to the ETAF Desktop demo." t))
        (lambda (context) (string-search "8 messages" (etaf-desktop-gui--text context))))
       (etaf-desktop-gui--action
        "demo-calculator-every-key-and-operations"
        (lambda (context)
          (etaf-desktop-gui--demo-full context "Calculator")
          (dolist (case '((("1" "2" "+" "3" "=") . "15")
                          (("9" "−" "2" "=") . "7")
                          (("4" "×" "5" "=") . "20")
                          (("8" "÷" "2" "=") . "4")
                          (("6" "." "." "5" "+" "0" "." "5" "=") . "7")
                          (("7" "÷" "0" "=") . "0")))
            (etaf-desktop-gui--demo-click context "Calculator" "C")
            (dolist (key (car case)) (etaf-desktop-gui--demo-click context "Calculator" key))
            (unless (string-match-p
                     (concat "\\_<" (regexp-quote (cdr case)) "\\_>")
                     (etaf-desktop-gui--ref-text
                      context (etaf-desktop-gui--demo-class-ref
                               context "Calculator" "etaf-desktop-demo-calc-display")))
              (error "Calculator produced the wrong result for %s" (car case)))))
        (lambda (_context) (not (plist-get (etaf-desktop-gui--demo-window "Calculator") :resizable))))
       (etaf-desktop-gui--demo-wait-action
        "demo-monitor-refresh-is-live"
        (lambda (context)
          (etaf-desktop-gui--demo-full context "Monitor")
          (etaf-gui-verifier-context-put
           context 'monitor-before
           (etaf-desktop-gui--ref-text
            context (etaf-desktop-gui--demo-class-ref context "Monitor" "etaf-window-content"))))
        (lambda (_context) t))
       (etaf-desktop-gui--action
        "demo-monitor-refresh-publishes-new-sample"
        (lambda (context) (etaf-desktop-gui--demo-click context "Monitor" "Refresh"))
        (lambda (context)
          (not (equal (etaf-gui-verifier-context-get context 'monitor-before)
                      (etaf-desktop-gui--ref-text
                       context (etaf-desktop-gui--demo-class-ref
                                context "Monitor" "etaf-window-content")))))))
      (mapcar
       (lambda (title)
         (etaf-desktop-gui--action
          (format "demo-%s-complete-window-lifecycle" (downcase title))
          (lambda (context) (etaf-desktop-gui--demo-lifecycle context title))
          (lambda (_context) (etaf-desktop-gui--demo-window title))))
       etaf-desktop-gui--demo-titles)
      (list
       (etaf-desktop-gui--action
        "demo-prepare-real-notes-geometry"
        (lambda (context)
          (etaf-desktop-gui--demo-taskbar context "Notes")
          (setq etaf-desktop-gui--notes-window (plist-get (etaf-desktop-gui--demo-window "Notes") :id))
          ;; Placement is fixture setup; all measured gesture actions below
          ;; use the same real rendered handles as the shell acceptance.
          (etaf-desktop-move-window etaf-desktop-gui--desktop etaf-desktop-gui--notes-window 24 3)
          (etaf-desktop-resize-window etaf-desktop-gui--desktop etaf-desktop-gui--notes-window 420 15))
        (lambda (_context) (equal etaf-desktop-gui--notes-window
                                   (etaf-desktop-active-window etaf-desktop-gui--desktop)))))
      (cl-remove-if-not
       (lambda (action)
         (member (etaf-gui-verifier-action-id action)
                 '("drag-notes-title" "resize-notes-right-handle" "resize-notes-all-edges-and-corners")))
       shell-actions)
      (list
       (etaf-desktop-gui--action
        "demo-real-content-scroll-after-resize"
        (lambda (context)
          (etaf-desktop-gui--demo-full context "Notes")
          (dotimes (_ 3) (etaf-desktop-gui--demo-click context "Notes" "Add line"))
          (etaf-desktop-gui--demo-click context "Notes" "Zoom")
          (etaf-desktop-resize-window etaf-desktop-gui--desktop
                                     etaf-desktop-gui--notes-window 420 9)
          (etaf-gui-verifier-context-put
           context 'demo-scroll-target (etaf-desktop-gui--demo-scroll-target context "Notes"))
          (etaf-desktop-gui--demo-wheel context 'wheel-down))
        (lambda (context) (etaf-desktop-gui--demo-scroll-settled-p context nil)))
       (etaf-desktop-gui--action
        "demo-reverse-wheel-restores-original-scroll-offset"
        (lambda (context) (etaf-desktop-gui--demo-wheel context 'wheel-up))
        (lambda (context) (etaf-desktop-gui--demo-scroll-settled-p context t)))
       (etaf-desktop-gui--action
        "demo-scrolled-app-control-remains-live"
        (lambda (context)
          (etaf-desktop-gui--demo-full context "Notes")
          (etaf-desktop-gui--demo-click context "Notes" "Add line"))
        (lambda (context) (string-search "line 7 written" (etaf-desktop-gui--text context)))))
      (cl-remove-if-not
       (lambda (action) (string-prefix-p "settings-" (etaf-gui-verifier-action-id action)))
       shell-actions)
      (list
       (etaf-desktop-gui--action
        "demo-shell-keyboard-and-modal-dismissal"
        (lambda (context)
          (dolist (pair '(("a" . etaf-desktop-launcher-open-p)
                          ("w" . etaf-desktop-switcher-open-p)
                          ("o" . etaf-desktop-settings-open-p)))
            (execute-kbd-macro (kbd (car pair)))
            (unless (funcall (cdr pair) etaf-desktop-gui--desktop)
              (error "Desktop shortcut %s did not open its modal" (car pair)))
            (execute-kbd-macro (kbd "<escape>"))
            (when (funcall (cdr pair) etaf-desktop-gui--desktop)
              (error "Escape did not close Desktop modal")))
          (etaf-desktop-gui--demo-taskbar context "Notes")
          (let ((before (etaf-desktop-active-window etaf-desktop-gui--desktop)))
            (execute-kbd-macro (kbd "n"))
            (when (equal before (etaf-desktop-active-window etaf-desktop-gui--desktop))
              (error "Desktop next-window shortcut did not change focus"))
            (execute-kbd-macro (kbd "p"))
            (unless (equal before (etaf-desktop-active-window etaf-desktop-gui--desktop))
              (error "Desktop focus traversal did not return"))))
        (lambda (_context) (not (etaf-desktop-settings-open-p etaf-desktop-gui--desktop))))
       (etaf-desktop-gui--action
        "demo-layout-policy-roundtrip-with-real-apps"
        (lambda (context)
          (etaf-desktop-gui--demo-taskbar context "Notes")
          (when (plist-get (etaf-desktop-gui--demo-window "Notes") :maximized)
            (etaf-desktop-gui--demo-click context "Notes" "Zoom"))
          (dolist (mode '(tiling master-stack monocle floating))
            (etaf-desktop-set-layout-mode etaf-desktop-gui--desktop mode)
            (unless (eq mode (etaf-desktop-layout-mode etaf-desktop-gui--desktop))
              (error "Desktop did not accept layout mode %s" mode))
            (etaf-desktop-gui--demo-taskbar context "Notes")
            (etaf-desktop-gui--demo-click context "Notes" "Minimize")
            (etaf-desktop-gui--demo-taskbar context "Notes")
            (unless (and (= 6 (length (etaf-desktop-windows etaf-desktop-gui--desktop)))
                         (not (plist-get (etaf-desktop-gui--demo-window "Notes") :minimized)))
              (error "Demo lifecycle failed in layout %s" mode))))
        (lambda (_context) (eq 'floating (etaf-desktop-layout-mode etaf-desktop-gui--desktop))))
       (etaf-desktop-gui--action
        "demo-app-error-preserves-existing-input"
        (lambda (context)
          (etaf-desktop-register-app
           etaf-desktop-gui--broken-app :title "Broken demo acceptance"
           :open (lambda (_context) (error "intentional Desktop GUI launch failure"))
           :replace t)
          (let* ((instance (etaf-desktop-launch etaf-desktop-gui--desktop etaf-desktop-gui--broken-app))
                 (id (plist-get instance :id)))
            (unless (and (eq 'error (plist-get instance :status))
                         (string-search "intentional Desktop GUI" (etaf-desktop-gui--text context)))
              (error "Failed demo launch was not isolated visibly"))
            (etaf-desktop-gui--demo-full context "Notes")
            (etaf-desktop-gui--demo-input context "Notes" "Title" "Input survives app error")
            (etaf-desktop-close-instance etaf-desktop-gui--desktop id)))
        (lambda (context) (string-search "Input survives app error" (etaf-desktop-gui--text context))))
       (etaf-desktop-gui--action
        "demo-shortcut-s-splits-only-visible-panes"
        #'etaf-desktop-gui--demo-two-panes
        (lambda (_context) (eq 'tiling (etaf-desktop-layout-mode etaf-desktop-gui--desktop))))
       (etaf-desktop-gui--action
        "demo-horizontal-divider-native-motion-reverse-and-limits"
        (lambda (context) (etaf-desktop-gui--demo-splitter context 'horizontal))
        (lambda (_context) (eq 'horizontal (nth 1 (etaf-desktop-layout-tree etaf-desktop-gui--desktop)))))
       (etaf-desktop-gui--action
        "demo-horizontal-tile-swap-shortcut-x"
        #'etaf-desktop-gui--demo-tiled-swap
        (lambda (_context) (eq 'tiling (etaf-desktop-layout-mode etaf-desktop-gui--desktop))))
       (etaf-desktop-gui--action
        "demo-vertical-divider-native-motion-reverse-and-limits"
        (lambda (context) (etaf-desktop-gui--demo-splitter context 'vertical))
        (lambda (_context) (eq 'vertical (nth 1 (etaf-desktop-layout-tree etaf-desktop-gui--desktop)))))
       (etaf-desktop-gui--action
        "demo-vertical-tile-swap-shortcut-x"
        #'etaf-desktop-gui--demo-tiled-swap
        (lambda (_context) (eq 'tiling (etaf-desktop-layout-mode etaf-desktop-gui--desktop))))
       (etaf-desktop-gui--action
        "demo-shortcuts-maximize-restore-minimize-close-layout"
        #'etaf-desktop-gui--demo-shortcut-lifecycle
        (lambda (_context) (= 6 (length (etaf-desktop-windows etaf-desktop-gui--desktop)))))
       (etaf-desktop-gui--demo-wait-action
        "demo-close-clock-leaves-no-periodic-updates"
        (lambda (context)
          (etaf-desktop-gui--demo-taskbar context "Clock")
          (etaf-desktop-gui--demo-click context "Clock" "Close")
          (etaf-gui-verifier-context-put context 'closed-revision
                                         (etaf-runtime-revision (etaf-desktop-gui--runtime context))))
        (lambda (context)
          (= (etaf-gui-verifier-context-get context 'closed-revision)
             (etaf-runtime-revision (etaf-desktop-gui--runtime context)))))
       (etaf-desktop-gui--action
        "demo-destroy-and-reopen"
        (lambda (context)
          (etaf-desktop-close etaf-desktop-gui--desktop)
          (etaf-desktop-gui--demo-open context))
        (lambda (_context) (= 6 (length (etaf-desktop-windows etaf-desktop-gui--desktop)))))
       (etaf-desktop-gui--demo-wait-action
        "demo-reopened-clock-ticks-and-input-works"
        (lambda (context)
          (etaf-desktop-gui--demo-full context "Clock")
          (etaf-gui-verifier-context-put context 'clock-before (etaf-desktop-gui--demo-clock-text context)))
        (lambda (context)
          (let ((now (etaf-desktop-gui--demo-clock-text context)))
            (and now (not (equal now (etaf-gui-verifier-context-get context 'clock-before)))))))
       (etaf-desktop-gui--action
        "demo-killed-buffer-can-reopen"
        (lambda (context)
          (kill-buffer (etaf-gui-verifier-context-target-buffer context))
          (etaf-desktop-gui--demo-open context))
        (lambda (_context) (= 6 (length (etaf-desktop-windows etaf-desktop-gui--desktop)))))
       (etaf-desktop-gui--action
        "demo-final-notes-input-after-reopen"
        (lambda (context)
          (etaf-desktop-gui--demo-full context "Notes")
          (etaf-desktop-gui--demo-input context "Notes" "Title" "Reopened desktop is interactive"))
        (lambda (context) (string-search "Reopened desktop is interactive" (etaf-desktop-gui--text context)))))))))

(defun etaf-desktop-gui-run (run-directory &optional scenario)
  "Run SCENARIO asynchronously into RUN-DIRECTORY.
SCENARIO is `shell' (the default static policy fixture) or `demo' (the real
six-application desktop).  Both reject new asynchronous timer errors."
  (interactive "DDesktop GUI evidence directory: ")
  (unless (memq scenario '(nil shell demo))
    (user-error "Unknown Desktop GUI scenario: %s" scenario))
  (setq etaf-desktop-gui--run-directory (expand-file-name run-directory))
  (setenv "ETAF_GUI_CAPTURE_PID" (number-to-string (emacs-pid)))
  (run-at-time 0.1 nil
               (lambda ()
                 ;; Timer failures can carry cyclic public error data.  Keep
                 ;; all printing bounded while allowing every real timer to run.
                 (let ((print-circle t) (print-level 8) (print-length 32))
                   (etaf-gui-verifier-run
                    (if (eq scenario 'demo)
                        (etaf-desktop-gui--demo-scenario)
                      (etaf-desktop-gui--scenario))
                    etaf-desktop-gui--run-directory))))
  'scheduled)

(provide 'desktop-gui-scenarios)
;;; desktop-gui-scenarios.el ends here
