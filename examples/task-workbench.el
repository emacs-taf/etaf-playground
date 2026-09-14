;;; task-workbench.el --- Composable task workbench -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; A complete public API example: reusable components and cells, controlled
;; inputs, slots, Context, Theme, resources, lifecycle, and independent Apps.
;; Load this module and run `wb-open'.  Use `wb-close' to dispose the App.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'etaf-ui)

;;; Data and ordinary functions

(defconst wb-tasks
  (append
   '((:id 1 :title "设计组件接口" :done nil)
    (:id 2 :title "编写使用示例" :done nil)
    (:id 3 :title "检查状态隔离" :done t)
    (:id 4 :title "验证键盘操作" :done nil)
     (:id 5 :title "补充文档" :done t))
   (cl-loop for id from 6 to 100
            for title = (nth (mod id 10)
                             '("整理项目资料" "检查发布清单" "优化任务流程"
                               "更新使用指南" "确认界面文案" "梳理组件边界"
                               "复核交互细节" "清理过期任务" "完善测试记录"
                               "准备版本说明"))
            collect (list :id id :title (format "%s %03d" title id)
                          :done (zerop (mod id 4)))))
  "Initial rows copied independently into each workbench.")

(defun wb-task-id (task)
  "Return TASK's stable identity."
  (plist-get task :id))

(defun wb-query (data query)
  "Apply QUERY to DATA and load its first page."
  (etaf-data-set-query data query)
  (etaf-data-set-page data 1)
  (etaf-data-load data))

(defun wb-theme (dark)
  "Return the workbench palette for DARK or light mode."
  (if dark
      '(:ui-fg "#E5EAF3" :ui-bg "#111827" :ui-border "#38465B"
        :ui-muted-fg "#A1AEC1" :ui-success-fg "#70D6B4"
        :ui-panel-fg "#E5EAF3" :ui-panel-bg "#1B2535"
        :ui-panel-border "#38465B"
        :ui-button-primary-fg "#FFFFFF" :ui-button-primary-bg "#4869D8"
        :ui-button-primary-border "#4869D8"
        :ui-button-secondary-fg "#DCE5FF" :ui-button-secondary-bg "#2C3C60"
        :ui-button-secondary-border "#2C3C60"
        :ui-button-ghost-fg "#B8C5DA" :ui-button-ghost-bg "#1B2535"
        :ui-button-ghost-border "#38465B"
        :ui-checkbox-enabled-fg "#D6E0F1" :ui-checkbox-enabled-bg "#263449"
        :ui-checkbox-enabled-border "#465872"
        :ui-disabled-fg "#8390A5" :ui-disabled-bg "#253044"
        :ui-disabled-border "#334157"
        :ui-table-border "#38465B" :ui-table-selected-fg "#E4ECFF"
        :ui-table-selected-bg "#2C3C60" :ui-pagination-muted-fg "#A1AEC1")
    '(:ui-fg "#172033" :ui-bg "#F3F5F8" :ui-border "#D8DFE8"
      :ui-muted-fg "#647084" :ui-success-fg "#24745C"
      :ui-panel-fg "#172033" :ui-panel-bg "#FFFFFF"
      :ui-panel-border "#D8DFE8"
      :ui-button-primary-fg "#FFFFFF" :ui-button-primary-bg "#3657D6"
      :ui-button-primary-border "#3657D6"
      :ui-button-secondary-fg "#263C78" :ui-button-secondary-bg "#E8EDF8"
      :ui-button-secondary-border "#E8EDF8"
      :ui-button-ghost-fg "#526174" :ui-button-ghost-bg "#FFFFFF"
      :ui-button-ghost-border "#D8DFE8"
      :ui-checkbox-enabled-fg "#33425C" :ui-checkbox-enabled-bg "#F0F3F9"
      :ui-checkbox-enabled-border "#CDD6E4"
      :ui-disabled-fg "#8290A3" :ui-disabled-bg "#F0F2F6"
      :ui-disabled-border "#E0E5ED"
      :ui-table-border "#E2E7EF" :ui-table-selected-fg "#263C78"
      :ui-table-selected-bg "#E8EDF8" :ui-pagination-muted-fg "#647084")))

