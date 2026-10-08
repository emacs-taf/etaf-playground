;;; performance-scenarios.el --- Research Shelf interaction latency -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Research Shelf workloads for the workspace `scripts/performance.py'.  Each
;; scenario mounts the example through `etaf-playground-mount-example' against
;; a fresh 256-record SQLite fixture with 12 rows per page, then repeats one
;; public event.  Batch runs use a fixed 1413x62 viewport; GUI runs follow the
;; displaying window.  Filter and page replace a page of keyed rows, so their
;; budget is two frames; the others must fit one frame.
;;
;;   etaf-playground.research.row-select     alternate rows 1 and 2
;;   etaf-playground.research.theme          toggle light and dark themes
;;   etaf-playground.research.filter         alternate Reading and All
;;   etaf-playground.research.page           alternate pages 1 and 2
;;   etaf-playground.research.resize         alternate 1413 and 720 pixels

;;; Code:
(require 'cl-lib)
(require 'subr-x)
(require 'etaf)
(require 'etaf-playground)
(declare-function taf-benchmark-register "performance-driver" (id &rest properties))

(defvar etaf-research-shelf-database-file)
(defvar etaf-research-shelf-fixture-size)
(defvar etaf-research-shelf-page-size)

(defconst etaf-playground-benchmark--viewport '(1413 . 62)
  "Fixed batch viewport in pixels and lines.")

(defun etaf-playground-benchmark--text (buffer)
  "Return BUFFER's plain text."
  (with-current-buffer buffer (buffer-substring-no-properties (point-min) (point-max))))

(defun etaf-playground-benchmark--observe (runtime buffer)
  "Return an :observe function forwarding RUNTIME's stage records in BUFFER."
  (lambda (sink)
    (etaf-performance-start runtime)
    (let ((before (mapcar (lambda (record) (cons (plist-get record :runtime-id)
                                                 (plist-get record :id)))
                          (plist-get (etaf-performance-report-data) :operations))))
      (lambda ()
        (etaf-performance-stop runtime)
        (dolist (operation (plist-get (etaf-performance-report-data) :operations))
          (when (and (equal (plist-get operation :buffer-name) (buffer-name buffer))
                     (not (member (cons (plist-get operation :runtime-id)
                                        (plist-get operation :id))
                                  before)))
            (dolist (stage (plist-get operation :stages))
              (funcall sink (append (list :provider (plist-get stage :provider)
                                          :stage (plist-get stage :stage)
                                          :duration-ms (plist-get stage :duration-ms))
                                    (plist-get stage :metadata))))))))))

(defun etaf-playground-benchmark--fixture (mode invoke check)
  "Mount Research Shelf for MODE and return a driver fixture.
INVOKE receives the runtime and the sample index.  CHECK receives the runtime,
the buffer and the sample index and returns non-nil when the result is right."
  (let* ((database (make-temp-file "etaf-research-shelf-" nil ".sqlite"))
         (saved (list (and (boundp 'etaf-research-shelf-database-file)
                           etaf-research-shelf-database-file)
                      (and (boundp 'etaf-research-shelf-fixture-size)
                           etaf-research-shelf-fixture-size)
                      (and (boundp 'etaf-research-shelf-page-size)
                           etaf-research-shelf-page-size)))
         (buffer (generate-new-buffer " *Research Shelf benchmark*"))
         runtime revision (sample 0))
    (delete-file database)
    (setq etaf-research-shelf-database-file database
          etaf-research-shelf-fixture-size 256
          etaf-research-shelf-page-size 12)
    (etaf-playground-mount-example
     (buffer-name buffer) "research-shelf" nil
     (and (eq mode 'batch)
          (list :viewport-width (car etaf-playground-benchmark--viewport)
                :viewport-height (cdr etaf-playground-benchmark--viewport))))
    (setq runtime (etaf-runtime-for-buffer buffer))
    (list
     :buffer buffer
     :ready (lambda ()
              (when (eq mode 'gui) (etaf-refit runtime (selected-window)))
              t)
     :prepare (lambda () (setq revision (etaf-runtime-revision runtime)))
     :invoke (lambda (index) (setq sample index) (funcall invoke runtime index))
     :observe (etaf-playground-benchmark--observe runtime buffer)
     :verify (lambda ()
               (cond ((not (> (etaf-runtime-revision runtime) revision))
                      "The event committed no buffer update")
                     ((not (funcall check runtime buffer sample))
                      "The buffer does not show the expected result")
                     (t t)))
     :cleanup (lambda ()
                (when (buffer-live-p buffer) (etaf-playground-close (buffer-name buffer)))
                (when (file-exists-p database) (delete-file database))
                (setq etaf-research-shelf-database-file (nth 0 saved)
                      etaf-research-shelf-fixture-size (nth 1 saved)
                      etaf-research-shelf-page-size (nth 2 saved))))))

(defun etaf-playground-benchmark--alternate (first second)
  "Return an invoke function pressing FIRST on even and SECOND on odd samples."
  (lambda (runtime index)
    (etaf-dispatch-event runtime (if (cl-evenp index) first second) 'press)))

(defun etaf-playground-benchmark--register
    (id description invoke check &optional impact budget)
  "Register scenario ID with DESCRIPTION, INVOKE and CHECK functions.
IMPACT defaults to `local' and BUDGET to one 16 ms frame."
  (taf-benchmark-register
   id :version 1 :modes '(batch gui) :isolation 'series :impact (or impact 'local)
   :required-providers '(ebox) :budget-ms (or budget 16) :description description
   :setup (lambda (mode) (etaf-playground-benchmark--fixture mode invoke check))))

(etaf-playground-benchmark--register
 "etaf-playground.research.row-select" "Select one of two visible Research Shelf rows"
 (etaf-playground-benchmark--alternate 'research-shelf-row-2 'research-shelf-row-1)
 (lambda (runtime _buffer index)
   (string-match-p "selected"
                   (or (plist-get (etaf-runtime-host-props-for
                                   runtime (if (cl-evenp index)
                                               'research-shelf-row-2
                                             'research-shelf-row-1))
                                  :class)
                       ""))))

(etaf-playground-benchmark--register
 "etaf-playground.research.theme" "Toggle the Research Shelf theme"
 (lambda (runtime _index) (etaf-dispatch-event runtime 'research-shelf-theme-toggle 'press))
 (lambda (_runtime buffer _index)
   (string-match-p "Dark theme\\|Light theme" (etaf-playground-benchmark--text buffer)))
 'mixed)

(etaf-playground-benchmark--register
 "etaf-playground.research.filter" "Alternate the Reading and All filters"
 (etaf-playground-benchmark--alternate 'research-shelf-filter-reading
                                       'research-shelf-filter-all)
 (lambda (_runtime buffer index)
   (string-match-p (if (cl-evenp index) "Showing Reading" "Showing All")
                   (etaf-playground-benchmark--text buffer)))
 'subtree 33)

(etaf-playground-benchmark--register
 "etaf-playground.research.page" "Alternate the first two pages"
 (etaf-playground-benchmark--alternate 'research-shelf-page-next
                                       'research-shelf-page-previous)
 (lambda (_runtime buffer index)
   (string-match-p (if (cl-evenp index) "Page 2 / 22" "Page 1 / 22")
                   (etaf-playground-benchmark--text buffer)))
 'subtree 33)

(etaf-playground-benchmark--register
 "etaf-playground.research.resize" "Alternate the viewport between 720 and 1413 pixels"
 (lambda (runtime index)
   (etaf-runtime-refit runtime (if (cl-evenp index) 720 (car etaf-playground-benchmark--viewport))
                       (cdr etaf-playground-benchmark--viewport)))
 (lambda (runtime _buffer index)
   (= (car (etaf-runtime-viewport runtime))
      (if (cl-evenp index) 720 (car etaf-playground-benchmark--viewport))))
 'mixed)

(provide 'performance-scenarios)
;;; performance-scenarios.el ends here
