;;; task-workbench-tests.el --- Public Workbench editing workflow -*- lexical-binding: t; -*-

;;; Commentary:
;; Mount the shipped example through Playground and operate its visible Hosts.

;;; Code:
(require 'ert)
(require 'cl-lib)
(require 'etaf-playground)
(require 'etaf)
(require 'ebox)

(defun wb-test--control (runtime label)
  "Return the unique visible control with LABEL in RUNTIME."
  (let ((entries (cl-remove-if-not
                  (lambda (entry) (equal label (plist-get (cdr entry) :aria-label)))
                  (etaf-runtime-host-props-entries runtime))))
    (should (= 1 (length entries)))
    (caar entries)))

(defun wb-test--row (runtime id)
  "Return the semantic row for task ID in RUNTIME."
  (car (cl-find-if
        (lambda (entry)
          (and (equal id (plist-get (cdr entry) :key))
               (member "etaf-table-row" (split-string (or (plist-get (cdr entry) :class) "")))))
        (etaf-runtime-host-props-entries runtime))))

(defun wb-test--row-text (runtime id)
  "Read the published text of task ID in RUNTIME."
  (let ((bounds (etaf-host-ref-bounds runtime (wb-test--row runtime id))))
    (with-current-buffer (etaf-runtime-buffer runtime)
      (buffer-substring-no-properties (car bounds) (cdr bounds)))))

(defun wb-test--press (runtime label)
  "Activate the public control with LABEL in RUNTIME."
  (etaf-dispatch-event runtime (wb-test--control runtime label) 'press))

(ert-deftest task-workbench-draft-validates-saves-cancels-and-isolates-instances ()
  "Editing only changes a draft until save; navigation resolves pending edits."
  (let ((first (generate-new-buffer " *workbench-form*"))
        (second (generate-new-buffer " *workbench-form-other*")))
    (unwind-protect
        (progn
          (dolist (buffer (list first second))
            (etaf-playground-mount-example (buffer-name buffer) "task-workbench"))
          (let ((runtime (etaf-runtime-for-buffer first))
                (other (etaf-runtime-for-buffer second)))
            (etaf-dispatch-event runtime (wb-test--row runtime 1) 'press)
            (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "   ")))
              (wb-test--press runtime "标题"))
            (should (with-current-buffer first (string-match-p "标题：不能为空" (buffer-string))))
            (should-error (wb-test--press runtime "保存修改") :type 'etaf-event-error)
            (should (string-match-p "设计组件接口" (wb-test--row-text runtime 1)))
            (wb-test--press runtime "取消修改")
            (should-not (with-current-buffer first (string-match-p "已修改 ·" (buffer-string))))
            (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "中文表单草稿")))
              (wb-test--press runtime "标题"))
            (should (string-match-p "标题 中文表单草稿"
                                    (ebox-render (plist-get (etaf-runtime-snapshot runtime) :input))))
            (should (with-current-buffer first (string-match-p "标题 中文表单草稿" (buffer-string))))
            (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "已完成")))
              (wb-test--press runtime "状态"))
            (should (string-match-p "设计组件接口" (wb-test--row-text runtime 1)))
            (should (string-match-p "☐" (wb-test--row-text runtime 1)))
            (should-not (with-current-buffer second (string-match-p "中文表单草稿" (buffer-string))))
            (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) nil)))
              (etaf-dispatch-event runtime (wb-test--row runtime 2) 'press))
            (should (with-current-buffer first (string-match-p "中文表单草稿" (buffer-string))))
            (wb-test--press runtime "保存修改")
            (should (string-match-p "中文表单草稿" (wb-test--row-text runtime 1)))
            (should (string-match-p "☑" (wb-test--row-text runtime 1)))
            (should (string-match-p "设计组件接口" (wb-test--row-text other 1)))
            (should-not (with-current-buffer first (string-match-p "已修改 ·" (buffer-string))))
            (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "待放弃草稿")))
              (wb-test--press runtime "标题"))
            (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) t)))
              (etaf-dispatch-event runtime (wb-test--row runtime 2) 'press))
            (should-not (with-current-buffer first (string-match-p "待放弃草稿" (buffer-string))))
            (should (string-match-p "中文表单草稿" (wb-test--row-text runtime 1)))
            (should-error (wb-test--press runtime "保存修改") :type 'etaf-event-error)))
      (dolist (buffer (list first second))
        (when-let* ((runtime (etaf-runtime-for-buffer buffer))) (etaf-unmount runtime))
        (kill-buffer buffer)))))

(provide 'task-workbench-tests)
;;; task-workbench-tests.el ends here