;;; Action: one named business operation reused by add/update/delete

(etaf-action-define wb-mutate (runtime data operation payload)
  (ignore runtime)
  (etaf-data-set-page data 1)
  (etaf-data-mutate data operation payload))

(etaf-action-define wb-focus (runtime target)
  (etaf-focus runtime target))

;;; Behavior: stable callbacks, additive to the Button's business action

(defun wb-trace-press ()
  "Report a completed control action."
  (message "动作已执行"))
(defun wb-trace-cleanup ()
  "Report disposal of a control's reusable behavior."
  (message "按钮行为已释放"))
(defun wb-trace-install ()
  "Return the cleanup callback for a control's reusable behavior."
  #'wb-trace-cleanup)

(etaf-define-behavior wb-trace ()
  (etaf-behavior-create 'wb-trace
                        :on-press #'wb-trace-press
                        :install #'wb-trace-install))

(etaf-define-component wb-button (&key label on-press disabled variant)
  :view
  (etaf-button :label label :on-press on-press :disabled disabled
               :variant variant :padding '((lh 0) (ch 2))
               :use (list (wb-trace))))

;;; Stateless layout: props, default slot, named slots, scoped styles

(etaf-define-component wb-shell (&key title)
  :view
  (column :width '(vw 100) :height '(vh 100) :overflow 'scroll
          :item-gap '(lh 1)
          :color (etaf-theme-token :ui-fg)
          :bgcolor (etaf-theme-token :ui-bg)
   (flex :width 'stretch :flex-wrap 'wrap :gap '((lh 1) (px 16))
         :align-items 'center :justify-content 'space-between
    (column :flex-grow 1 :min-width '(ch 0)
     (text :class "title" (expr title))
     (etaf-label :variant 'muted :text "个人任务 · 本地工作空间"))
    (flex :width 'max-content :flex-wrap 'wrap :gap '((lh 1) (px 10))
          :align-items 'center
     (slot :name 'toolbar)))
   (flex :width 'stretch :flex-wrap 'wrap :gap '((lh 1) (px 16))
         :align-items 'flex-start
    (slot))
   (slot :name 'footer (text "准备就绪")))
  :styles
  (("&" :padding ((lh 1) (ch 3)))
   (".title" :font-weight bold)
   (".etaf-table-body" :item-gap (lh 1))
   (".etaf-table-header" :padding ((lh 0) (ch 1)))))

;;; Reusable cell: Context dependency + controlled Checkbox + disabled Button

(etaf-define-component wb-task-controls (&key task)
  :bindings ((data (etaf-inject 'wb-data nil t)))
  :view
  (row :item-gap '(ch 1)
       (etaf-checkbox
        :label "完成" :checked (plist-get task :done)
        :on-press #'wb-trace-press      ; Additive; does not replace on-change.
        :on-change
        (lambda (next)
          (etaf-dispatch 'wb-mutate data 'update
                         (plist-put (copy-sequence task) :done next))))
       (wb-button
        :label "删除" :variant 'ghost :disabled (not (plist-get task :done))
        :on-press
        (lambda ()
          (etaf-dispatch 'wb-mutate data 'delete (wb-task-id task))))))

(defun wb-controls-cell (row)
  "Return reusable task controls for ROW at the consuming cell."
  (etaf-view (wb-task-controls :task row)))

(defconst wb-columns
  '((:key :title :label "任务" :width (fr 1))
    (:key :actions :label "操作" :width 22 :cell wb-controls-cell))
  "Task columns with stable identities and an ordinary View factory.")

;;; Dynamic composition: expr returns an ordinary Component

(etaf-define-component wb-task-info (&key task)
  :view
  (column
   (text :font-weight 'bold (expr (plist-get task :title)))
   (text (expr (if (plist-get task :done) "已完成" "进行中")))))

(etaf-define-component wb-detail ()
  :bindings ((data (etaf-inject 'wb-data nil t))
             (expanded (etaf-ref t)))
  :view
  (etaf-panel :title "详情" :item-gap '(lh 1)
              (expr
               (if-let* ((task (etaf-data-selected-item data)))
                   (etaf-view (wb-task-info :task task))
                 (etaf-view (text "点击任务行查看详情"))))
              (etaf-checkbox
               :label "显示说明" :bind expanded)
              (box :if (etaf-value expanded) :height '(lh 3) :overflow 'scroll
                   (column
                    (text :for (tip '("点击行：选择任务"
                                      "勾选：修改完成状态"
                                      "完成后可以删除"
                                      "TAB：移动焦点"
                                      "RET：激活控件"))
                          :key tip
                          (expr tip))))))

;;; Resource: explicit status/error/retry, scoped result cleanup
;;; This is a synchronous demo loader, not a simulated asynchronous API.

(defun wb-service-cleanup ()
  "Report disposal of a previously loaded service result."
  (message "旧服务结果已释放"))

(etaf-define-component wb-service ()
  :bindings
  ((fail-next (etaf-ref nil))
   (resource
    (etaf-resource
     (lambda ()
       (when (etaf-value fail-next)
         (setf (etaf-value fail-next) nil)
         (error "模拟加载失败"))
       (etaf-resource-result "服务正常"
                             :cleanup #'wb-service-cleanup))
     :immediate nil)))
  :setup (etaf-on-mounted (lambda () (etaf-resource-load resource)))
  :view
  (etaf-panel :title "服务状态" :item-gap '(lh 1)
              (text
               (expr
                (pcase (etaf-resource-status resource)
                  ('success (etaf-resource-value resource))
                  ('error (error-message-string (etaf-resource-error resource)))
                  (_ "加载中…"))))
              (row :item-gap '(ch 10)
                   (wb-button :label "刷新 / 重试" :variant 'secondary
                              :on-press (lambda () (etaf-resource-load resource)))
                   (wb-button :label "模拟失败" :variant 'ghost
                              :on-press
                              (lambda ()
                                (setf (etaf-value fail-next) t)
                                (etaf-resource-load resource))))))

;;; App owner: Data, refs, computed, watch, Context, Theme, lifecycle

(etaf-define-component wb-app ()
  :bindings
  ((data (etaf-data-controller
          (etaf-data-memory-source (copy-tree wb-tasks) :id-key :id)
          :page-size 10 :auto-load nil))
   (dark (etaf-ref nil))
   (next-id (etaf-ref (1+ (apply #'max (mapcar #'wb-task-id wb-tasks)))))
   (summary
    (etaf-computed
     (lambda ()
       (format "共 %d 条 · 当前页 %d 条"
               (etaf-value (etaf-data-total data))
               (length (etaf-value (etaf-data-items data)))))))
   (add-ref (etaf-local-ref 'add)))
  :setup
  (progn
    (etaf-provide 'wb-data data)
    (etaf-theme-provide
     (etaf-computed (lambda () (wb-theme (etaf-value dark)))))
    (etaf-watch dark
                (lambda (new _old)
                  (message "切换到%s主题" (if new "深色" "浅色"))))
    (etaf-on-mounted (lambda () (etaf-data-load data)))
    (etaf-on-updated (lambda () (message "工作台已更新")))
    ;; Data, computed, watch and nested Resource scopes dispose automatically.
    (etaf-on-unmounted (lambda () (message "工作台已卸载"))))
  :view
  (wb-shell :title "任务工作台"
            (slot :name 'toolbar
                  (wb-button
                   :ref add-ref :label "新增任务"
                   :on-press
                   (lambda ()
                     (let ((title (string-trim (read-string "任务名称："))))
                       (unless (string-empty-p title)
                         (let ((id (etaf-value next-id)))
                           (cl-incf (etaf-value next-id))
                           (etaf-dispatch 'wb-mutate data 'insert
                                          (list :id id :title title :done nil)))))))
                  (etaf-checkbox :label "深色" :bind dark)
                  (wb-button :label "定位新增按钮" :variant 'ghost
                             :on-press (lambda () (etaf-dispatch 'wb-focus add-ref))))

            ;; Parent owns each panel's participation in this Flex layout.
            (etaf-panel :title "筛选" :flex-basis '(ch 18) :flex-grow 1 :flex-shrink 0 :item-gap '(lh 1)
                        (flex :flex-wrap 'wrap :gap '((lh 1) (px 10)) :align-items 'stretch
                              (wb-button :label "全部" :width 'stretch :flex-basis '(ch 16) :flex-grow 1
                                         :variant (if (null (etaf-value (etaf-data-query data)))
                                                      'secondary 'ghost)
                                         :on-press (lambda () (wb-query data nil)))
                              (wb-button :label "未完成" :width 'stretch :flex-basis '(ch 16) :flex-grow 1
                                         :variant (if (equal (etaf-value (etaf-data-query data)) '(:done nil))
                                                      'secondary 'ghost)
                                         :on-press (lambda () (wb-query data '(:done nil))))
                              (wb-button :label "已完成" :width 'stretch :flex-basis '(ch 16) :flex-grow 1
                                         :variant (if (equal (etaf-value (etaf-data-query data)) '(:done t))
                                                      'secondary 'ghost)
                                         :on-press (lambda () (wb-query data '(:done t))))
                              (wb-button :label "搜索" :variant 'secondary :width 'stretch
                                         :flex-basis '(ch 16) :flex-grow 1
                                         :on-press (lambda () (wb-query data (read-string "搜索："))))))

            (etaf-panel :title "任务" :flex-grow 4 :flex-basis '(ch 64) :min-width '(ch 0)
                        :item-gap '(lh 1)
                        (etaf-data-grid
                         :controller data :columns wb-columns :row-key #'wb-task-id
                         :on-row-press (lambda (row) (etaf-data-select-one data (wb-task-id row)))
                         :loading-label "读取任务…" :error-label "读取失败，请重新筛选"
                         :empty-label "没有匹配的任务"
                         (slot :name 'footer
                               (etaf-pagination :controller data
                                                :previous-label "‹ 上一页" :next-label "下一页 ›")))
                        (etaf-number-input
                         :label "每页条数" :value (etaf-value (etaf-data-page-size data))
                         :min 1 :max 20
                         :on-change
                         (lambda (next)
                           (etaf-data-set-page-size data next)
                           (etaf-data-set-page data 1)
                           (etaf-data-load data))))

            (flex :flex-wrap 'wrap :flex-basis '(ch 36) :flex-grow 1 :min-width '(ch 0)
                  :align-content 'space-between :align-items 'flex-start :gap '((lh 1) (px 16))
                  (wb-detail :flex-basis '(ch 28) :flex-grow 1)
                  (wb-service :flex-basis '(ch 28) :flex-grow 1))

            (slot :name 'footer
                  (grid :width 'stretch :grid-template-columns '((fr 1) (fr 1)) :gap '((lh 1) (ch 1))
                        (etaf-label :variant 'muted :text (etaf-value summary))
                        (etaf-label :variant 'muted
                                    :text "数据仅保存在当前工作台内存中")))))

;;; Open / close. Each buffer gets independent App state and local refs.

(defun wb-open (&optional buffer-name)
  "Open an independent workbench in BUFFER-NAME or the default buffer."
  (interactive)
  (switch-to-buffer
   (etaf-mount (or buffer-name "*任务工作台*") (etaf-view (wb-app)))))

(defun wb-close (&optional buffer-name)
  "Dispose the workbench in BUFFER-NAME and close its buffer."
  (interactive)
  (let ((name (or buffer-name "*任务工作台*")))
    (when-let* ((runtime (etaf-runtime-for-buffer name)))
      (etaf-unmount runtime))
    (when-let* ((buffer (get-buffer name)))
      (kill-buffer buffer))))

;; Usage:
;; (wb-open)
;; (wb-open "*另一个独立工作台*")
;; (wb-close)

(provide 'task-workbench)
;;; task-workbench.el ends here
