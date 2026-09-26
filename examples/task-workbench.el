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
(require 'etaf-playground)

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

(defun wb-defer (seconds work &optional uncancellable)
  "Run WORK later using native timers; return an asynchronous source result.
UNCANCELLABLE models work whose completion cannot be prevented."
  (etaf-async
   (lambda (resolve reject)
     (let ((timer
            (run-at-time
             seconds nil
             (lambda ()
               (let (result failure)
                 (condition-case problem
                     (setq result (funcall work))
                   (error (setq failure problem)))
                 ;; Publication errors belong to Data, outside the source boundary.
                 (if failure (funcall reject failure) (funcall resolve result)))))))
       (unless uncancellable (lambda () (cancel-timer timer)))))))

(defun wb-source (mode)
  "Adapt the memory provider to native asynchronous delivery controlled by MODE."
  (let* ((capabilities (etaf-data-source-capabilities
                        (etaf-data-memory-source (copy-tree wb-tasks) :id-key :id)))
         (load (plist-get capabilities :load))
         (mutate (plist-get capabilities :mutate))
         fail-refresh)
    (setf
     (plist-get capabilities :load)
     (lambda (query page page-size)
       (let* ((behavior (etaf-value mode))
              (failure (or fail-refresh (eq behavior 'read-error)))
              ;; Snapshot the requested data before arranging delivery order.
              (result (funcall load query page page-size))
              (delay (pcase behavior
                       ('timeout 2)
                       ('out-of-order (if (equal query "接口") 0.3 0.02))
                       (_ 0.05))))
         (setq fail-refresh nil)
         (wb-defer delay
                   (lambda () (if failure (error "数据服务暂时不可用") result))
                   (memq behavior '(out-of-order timeout)))))
     (plist-get capabilities :mutate) nil
     (plist-get capabilities :mutate-v2)
     (lambda (operation payload)
       (let ((behavior (etaf-value mode)))
         (wb-defer
          (if (eq behavior 'timeout) 2 0.05)
          (lambda ()
            (if (eq behavior 'write-error)
                '(:certainty rolled-back :error (error "服务拒绝本次保存，未修改数据"))
              (when (eq operation 'update)
                (let ((stored (car (plist-get (funcall load (list :id (wb-task-id payload)) 1 1) :items))))
                  (setq payload (plist-put (copy-sequence payload) :revision
                                           (1+ (or (plist-get stored :revision) 0))))))
              (funcall mutate operation payload)
              (setq fail-refresh (eq behavior 'refresh-error))
              (if (eq behavior 'unknown)
                  '(:certainty external-unknown :error (error "保存回执丢失，请核对实际记录"))
                (list :certainty 'committed
                      :result (list :operation operation :item payload :changes 1)))))
          (memq behavior '(unknown timeout))))))
    (apply #'etaf-data-source capabilities)))

(defun wb-busy-p (data)
  "Return non-nil while DATA is waiting for a read or write."
  (not (null (memq (etaf-value (etaf-data-status data)) '(loading refreshing)))))

(defun wb-submission-locked-p (data submitted)
  "Return non-nil while SUBMITTED has no safe write-retry outcome in DATA."
  (and (not (null (etaf-value submitted)))
       (not (null (memq (plist-get (etaf-data-mutation-outcome data) :certainty)
                        '(committed external-unknown))))))

(defun wb-reconciliation-pending-p (data)
  "Return non-nil when DATA still needs to reconcile a committed write."
  (and (eq (plist-get (etaf-data-mutation-outcome data) :certainty) 'committed)
       (memq (etaf-data-reconciliation-state data)
             '(reconciliation-pending projection-pending render-pending))))

(defun wb-data-message (data)
  "Describe DATA's read state and external write certainty separately."
  (let* ((status (etaf-value (etaf-data-status data)))
         (outcome (etaf-data-mutation-outcome data))
         (certainty (plist-get outcome :certainty)))
    (cond
     ((plist-get outcome :pending-p) "正在保存…")
     ((and (wb-reconciliation-pending-p data) (eq status 'refreshing)) "已写入，正在刷新…")
     ((and (wb-reconciliation-pending-p data) (memq status '(error cancelled)))
      "已写入；刷新未完成。重试读取不会重复保存。")
     ((and (eq certainty 'external-unknown) (not (memq status '(loading refreshing))))
      "写入结果未知，请核对已保存内容；结束编辑不会撤销写入。")
     ((and (eq certainty 'rolled-back) (eq status 'error)) "保存失败，草稿已保留，可以重试。")
     ((eq status 'error) (format "读取失败：%s" (error-message-string (etaf-value (etaf-data-error data)))))
     ((eq status 'cancelled) "读取已取消，可重新读取。")
     ((memq status '(loading refreshing)) "正在读取任务…")
     ((eq status 'success) "数据已加载")
     (t "准备读取任务…"))))

(defun wb-discard-draft (draft submitted)
  "Resolve DRAFT and SUBMITTED before navigation; return non-nil to continue."
  (when (or (null (etaf-value draft))
            (etaf-confirm-dialog "放弃未保存的修改？"))
    (setf (etaf-value draft) nil (etaf-value submitted) nil)
    t))

(defun wb-query (data draft submitted query)
  "Apply QUERY to DATA after resolving DRAFT and SUBMITTED state."
  (when (wb-discard-draft draft submitted)
    (etaf-data-set-query data query)
    (etaf-data-set-page data 1)
    (etaf-data-load data)))

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

;;; Reusable control sizing

(etaf-define-component wb-button (&key label on-press disabled variant)
  :view
  (etaf-button :label label :on-press on-press :disabled disabled
               :variant variant :padding '((lh 0) (ch 2))))

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

;;; Reusable cell: controlled Checkbox + Menu + confirmation

(etaf-define-component wb-task-controls (&key task)
  :bindings ((data (etaf-inject 'wb-data nil t))
             (draft (etaf-inject 'wb-draft nil t))
             (submitted (etaf-inject 'wb-submitted nil t)))
  :view
  (row :item-gap '(ch 1)
       (etaf-checkbox
        :label "完成" :checked (plist-get task :done)
        :disabled (or (wb-busy-p data) (wb-submission-locked-p data submitted))
        :on-change
        (lambda (next)
          (etaf-dispatch 'wb-mutate data 'update
                         (plist-put (copy-sequence task) :done next))))
       (etaf-menu
        :label "操作"
        :disabled (or (wb-busy-p data) (wb-submission-locked-p data submitted))
        :items (list '(:key edit :label "编辑")
                     (list :key 'delete :label "删除" :disabled (not (plist-get task :done))))
        :on-select
        (lambda (action)
          (pcase action
            ('edit
             (when (or (equal (etaf-data-selected-item data) task)
                       (wb-discard-draft draft submitted))
               (etaf-data-select-one data (wb-task-id task))))
            ('delete
             (when (etaf-confirm-dialog (format "删除任务「%s」？" (plist-get task :title)))
               (when (equal (plist-get (etaf-value draft) :id) (wb-task-id task))
                 (setf (etaf-value draft) nil (etaf-value submitted) nil))
               (etaf-dispatch 'wb-mutate data 'delete (wb-task-id task)))))))))

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
   (text (expr (if (plist-get task :done) "已完成" "进行中")))
   (etaf-label :variant 'muted :text (format "已保存版本 %d" (or (plist-get task :revision) 0)))))

(defun wb-edit-field (draft original task field value)
  "Update TASK's FIELD to VALUE in DRAFT, clearing it when equal to ORIGINAL."
  (let ((next (plist-put (copy-sequence task) field value)))
    (setf (etaf-value draft) (unless (equal next original) next))))

(etaf-define-component wb-task-form (&key task original draft submitted data)
  :view
  (column :item-gap '(lh 1)
   (etaf-text-input
    :label "标题" :value (plist-get task :title)
    :disabled (or (wb-busy-p data) (wb-submission-locked-p data submitted))
    :on-change (lambda (next) (wb-edit-field draft original task :title next)))
   (etaf-select
    :ref 'wb-task-status :label "状态" :value (plist-get task :done)
    :disabled (or (wb-busy-p data) (wb-submission-locked-p data submitted))
    :options '((nil . "进行中") (t . "已完成"))
    :on-change (lambda (next) (wb-edit-field draft original task :done next)))
   (etaf-label :variant 'danger
               :text (if (string-empty-p (string-trim (plist-get task :title)))
                         "标题：不能为空" ""))
   (etaf-label :variant 'muted :text (if (etaf-value draft) "已修改 · 尚未保存" "与已保存内容一致"))
   (row :item-gap '(ch 1)
    (etaf-button
     :label "保存修改"
     :disabled (or (null (etaf-value draft)) (wb-busy-p data)
                   (wb-submission-locked-p data submitted)
                   (string-empty-p (string-trim (plist-get task :title))))
     :on-press
     (lambda ()
       (setf (etaf-value submitted) t)
       (etaf-data-mutate data 'update (plist-put (copy-sequence task) :title
                                                (string-trim (plist-get task :title))))))
    (etaf-button :label "取消修改" :variant 'ghost
                 :disabled (or (null (etaf-value draft)) (wb-busy-p data))
                 :on-press (lambda () (setf (etaf-value draft) nil (etaf-value submitted) nil))))
   (etaf-button
    :if (and (etaf-value submitted)
             (eq (plist-get (etaf-data-mutation-outcome data) :certainty) 'external-unknown))
    :label "采用已保存内容" :variant 'secondary
    :disabled (not (eq (etaf-value (etaf-data-status data)) 'success))
    :on-press (lambda () (setf (etaf-value draft) nil (etaf-value submitted) nil)))))

(etaf-define-component wb-detail ()
  :bindings ((data (etaf-inject 'wb-data nil t))
             (draft (etaf-inject 'wb-draft nil t))
             (submitted (etaf-inject 'wb-submitted nil t))
             (expanded (etaf-ref t)))
  :view
  (etaf-panel :title "详情" :item-gap '(lh 1)
              (expr
               (if-let* ((task (or (etaf-value draft) (etaf-data-selected-item data))))
                   (etaf-view
                    (column :item-gap '(lh 1)
                     (wb-task-info :task (or (etaf-data-selected-item data) task))
                     (wb-task-form :task task :original (etaf-data-selected-item data)
                                   :draft draft :submitted submitted :data data)))
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

;;; Resource: explicit service status
;;; The same native asynchronous adapter delivers service and task results.

(etaf-define-component wb-data-service ()
  :bindings ((data (etaf-inject 'wb-data nil t)) (mode (etaf-inject 'wb-mode nil t)))
  :view
  (column :item-gap '(lh 1)
   (etaf-label :role 'status :aria-label "任务数据状态"
               :aria-busy (wb-busy-p data) :text (wb-data-message data))
   (etaf-select :ref 'wb-data-mode :label "数据服务" :bind mode
                :options '((normal . "正常") (read-error . "读取失败")
                           (write-error . "保存失败") (refresh-error . "写入后刷新失败")
                           (out-of-order . "搜索乱序") (timeout . "请求超时")
                           (unknown . "保存回执丢失")))
   (row :item-gap '(ch 1)
    (etaf-button
     :label "重试读取" :variant 'secondary :disabled (wb-busy-p data)
     :on-press (lambda ()
                 (if (wb-reconciliation-pending-p data)
                     (etaf-data-retry-reconciliation data)
                   (etaf-data-load data))))
    (etaf-button :label "取消等待" :variant 'ghost :disabled (not (wb-busy-p data))
                 :on-press (lambda () (etaf-data-cancel data))))
   (etaf-button
    :if (eq (plist-get (etaf-data-mutation-outcome data) :certainty) 'external-unknown)
    :label "核对已保存内容" :variant 'secondary :disabled (wb-busy-p data)
    :on-press (lambda () (etaf-data-load data)))))

(etaf-define-component wb-service ()
  :bindings
  ((fail-next (etaf-ref nil))
   (resource
    (etaf-resource
     (lambda ()
       (let ((fail (etaf-value fail-next)))
         (when fail (setf (etaf-value fail-next) nil))
         (wb-defer 0.05
                   (lambda ()
                     (when fail (error "模拟加载失败"))
                     "服务正常"))))
     :immediate nil :timeout 0.5)))
  :setup (etaf-on-mounted (lambda () (etaf-resource-load resource)))
  :view
  (etaf-panel :title "服务状态" :item-gap '(lh 1)
              (wb-data-service)
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

(etaf-define-component wb-app (&key (title "任务工作台"))
  :bindings
  ((mode (etaf-ref 'normal))
   (data (etaf-data-controller (wb-source mode) :page-size 10 :auto-load nil :timeout 0.5))
   (dark (etaf-ref nil))
   (draft (etaf-ref nil))
   (submitted (etaf-ref nil))
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
    (etaf-provide 'wb-draft draft)
    (etaf-provide 'wb-submitted submitted)
    (etaf-provide 'wb-mode mode)
    (etaf-watch
     (lambda () (list (etaf-value (etaf-data-status data)) (etaf-data-mutation-outcome data)))
     (lambda (state _old)
       (when (and (etaf-value submitted) (eq (car state) 'success)
                  (eq (plist-get (cadr state) :certainty) 'committed))
         (setf (etaf-value draft) nil (etaf-value submitted) nil))))
    (etaf-theme-provide
     (etaf-computed (lambda () (wb-theme (etaf-value dark)))))
    ;; Data, computed, watch and nested Resource scopes dispose automatically.
    (etaf-on-mounted (lambda () (etaf-data-load data))))
  :view
  (wb-shell :title title
            (slot :name 'toolbar
                  (wb-button
                   :ref add-ref :label "新增任务"
                   :disabled (or (wb-busy-p data) (wb-submission-locked-p data submitted))
                   :on-press
                   (lambda ()
                     (let ((title (string-trim
                                   (etaf-call-with-input (lambda () (read-string "任务名称："))))))
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
                                         :disabled (or (plist-get (etaf-data-mutation-outcome data) :pending-p)
                                                       (wb-submission-locked-p data submitted))
                                         :on-press (lambda () (wb-query data draft submitted nil)))
                              (wb-button :label "未完成" :width 'stretch :flex-basis '(ch 16) :flex-grow 1
                                         :variant (if (equal (etaf-value (etaf-data-query data)) '(:done nil))
                                                      'secondary 'ghost)
                                         :disabled (or (plist-get (etaf-data-mutation-outcome data) :pending-p)
                                                       (wb-submission-locked-p data submitted))
                                         :on-press (lambda () (wb-query data draft submitted '(:done nil))))
                              (wb-button :label "已完成" :width 'stretch :flex-basis '(ch 16) :flex-grow 1
                                         :variant (if (equal (etaf-value (etaf-data-query data)) '(:done t))
                                                      'secondary 'ghost)
                                         :disabled (or (plist-get (etaf-data-mutation-outcome data) :pending-p)
                                                       (wb-submission-locked-p data submitted))
                                         :on-press (lambda () (wb-query data draft submitted '(:done t))))
                              (etaf-text-input :label "搜索" :width 'stretch
                                         :disabled (or (plist-get (etaf-data-mutation-outcome data) :pending-p)
                                                       (wb-submission-locked-p data submitted))
                                         :flex-basis '(ch 16) :flex-grow 1
                                         :value (let ((query (etaf-value (etaf-data-query data))))
                                                  (if (stringp query) query ""))
                                         :on-change (lambda (next) (wb-query data draft submitted next)))))

            (etaf-panel :title "任务" :flex-grow 4 :flex-basis '(ch 64) :min-width '(ch 0)
                        :item-gap '(lh 1)
                        (etaf-data-grid
                         :controller data :columns wb-columns :row-key #'wb-task-id
                         :row-ref (lambda (task) (intern (format "wb-task-%s" (wb-task-id task))))
                         :on-row-press (lambda (row)
                                         (when (and (not (plist-get (etaf-data-mutation-outcome data) :pending-p))
                                                    (or (equal (etaf-data-selected-item data) row)
                                                        (wb-discard-draft draft submitted)))
                                           (etaf-data-select-one data (wb-task-id row))))
                         :loading-label (wb-data-message data)
                         :error-label (wb-data-message data)
                         :empty-label "没有匹配的任务"
                         (slot :name 'footer
                               (etaf-pagination :controller data
                                                :previous-label "‹ 上一页" :next-label "下一页 ›")))
                        (etaf-number-input
                         :label "每页条数" :value (etaf-value (etaf-data-page-size data))
                         :min 1 :max 20 :disabled (or (wb-busy-p data) (wb-submission-locked-p data submitted))
                         :on-change
                         (lambda (next)
                           (when (wb-discard-draft draft submitted)
                             (etaf-data-set-page-size data next)
                             (etaf-data-set-page data 1)
                             (etaf-data-load data)))))

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

(defun wb-root (static-form &optional _styles)
  "Create the Workbench View from inert STATIC-FORM props."
  (etaf-node (car static-form) (cdr static-form) nil))

(etaf-playground-register-example "task-workbench" :root #'wb-root)

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
