;;; pathfinding.el --- Interactive BFS and A* laboratory -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; A Playground consumer, not a second renderer.  Pure search state, caller-owned
;; cell refs, view projection and a mount-owned one-shot timer are separated below.
;; Run `etaf-pathfinding-open' for a standalone board, or open the "pathfinding"
;; Playground workspace to edit its source.  Maps live only in this instance.

;;; Code:
(require 'cl-lib)
(require 'etaf-ui)
(require 'etaf-playground)

;;; THEME: semantic colors in one place, no per-cell Theme dependency.
(defconst pathfinding--colors
  '((empty . "#182332") (wall . "#46546C") (frontier . "#167B9A")
    (visited . "#25445D") (current . "#9752BA") (path . "#8D6C1C")
    (start . "#176D50") (goal . "#98435C")))
(defconst pathfinding--palette
  '(:ui-fg "#E5EDF7" :ui-bg "#101925" :ui-muted-fg "#9CADC1"
    :ui-button-primary-bg "#356BB2" :ui-button-primary-fg "#FFFFFF"
    :ui-button-secondary-bg "#253B55" :ui-button-secondary-fg "#E5EDF7"
    :ui-button-ghost-fg "#B9CADC"))

;;; SEARCH: bounded, deterministic, four-way, uniform-cost; no UI or timers.
(cl-defstruct (pathfinding--search (:constructor pathfinding--make-search))
  rows columns walls start goal algorithm costs parents closed queue
  (head 0) (tail 0) heap (heap-size 0) (serial 0) (frontier 1)
  (expanded 0) (phase 'search) path distance)

(defun pathfinding--heuristic (search index)
  "Return Manhattan distance from INDEX to SEARCH's goal."
  (let ((columns (pathfinding--search-columns search))
        (goal (pathfinding--search-goal search)))
    (+ (abs (- (% index columns) (% goal columns)))
       (abs (- (/ index columns) (/ goal columns))))))

(defun pathfinding--priority-before-p (left right)
  "Order heap entries LEFT and RIGHT by f, then larger g, then arrival."
  (or (< (aref left 0) (aref right 0))
      (and (= (aref left 0) (aref right 0))
           (or (< (aref left 1) (aref right 1))
               (and (= (aref left 1) (aref right 1))
                    (< (aref left 2) (aref right 2)))))))

(defun pathfinding--heap-push (search index cost)
  "Insert INDEX with COST into SEARCH's binary min-heap."
  (let* ((size (pathfinding--search-heap-size search))
         (heap (pathfinding--search-heap search))
         (entry (vector (+ cost (pathfinding--heuristic search index))
                        (- cost) (cl-incf (pathfinding--search-serial search)) index)))
    (when (= size (length heap))
      (setq heap (vconcat heap (make-vector (max 1 size) nil)))
      (setf (pathfinding--search-heap search) heap))
    (let ((position size))
      (while (and (> position 0)
                  (pathfinding--priority-before-p entry (aref heap (/ (1- position) 2))))
        (aset heap position (aref heap (/ (1- position) 2)))
        (setq position (/ (1- position) 2)))
      (aset heap position entry))
    (cl-incf (pathfinding--search-heap-size search))))

(defun pathfinding--heap-pop (search)
  "Remove the minimum entry from SEARCH, returning its cell index or nil."
  (when (> (pathfinding--search-heap-size search) 0)
    (let* ((heap (pathfinding--search-heap search))
           (top (aref heap 0))
           (size (cl-decf (pathfinding--search-heap-size search)))
           (last (aref heap size)) (position 0))
      (aset heap size nil)
      (when (> size 0)
        (let (finished)
          (while (not finished)
            (let ((child (1+ (* 2 position))))
              (if (>= child size) (setq finished t)
                (when (and (< (1+ child) size)
                           (pathfinding--priority-before-p
                            (aref heap (1+ child)) (aref heap child)))
                  (cl-incf child))
                (if (pathfinding--priority-before-p (aref heap child) last)
                    (progn (aset heap position (aref heap child)) (setq position child))
                  (setq finished t)))))
          (aset heap position last)))
      (aref top 3))))

(defun pathfinding--search-create (rows columns walls start goal algorithm)
  "Create an isolated SEARCH snapshot for ROWS, COLUMNS, WALLS and endpoints."
  (let* ((count (* rows columns))
         (search (pathfinding--make-search
                  :rows rows :columns columns :walls (copy-sequence walls)
                  :start start :goal goal :algorithm algorithm
                  :costs (make-vector count -1) :parents (make-vector count nil)
                  :closed (make-vector count nil) :queue (make-vector count nil)
                  :heap (make-vector count nil))))
    (aset (pathfinding--search-costs search) start 0)
    (if (eq algorithm 'bfs)
        (progn (aset (pathfinding--search-queue search) 0 start)
               (setf (pathfinding--search-tail search) 1))
      (pathfinding--heap-push search start 0))
    search))

(defun pathfinding--neighbors (search index)
  "Return SEARCH's in-bounds neighbors of INDEX in stable right/down/left/up order."
  (let ((columns (pathfinding--search-columns search))
        (rows (pathfinding--search-rows search)) result)
    (when (> (/ index columns) 0) (push (- index columns) result))
    (when (> (% index columns) 0) (push (1- index) result))
    (when (< (/ index columns) (1- rows)) (push (+ index columns) result))
    (when (< (% index columns) (1- columns)) (push (1+ index) result))
    result))

(defun pathfinding--search-step (search)
  "Advance SEARCH once; return changed (INDEX . VISUAL-STATE) cells."
  (pcase (pathfinding--search-phase search)
    ('trace
     (let ((index (pop (pathfinding--search-path search))))
       (unless (pathfinding--search-path search)
         (setf (pathfinding--search-phase search) 'found))
       (when index (list (cons index 'path)))))
    ('search
     (let (index changes)
       (if (eq (pathfinding--search-algorithm search) 'bfs)
           (when (< (pathfinding--search-head search) (pathfinding--search-tail search))
             (setq index (aref (pathfinding--search-queue search)
                               (pathfinding--search-head search)))
             (cl-incf (pathfinding--search-head search)))
         (while (and (> (pathfinding--search-heap-size search) 0) (null index))
           (let ((next (pathfinding--heap-pop search)))
             (unless (aref (pathfinding--search-closed search) next) (setq index next)))))
       (if (null index)
           (setf (pathfinding--search-phase search) 'unreachable)
         (aset (pathfinding--search-closed search) index t)
         (cl-incf (pathfinding--search-expanded search))
         (cl-decf (pathfinding--search-frontier search))
         (push (cons index 'current) changes)
         (if (= index (pathfinding--search-goal search))
             (let ((cursor index) route)
               (while cursor
                 (push cursor route)
                 (setq cursor (aref (pathfinding--search-parents search) cursor)))
               (let ((interior (butlast (cdr route))))
                 (setf (pathfinding--search-path search) interior
                       (pathfinding--search-distance search) (1- (length route))
                       (pathfinding--search-phase search) (if interior 'trace 'found))))
           (dolist (next (pathfinding--neighbors search index))
             (let ((cost (1+ (aref (pathfinding--search-costs search) index)))
                   (old (aref (pathfinding--search-costs search) next)))
               (when (and (not (aref (pathfinding--search-walls search) next))
                          (not (aref (pathfinding--search-closed search) next))
                          (or (< old 0) (< cost old)))
                 (when (< old 0) (cl-incf (pathfinding--search-frontier search)))
                 (aset (pathfinding--search-costs search) next cost)
                 (aset (pathfinding--search-parents search) next index)
                 (if (eq (pathfinding--search-algorithm search) 'bfs)
                     (progn
                       (aset (pathfinding--search-queue search)
                             (pathfinding--search-tail search) next)
                       (cl-incf (pathfinding--search-tail search)))
                   (pathfinding--heap-push search next cost))
                 (push (cons next 'frontier) changes))))))
       changes))))

;;; MODEL: board truth and visual refs, headless and independent per mount.
(cl-defstruct (pathfinding--model (:constructor pathfinding--make-model))
  rows columns walls cells start goal search current
  algorithm tool speed status summary detail notice)

(defun pathfinding--model-create (rows columns)
  "Create a bounded in-memory board of ROWS by COLUMNS."
  (let* ((count (* rows columns))
         (model (pathfinding--make-model
                 :rows rows :columns columns :walls (make-vector count nil)
                 :cells (vconcat (cl-loop repeat count collect (etaf-ref 'empty)))
                 :start (+ (* columns 2) 2) :goal (+ (* columns (- rows 3)) (- columns 3))
                 :algorithm (etaf-ref 'astar) :tool (etaf-ref 'wall) :speed (etaf-ref 15)
                 :status (etaf-ref 'ready) :summary (etaf-ref "") :detail (etaf-ref "")
                 :notice (etaf-ref "点击格子添障碍；再点一次擦除。"))))
    (pathfinding--preset model)
    (pathfinding--reset model)
    model))

(defun pathfinding--preset (model)
  "Replace MODEL's walls with alternating corridor barriers."
  (fillarray (pathfinding--model-walls model) nil)
  (let ((rows (pathfinding--model-rows model)) (columns (pathfinding--model-columns model)))
    (cl-loop for column from 6 below (- columns 3) by 6
             for barrier from 0 do
             (dotimes (row rows)
               (unless (= row (if (zerop (% barrier 2)) (- rows 4) 3))
                 (aset (pathfinding--model-walls model) (+ (* row columns) column) t)))))
  (aset (pathfinding--model-walls model) (pathfinding--model-start model) nil)
  (aset (pathfinding--model-walls model) (pathfinding--model-goal model) nil))

(defun pathfinding--paint (model index state)
  "Project STATE into MODEL's cell INDEX while preserving endpoints and walls."
  (setf (etaf-value (aref (pathfinding--model-cells model) index))
        (cond ((= index (pathfinding--model-start model)) 'start)
              ((= index (pathfinding--model-goal model)) 'goal)
              ((aref (pathfinding--model-walls model) index) 'wall)
              (t state))))

(defun pathfinding--update-summary (model)
  "Publish MODEL's fixed-width counters, separate from its control structure."
  (let ((search (pathfinding--model-search model)))
    (setf (etaf-value (pathfinding--model-summary model))
          (format "探索 %4d 格    前沿 %4d 格"
                  (pathfinding--search-expanded search) (pathfinding--search-frontier search))
          (etaf-value (pathfinding--model-detail model))
          (format "路径 %4s 步    阶段 %s"
                  (or (pathfinding--search-distance search) "--")
                  (pcase (pathfinding--search-phase search)
                    ('trace "点亮路线") ('found "找到最短路径")
                    ('unreachable "没有可达路径") (_ "搜索中"))))))

(defun pathfinding--reset (model)
  "Reset only MODEL's search; keep terrain, endpoints, algorithm and speed."
  (setf (pathfinding--model-search model)
        (pathfinding--search-create
         (pathfinding--model-rows model) (pathfinding--model-columns model)
         (pathfinding--model-walls model) (pathfinding--model-start model)
         (pathfinding--model-goal model) (etaf-value (pathfinding--model-algorithm model)))
        (pathfinding--model-current model) nil)
  (etaf-batch
    (dotimes (index (length (pathfinding--model-cells model)))
      (pathfinding--paint model index 'empty))
    (pathfinding--paint model (pathfinding--model-start model) 'frontier)
    (setf (etaf-value (pathfinding--model-status model)) 'ready)
    (pathfinding--update-summary model)))

(defun pathfinding--advance (model)
  "Expand one node or illuminate one path cell in MODEL, in one batch."
  (let* ((search (pathfinding--model-search model))
         (phase (pathfinding--search-phase search)))
    (unless (memq phase '(found unreachable))
      (etaf-batch
        (when (and (eq phase 'search) (pathfinding--model-current model))
          (pathfinding--paint model (pathfinding--model-current model) 'visited))
        (dolist (change (pathfinding--search-step search))
          (when (eq (cdr change) 'current)
            (setf (pathfinding--model-current model) (car change)))
          (pathfinding--paint model (car change) (cdr change)))
        (when (memq (pathfinding--search-phase search) '(found unreachable))
          (setf (etaf-value (pathfinding--model-status model))
                (pathfinding--search-phase search)))
        (pathfinding--update-summary model)))))

;;; APP: timer, keyboard and lifecycle; never run work from View evaluation.
(defvar-local pathfinding--session nil)
(defvar pathfinding--command-maps
  (list
   (cons 'pathfinding--session
         (let ((map (make-sparse-keymap)))
           (define-key map (kbd "p") #'pathfinding--toggle-command)
           (define-key map (kbd "n") #'pathfinding--step-command)
           (define-key map (kbd "r") #'pathfinding--reset-command)
           (define-key map (kbd "q") #'pathfinding--close-command)
           (define-key map (kbd "<right>") (lambda () (interactive) (pathfinding--move-focus 0 1)))
           (define-key map (kbd "<left>") (lambda () (interactive) (pathfinding--move-focus 0 -1)))
           (define-key map (kbd "<down>") (lambda () (interactive) (pathfinding--move-focus 1 0)))
           (define-key map (kbd "<up>") (lambda () (interactive) (pathfinding--move-focus -1 0)))
           map))))

(defun pathfinding--stop-timer (session)
  "Cancel SESSION's sole pending timer."
  (when (timerp (plist-get session :timer)) (cancel-timer (plist-get session :timer)))
  (setf (plist-get session :timer) nil))

(defun pathfinding--dispose (session)
  "Release SESSION without touching another mounted instance."
  (pathfinding--stop-timer session)
  (setf (plist-get session :disposed) t)
  (when-let* ((runtime (plist-get session :runtime))
              (buffer (etaf-runtime-buffer runtime)))
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (when (eq pathfinding--session session)
          (setq pathfinding--session nil)
          (setq-local emulation-mode-map-alists
                      (remq 'pathfinding--command-maps emulation-mode-map-alists)))))))

(defun pathfinding--arm (session)
  "Schedule one future animation step in SESSION, without catch-up bursts."
  (pathfinding--stop-timer session)
  (let ((model (plist-get session :model)))
    (when (and (not (plist-get session :disposed))
               (eq (etaf-value (pathfinding--model-status model)) 'running))
      (setf (plist-get session :timer)
            (run-at-time (/ 1.0 (etaf-value (pathfinding--model-speed model))) nil
                         #'pathfinding--tick session)))))

(defun pathfinding--tick (session)
  "Advance a live, visible SESSION once; stop at completion or the safety bound."
  (setf (plist-get session :timer) nil)
  (let* ((runtime (plist-get session :runtime))
         (model (plist-get session :model))
         (buffer (and runtime (etaf-runtime-buffer runtime))))
    (when (and (not (plist-get session :disposed))
               (buffer-live-p buffer) (eq runtime (etaf-runtime-for-buffer buffer))
               (eq (etaf-value (pathfinding--model-status model)) 'running))
      (cond
       ((not (get-buffer-window buffer t))
        (etaf-batch
          (setf (etaf-value (pathfinding--model-status model)) 'paused
                (etaf-value (pathfinding--model-notice model)) "棋盘隐藏，已暂停；回来后按 p 继续。")))
       ((>= (cl-incf (plist-get session :ticks))
            (* 3 (length (pathfinding--model-cells model))))
        (etaf-batch
          (setf (etaf-value (pathfinding--model-status model)) 'paused
                (etaf-value (pathfinding--model-notice model)) "达到安全步数上限，已暂停；请重置搜索。")))
       (t
        ;; A failed publication is a visible failure, never an infinite timer.
        (condition-case problem
            (progn (pathfinding--advance model) (pathfinding--arm session))
          (error
           (pathfinding--stop-timer session)
           (setf (etaf-value (pathfinding--model-status model)) 'paused)
           (message "寻路已暂停：%s" (error-message-string problem)))))))))

(defun pathfinding--restart (session notice)
  "Rebuild SESSION's search after an edit, preserving its running/paused choice."
  (let* ((model (plist-get session :model))
         (running (eq (etaf-value (pathfinding--model-status model)) 'running))
         (paused (eq (etaf-value (pathfinding--model-status model)) 'paused)))
    (pathfinding--stop-timer session)
    (setf (plist-get session :ticks) 0)
    (etaf-batch
      (pathfinding--reset model)
      (setf (etaf-value (pathfinding--model-status model))
            (cond (running 'running) (paused 'paused) (t 'ready))
            (etaf-value (pathfinding--model-notice model)) notice))
    (pathfinding--arm session)))

(defun pathfinding--action (session action)
  "Apply ACTION through SESSION's application boundary."
  (let ((model (plist-get session :model)))
    (pcase action
      ('start
       (when (memq (etaf-value (pathfinding--model-status model)) '(found unreachable))
         (pathfinding--restart session "已开始新一轮搜索。"))
       (setf (etaf-value (pathfinding--model-status model)) 'running)
       (pathfinding--arm session))
      ('pause
       (pathfinding--stop-timer session)
       (unless (memq (etaf-value (pathfinding--model-status model)) '(found unreachable))
         (setf (etaf-value (pathfinding--model-status model)) 'paused)))
      ('step
       (pathfinding--action session 'pause)
       (pathfinding--advance model))
      ('reset
       (pathfinding--stop-timer session)
       (setf (plist-get session :ticks) 0)
       (etaf-batch (pathfinding--reset model)
         (setf (etaf-value (pathfinding--model-notice model)) "已重置搜索，地图和起终点保留。")))
      ('clear
       (fillarray (pathfinding--model-walls model) nil)
       (pathfinding--restart session "障碍已清空，已重新准备搜索。"))
      ('preset
       (pathfinding--preset model)
       (pathfinding--restart session "示例地图已载入，已重新准备搜索。")))))

(defun pathfinding--edit (session row column)
  "Apply SESSION's selected editing tool at ROW,COLUMN, then restart if changed."
  (let* ((model (plist-get session :model))
         (index (+ (* row (pathfinding--model-columns model)) column))
         (walls (pathfinding--model-walls model)) changed)
    (pcase (etaf-value (pathfinding--model-tool model))
      ('start
       (unless (or (= index (pathfinding--model-goal model))
                   (= index (pathfinding--model-start model)))
         (setf (pathfinding--model-start model) index)
         (aset walls index nil) (setq changed t)))
      ('goal
       (unless (or (= index (pathfinding--model-start model))
                   (= index (pathfinding--model-goal model)))
         (setf (pathfinding--model-goal model) index)
         (aset walls index nil) (setq changed t)))
      ((or 'wall 'erase)
       (unless (or (= index (pathfinding--model-start model))
                   (= index (pathfinding--model-goal model)))
         (let ((next (and (eq (etaf-value (pathfinding--model-tool model)) 'wall)
                          (not (aref walls index)))))
           (unless (eq next (aref walls index))
             (aset walls index next) (setq changed t))))))
    (when changed (pathfinding--restart session "地图改变，已从当前起点重新寻路。"))))

(defun pathfinding--install (session)
  "Attach SESSION to its mounted buffer and register exact-instance cleanup."
  (let ((runtime (etaf-current-runtime)))
    (setf (plist-get session :runtime) runtime)
    (with-current-buffer (etaf-runtime-buffer runtime)
      (setq-local pathfinding--session session)
      (setq-local emulation-mode-map-alists
                  (cons 'pathfinding--command-maps
                        (remq 'pathfinding--command-maps emulation-mode-map-alists))))
    (etaf-on-unmounted (lambda () (pathfinding--dispose session)))))

(defun pathfinding--toggle-command ()
  "Toggle the current laboratory's animation."
  (interactive)
  (pathfinding--action pathfinding--session
                      (if (eq (etaf-value (pathfinding--model-status
                                            (plist-get pathfinding--session :model))) 'running)
                          'pause 'start)))
(defun pathfinding--step-command ()
  "Single-step the current laboratory."
  (interactive) (pathfinding--action pathfinding--session 'step))
(defun pathfinding--reset-command ()
  "Reset the current laboratory's search."
  (interactive) (pathfinding--action pathfinding--session 'reset))
(defun pathfinding--close-command ()
  "Close only the current laboratory."
  (interactive)
  (when-let* ((runtime (etaf-runtime-for-buffer (current-buffer)))) (etaf-unmount runtime))
  (kill-buffer (current-buffer)))

(defun pathfinding--cell-ref (row column)
  "Return this instance's public coordinate address for ROW,COLUMN."
  (intern (format "pf-cell-%d-%d" row column)))

(defun pathfinding--move-focus (dr dc)
  "Move the board's logical focus by DR,DC, without changing application focus."
  (let* ((runtime (plist-get pathfinding--session :runtime))
         (model (plist-get pathfinding--session :model))
         (ref (etaf-focused-host-ref runtime))
         (name (and (symbolp ref) (symbol-name ref)))
         (row 0) (column 0))
    (when (and name (string-match "\\`pf-cell-\\([0-9]+\\)-\\([0-9]+\\)\\'" name))
      (setq row (string-to-number (match-string 1 name))
            column (string-to-number (match-string 2 name))))
    (etaf-focus runtime
                (pathfinding--cell-ref
                 (max 0 (min (1- (pathfinding--model-rows model)) (+ row dr)))
                 (max 0 (min (1- (pathfinding--model-columns model)) (+ column dc)))))))

