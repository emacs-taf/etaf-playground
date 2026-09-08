;;; task-workbench-tests.el --- Workbench acceptance preflight -*- lexical-binding: t; -*-

;;; Commentary:

;; Exercise the complete example through mounted public event entry points.
;; Minibuffer readers are stubbed only in this batch preflight.  Real input,
;; redisplay, layout, and screenshots belong to task-workbench-gui-scenarios.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'task-workbench
         (expand-file-name "../examples/task-workbench.el"
                           (file-name-directory
                            (or load-file-name
                                (bound-and-true-p byte-compile-current-file)
                                buffer-file-name))))

(defun wb-test--instance (runtime name)
  "Return RUNTIME's sole component instance named NAME."
  (let ((instances
         (cl-remove-if-not
          (lambda (instance)
            (eq name (etaf--component-spec-name
                      (etaf--component-instance-spec instance))))
          (hash-table-values (etaf-runtime-instances runtime)))))
    (should (= (length instances) 1))
    (car instances)))

(defun wb-test--data (runtime)
  "Read RUNTIME's example-owned controller for result assertions."
  (plist-get (etaf--component-instance-state
              (wb-test--instance runtime 'wb-app)) :data))

(defun wb-test--text (runtime)
  "Return RUNTIME's rendered plain text."
  (with-current-buffer (etaf-runtime-buffer runtime)
    (buffer-substring-no-properties (point-min) (point-max))))

(defun wb-test--row (runtime identity)
  "Return the semantic row reference for IDENTITY in RUNTIME."
  (let ((entry
         (cl-find-if
          (lambda (entry)
            (and (equal (plist-get (cdr entry) :key) identity)
                 (member "etaf-table-row"
                         (split-string (or (plist-get (cdr entry) :class) "")))))
          (etaf-runtime-host-props-entries runtime))))
    (should entry)
    (car entry)))

(defun wb-test--control (runtime label &optional parent)
  "Return RUNTIME control with aria LABEL, optionally inside PARENT."
  (let* ((entries
          (cl-remove-if-not
           (lambda (entry) (equal (plist-get (cdr entry) :aria-label) label))
           (etaf-runtime-host-props-entries runtime)))
         (ancestries (and parent
                          (etaf-runtime-host-ancestries runtime
                                                       (mapcar #'car entries))))
         (parent-id (and parent
                         (car (gethash parent
                                       (etaf-runtime-host-ancestries
                                        runtime (list parent)))))))
    (when parent
      (setq entries
            (cl-remove-if-not
             (lambda (entry) (memq parent-id (gethash (car entry) ancestries)))
             entries)))
    (should (= (length entries) 1))
    (caar entries)))

(defun wb-test--press (runtime label &optional parent)
  "Press RUNTIME control with LABEL, optionally inside PARENT."
  (etaf-dispatch-event runtime (wb-test--control runtime label parent) 'press))

(defun wb-test--ids (data)
  "Return the currently loaded identities from DATA."
  (mapcar #'wb-task-id (etaf-value (etaf-data-items data))))

(defun wb-test--layout-bounds (runtime)
  "Snapshot public bounds across RUNTIME's toolbar, panels, and ten rows."
  (mapcar
   (lambda (entry)
     (let ((bounds (etaf-host-ref-bounds runtime (cdr entry))))
       (should bounds)
       (cons (car entry) (copy-tree bounds))))
   (append
    (mapcar (lambda (label) (cons label (wb-test--control runtime label)))
            '("新增任务" "深色" "定位新增按钮" "全部" "未完成" "已完成"
              "搜索" "每页条数 10 ✎" "显示说明" "刷新 / 重试" "模拟失败"))
    (mapcar (lambda (identity) (cons identity (wb-test--row runtime identity)))
            (number-sequence 1 10)))))

(defun wb-test--line-widths (runtime)
  "Return measured widths of RUNTIME's rendered lines, including display props."
  (with-current-buffer (etaf-runtime-buffer runtime)
    (mapcar #'ebox-string-pixel-width (split-string (buffer-string) "\n" nil))))

(defun wb-test--desktop-header-inline-p (runtime)
  "Return non-nil when RUNTIME's desktop title and toolbar share a line."
  (with-current-buffer (etaf-runtime-buffer runtime)
    (save-excursion
      (goto-char (point-min))
      (unless (search-forward "任务工作台" nil t) (error "Workbench title is absent"))
      (= (line-number-at-pos)
         (line-number-at-pos
          (etaf-host-ref-position runtime (wb-test--control runtime "新增任务")))))))

(defun wb-test--card-layout (runtime control-label)
  "Return public bounds and line geometry for CONTROL-LABEL's card in RUNTIME."
  (let* ((control (wb-test--control runtime control-label))
         (panels
          (cl-remove-if-not
           (lambda (entry)
             (let ((classes (plist-get (cdr entry) :class)))
               (member "etaf-panel"
                       (if (stringp classes) (split-string classes) classes))))
           (etaf-runtime-host-props-entries runtime)))
         (ancestries (etaf-runtime-host-ancestries
                      runtime (cons control (mapcar #'car panels))))
         (matches
          (cl-remove-if-not
           (lambda (entry)
             (memq (car (gethash (car entry) ancestries))
                   (gethash control ancestries)))
           panels)))
    (should (= (length matches) 1))
    (let* ((host (caar matches))
           (bounds (etaf-host-ref-bounds runtime host)))
      (should bounds)
      (should (< (car bounds) (cdr bounds)))
      (with-current-buffer (etaf-runtime-buffer runtime)
        (let ((top (line-number-at-pos (car bounds)))
              (bottom (line-number-at-pos (1- (cdr bounds)))))
          (list :host host :bounds (copy-tree bounds)
                :top top :bottom bottom :height (1+ (- bottom top))
                :left
                (save-excursion
                  (goto-char (car bounds))
                  (ebox-string-pixel-width
                   (buffer-substring (line-beginning-position) (point))))))))))

(cl-defmacro wb-test--with-app ((runtime data &optional viewport-width) &rest body)
  "Mount RUNTIME and DATA at optional VIEWPORT-WIDTH, then execute BODY."
  (declare (indent 1))
  `(with-temp-buffer
     (let (,runtime ,data)
       (unwind-protect
           (progn
             (etaf-mount (current-buffer) (etaf-view (wb-app))
                         (list :viewport-width (or ,viewport-width 1600)
                               :viewport-height 80))
             (setq ,runtime (etaf-runtime-for-buffer (current-buffer))
                   ,data (wb-test--data ,runtime))
             ,@body)
         (when-let* ((mounted (etaf-runtime-for-buffer (current-buffer))))
           (etaf-unmount mounted))))))

(ert-deftest wb-workbench-mounts-composed-app ()
  "Slots, custom cells, resource, and summary all survive a full mount."
  (wb-test--with-app (runtime data)
    (should (etaf-runtime-mounted-p runtime))
    (should (equal (wb-test--ids data) (number-sequence 1 10)))
    (should (= (etaf-value (etaf-data-total data)) 100))
    (should (= (etaf-value (etaf-data-page-size data)) 10))
    (dolist (label '("任务工作台" "筛选" "设计组件接口" "检查状态隔离"
                     "点击任务行查看详情" "服务正常" "共 100 条 · 当前页 10 条"))
      (should (string-match-p (regexp-quote label) (wb-test--text runtime))))
    (dolist (identity (number-sequence 1 10))
      (let ((row (wb-test--row runtime identity)))
        (should (wb-test--control runtime "完成" row))
        (should (wb-test--control runtime "删除" row))))
    (should (plist-get (etaf-runtime-host-props-for
                       runtime (wb-test--control runtime "Previous page"))
                      :disabled))))

(ert-deftest wb-workbench-filter-search-and-pagination ()
  "Filter and search reset paging; both pager directions update rows."
  (wb-test--with-app (runtime data)
    (wb-test--press runtime "Next page")
    (should (= (etaf-value (etaf-data-page data)) 2))
    (should (equal (wb-test--ids data) (number-sequence 11 20)))
    (wb-test--press runtime "Previous page")
    (should (equal (wb-test--ids data) (number-sequence 1 10)))
    (wb-test--press runtime "未完成")
    (should (equal (wb-test--ids data) '(1 2 4 6 7 9 10 11 13 14)))
    (should (= (etaf-value (etaf-data-total data)) 74))
    (wb-test--press runtime "已完成")
    (should (equal (wb-test--ids data) '(3 5 8 12 16 20 24 28 32 36)))
    (should (= (etaf-value (etaf-data-total data)) 26))
    (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "键盘")))
      (wb-test--press runtime "搜索"))
    (should (equal (wb-test--ids data) '(4)))
    (should (= (etaf-value (etaf-data-page data)) 1))
    (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "不存在的任务")))
      (wb-test--press runtime "搜索"))
    (should-not (wb-test--ids data))
    (should (string-match-p "没有匹配的任务" (wb-test--text runtime)))
    (wb-test--press runtime "全部")
    (should (equal (wb-test--ids data) (number-sequence 1 10)))
    (should (= (etaf-value (etaf-data-total data)) 100))))

(ert-deftest wb-workbench-page-size-validates-and-reloads ()
  "The NumberInput's public press callback applies valid input only."
  (wb-test--with-app (runtime data)
    (wb-test--press runtime "Next page")
    (cl-letf (((symbol-function 'read-number) (lambda (&rest _) 2)))
      (wb-test--press runtime "每页条数 10 ✎"))
    (should (= (etaf-value (etaf-data-page-size data)) 2))
    (should (= (etaf-value (etaf-data-page data)) 1))
    (should (equal (wb-test--ids data) '(1 2)))
    (should (string-match-p "Page 1 / 50" (wb-test--text runtime)))
    (cl-letf (((symbol-function 'read-number) (lambda (&rest _) 0)))
      (should-error (wb-test--press runtime "每页条数 2 ✎") :type 'user-error))
    (should (= (etaf-value (etaf-data-page-size data)) 2))
    (should (equal (wb-test--ids data) '(1 2)))))

(ert-deftest wb-workbench-cell-toggle-delete-and-detail ()
  "Cell actions retain the row and dynamic detail, and respect disabled."
  (let ((observed 0))
    (cl-letf (((symbol-function 'wb-trace-press) (lambda () (cl-incf observed))))
      (wb-test--with-app (runtime data)
        (let* ((row (wb-test--row runtime 1))
               (remove-ref (wb-test--control runtime "删除" row)))
          (should-error (etaf-dispatch-event runtime remove-ref 'press)
                        :type 'etaf-event-error)
          (should-error (etaf-focus runtime remove-ref) :type 'etaf-event-error)
          (should-not (etaf-data-selected-item data))
          (etaf-dispatch-event runtime row 'press)
          (should (= (wb-task-id (etaf-data-selected-item data)) 1))
          (should (string-match-p "进行中" (wb-test--text runtime)))
          (let ((detail (wb-test--instance runtime 'wb-task-info)))
            (wb-test--press runtime "完成" row)
            (should (= observed 1))
            (should (plist-get (car (etaf-value (etaf-data-items data))) :done))
            (should (equal (plist-get (car (etaf-value (etaf-data-items data))) :title)
                           "设计组件接口"))
            (should (eq detail (wb-test--instance runtime 'wb-task-info)))
            (should (equal row (wb-test--row runtime 1)))
            (should (equal remove-ref (wb-test--control runtime "删除" row)))
            (should-not (plist-get (etaf-runtime-host-props-for runtime remove-ref)
                                   :disabled))
            (etaf-dispatch-event runtime remove-ref 'press)
            (should (= observed 2))
            (should (= (etaf-value (etaf-data-total data)) 99))
            (should (equal (wb-test--ids data) (number-sequence 2 11)))
            (should-not (etaf-data-selected-item data))
            (should-not (etaf-effect-scope-active-p
                         (etaf--component-instance-scope detail)))
            (should (string-match-p "点击任务行查看详情" (wb-test--text runtime)))))))))

(ert-deftest wb-workbench-add-trims-and-ignores-empty-input ()
  "Add creates a complete row once and leaves whitespace-only input alone."
  (wb-test--with-app (runtime data)
    (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "  新增验收任务  ")))
      (wb-test--press runtime "新增任务"))
    (should (= (etaf-value (etaf-data-total data)) 101))
    (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "  ")))
      (wb-test--press runtime "新增任务"))
    (should (= (etaf-value (etaf-data-total data)) 101))
    (dotimes (_ 10) (wb-test--press runtime "Next page"))
    (should (= (etaf-value (etaf-data-page data)) 11))
    (should (equal (wb-test--ids data) '(101)))
    (should (equal (car (last (etaf-value (etaf-data-items data))))
                   '(:id 101 :title "新增验收任务" :done nil)))
    (should (plist-get (etaf-runtime-host-props-for
                       runtime (wb-test--control runtime "Next page")) :disabled))))

(ert-deftest wb-workbench-last-page-and-high-id-deletion ()
  "Task 100 is selectable and deletable, with a correct shorter last page."
  (wb-test--with-app (runtime data)
    (dotimes (_ 9) (wb-test--press runtime "Next page"))
    (should (= (etaf-value (etaf-data-page data)) 10))
    (should (equal (wb-test--ids data) (number-sequence 91 100)))
    (should (plist-get (etaf-runtime-host-props-for
                       runtime (wb-test--control runtime "Next page")) :disabled))
    (let ((row (wb-test--row runtime 100)))
      (etaf-dispatch-event runtime row 'press)
      (should (= (wb-task-id (etaf-data-selected-item data)) 100))
      (should (plist-get (etaf-data-selected-item data) :done))
      (wb-test--press runtime "删除" row)
      (should (= (etaf-value (etaf-data-total data)) 99))
      (should (= (etaf-value (etaf-data-page data)) 1))
      (should (equal (wb-test--ids data) (number-sequence 1 10)))
      (should-not (etaf-data-selected-item data))
      (should-error (etaf-dispatch-event runtime row 'press) :type 'etaf-event-error))
    (dotimes (_ 9) (wb-test--press runtime "Next page"))
    (should (equal (wb-test--ids data) (number-sequence 91 99)))
    (should (string-match-p "91–99 of 99" (wb-test--text runtime)))))

(ert-deftest wb-workbench-theme-focus-and-conditional-slot-content ()
  "Theme changes paint without moving layout; local focus and details work."
  (wb-test--with-app (runtime data)
    (ignore data)
    (let ((before (with-current-buffer (etaf-runtime-buffer runtime)
                    (buffer-string)))
          (layout (wb-test--layout-bounds runtime))
          (widths (wb-test--line-widths runtime))
          (add (wb-test--control runtime "新增任务")))
      (should (wb-test--desktop-header-inline-p runtime))
      (wb-test--press runtime "深色")
      (should (etaf-value (plist-get (etaf--component-instance-state
                                     (wb-test--instance runtime 'wb-app)) :dark)))
      (should-not (equal-including-properties
                   before (with-current-buffer (etaf-runtime-buffer runtime)
                            (buffer-string))))
      (should (equal layout (wb-test--layout-bounds runtime)))
      (should (equal widths (wb-test--line-widths runtime)))
      (should (wb-test--desktop-header-inline-p runtime))
      (should (equal add (wb-test--control runtime "新增任务")))
      (wb-test--press runtime "定位新增按钮")
      (should (eq add (etaf-focused-host-ref runtime)))
      (wb-test--press runtime "显示说明")
      (should-not (string-match-p "点击行：选择任务" (wb-test--text runtime)))
      (wb-test--press runtime "显示说明")
      (should (string-match-p "点击行：选择任务" (wb-test--text runtime)))
      (wb-test--press runtime "深色")
      (should-not (etaf-value (plist-get (etaf--component-instance-state
                                         (wb-test--instance runtime 'wb-app)) :dark)))
      (should (equal layout (wb-test--layout-bounds runtime)))
      (should (equal widths (wb-test--line-widths runtime)))
      (should (wb-test--desktop-header-inline-p runtime)))))

(ert-deftest wb-workbench-explanation-toggle-isolates-card-heights ()
  "Explanation changes only detail height across three rendered layouts."
  (dolist (viewport '((250 . stacked-sidebar) (500 . side-by-side-sidebar)
                      (70 . single-column)))
    (ert-info ((format "Workbench explanation layout: %S" viewport))
      (wb-test--with-app (runtime data (car viewport))
        (etaf-dispatch-event runtime (wb-test--row runtime 1) 'press)
        (cl-labels
            ((cards ()
               (mapcar (lambda (entry)
                         (cons (car entry) (wb-test--card-layout runtime (cdr entry))))
                       '((filter . "全部") (tasks . "每页条数 10 ✎")
                         (detail . "显示说明") (service . "刷新 / 重试")))))
          (let* ((before (cards))
                 (text (wb-test--text runtime))
                 (items (etaf-value (etaf-data-items data)))
                 (selected (etaf-data-selected-item data))
                 (detail (wb-test--instance runtime 'wb-detail))
                 (service (wb-test--instance runtime 'wb-service))
                 (expanded (plist-get (etaf--component-instance-state detail) :expanded))
                 (resource (plist-get (etaf--component-instance-state service) :resource))
                 (rows (mapcar (lambda (id) (wb-test--row runtime id))
                               (number-sequence 1 10)))
                 (control (wb-test--control runtime "显示说明"))
                 (filter (alist-get 'filter before))
                 (tasks (alist-get 'tasks before))
                 (detail-layout (alist-get 'detail before))
                 (service-layout (alist-get 'service before)))
            ;; Prove the viewport actually exercises the intended wrapping
            ;; shape from published host bounds, rather than style declarations.
            (pcase (cdr viewport)
              ('stacked-sidebar
               (should (= (plist-get filter :top) (plist-get tasks :top)
                          (plist-get detail-layout :top)))
               (should (< (plist-get tasks :left) (plist-get detail-layout :left)))
               (should (< (plist-get detail-layout :bottom)
                          (plist-get service-layout :top))))
              ('side-by-side-sidebar
               (should (= (plist-get filter :top) (plist-get tasks :top)
                          (plist-get detail-layout :top) (plist-get service-layout :top)))
               (should (< (plist-get detail-layout :left)
                          (plist-get service-layout :left))))
              ('single-column
               (should (< (plist-get filter :bottom) (plist-get tasks :top)))
               (should (< (plist-get tasks :bottom) (plist-get detail-layout :top)))
               (should (< (plist-get detail-layout :bottom)
                          (plist-get service-layout :top)))))
            (should (etaf-value expanded))
            (should (= (wb-task-id selected) 1))
            (should (string-match-p "点击行：选择任务" text))
            (dolist (visible '(nil t))
              (wb-test--press runtime "显示说明")
              (let ((current (cards)))
                (message "Workbench explanation width=%d visible=%S heights=%S -> %S"
                         (car viewport) visible
                         (mapcar (lambda (entry) (plist-get (cdr entry) :height)) before)
                         (mapcar (lambda (entry) (plist-get (cdr entry) :height)) current))
                (dolist (card '(filter tasks service))
                  (should (= (plist-get (alist-get card before) :height)
                             (plist-get (alist-get card current) :height))))
                (should (funcall (if visible #'= #'<)
                                 (plist-get (alist-get 'detail current) :height)
                                 (plist-get detail-layout :height)))
                (dolist (card '(filter tasks detail service))
                  (should (equal (plist-get (alist-get card before) :host)
                                 (plist-get (alist-get card current) :host))))
                (should (eq visible (etaf-value expanded)))
                (should (eq detail (wb-test--instance runtime 'wb-detail)))
                (should (eq service (wb-test--instance runtime 'wb-service)))
                (should (eq items (etaf-value (etaf-data-items data))))
                (should (eq selected (etaf-data-selected-item data)))
                (should (= (etaf-value (etaf-data-total data)) 100))
                (should (= (etaf-value (etaf-data-page data)) 1))
                (should (= (etaf-value (etaf-data-page-size data)) 10))
                (should (eq (etaf-resource-status resource) 'success))
                (should (equal rows (mapcar (lambda (id) (wb-test--row runtime id))
                                           (number-sequence 1 10))))
                (should (equal control (wb-test--control runtime "显示说明")))
                (should (string-match-p "设计组件接口" (wb-test--text runtime)))
                (should (string-match-p "服务正常" (wb-test--text runtime)))
                (should (eq visible
                            (not (null (string-match-p "点击行：选择任务"
                                                       (wb-test--text runtime))))))))
            (should (equal before (cards)))
            (should (equal text (wb-test--text runtime)))))))))

(ert-deftest wb-workbench-theme-render-failure-retains-published-handlers ()
  "A failed theme render keeps the published UI and usable old callbacks."
  (wb-test--with-app (runtime data)
    (let* ((theme (symbol-function 'wb-theme))
           (dark (plist-get (etaf--component-instance-state
                            (wb-test--instance runtime 'wb-app)) :dark))
           (generation (etaf-runtime-current-generation runtime))
           (before (with-current-buffer (etaf-runtime-buffer runtime)
                     (buffer-string))))
      (cl-letf (((symbol-function 'wb-theme)
                 (lambda (value)
                   (if value (error "Rejected theme candidate")
                     (funcall theme value)))))
        (should-error (wb-test--press runtime "深色")))
      (should (eq generation (etaf-runtime-current-generation runtime)))
      (should (equal-including-properties
               before (with-current-buffer (etaf-runtime-buffer runtime)
                        (buffer-string))))
      ;; The App passes a checked value, so the published Checkbox keeps that
      ;; snapshot.  Its next press still requests true; UI rollback does not
      ;; restore the separately owned business ref.
      (should (etaf-value dark))
      (wb-test--press runtime "深色")
      (should (etaf-value dark))
      (should (eq generation (etaf-runtime-current-generation runtime)))
      ;; Restore the business value explicitly, then retry through the same
      ;; public control after removing the injected render failure.
      (setf (etaf-value dark) nil)
      (should (equal (wb-test--ids data) (number-sequence 1 10)))
      (let ((retry-generation (etaf-runtime-current-generation runtime)))
        (wb-test--press runtime "深色")
        (should (etaf-value dark))
        (should-not (eq retry-generation
                        (etaf-runtime-current-generation runtime)))
        (let ((bounds (etaf-host-ref-bounds
                       runtime (wb-test--control runtime "深色"))))
          (should bounds)
          (should (string-match-p
                   "☑" (with-current-buffer (etaf-runtime-buffer runtime)
                         (buffer-substring-no-properties
                          (car bounds) (cdr bounds))))))))))

(ert-deftest wb-workbench-resource-failure-retry-and-cleanup ()
  "The resource reports failure, retries, and disposes its last value once."
  (let ((cleanups 0))
    (cl-letf (((symbol-function 'wb-service-cleanup) (lambda () (cl-incf cleanups))))
      (wb-test--with-app (runtime data)
        (ignore data)
        (let* ((instance (wb-test--instance runtime 'wb-service))
               (resource (plist-get (etaf--component-instance-state instance)
                                    :resource)))
          (should (eq (etaf-resource-status resource) 'success))
          (wb-test--press runtime "模拟失败")
          (should (eq (etaf-resource-status resource) 'error))
          (should (string-match-p "模拟加载失败" (wb-test--text runtime)))
          (wb-test--press runtime "刷新 / 重试")
          (should (eq (etaf-resource-status resource) 'success))
          (should (string-match-p "服务正常" (wb-test--text runtime)))
          (should-not (string-match-p "模拟加载失败" (wb-test--text runtime)))
          (should (= cleanups 1))
          (wb-test--press runtime "刷新 / 重试")
          (should (= cleanups 2))
          (etaf-unmount runtime)
          (should (= cleanups 3))
          (should-not (etaf-resource-active-p resource))
          (should-not (etaf-effect-scope-active-p
                       (etaf--component-instance-scope instance))))))))

(ert-deftest wb-workbench-apps-isolate-state-and-remount-cleans-scopes ()
  "Two mounts isolate state; teardown releases all component-owned resources."
  (let ((installed 0) (cleaned 0)
        (one (generate-new-buffer " *wb-one*"))
        (two (generate-new-buffer " *wb-two*")))
    (cl-letf (((symbol-function 'wb-trace-install)
               (lambda () (cl-incf installed) (lambda () (cl-incf cleaned)))))
      (unwind-protect
          (progn
            (dolist (buffer (list one two))
              (etaf-mount buffer (etaf-view (wb-app))
                          '(:viewport-width 1600 :viewport-height 80)))
            (let* ((r1 (etaf-runtime-for-buffer one))
                   (r2 (etaf-runtime-for-buffer two))
                   (d1 (wb-test--data r1))
                   (d2 (wb-test--data r2))
                   (scopes (mapcar #'etaf--component-instance-scope
                                   (hash-table-values (etaf-runtime-instances r1)))))
              (should-not (eq d1 d2))
              (should-not (eq (wb-test--control r1 "新增任务")
                              (wb-test--control r2 "新增任务")))
              (wb-test--press r1 "完成" (wb-test--row r1 1))
              (should (plist-get (car (etaf-value (etaf-data-items d1))) :done))
              (should-not (plist-get (car (etaf-value (etaf-data-items d2))) :done))
              (wb-test--press r1 "深色")
              (should-not (etaf-value (plist-get (etaf--component-instance-state
                                                 (wb-test--instance r2 'wb-app))
                                                :dark)))
              (etaf-unmount r1)
              (should-not (etaf-runtime-for-buffer one))
              (should (cl-every (lambda (scope)
                                  (not (etaf-effect-scope-active-p scope))) scopes))
              (should (etaf-runtime-mounted-p r2))
              (etaf-mount one (etaf-view (wb-app))
                          '(:viewport-width 1600 :viewport-height 80))
              (let ((fresh (wb-test--data (etaf-runtime-for-buffer one))))
                (should-not (eq d1 fresh))
                (should (equal (wb-test--ids fresh) (number-sequence 1 10)))
                (should (= (etaf-value (etaf-data-total fresh)) 100))
                (should-not (plist-get (car (etaf-value (etaf-data-items fresh))) :done)))))
        (dolist (buffer (list one two))
          (when-let* ((runtime (etaf-runtime-for-buffer buffer)))
            (etaf-unmount runtime))
          (when (buffer-live-p buffer) (kill-buffer buffer))))
      (should (> installed 0))
      (should (= installed cleaned)))))

(provide 'task-workbench-tests)
;;; task-workbench-tests.el ends here
