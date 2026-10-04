;;; pathfinding-gui-scenarios.el --- Search laboratory GUI acceptance -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Run in an existing owned graphical server without activating the application.
;; The shared verifier owns settlement, assertions and window-only screenshots.

;;; Code:
(require 'cl-lib)
(require 'subr-x)
(require 'etaf-playground)
(require 'etaf-ui)
(require 'emacs-gui-verifier)

(defun pf-gui--runtime (context)
  "Return CONTEXT's mounted public Runtime."
  (etaf-runtime-for-buffer (etaf-gui-verifier-context-target-buffer context)))
(defun pf-gui--text (context &optional ref)
  "Read CONTEXT's published plain text, optionally inside REF."
  (let* ((runtime (pf-gui--runtime context))
         (bounds (and ref (etaf-host-ref-bounds runtime ref))))
    (with-current-buffer (etaf-runtime-buffer runtime)
      (buffer-substring-no-properties (if bounds (car bounds) (point-min))
                                      (if bounds (cdr bounds) (point-max))))))
(defun pf-gui--cell (context row column)
  "Read CONTEXT's published tile at ROW,COLUMN."
  (string-trim (pf-gui--text context (intern (format "pf-cell-%d-%d" row column)))))
(defun pf-gui--counter (context label)
  "Read CONTEXT's displayed integer for LABEL."
  (let ((text (pf-gui--text context)))
    (when (string-match (concat label " +\\([0-9]+\\)") text)
      (string-to-number (match-string 1 text)))))
(defun pf-gui--press (context ref)
  "Activate CONTEXT's REF through real logical focus and RET."
  (etaf-focus (pf-gui--runtime context) ref)
  (execute-kbd-macro (kbd "RET")))
(defun pf-gui--choose (context field label)
  "Choose the visible LABEL chip inside CONTEXT's FIELD."
  (let* ((runtime (pf-gui--runtime context))
         (bounds (etaf-host-ref-bounds runtime field))
         (entries (cl-remove-if-not
                   (lambda (entry)
                     (let ((position (etaf-host-ref-position runtime (car entry))))
                       (and (equal label (plist-get (cdr entry) :aria-label)) position bounds
                            (<= (car bounds) position) (< position (cdr bounds)))))
                   (etaf-runtime-host-props-entries runtime))))
    (unless (= 1 (length entries)) (error "Missing unique %s chip" label))
    (pf-gui--press context (caar entries))))
(defun pf-gui--action (id execute verify)
  "Create an ordered screenshot action ID with EXECUTE and VERIFY."
  (etaf-gui-verifier-action-create
   :id id :execute execute :screenshot t
   :settled-p verify :settle-timeout 5
   :assertions (lambda (context) (list (etaf-gui-verifier-assert id (funcall verify context))))))

(defun pf-gui--invariants (context)
  "Return CONTEXT's mounted, selected-buffer and physical row assertions."
  (append
   (list (etaf-gui-verifier-assert "laboratory-mounted" (pf-gui--runtime context))
         (etaf-gui-verifier-assert
          "target-selected"
          (eq (window-buffer (selected-window)) (etaf-gui-verifier-context-target-buffer context)))
         (etaf-gui-verifier-assert
          "no-render-error"
          (not (string-match-p "runtime error\\|Wrong type argument\\|could not render"
                              (pf-gui--text context)))))
   (etaf-gui-verifier-line-height-assertions (etaf-gui-verifier-context-target-buffer context))))

(defun pf-gui--resize (width height)
  "Create a maintained WIDTH/HEIGHT layout action."
  (pf-gui--action
   (format "layout-%dx%d" width height)
   (lambda (_context) (set-frame-size (selected-frame) width height))
   (lambda (context)
     (and (= (frame-width) width) (= (frame-height) height)
          (etaf-gui-verifier-canvas-filled-p (etaf-gui-verifier-context-target-buffer context))
          (etaf-host-ref-bounds (pf-gui--runtime context) 'pf-start)))))

(defun pf-gui--scenario ()
  "Return the public search laboratory's full interactive GUI scenario."
  (etaf-gui-verifier-scenario-create
   :name "pathfinding" :claim "Interactive algorithms, controls, lifecycle and layout; background GUI"
   :initialize
   (lambda (context)
     (let ((buffer (get-buffer-create "*寻路 GUI 验收*")))
       (setf (etaf-gui-verifier-context-target-buffer context) buffer)
       (switch-to-buffer buffer) (delete-other-windows)
       (etaf-playground-mount-example (buffer-name buffer) "pathfinding")
       (etaf-refit (pf-gui--runtime context) (selected-window))))
   :invariants #'pf-gui--invariants
   :adapter (lambda (context)
              (list (cons 'explored (pf-gui--counter context "探索"))
                    (cons 'distance (pf-gui--counter context "路径"))
                    (cons 'state (string-trim (pf-gui--text context 'pf-status)))
                    (cons 'frame_width (frame-width)) (cons 'frame_height (frame-height))))
   :actions
   (append
    (list
     (pf-gui--action "initial-board" #'ignore
                     (lambda (c) (and (equal (pf-gui--cell c 2 2) "S")
                                      (equal (pf-gui--cell c 11 21) "G"))))
     (pf-gui--action "teaching-copy" #'ignore
                     (lambda (c)
                       (and (string-match-p "候选" (pf-gui--text c))
                            (string-match-p "单步" (pf-gui--text c 'pf-hint))
                            (string-match-p "跑完" (pf-gui--text c 'pf-compare)))))
     (pf-gui--action "keyboard-single-step" (lambda (_c) (execute-kbd-macro (kbd "n")))
                     (lambda (c) (= 1 (pf-gui--counter c "探索"))))
     (pf-gui--action "paint-wall-with-ret" (lambda (c) (pf-gui--press c 'pf-cell-0-0))
                     (lambda (c) (equal (pf-gui--cell c 0 0) "#")))
     (pf-gui--action "erase-wall" (lambda (c) (pf-gui--choose c 'pf-tool "擦除")
                                   (pf-gui--press c 'pf-cell-0-0))
                     (lambda (c) (equal (pf-gui--cell c 0 0) ".")))
     (pf-gui--action "move-start" (lambda (c) (pf-gui--choose c 'pf-tool "起点")
                                   (pf-gui--press c 'pf-cell-1-1))
                     (lambda (c) (equal (pf-gui--cell c 1 1) "S")))
     (pf-gui--action "move-goal" (lambda (c) (pf-gui--choose c 'pf-tool "终点")
                                  (pf-gui--press c 'pf-cell-2-5))
                     (lambda (c) (equal (pf-gui--cell c 2 5) "G")))
     (pf-gui--action "protect-endpoints" (lambda (c) (pf-gui--choose c 'pf-tool "障碍")
                                          (pf-gui--press c 'pf-cell-1-1))
                     (lambda (c) (equal (pf-gui--cell c 1 1) "S")))
     (pf-gui--action "all-speed-options"
                     (lambda (c) (dolist (label '("慢速" "正常" "快速"))
                                   (pf-gui--choose c 'pf-speed label)))
                     (lambda (c) (string-match-p "快速" (pf-gui--text c 'pf-speed))))
     (pf-gui--action "clear-obstacles" (lambda (c) (pf-gui--press c 'pf-clear))
                     (lambda (c) (equal (pf-gui--cell c 0 6) ".")))
     (pf-gui--action "animate-astar-to-completion" (lambda (c) (pf-gui--press c 'pf-start))
                     (lambda (c) (and (string-match-p "已找到" (pf-gui--text c 'pf-status))
                                      (= 5 (pf-gui--counter c "路径")))))
     (pf-gui--action "switch-to-bfs" (lambda (c) (pf-gui--choose c 'pf-algorithm "BFS"))
                     (lambda (c) (= 0 (pf-gui--counter c "探索"))))
     (pf-gui--action "animate-bfs-to-completion" (lambda (_c) (execute-kbd-macro (kbd "p")))
                     (lambda (c) (and (string-match-p "已找到" (pf-gui--text c 'pf-status))
                                      (= 5 (pf-gui--counter c "路径")))))
     (pf-gui--action "reset-keeps-map" (lambda (c) (pf-gui--press c 'pf-reset))
                     (lambda (c) (and (= 0 (pf-gui--counter c "探索"))
                                      (equal (pf-gui--cell c 1 1) "S"))))
     (pf-gui--action "running-edit-restarts"
                     (lambda (c) (pf-gui--press c 'pf-start)
                       (pf-gui--press c 'pf-cell-0-0)
                       (pf-gui--press c 'pf-pause))
                     (lambda (c) (and (equal (pf-gui--cell c 0 0) "#")
                                      (string-match-p "已暂停" (pf-gui--text c 'pf-status)))))
     (pf-gui--action "restore-preset" (lambda (c) (pf-gui--press c 'pf-preset))
                     (lambda (c) (equal (pf-gui--cell c 0 6) "#")))
     (pf-gui--action "arrows-and-tab"
                     (lambda (c) (etaf-focus (pf-gui--runtime c) 'pf-cell-0-0)
                       (execute-kbd-macro (kbd "<right> <down> <left> <up>"))
                       (unless (eq (etaf-focused-host-ref (pf-gui--runtime c)) 'pf-cell-0-0)
                         (error "Arrow navigation lost its target"))
                       (etaf-focus (pf-gui--runtime c) 'pf-start)
                       (execute-kbd-macro (kbd "TAB")))
                     (lambda (c) (eq (etaf-focused-host-ref (pf-gui--runtime c)) 'pf-pause))))
    (mapcar (lambda (size) (pf-gui--resize (car size) (cdr size)))
            '((130 . 50) (90 . 50) (60 . 50) (60 . 30)))
    (list
     (pf-gui--action "short-window-scroll"
                     (lambda (_c) (execute-kbd-macro (kbd "C-v")))
                     (lambda (c) (and (pf-gui--runtime c)
                                      (string-match-p "TAB 选控件" (pf-gui--text c)))))
     (pf-gui--resize 100 50)
     (pf-gui--action "refresh-releases-old-animation"
                     (lambda (c)
                       (pf-gui--press c 'pf-start)
                       (etaf-playground-mount-example
                        (buffer-name (etaf-gui-verifier-context-target-buffer c)) "pathfinding")
                       (etaf-refit (pf-gui--runtime c)))
                     (lambda (c) (and (string-match-p "准备就绪" (pf-gui--text c 'pf-status))
                                      (= 0 (pf-gui--counter c "探索"))
                                      (equal (pf-gui--cell c 2 2) "S"))))))
   :completion (lambda (context) (= 0 (pf-gui--counter context "探索")))))

(defun pathfinding-gui-run (directory)
  "Run all maintained GUI actions into fresh evidence DIRECTORY."
  (etaf-gui-verifier-run (pf-gui--scenario) directory))

(provide 'pathfinding-gui-scenarios)
;;; pathfinding-gui-scenarios.el ends here
