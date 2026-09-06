;;; task-workbench-gui-scenarios.el --- Workbench GUI acceptance -*- lexical-binding: t; -*-

;;; Commentary:

;; A concrete adapter for the existing temporal GUI verifier.  Keyboard
;; actions traverse TAB and RET bindings; mouse actions use actual displayed
;; positions; text entry goes through the real minibuffer.  The caller connects
;; to the existing GUI server and owns recording, screenshots, and visual review.
;; This adapter records observations; it does not certify visual quality or
;; turn action timings (which include user input) into performance benchmarks.

;;; Code:

(require 'cl-lib)
(require 'playground-gui-scenarios)
(require 'task-workbench
         (expand-file-name "../examples/task-workbench.el"
                           (file-name-directory
                            (or load-file-name
                                (bound-and-true-p byte-compile-current-file)
                                buffer-file-name))))

(defconst wb-gui--primary-name "*ETAF GUI Task Workbench*"
  "Dedicated primary buffer used throughout one Workbench verification run.")
(defconst wb-gui--secondary-name "*ETAF GUI Independent Workbench*"
  "Dedicated buffer used to verify independent App state.")
(defvar wb-gui--prepared-buffer nil
  "Fresh unmounted target prepared before the screen recorder starts.")

(defun wb-gui--configure-native ()
  "Preserve the current backend, or verify an explicitly requested module."
  (let* ((configured (getenv "EBOX_NATIVE_REFLOW_MODULE_PATH"))
         (path
          (when configured
            (when (string-empty-p configured)
              (error "EBOX_NATIVE_REFLOW_MODULE_PATH must not be empty"))
            (expand-file-name configured))))
    (when (and path (not (file-readable-p path)))
      (error "Prepared Ebox native module path is unreadable: %s" path))
    (when path
      (setq ebox-native-reflow-module-path path))
    (let* ((report (ebox-native-reflow-runtime-report))
           (loaded (plist-get report :loaded-module-path)))
      (when (and path (not (plist-get report :layout-ready-p)))
        (error "Ebox native module is unavailable at %s: %S"
               path (plist-get report :load-error)))
      (when (and path
                 (not (and loaded
                           (file-equal-p
                            (if (file-directory-p path)
                                (file-name-directory loaded) loaded)
                            path))))
        (error "Loaded Ebox module differs from configured path: %s / %s"
               loaded path))
      (when loaded
        (message "Workbench GUI native module: %s (SHA256 %s)"
                 loaded (plist-get report :loaded-module-hash)))
      report)))

(defun wb-gui--redisplay-for-geometry ()
  "Clear this adapter's native diagnostic and paint before measuring geometry."
  (when-let* ((diagnostic (current-message))
              ((string-prefix-p "Workbench GUI native module: " diagnostic)))
    (message nil))
  (redisplay t))

;;;###autoload
(defun task-workbench-gui-prepare (&optional foreground)
  "Prepare a fresh target in the existing frame before recording starts.
Preserve application focus unless FOREGROUND is explicitly non-nil."
  (unless (display-graphic-p) (error "Workbench acceptance needs GUI Emacs"))
  (when (or (get-buffer wb-gui--primary-name)
            (get-buffer wb-gui--secondary-name))
    (error "Workbench verification requires fresh dedicated buffers"))
  (wb-gui--configure-native)
  (setq wb-gui--prepared-buffer (get-buffer-create wb-gui--primary-name))
  (with-current-buffer wb-gui--prepared-buffer
    (insert "任务工作台\n")
    (goto-char (point-min)))
  (switch-to-buffer wb-gui--prepared-buffer)
  (delete-other-windows)
  (when foreground (select-frame-set-input-focus (selected-frame)))
  (wb-gui--redisplay-for-geometry)
  wb-gui--prepared-buffer)

(defun wb-gui--runtime (context)
  "Return the Runtime mounted in CONTEXT's target buffer."
  (etaf-runtime-for-buffer (etaf-gui-verifier-context-target-buffer context)))

(defun wb-gui--data (context)
  "Inspect CONTEXT's app-owned Data controller for result assertions."
  (let ((instance
         (cl-find-if
          (lambda (instance)
            (eq 'wb-app (etaf--component-spec-name
                         (etaf--component-instance-spec instance))))
          (hash-table-values (etaf-runtime-instances (wb-gui--runtime context))))))
    (plist-get (etaf--component-instance-state instance) :data)))

(defun wb-gui--ids (context)
  "Return the currently loaded task identities in CONTEXT."
  (mapcar #'wb-task-id (etaf-value (etaf-data-items (wb-gui--data context)))))

(defun wb-gui--selected-id (context)
  "Return CONTEXT's selected task identity, or nil."
  (when-let* ((item (etaf-data-selected-item (wb-gui--data context))))
    (wb-task-id item)))

(defun wb-gui--text-p (context text)
  "Return non-nil when CONTEXT's rendered output contains TEXT."
  (string-match-p (regexp-quote text)
                  (etaf-playground-gui-scenarios--buffer-text context)))

(defun wb-gui--control (context label &optional row-id)
  "Find CONTEXT control by aria LABEL, optionally within ROW-ID."
  (let* ((runtime (wb-gui--runtime context))
         (entries (etaf-runtime-host-props-entries runtime))
         (row (and row-id
                   (cl-find-if
                    (lambda (entry)
                      (and (equal (plist-get (cdr entry) :key) row-id)
                           (member "etaf-table-row"
                                   (split-string
                                    (or (plist-get (cdr entry) :class) "")))))
                    entries)))
         (matches (cl-remove-if-not
                   (lambda (entry)
                     (equal label (plist-get (cdr entry) :aria-label))) entries)))
    (when row-id
      (unless row (error "No task row %S" row-id))
      (let* ((ancestries (etaf-runtime-host-ancestries
                         runtime (cons (car row) (mapcar #'car matches))))
             (parent (car (gethash (car row) ancestries))))
        (setq matches
              (cl-remove-if-not
               (lambda (entry) (memq parent (gethash (car entry) ancestries)))
               matches))))
    (unless (= (length matches) 1)
      (error "Expected one control %S in row %S, got %d"
             label row-id (length matches)))
    (caar matches)))

(defun wb-gui--layout-snapshot (context)
  "Observe painted control pixels and semantic row bounds in CONTEXT.
The viewport and font are part of the comparison; character offsets alone
cannot establish that Emacs painted a control on the same visual line."
  (let* ((runtime (wb-gui--runtime context))
         (window (selected-window))
         (frame (window-frame window))
         (entries (etaf-runtime-host-props-entries runtime))
         (targets
          (append
           (list (cons "title" (wb-gui--find-text "任务工作台")))
           (mapcar
            (lambda (target)
              (cons (format "%s%s" (car target) (or (cadr target) ""))
                    (etaf-host-ref-position
                     runtime (wb-gui--control context (car target) (cadr target)))))
            (append
             (mapcar #'list '("新增任务" "深色" "定位新增按钮" "全部" "未完成"
                             "已完成" "搜索" "每页条数 10 ✎" "显示说明"
                             "刷新 / 重试" "模拟失败"))
             (mapcar (lambda (id) (list "完成" id)) (number-sequence 1 10)))))))
    (unless (and (display-graphic-p frame)
                 (eq (window-buffer window) (etaf-runtime-buffer runtime)))
      (error "Pixel geometry requires the displayed Workbench GUI target"))
    (list
     :viewport (list (window-inside-pixel-edges window)
                     (window-start window) (window-hscroll window))
     :font (list (format "%s" (frame-parameter frame 'font))
                 (frame-char-width frame) (frame-char-height frame))
     :controls
     (mapcar
      (lambda (target)
        (let* ((position (cdr target))
               (displayed (and position (pos-visible-in-window-p position window)))
               (posn (and displayed (posn-at-point position window)))
               (xy (and posn (posn-x-y posn))))
          (unless (and (numberp (car xy)) (numberp (cdr xy)))
            (error "Theme geometry target is not visibly painted: %s" (car target)))
          (list (car target) (car xy) (cdr xy))))
      targets)
     :rows
     (mapcar
      (lambda (identity)
        (let* ((entry
                (cl-find-if
                 (lambda (entry)
                   (and (equal identity (plist-get (cdr entry) :key))
                        (member "etaf-table-row"
                                (split-string (or (plist-get (cdr entry) :class) "")))))
                 entries))
               (bounds (and entry (etaf-host-ref-bounds runtime (car entry)))))
          (unless bounds (error "Theme geometry row has no live bounds: %s" identity))
          (list identity (car bounds) (cdr bounds))))
      (number-sequence 1 10)))))

(defun wb-gui--capture-theme-baseline (context)
  "Capture CONTEXT's initial geometry once it survives another paint turn."
  (when (etaf-gui-verifier-context-get context 'light-layout)
    (error "Initial theme geometry must only be captured once"))
  (wb-gui--redisplay-for-geometry)
  (let ((previous (wb-gui--layout-snapshot context))
        (deadline (+ (float-time) 5.0))
        stable)
    (while (not stable)
      (when (>= (float-time) deadline)
        (error "Initial Workbench geometry did not settle before theme input"))
      (sit-for 0.05)
      (redisplay t)
      (let ((current (wb-gui--layout-snapshot context)))
        (setq stable (equal previous current)
              previous current)))
    (etaf-gui-verifier-context-put context 'light-layout previous)))

(defun wb-gui--theme-layout-preserved-p (context)
  "Compare CONTEXT's current painted geometry with its settled light theme."
  (let ((current (wb-gui--layout-snapshot context)))
    (etaf-gui-verifier-context-put context 'theme-layout-current current)
    (equal (etaf-gui-verifier-context-get context 'light-layout) current)))

(defun wb-gui--root-background-p (context color)
  "Check that CONTEXT's painted root uses COLOR in its buffer face remap."
  (with-current-buffer (etaf-gui-verifier-context-target-buffer context)
    (let* ((face (get-text-property (point-min) 'face))
           (mapping (and (symbolp face) (assq face face-remapping-alist))))
      (and mapping
           (cl-some (lambda (attrs)
                      (and (listp attrs)
                           (equal color (plist-get attrs :background))))
                    (cdr mapping))))))

(defun wb-gui--tab-to (context ref)
  "Reach REF in CONTEXT by executing actual TAB key bindings."
  (let* ((runtime (wb-gui--runtime context))
         (limit (1+ (length (etaf-runtime-host-props-entries runtime))))
         (at-target
          (lambda ()
            (and (equal ref (etaf-focused-host-ref runtime))
                 (equal (point) (etaf-host-ref-position runtime ref))))))
    (unless (eq (current-buffer) (etaf-runtime-buffer runtime))
      (error "Keyboard input target drifted from the Workbench buffer"))
    (while (and (> limit 0) (not (funcall at-target)))
      (execute-kbd-macro (kbd "TAB"))
      (cl-decf limit))
    (unless (funcall at-target)
      (error "TAB cannot reach the expected control"))))

(defun wb-gui--press (context label &optional row-id)
  "Use TAB and RET to activate LABEL within CONTEXT's optional ROW-ID."
  (wb-gui--tab-to context (wb-gui--control context label row-id))
  (execute-kbd-macro (kbd "RET")))

(defun wb-gui--visit-next-page (context)
  "Advance CONTEXT one page and retain the complete visited task sequence."
  (let ((visited (etaf-gui-verifier-context-get
                  context 'visited-task-ids (wb-gui--ids context))))
    (wb-gui--press context "Next page")
    (setq visited (append visited (wb-gui--ids context)))
    (etaf-gui-verifier-context-put context 'visited-task-ids visited)
    (etaf-gui-verifier-context-put context 'visited-tasks (length visited))))

(defun wb-gui--enter (context label text)
  "Activate LABEL and type TEXT through the actual minibuffer in CONTEXT."
  (let (received)
    (let ((minibuffer-exit-hook
           (cons (lambda ()
                   (setq received (minibuffer-contents-no-properties)))
                 minibuffer-exit-hook)))
      (minibuffer-with-setup-hook
          (lambda ()
            ;; The recursive input loop starts after setup hooks return.
            ;; Queue real input events; RET during setup has no exit target.
            (setq unread-command-events
                  (append (listify-key-sequence (vconcat text (kbd "RET")))
                          unread-command-events)))
        (wb-gui--press context label)))
    (unless (equal received text)
      (error "Minibuffer did not receive the expected keyboard input"))))

(defun wb-gui--mouse-at (position)
  "Click the actual visible buffer POSITION using its displayed event data."
  (redisplay t)
  (let ((position-data (posn-at-point position (selected-window))))
    (unless (and position-data (pos-visible-in-window-p position))
      (error "Mouse target is not currently displayed: %S" position))
    (execute-kbd-macro (vector (list 'mouse-1 position-data)))))

(defun wb-gui--click (context label &optional row-id)
  "Click LABEL at its rendered position within CONTEXT's optional ROW-ID."
  (let* ((runtime (wb-gui--runtime context))
         (ref (wb-gui--control context label row-id))
         (position (etaf-host-ref-position runtime ref)))
    (unless position (error "Control %S has no live bounds" label))
    (wb-gui--mouse-at position)))

(defun wb-gui--find-text (text)
  "Return a buffer position inside visible TEXT or signal a missing target."
  (save-excursion
    (goto-char (point-min))
    (unless (search-forward text nil t)
      (error "Rendered text target is absent: %S" text))
    (- (point) (length text))))

(defun wb-gui--action (id execute predicate)
  "Create action ID with EXECUTE and a persistent product PREDICATE."
  (etaf-gui-verifier-action-create
   :id id :execute execute :screenshot t
   :settled-p
   (lambda (context)
     (and (etaf-playground-gui-scenarios--mounted-settled-p context)
          (funcall predicate context)))
   :assertions
   (lambda (context)
     (list (etaf-gui-verifier-assert id (funcall predicate context))))))

(defun wb-gui--adapter (context)
  "Return primitive evidence for CONTEXT without copying private task text."
  (append
   (etaf-playground-gui-scenarios--adapter context)
   (let ((native (ebox-native-reflow-runtime-report)))
     (list (cons 'native_layout_ready (and (plist-get native :layout-ready-p) t))
           (cons 'native_module_path (or (plist-get native :loaded-module-path) ""))
           (cons 'native_module_hash (or (plist-get native :loaded-module-hash) ""))))
   (mapcar
    (lambda (entry)
      (cons (car entry)
            (vconcat
             (mapcar #'vconcat
                     (plist-get (etaf-gui-verifier-context-get context (cdr entry))
                                :controls)))))
    '((theme_pixels_before . light-layout)
      (theme_pixels_after . theme-layout-current)))
   (when (wb-gui--runtime context)
     (let ((data (wb-gui--data context)))
       (list (cons 'total (etaf-value (etaf-data-total data)))
             (cons 'page (etaf-value (etaf-data-page data)))
             (cons 'page_size (etaf-value (etaf-data-page-size data)))
             (cons 'visited_tasks
                   (etaf-gui-verifier-context-get context 'visited-tasks 0))
             (cons 'visible_rows (length (wb-gui--ids context)))
             (cons 'selected_task (or (wb-gui--selected-id context) 0)))))))

(defun wb-gui--nested-scroll (context)
  "Scroll CONTEXT's help box and retain both inner and outer observations."
  (goto-char (wb-gui--find-text "点击行：选择任务"))
  (let* ((regions (cl-remove-if-not #'ebox-scroll-state
                                    (ebox--scroll-region-ids-at-point)))
         (inner (car regions)))
    (unless inner (error "Help text has no active scroll container"))
    (etaf-gui-verifier-context-put context 'inner-region inner)
    (etaf-gui-verifier-context-put
     context 'inner-offset (plist-get (ebox-scroll-state inner) :scroll-offset))
    (etaf-gui-verifier-context-put
     context 'outer-offsets
     (mapcar (lambda (id) (cons id (plist-get (ebox-scroll-state id) :scroll-offset)))
             (cdr regions)))
    (etaf-gui-verifier-context-put context 'outer-window-start (window-start))
    (ebox-scroll-down 1)))

(defun wb-gui--nested-scrolled-p (context)
  "Return non-nil when CONTEXT's inner help scrolled without its parent."
  (let ((inner (ebox-scroll-state
                (etaf-gui-verifier-context-get context 'inner-region))))
    (and (> (plist-get inner :scroll-offset)
            (etaf-gui-verifier-context-get context 'inner-offset))
         (= (window-start)
            (etaf-gui-verifier-context-get context 'outer-window-start))
         (cl-every
          (lambda (entry)
            (equal (cdr entry) (plist-get (ebox-scroll-state (car entry))
                                         :scroll-offset)))
          (etaf-gui-verifier-context-get context 'outer-offsets)))))

(defun wb-gui--reset-outer-scroll (_context)
  "Reset the outer Ebox viewport and its containing Emacs window."
  (goto-char (point-min))
  (condition-case nil (ebox-scroll-up 10000) (beginning-of-buffer nil))
  (goto-char (point-min))
  (set-window-start (selected-window) (point-min)))

(defun wb-gui--outer-reset-p (_context)
  "Return non-nil when both the outer Ebox viewport and window are at top."
  (and (= (window-start) (point-min))
       (save-excursion
         (goto-char (point-min))
         (cl-every
          (lambda (id)
            (zerop (or (plist-get (ebox-scroll-state id) :scroll-offset) 0)))
          (ebox--scroll-region-ids-at-point)))))

;;;###autoload
(defun task-workbench-gui-scenario ()
  "Return the complete Workbench temporal GUI acceptance scenario."
  (let ((primary wb-gui--primary-name)
        (secondary wb-gui--secondary-name))
    (etaf-gui-verifier-scenario-create
     :name "task-workbench"
     :claim "Workbench layout and public input, CRUD, resources, and isolated lifecycle"
     :initialize
     (lambda (context)
       (unless (display-graphic-p) (error "Workbench acceptance needs GUI Emacs"))
       (let ((buffer (get-buffer primary)))
         (unless (and (buffer-live-p buffer)
                      (eq buffer wb-gui--prepared-buffer)
                      (not (etaf-runtime-for-buffer buffer))
                      (not (get-buffer secondary)))
           (error "Workbench target is not the fresh prepared unmounted buffer"))
         (etaf-gui-verifier-context-select-buffer context buffer)
         (setq wb-gui--prepared-buffer nil)))
     :invariants
     (lambda (context)
       (etaf-playground-gui-scenarios--invariants context nil))
     :adapter #'wb-gui--adapter
     :actions
     (append
      (list
      (wb-gui--action
       "mount"
       (lambda (context)
         (etaf-gui-verifier-context-put
          context 'target-fullscreen (frame-parameter nil 'fullscreen))
         (wb-open primary)
         (etaf-gui-verifier-context-select-buffer context (get-buffer primary))
         (etaf-gui-verifier-context-put context 'expects-mounted t))
       (lambda (context)
         (and (equal (wb-gui--ids context) (number-sequence 1 10))
              (wb-gui--text-p context "共 100 条 · 当前页 10 条")
              (wb-gui--text-p context "服务正常"))))
      (wb-gui--action
       "keyboard-theme"
       (lambda (context)
         (wb-gui--capture-theme-baseline context)
         (wb-gui--press context "深色"))
       (lambda (context)
         (and (wb-gui--theme-layout-preserved-p context)
              (wb-gui--root-background-p context "#111827"))))
      (wb-gui--action
       "keyboard-focus-add"
       (lambda (context) (wb-gui--press context "定位新增按钮"))
       (lambda (context)
         (equal (etaf-focused-host-ref (wb-gui--runtime context))
                (wb-gui--control context "新增任务"))))
      (wb-gui--action
       "minibuffer-add"
       (lambda (context) (wb-gui--enter context "新增任务" "GUI 验收任务"))
       (lambda (context)
         (= (etaf-value (etaf-data-total (wb-gui--data context))) 101))))
      (cl-loop for page from 2 to 11
               collect
               (let ((target page))
                 (wb-gui--action
                  (format "page-next-%d" target) #'wb-gui--visit-next-page
                  (lambda (c)
                    (and (equal (wb-gui--ids c)
                                (number-sequence (1+ (* 10 (1- target)))
                                                 (min 101 (* 10 target))))
                         (equal (etaf-gui-verifier-context-get c 'visited-task-ids)
                                (number-sequence 1 (min 101 (* 10 target))))
                         (or (< target 11)
                             (and (wb-gui--text-p c "GUI 验收任务")
                                  (plist-get
                                   (etaf-runtime-host-props-for
                                    (wb-gui--runtime c) (wb-gui--control c "Next page"))
                                   :disabled))))))))
      (cl-loop for page from 10 downto 1
               collect
               (let ((target page))
                 (wb-gui--action
                  (format "page-previous-%d" target)
                  (lambda (c) (wb-gui--press c "Previous page"))
                  (lambda (c)
                    (equal (wb-gui--ids c)
                           (number-sequence (1+ (* 10 (1- target))) (* 10 target)))))))
      (list
      (wb-gui--action "disabled-cell-mouse" (lambda (c) (wb-gui--click c "删除" 1))
                      (lambda (c) (and (not (wb-gui--selected-id c))
                                       (equal (wb-gui--ids c) (number-sequence 1 10)))))
      (wb-gui--action
       "row-mouse-select"
       (lambda (_context) (wb-gui--mouse-at (wb-gui--find-text "设计组件接口")))
       (lambda (c) (and (equal (wb-gui--selected-id c) 1)
                        (wb-gui--text-p c "进行中"))))
      (wb-gui--action
       "cell-mouse-toggle" (lambda (c) (wb-gui--click c "完成" 1))
       (lambda (c) (and (plist-get (etaf-data-selected-item (wb-gui--data c)) :done)
                        (equal (wb-gui--selected-id c) 1))))
      (wb-gui--action "cell-mouse-delete" (lambda (c) (wb-gui--click c "删除" 1))
                      (lambda (c) (and (equal (wb-gui--ids c) (number-sequence 2 11))
                                       (= (etaf-value (etaf-data-total
                                                       (wb-gui--data c))) 100)
                                       (not (wb-gui--selected-id c)))))
      (wb-gui--action "filter-open" (lambda (c) (wb-gui--press c "未完成"))
                      (lambda (c)
                        (and (equal (wb-gui--ids c) '(2 4 6 7 9 10 11 13 14 15))
                             (= (etaf-value (etaf-data-total (wb-gui--data c))) 74))))
      (wb-gui--action "filter-done" (lambda (c) (wb-gui--press c "已完成"))
                      (lambda (c)
                        (and (equal (wb-gui--ids c) '(3 5 8 12 16 20 24 28 32 36))
                             (= (etaf-value (etaf-data-total (wb-gui--data c))) 26))))
      (wb-gui--action "minibuffer-search"
                      (lambda (c) (wb-gui--enter c "搜索" "键盘"))
                      (lambda (c) (equal (wb-gui--ids c) '(4))))
      (wb-gui--action "filter-all" (lambda (c) (wb-gui--press c "全部"))
                      (lambda (c) (equal (wb-gui--ids c) (number-sequence 2 11))))
      (wb-gui--action "minibuffer-page-size"
                      (lambda (c) (wb-gui--enter c "每页条数 10 ✎" "2"))
                      (lambda (c) (and (equal (wb-gui--ids c) '(2 3))
                                       (wb-gui--text-p c "Page 1 / 50"))))
      (wb-gui--action "hide-help" (lambda (c) (wb-gui--press c "显示说明"))
                      (lambda (c) (not (wb-gui--text-p c "点击行：选择任务"))))
      (wb-gui--action "show-help" (lambda (c) (wb-gui--press c "显示说明"))
                      (lambda (c) (wb-gui--text-p c "点击行：选择任务")))
      (wb-gui--action "resource-failure" (lambda (c) (wb-gui--press c "模拟失败"))
                      (lambda (c) (wb-gui--text-p c "模拟加载失败")))
      (wb-gui--action "resource-retry" (lambda (c) (wb-gui--press c "刷新 / 重试"))
                      (lambda (c) (and (wb-gui--text-p c "服务正常")
                                       (not (wb-gui--text-p c "模拟加载失败")))))
      (wb-gui--action "nested-scroll" #'wb-gui--nested-scroll
                      #'wb-gui--nested-scrolled-p)
      (etaf-playground-gui-scenarios--windowed-action)
      (etaf-playground-gui-scenarios--resize-action "resize-compact" 700 500)
      (etaf-playground-gui-scenarios--scroll-action "outer-scroll" #'ebox-scroll-page-down)
      (wb-gui--action "reset-scroll" #'wb-gui--reset-outer-scroll
                      #'wb-gui--outer-reset-p)
      (etaf-playground-gui-scenarios--resize-action "resize-wide" 1300 750)
      (wb-gui--action
       "second-independent-app"
       (lambda (context)
         (etaf-gui-verifier-context-put context 'primary-data (wb-gui--data context))
         (wb-open secondary)
         (etaf-gui-verifier-context-select-buffer context (get-buffer secondary)))
       (lambda (c)
         (and (equal (wb-gui--ids c) (number-sequence 1 10))
              (= (etaf-value (etaf-data-total (wb-gui--data c))) 100)
              (not (eq (wb-gui--data c)
                       (etaf-gui-verifier-context-get c 'primary-data))))))
      (wb-gui--action
       "close-second-app"
       (lambda (context)
         (wb-close secondary)
         (etaf-gui-verifier-context-select-buffer context (get-buffer primary)))
       (lambda (c) (and (not (get-buffer secondary))
                        (equal (wb-gui--ids c) '(2 3)))))
      (wb-gui--action
       "unmount-remount"
       (lambda (context)
         (let ((old (wb-gui--runtime context)))
           (etaf-gui-verifier-context-put context 'retired-runtime old)
           (etaf-unmount old)
           (wb-open primary)
           (etaf-gui-verifier-context-select-buffer context (get-buffer primary))))
       (lambda (c)
         (and (not (etaf-runtime-mounted-p
                    (etaf-gui-verifier-context-get c 'retired-runtime)))
              (equal (wb-gui--ids c) (number-sequence 1 10))
              (= (etaf-value (etaf-data-total (wb-gui--data c))) 100))))))
     :completion
     (lambda (context)
       (and (= (etaf-gui-verifier-context-action-count context)
               (length (etaf-gui-verifier-scenario-actions
                        (etaf-gui-verifier-context-scenario context))))
            (not (get-buffer secondary))
            (= (etaf-gui-verifier-context-get context 'visited-tasks 0) 101)
            (equal (wb-gui--ids context) (number-sequence 1 10)))))))

;;;###autoload
(defun task-workbench-gui-run (run-directory)
  "Run Workbench GUI acceptance into prepared RUN-DIRECTORY."
  (unless (buffer-live-p wb-gui--prepared-buffer)
    (task-workbench-gui-prepare))
  (etaf-gui-verifier-run (task-workbench-gui-scenario) run-directory))

;;;###autoload
(defun task-workbench-gui-run-from-environment ()
  "Run Workbench acceptance in the generic runner's evidence directory."
  (task-workbench-gui-run
   (or (getenv "ETAF_GUI_RUN_DIR")
       (error "ETAF_GUI_RUN_DIR is not configured"))))

(provide 'task-workbench-gui-scenarios)
;;; task-workbench-gui-scenarios.el ends here
