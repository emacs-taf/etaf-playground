;;; pathfinding-tests.el --- Public search laboratory workflows -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Mount the shipped companion; operate only visible controls and public ETAF
;; queries.  No model access, timer inspection, private calls or network.

;;; Code:
(require 'ert)
(require 'cl-lib)
(require 'subr-x)
(require 'etaf-playground)
(require 'etaf-ui)

(defun pf-test--mount (buffer)
  "Mount the maintained laboratory into BUFFER with a resolved viewport."
  (etaf-playground-mount-example
   (buffer-name buffer) "pathfinding" nil
   (list :viewport-width (* 100 (frame-char-width)) :viewport-height 52))
  (etaf-runtime-for-buffer buffer))

(cl-defmacro pf-test--with-lab ((buffer runtime) &rest body)
  "Run BODY in an isolated public laboratory BUFFER and RUNTIME."
  (declare (indent 1) (debug (form body)))
  `(let ((,buffer (generate-new-buffer " *Pathfinding acceptance*")))
     (unwind-protect
         (let ((,runtime (pf-test--mount ,buffer))) ,@body)
       (when-let* ((live (etaf-runtime-for-buffer ,buffer))) (etaf-unmount live))
       (when (buffer-live-p ,buffer) (kill-buffer ,buffer)))))

(defun pf-test--text (runtime &optional ref)
  "Read RUNTIME's published plain text, optionally just Host REF."
  (let ((bounds (and ref (etaf-host-ref-bounds runtime ref))))
    (with-current-buffer (etaf-runtime-buffer runtime)
      (buffer-substring-no-properties (if bounds (car bounds) (point-min))
                                      (if bounds (cdr bounds) (point-max))))))

(defun pf-test--cell-ref (row column)
  "Return the documented coordinate address for ROW,COLUMN."
  (intern (format "pf-cell-%d-%d" row column)))

(defun pf-test--cell (runtime row column)
  "Read RUNTIME's visible tile at ROW,COLUMN."
  (string-trim (pf-test--text runtime (pf-test--cell-ref row column))))

(defun pf-test--press (runtime ref)
  "Press RUNTIME's public Host REF."
  (etaf-dispatch-event runtime ref 'press))

(defun pf-test--choose (runtime field label)
  "Choose the visible LABEL chip inside RUNTIME's FIELD."
  (let* ((bounds (etaf-host-ref-bounds runtime field))
         (choices
          (cl-remove-if-not
           (lambda (entry)
             (let ((position (etaf-host-ref-position runtime (car entry))))
               (and (equal label (plist-get (cdr entry) :aria-label)) position bounds
                    (<= (car bounds) position) (< position (cdr bounds)))))
           (etaf-runtime-host-props-entries runtime))))
    (should (= (length choices) 1))
    (pf-test--press runtime (caar choices))))

(defun pf-test--counter (runtime label)
  "Read the integer counter named LABEL from RUNTIME."
  (let ((text (pf-test--text runtime)))
    (should (string-match (concat label " +\\([0-9]+\\)") text))
    (string-to-number (match-string 1 text))))

(defun pf-test--finish (runtime)
  "Single-step RUNTIME to an observable terminal state, with a fixed bound."
  (let ((remaining 1008))
    (while (and (> remaining 0)
                (not (string-match-p "已找到\\|不可达" (pf-test--text runtime 'pf-status))))
      (cl-decf remaining)
      (pf-test--press runtime 'pf-step))
    (should (> remaining 0))))

(defun pf-test--wait (predicate)
  "Wait at most two seconds for PREDICATE while Emacs timers progress."
  (let ((deadline (+ (float-time) 2)))
    (while (and (< (float-time) deadline) (not (funcall predicate))) (sleep-for 0.02))
    (should (funcall predicate))))

(ert-deftest pathfinding-editing-tools-protect-and-move-endpoints ()
  "Toggling and erasing walls preserve distinct movable start/goal cells."
  (pf-test--with-lab (buffer runtime)
    (ignore buffer)
    (should (equal (pf-test--cell runtime 2 2) "S"))
    (should (equal (pf-test--cell runtime 11 21) "G"))
    (pf-test--press runtime 'pf-cell-0-0)
    (should (equal (pf-test--cell runtime 0 0) "#"))
    (pf-test--choose runtime 'pf-tool "擦除")
    (pf-test--press runtime 'pf-cell-0-0)
    (should (equal (pf-test--cell runtime 0 0) "."))
    (pf-test--choose runtime 'pf-tool "障碍")
    (pf-test--press runtime 'pf-cell-2-2)
    (should (equal (pf-test--cell runtime 2 2) "S"))
    (pf-test--choose runtime 'pf-tool "起点")
    (pf-test--press runtime 'pf-cell-0-0)
    (should (equal (pf-test--cell runtime 0 0) "S"))
    (should (equal (pf-test--cell runtime 2 2) "."))
    (pf-test--choose runtime 'pf-tool "终点")
    (pf-test--press runtime 'pf-cell-0-0)
    (should (equal (pf-test--cell runtime 0 0) "S"))
    (pf-test--press runtime 'pf-cell-0-1)
    (should (equal (pf-test--cell runtime 0 1) "G"))
    (should (equal (pf-test--cell runtime 11 21) "."))))

(ert-deftest pathfinding-bfs-and-astar-find-the-same-shortest-detour ()
  "Both algorithms find a five-step detour and never traverse the obstacle."
  (pf-test--with-lab (buffer runtime)
    (ignore buffer)
    (pf-test--press runtime 'pf-clear)
    (pf-test--choose runtime 'pf-tool "终点")
    (pf-test--press runtime 'pf-cell-2-5)
    (pf-test--choose runtime 'pf-tool "障碍")
    (pf-test--press runtime 'pf-cell-2-3)
    (let (astar-expanded)
      (dolist (algorithm '("A*" "BFS"))
        (pf-test--choose runtime 'pf-algorithm algorithm)
        (pf-test--finish runtime)
        (should (string-match-p "已找到" (pf-test--text runtime 'pf-status)))
        (should (= (pf-test--counter runtime "路径") 5))
        (should (equal (pf-test--cell runtime 2 3) "#"))
        (should (equal (pf-test--cell runtime 2 2) "S"))
        (should (equal (pf-test--cell runtime 2 5) "G"))
        (let ((expanded (pf-test--counter runtime "探索")))
          (if (equal algorithm "A*") (setq astar-expanded expanded)
            (should (<= astar-expanded expanded))))))))

(ert-deftest pathfinding-default-maze-produces-a-contiguous-shortest-route ()
  "A* and BFS solve the shipped maze with equal distances and contiguous cells."
  (pf-test--with-lab (buffer runtime)
    (ignore buffer)
    (let (distance)
      (dolist (algorithm '("A*" "BFS"))
        (pf-test--choose runtime 'pf-algorithm algorithm)
        (pf-test--finish runtime)
        (should (string-match-p "已找到" (pf-test--text runtime 'pf-status)))
        (let ((next-distance (pf-test--counter runtime "路径")) (path (make-hash-table :test 'equal)))
          (dotimes (row 14)
            (dotimes (column 24)
              (when (member (pf-test--cell runtime row column) '("+" "S" "G"))
                (puthash (cons row column) t path))))
          (should (= (hash-table-count path) (1+ next-distance)))
          (maphash
           (lambda (cell _present)
             (let ((r (car cell)) (c (cdr cell)))
               (should (= (if (member cell '((2 . 2) (11 . 21))) 1 2)
                          (cl-count-if (lambda (next) (gethash next path))
                                       (list (cons (1+ r) c) (cons (1- r) c)
                                             (cons r (1+ c)) (cons r (1- c))))))))
           path)
          (if distance (should (= distance next-distance)) (setq distance next-distance)))))))

(ert-deftest pathfinding-unreachable-finishes-and-reset-preserves-terrain ()
  "An enclosed start terminates explicitly; reset keeps walls and endpoints."
  (pf-test--with-lab (buffer runtime)
    (ignore buffer)
    (pf-test--press runtime 'pf-clear)
    (dolist (ref '(pf-cell-2-1 pf-cell-2-3 pf-cell-1-2 pf-cell-3-2))
      (pf-test--press runtime ref))
    (pf-test--finish runtime)
    (should (string-match-p "不可达" (pf-test--text runtime 'pf-status)))
    (should (= (pf-test--counter runtime "探索") 1))
    (pf-test--press runtime 'pf-reset)
    (should (string-match-p "准备就绪" (pf-test--text runtime 'pf-status)))
    (should (equal (pf-test--cell runtime 2 1) "#"))
    (should (equal (pf-test--cell runtime 2 2) "S"))
    (pf-test--press runtime 'pf-preset)
    (should (equal (pf-test--cell runtime 2 1) "."))
    (should (equal (pf-test--cell runtime 0 6) "#"))))

(ert-deftest pathfinding-animation-pauses-resumes-edits-and-isolates-mounts ()
  "The real timer advances, respects pause, restarts edits and leaves peers alone."
  (pf-test--with-lab (buffer runtime)
    (save-window-excursion
      (set-window-buffer (selected-window) buffer)
      (pf-test--choose runtime 'pf-speed "快速")
      (pf-test--press runtime 'pf-start)
      (pf-test--wait (lambda () (> (pf-test--counter runtime "探索") 0)))
      (pf-test--press runtime 'pf-pause)
      (let ((count (pf-test--counter runtime "探索")))
        (sleep-for 0.1)
        (should (= (pf-test--counter runtime "探索") count)))
      (pf-test--press runtime 'pf-start)
      (pf-test--press runtime 'pf-cell-0-0)
      (should (string-match-p "运行中" (pf-test--text runtime 'pf-status)))
      (should (= (pf-test--counter runtime "探索") 0))
      (pf-test--wait (lambda () (> (pf-test--counter runtime "探索") 0)))
      (pf-test--choose runtime 'pf-algorithm "BFS")
      (should (= (pf-test--counter runtime "探索") 0))
      (pf-test--press runtime 'pf-pause)
      (pf-test--with-lab (peer peer-runtime)
        (ignore peer)
        (should (equal (pf-test--cell peer-runtime 0 0) "."))
        (let ((peer-text (pf-test--text peer-runtime)))
          (pf-test--press runtime 'pf-start)
          (etaf-unmount runtime)
          (sleep-for 0.15)
          (should-not (etaf-runtime-for-buffer buffer))
          (should (equal peer-text (pf-test--text peer-runtime))))))))

(ert-deftest pathfinding-hidden-and-replaced-mounts-stop-old-animation ()
  "Hidden boards pause automatically; replacement cannot receive obsolete ticks."
  (pf-test--with-lab (buffer runtime)
    (pf-test--press runtime 'pf-start)
    (pf-test--wait (lambda () (string-match-p "已暂停" (pf-test--text runtime 'pf-status))))
    (should (= (pf-test--counter runtime "探索") 0))
    (should (string-match-p "棋盘隐藏" (pf-test--text runtime)))
    (pf-test--press runtime 'pf-start)
    (let* ((replacement (pf-test--mount buffer)) (text (pf-test--text replacement)))
      (sleep-for 0.15)
      (should (equal text (pf-test--text replacement)))
      (should (string-match-p "准备就绪" text)))))

(ert-deftest pathfinding-keyboard-controls-and-coordinate-navigation ()
  "Real key bindings route arrows/RET, TAB, step, reset and close correctly."
  (pf-test--with-lab (buffer runtime)
    (save-window-excursion
      (switch-to-buffer buffer)
      (etaf-focus runtime 'pf-cell-0-0)
      (execute-kbd-macro (kbd "RET"))
      (should (equal (pf-test--cell runtime 0 0) "#"))
      (execute-kbd-macro (kbd "<right> RET"))
      (should (eq (etaf-focused-host-ref runtime) 'pf-cell-0-1))
      (should (equal (pf-test--cell runtime 0 1) "#"))
      (execute-kbd-macro (kbd "<down> <left> <up>"))
      (should (eq (etaf-focused-host-ref runtime) 'pf-cell-0-0))
      (execute-kbd-macro (kbd "n"))
      (should (= (pf-test--counter runtime "探索") 1))
      (execute-kbd-macro (kbd "r"))
      (should (= (pf-test--counter runtime "探索") 0))
      (execute-kbd-macro (kbd "p"))
      (should (string-match-p "运行中" (pf-test--text runtime 'pf-status)))
      (execute-kbd-macro (kbd "p"))
      (should (string-match-p "已暂停" (pf-test--text runtime 'pf-status)))
      (etaf-focus runtime 'pf-start)
      (execute-kbd-macro (kbd "TAB"))
      (should (eq (etaf-focused-host-ref runtime) 'pf-pause))
      (execute-kbd-macro (kbd "q"))
      (sleep-for 0.1)
      (should-not (buffer-live-p buffer)))))

(ert-deftest pathfinding-animation-step-is-one-local-publication ()
  "A warm animation step publishes bounded local text/paint, not the whole board."
  (pf-test--with-lab (buffer runtime)
    (ignore buffer)
    (pf-test--press runtime 'pf-step)
    (etaf-performance-start runtime)
    (unwind-protect
        (progn
          (pf-test--press runtime 'pf-step)
          (let* ((operation (car (last (plist-get (etaf-performance-report-data) :operations))))
                 (writes (cl-remove-if-not
                          (lambda (stage) (eq (plist-get stage :provider) 'ebox-publication))
                          (plist-get operation :stages))))
            (should (= (length writes) 1))
            (let ((facts (plist-get (car writes) :metadata)))
              (should-not (plist-get facts :full-root))
              (should-not (plist-get facts :scope-fallback))
              (should (< (plist-get facts :touched-characters) 100)))))
      (etaf-performance-stop runtime))))

(provide 'pathfinding-tests)
;;; pathfinding-tests.el ends here