;;; VIEW: refs read only in the property/text that actually changes.
(etaf-define-component pathfinding--controls (&key session model)
  :view
  (column :item-gap '(lh 1)
    (flex :flex-wrap 'wrap :gap '((lh 1) (ch 1))
      (etaf-button :label "开始/继续" :ref 'pf-start
                   :on-press (lambda () (pathfinding--action session 'start)))
      (etaf-button :label "暂停" :ref 'pf-pause :variant 'secondary
                   :on-press (lambda () (pathfinding--action session 'pause)))
      (etaf-button :label "单步" :ref 'pf-step :variant 'secondary
                   :on-press (lambda () (pathfinding--action session 'step)))
      (etaf-button :label "重置搜索" :ref 'pf-reset :variant 'ghost
                   :on-press (lambda () (pathfinding--action session 'reset))))
    (flex :flex-wrap 'wrap :gap '((lh 1) (ch 2)) :align-items 'center
      (etaf-select :label "算法" :value (etaf-value (pathfinding--model-algorithm model))
                   :options '((astar . "A*") (bfs . "BFS")) :presentation 'chips :ref 'pf-algorithm
                   :on-change (lambda (next)
                                (setf (etaf-value (pathfinding--model-algorithm model)) next)
                                (pathfinding--restart session "算法已切换，地图保持不变。")))
      (etaf-select :label "速度" :value (etaf-value (pathfinding--model-speed model))
                   :options '((5 . "慢速") (15 . "正常") (30 . "快速"))
                   :presentation 'chips :ref 'pf-speed
                   :on-change (lambda (next)
                                (setf (etaf-value (pathfinding--model-speed model)) next)
                                (pathfinding--arm session))))
    (etaf-select :label "工具" :value (etaf-value (pathfinding--model-tool model))
                 :options '((wall . "障碍") (erase . "擦除") (start . "起点") (goal . "终点"))
                 :presentation 'chips :ref 'pf-tool
                 :on-change (lambda (next) (setf (etaf-value (pathfinding--model-tool model)) next)))
    (flex :flex-wrap 'wrap :gap '((lh 0) (ch 1))
      (etaf-button :label "示例地图" :ref 'pf-preset :variant 'ghost
                   :on-press (lambda () (pathfinding--action session 'preset)))
      (etaf-button :label "清空障碍" :ref 'pf-clear :variant 'ghost
                   :on-press (lambda () (pathfinding--action session 'clear))))))

(etaf-define-component pathfinding--board (&key session model)
  :view
  (etaf-tile-grid
   :rows (pathfinding--model-rows model) :columns (pathfinding--model-columns model)
   :cell-width 2 :cell-ref #'pathfinding--cell-ref
   :cell-background (lambda (row column)
                      (cdr (assq (etaf-value
                                  (aref (pathfinding--model-cells model)
                                        (+ (* row (pathfinding--model-columns model)) column)))
                                 pathfinding--colors)))
   :cell-text (lambda (row column)
                (pcase (etaf-value (aref (pathfinding--model-cells model)
                                       (+ (* row (pathfinding--model-columns model)) column)))
                  ('start "S") ('goal "G") ('wall "#") ('path "+")
                  ('current "@") (_ ".")))
   :on-cell-press (lambda (row column) (pathfinding--edit session row column))))

(etaf-define-component pathfinding-app (&key (rows 14) (columns 24))
  :validate
  (progn
    (etaf-check-prop :rows rows (and (integerp rows) (<= 6 rows 24)) "an integer from 6 to 24")
    (etaf-check-prop :columns columns (and (integerp columns) (<= 6 columns 40)) "an integer from 6 to 40"))
  :bindings ((model (pathfinding--model-create rows columns))
             (session (list :model model :timer nil :runtime nil :disposed nil :ticks 0)))
  :setup (progn (etaf-theme-provide pathfinding--palette) (pathfinding--install session))
  :view
  (column :width '(vw 100) :height '(vh 100) :overflow 'scroll
          :padding '((lh 1) (ch 2)) :item-gap '(lh 1)
          :color (plist-get pathfinding--palette :ui-fg)
          :background-color (plist-get pathfinding--palette :ui-bg)
    (text :font-weight 'bold "寻路实验台")
    (etaf-label :width 'stretch :wrap-mode 'word :text "搜索前沿会扩散；你可以随时改变地图。")
    (pathfinding--controls :session session :model model)
    (column :width '(ch 48) :wrap-mode 'none
      (box :width '(ch 48) :height '(lh 1)
        (text :ref 'pf-status
              (expr (format "状态：%s"
                            (pcase (etaf-value (pathfinding--model-status model))
                              ('running "运行中") ('paused "已暂停") ('found "已找到")
                              ('unreachable "不可达") (_ "准备就绪"))))))
      (box :width '(ch 48) :height '(lh 1)
        (text :ref 'pf-summary (expr (etaf-value (pathfinding--model-summary model)))))
      (box :width '(ch 48) :height '(lh 1)
        (text :ref 'pf-detail (expr (etaf-value (pathfinding--model-detail model))))))
    (pathfinding--board :session session :model model)
    (flex :flex-wrap 'wrap :gap '((lh 0) (ch 1))
      (text :background-color (cdr (assq 'start pathfinding--colors)) " S 起点 ")
      (text :background-color (cdr (assq 'goal pathfinding--colors)) " G 终点 ")
      (text :background-color (cdr (assq 'wall pathfinding--colors)) " # 障碍 ")
      (text :background-color (cdr (assq 'frontier pathfinding--colors)) " 前沿 ")
      (text :background-color (cdr (assq 'visited pathfinding--colors)) " 已探索 ")
      (text :background-color (cdr (assq 'path pathfinding--colors)) " + 路径 "))
    (etaf-label :width 'stretch :wrap-mode 'word :text (pathfinding--model-notice model))
    (etaf-label :width 'stretch :wrap-mode 'word :variant 'muted
                :text "p 开始/暂停 · n 单步 · r 重置 · q 关闭")
    (etaf-label :width 'stretch :wrap-mode 'word :variant 'muted
                :text "方向键 移动格子焦点 · RET 使用工具 · TAB 选控件")))

(defun etaf-pathfinding-root (static-form &optional _styles)
  "Construct the shipped search laboratory from inert STATIC-FORM props."
  (etaf-node (car static-form) (cdr static-form) nil))

(etaf-playground-register-example "pathfinding" :root #'etaf-pathfinding-root
                                  :reload-on-refresh t)

;;;###autoload
(defun etaf-pathfinding-open (&optional buffer-name)
  "Open an independent search laboratory in BUFFER-NAME."
  (interactive)
  (switch-to-buffer
   (etaf-playground-mount-example (or buffer-name "*寻路实验台*") "pathfinding")))

(provide 'pathfinding)
;;; pathfinding.el ends here
