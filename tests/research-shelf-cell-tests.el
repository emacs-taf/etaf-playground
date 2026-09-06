;;; research-shelf-cell-tests.el --- SQLite editing cell acceptance -*- lexical-binding: t; -*-

;;; Commentary:

;; Mount the real 256-record application through its public root.  UI events
;; drive edits; independent SQLite reads prove persistence.  Runtime internals
;; are inspected only to obtain the example-owned model for invariant checks.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'etaf-research-shelf
         (expand-file-name "../examples/research-shelf.el"
                           (file-name-directory
                            (or load-file-name
                                (bound-and-true-p byte-compile-current-file)
                                buffer-file-name))))

(defun research-cell-test--mount (buffer database-file)
  "Mount a fresh Research App in BUFFER backed by DATABASE-FILE."
  (let ((etaf-research-shelf-database-file database-file)
        (etaf-research-shelf-fixture-size 256)
        (etaf-research-shelf-page-size 12))
    (etaf-mount
     buffer
     (etaf-research-shelf-root
      (etaf-playground-read-static "research-shelf")
      (etaf-playground-read-ecss "research-shelf"))
     '(:viewport-width 1400 :viewport-height 80))
    (etaf-runtime-for-buffer buffer)))

(defun research-cell-test--model (runtime)
  "Return the sole reading list's application model in RUNTIME."
  (let ((instances
         (cl-remove-if-not
          (lambda (instance)
            (eq 'etaf-research-shelf-reading-list
                (etaf--component-spec-name
                 (etaf--component-instance-spec instance))))
          (hash-table-values (etaf-runtime-instances runtime)))))
    (should (= (length instances) 1))
    (plist-get (etaf--component-instance-state (car instances)) :model)))

(defun research-cell-test--control (runtime identity label)
  "Find the control with LABEL in RUNTIME's row with IDENTITY."
  (let* ((row (intern (format "research-shelf-row-%d" identity)))
         (row-id (car (gethash row (etaf-runtime-host-ancestries
                                  runtime (list row)))))
         (entries
          (cl-remove-if-not
           (lambda (entry) (equal label (plist-get (cdr entry) :aria-label)))
           (etaf-runtime-host-props-entries runtime)))
         (ancestries (etaf-runtime-host-ancestries runtime (mapcar #'car entries))))
    (should row-id)
    (setq entries
          (cl-remove-if-not
           (lambda (entry) (memq row-id (gethash (car entry) ancestries)))
           entries))
    (should (= (length entries) 1))
    (caar entries)))

(defun research-cell-test--press (runtime identity label)
  "Press the control with LABEL in RUNTIME's row with IDENTITY."
  (etaf-dispatch-event
   runtime (research-cell-test--control runtime identity label) 'press))

(defun research-cell-test--row (database-file identity)
  "Read IDENTITY from DATABASE-FILE through an independent SQLite source."
  (let* ((etaf-research-shelf-database-file database-file)
         (source (etaf-sqlite-source (etaf-research-shelf--database))))
    (car (plist-get (etaf-data-source-load-page source (list :id identity) 1 1)
                    :items))))

(defun research-cell-test--text (runtime &optional ref)
  "Return RUNTIME's displayed text, restricted to REF when supplied."
  (with-current-buffer (etaf-runtime-buffer runtime)
    (let ((bounds (and ref (etaf-host-ref-bounds runtime ref))))
      (when ref (should bounds))
      (buffer-substring-no-properties
       (if bounds (car bounds) (point-min))
       (if bounds (cdr bounds) (point-max))))))

(cl-defmacro research-cell-test--with-app ((runtime database-file) &rest body)
  "Mount RUNTIME using a temporary DATABASE-FILE, then run BODY and clean up."
  (declare (indent 1))
  `(let ((,database-file (make-temp-file "research-cell-" nil ".sqlite")))
     (unwind-protect
         (with-temp-buffer
           (let ((,runtime (research-cell-test--mount (current-buffer)
                                                    ,database-file)))
             (unwind-protect (progn ,@body)
               (etaf-unmount ,runtime))))
       (delete-file ,database-file))))

(ert-deftest research-shelf-cell-edits-persist-without-selecting-the-row ()
  "Controlled cells share SQLite updates with detail actions, not selection."
  (research-cell-test--with-app (runtime database-file)
    (let* ((model (research-cell-test--model runtime))
           (data (etaf-research-shelf--controller model)))
      (should (= (etaf-value (etaf-data-total data)) 256))
      (should (= (etaf-value (etaf-data-page-size data)) 12))
      (should (= (length (etaf-value (etaf-data-items data))) 12))
      (etaf-dispatch-event runtime 'research-shelf-row-1 'press)
      (let ((star (research-cell-test--control runtime 2 "Star reading")))
        (should (string-match-p "☐" (research-cell-test--text runtime star)))
        (research-cell-test--press runtime 2 "Star reading")
        (should (= (plist-get (research-cell-test--row database-file 2) :starred) 1))
        (should (equal star (research-cell-test--control runtime 2 "Star reading")))
        (should (string-match-p "☑" (research-cell-test--text runtime star)))
        (research-cell-test--press runtime 2 "Star reading")
        (should (= (plist-get (research-cell-test--row database-file 2) :starred) 0)))
      (research-cell-test--press runtime 2 "Advance reading")
      (should (= (plist-get (research-cell-test--row database-file 2) :progress) 10))
      (should (equal (plist-get (research-cell-test--row database-file 2) :status)
                     "reading"))
      (should (equal (etaf-value (etaf-data-selection data)) '(1)))
      (should (equal (plist-get (etaf-data-selected-item data) :title)
                     "The Shape of Tools"))
      ;; A detail edit must refresh the same controlled cell's current props.
      (etaf-dispatch-event runtime 'research-shelf-row-2 'press)
      (etaf-dispatch-event runtime 'research-shelf-star 'press)
      (should (string-match-p
               "☑" (research-cell-test--text
                    runtime (research-cell-test--control runtime 2 "Star reading"))))
      (etaf-dispatch-event runtime 'research-shelf-finish 'press)
      (let ((advance (research-cell-test--control runtime 2 "Advance reading")))
        (should (plist-get (etaf-runtime-host-props-for runtime advance) :disabled))
        (should-error (etaf-dispatch-event runtime advance 'press)
                      :type 'etaf-event-error)
        (should (= (plist-get (research-cell-test--row database-file 2) :progress) 100)))
      (etaf-dispatch-event runtime 'research-shelf-row-1 'press)
      (etaf-dispatch-event runtime 'research-shelf-archive 'press)
      (should (plist-get
               (etaf-runtime-host-props-for
                runtime (research-cell-test--control runtime 1 "Advance reading"))
               :disabled)))))

(ert-deftest research-shelf-edit-controls-have-distinct-column-owners ()
  "Star and advance controls belong to separate stable Table columns."
  (research-cell-test--with-app (runtime database-file)
    (ignore database-file)
    (let* ((entries (etaf-runtime-host-props-entries runtime))
           (ancestries
            (etaf-runtime-host-ancestries runtime (mapcar #'car entries))))
      (dolist (expected '(("Star reading" . :starred)
                          ("Advance reading" . :advance)))
        (let* ((control (research-cell-test--control runtime 2 (car expected)))
               (chain (gethash control ancestries))
               (cell
                (cl-find-if
                 (lambda (entry)
                   (and (member "etaf-table-cell"
                                (split-string (or (plist-get (cdr entry) :class) "")))
                        (memq (car (gethash (car entry) ancestries)) chain)))
                 entries)))
          (should cell)
          (should (eq (cdr expected) (plist-get (cdr cell) :key))))))))

(ert-deftest research-shelf-cells-follow-filter-page-and-theme ()
  "Filtered removal and paging recreate cells with current SQLite values."
  (research-cell-test--with-app (runtime database-file)
    (let* ((data (etaf-research-shelf--controller
                  (research-cell-test--model runtime))))
      (etaf-dispatch-event runtime 'research-shelf-filter-starred 'press)
      (should (= (etaf-value (etaf-data-total data)) 54))
      (let ((old-star (research-cell-test--control runtime 1 "Star reading")))
        (research-cell-test--press runtime 1 "Star reading")
        (should (= (etaf-value (etaf-data-total data)) 53))
        (should-not (etaf-runtime-host-props-for runtime 'research-shelf-row-1))
        (should-not (etaf-runtime-host-props-for runtime old-star)))
      (etaf-dispatch-event runtime 'research-shelf-theme-toggle 'press)
      (dolist (item (etaf-value (etaf-data-items data)))
        (should (string-match-p
                 "☑" (research-cell-test--text
                      runtime (research-cell-test--control
                               runtime (plist-get item :id) "Star reading")))))
      (etaf-dispatch-event runtime 'research-shelf-filter-all 'press)
      (should (= (etaf-value (etaf-data-total data)) 256))
      (should (string-match-p
               "☐" (research-cell-test--text
                    runtime (research-cell-test--control runtime 1 "Star reading"))))
      (etaf-dispatch-event runtime 'research-shelf-page-next 'press)
      (should (equal (mapcar #'etaf-research-shelf--item-id
                             (etaf-value (etaf-data-items data)))
                     (number-sequence 13 24)))
      (research-cell-test--press runtime 13 "Star reading")
      (research-cell-test--press runtime 13 "Advance reading")
      (should (= (plist-get (research-cell-test--row database-file 13) :progress) 52))
      (etaf-dispatch-event runtime 'research-shelf-page-previous 'press)
      (should (string-match-p
               "☐" (research-cell-test--text
                    runtime (research-cell-test--control runtime 1 "Star reading"))))
      (etaf-dispatch-event runtime 'research-shelf-page-next 'press)
      (etaf-dispatch-event runtime 'research-shelf-theme-toggle 'press)
      (should (string-match-p
               "☑" (research-cell-test--text
                    runtime (research-cell-test--control runtime 13 "Star reading"))))
      (research-cell-test--press runtime 13 "Advance reading")
      (should (= (plist-get (research-cell-test--row database-file 13) :progress) 62)))))

(ert-deftest research-shelf-cell-sqlite-abort-reloads-the-controlled-value ()
  "A real SQLite abort preserves the record; Reload restores editable cells."
  (research-cell-test--with-app (runtime database-file)
    (let ((before (research-cell-test--row database-file 2))
          (connection (sqlite-open database-file)))
      (unwind-protect
          (progn
            (sqlite-execute
             connection
             "CREATE TRIGGER reject_cell_edit BEFORE UPDATE ON reading_items
              WHEN NEW.id = 2 BEGIN SELECT RAISE(ABORT, 'cell write rejected'); END")
            (research-cell-test--press runtime 2 "Star reading")
            (should (equal before (research-cell-test--row database-file 2)))
            (should (string-match-p "Could not save" (research-cell-test--text runtime)))
            (should (string-match-p "Use Reload" (research-cell-test--text runtime)))
            (etaf-dispatch-event runtime 'research-shelf-reload 'press)
            (should (string-match-p
                     "☐" (research-cell-test--text
                          runtime (research-cell-test--control runtime 2 "Star reading"))))
            (research-cell-test--press runtime 2 "Advance reading")
            (should (equal before (research-cell-test--row database-file 2)))
            (should (string-match-p "Could not save" (research-cell-test--text runtime)))
            (sqlite-execute connection "DROP TRIGGER reject_cell_edit")
            (etaf-dispatch-event runtime 'research-shelf-reload 'press)
            (research-cell-test--press runtime 2 "Star reading")
            (research-cell-test--press runtime 2 "Advance reading")
            (should (= (plist-get (research-cell-test--row database-file 2) :starred) 1))
            (should (= (plist-get (research-cell-test--row database-file 2) :progress) 10))
            (should (string-match-p
                     "☑" (research-cell-test--text
                          runtime (research-cell-test--control runtime 2 "Star reading")))))
        (sqlite-close connection)))))

(ert-deftest research-shelf-cell-component-reuses-across-independent-apps ()
  "One cell definition resolves each App's own Context, including remounts."
  (research-cell-test--with-app (left left-file)
    (research-cell-test--with-app (right right-file)
      (let ((right-text (research-cell-test--text right))
            (left-data (etaf-research-shelf--controller
                        (research-cell-test--model left)))
            (right-data (etaf-research-shelf--controller
                         (research-cell-test--model right))))
        (should-not (eq left-data right-data))
        (dolist (data (list left-data right-data))
          (should (= (etaf-value (etaf-data-total data)) 256))
          (should (= (length (etaf-value (etaf-data-items data))) 12)))
        (etaf-dispatch-event left 'research-shelf-row-1 'press)
        (research-cell-test--press left 2 "Star reading")
        (research-cell-test--press left 2 "Advance reading")
        (should (equal right-text (research-cell-test--text right)))
        (should (= (plist-get (research-cell-test--row right-file 2) :starred) 0))
        (should (= (plist-get (research-cell-test--row right-file 2) :progress) 0))
        (should (equal (etaf-value (etaf-data-selection left-data)) '(1)))
        (should-not (etaf-value (etaf-data-selection right-data)))
        (etaf-dispatch-event right 'research-shelf-theme-toggle 'press)
        (research-cell-test--press right 1 "Star reading")
        (should (= (plist-get (research-cell-test--row left-file 1) :starred) 1))
        (should (= (plist-get (research-cell-test--row right-file 1) :starred) 0))
        (let ((old-left left)
              (buffer (etaf-runtime-buffer left)))
          (etaf-unmount left)
          (should-not (etaf-runtime-mounted-p old-left))
          (should-not (etaf-runtime-for-buffer buffer))
          (research-cell-test--press right 2 "Advance reading")
          (should (= (plist-get (research-cell-test--row right-file 2) :progress) 10))
          (setq left (research-cell-test--mount buffer left-file))
          (should-not (eq left old-left))
          (should (= (plist-get (research-cell-test--row left-file 2) :progress) 10))
          (should (string-match-p
                   "☑" (research-cell-test--text
                        left (research-cell-test--control left 2 "Star reading"))))
          (research-cell-test--press left 2 "Advance reading")
          (should (= (plist-get (research-cell-test--row left-file 2) :progress) 20))
          (should (= (plist-get (research-cell-test--row right-file 2) :progress) 10)))))))

(provide 'research-shelf-cell-tests)
;;; research-shelf-cell-tests.el ends here
