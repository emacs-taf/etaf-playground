;;; etaf-playground.el --- ETAF public examples -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Author: ETAF contributors
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (etaf "0.1.0"))
;; URL: https://github.com/ginqi7/etaf-playground

;;; Commentary:

;; This package is a runnable example application, not a second framework
;; layer.  The core example depends only on ETAF.  The optional catalog demo
;; loads `etaf-ui' only when its public command is called.

;;; Code:

(require 'cl-lib)
(require 'etaf)

(defconst etaf-playground-buffer-name "*ETAF Playground*"
  "Default buffer name used by `etaf-playground-open'.")

(defconst etaf-playground-showcase-buffer-name "*ETAF Showcase*"
  "Default buffer name used by `etaf-playground-open-showcase'.")

;;;###autoload
(etaf-define-component etaf-playground-counter (&key title)
  "Render a retained counter titled TITLE."
  :setup
  (let ((count (etaf-ref 0 :name 'playground-count)))
    (lambda ()
      (etaf-view
       (column
        :class "etaf-playground-counter"
        :width 'stretch
        :max-width '(560)
        :padding '(1 (14))
        :bgcolor "#FFFDF8"
        :border '((1) solid "#A8A297")
        (text :face 'bold :color "#7B301F" (expr :value title))
        (text :face 'bold :color "#252A2E"
              (expr :value (format "Count: %d" (etaf-value count))))
        (flex
         :flex-flow '(row wrap)
         :gap '(1 (10))
         (text :ref 'decrement :role 'button :tab-index 0
               :on-press (lambda () (cl-decf (etaf-value count)))
               :color "#FFFDF8" :bgcolor "#7B301F"
               :border '((1) solid "#7B301F") :padding '(0 (12))
               "−")
         (text :ref 'increment :role 'button :tab-index 0
               :on-press (lambda () (cl-incf (etaf-value count)))
               :color "#FFFDF8" :bgcolor "#3F684B"
               :border '((1) solid "#3F684B") :padding '(0 (12))
               "+")))))))

(defun etaf-playground--showcase-palette (dark-p)
  "Return the Showcase palette for DARK-P."
  (if dark-p
      '(:color "#F2EEE4" :bgcolor "#1B1F20" :surface "#252B2C"
        :surface-alt "#333B3B" :muted "#B2BBB4" :accent "#E58A6A"
        :accent-strong "#F3B49D" :success "#8BC79A" :warning "#F2C56B"
        :danger "#F29A93" :border "#596362" :terracotta "#5A342B"
        :sage "#30483A" :blue "#294352" :violet "#403A55")
    '(:color "#252A2E" :bgcolor "#F8F5EE" :surface "#FFFDF8"
      :surface-alt "#EEEAE2" :muted "#66706A" :accent "#B84F35"
      :accent-strong "#7B301F" :success "#3F684B" :warning "#8A5B10"
      :danger "#9E3F3F" :border "#A8A297" :terracotta "#F1D4C9"
      :sage "#DCEBDD" :blue "#D9EAF2" :violet "#E7E2F1")))

(defun etaf-playground--showcase-palette-value (palette key)
  "Return KEY from reactive Showcase PALETTE."
  (plist-get (etaf-value palette) key))

(defun etaf-playground--showcase-window-width (window)
  "Return the display-safe Ebox viewport width for WINDOW."
  (let ((body-width (window-body-width window t))
        (reserve (max 1 (frame-char-width (window-frame window)))))
    (max 1 (- body-width reserve))))

(defun etaf-playground--showcase-sync-viewport (buffer)
  "Rerender Showcase BUFFER against its visible window dimensions.

This keeps viewport-height shells and full-surface theme changes correct after
the buffer is displayed.  Return nil when BUFFER is not visible yet."
  (when-let ((window (get-buffer-window buffer t)))
    (let ((width (etaf-playground--showcase-window-width window))
          (height (window-body-height window)))
      (when (and (> width 0) (> height 0))
        (ebox-rerender-buffer-with-context buffer width height)))))

(defun etaf-playground--showcase-schedule-viewport-sync (buffer)
  "Schedule a viewport sync for visible Showcase BUFFER.

The first window geometry reported while a frame is being displayed can be
stale.  Deferring one sync to the next event-loop turn lets Ebox receive the
window dimensions that are actually visible without making the component own
any frame lifecycle state."
  (run-at-time
   0 nil
   (lambda ()
     (when (buffer-live-p buffer)
       (etaf-playground--showcase-sync-viewport buffer)))))

(defun etaf-playground--showcase-border (palette)
  "Return a border using the current Showcase PALETTE."
  (list '(1) 'solid
        (etaf-playground--showcase-palette-value palette :border)))

(defun etaf-playground--showcase-button
    (label ref callback palette &optional active-p)
  "Return a Showcase button for LABEL, REF, CALLBACK, PALETTE, and ACTIVE-P."
  (etaf-view
   (text
    :class (if active-p "etaf-showcase-button active" "etaf-showcase-button")
    :ref ref
    :role 'button
    :tab-index 0
    :on-press callback
    :color (etaf-playground--showcase-palette-value
            palette (if active-p :bgcolor :accent-strong))
    :bgcolor (etaf-playground--showcase-palette-value
              palette (if active-p :accent :surface-alt))
    :border (etaf-playground--showcase-border palette)
    :padding '(0 (10))
    (expr :value label))))

(defun etaf-playground--showcase-metric (label value tone palette)
  "Return a metric card for LABEL, VALUE, TONE, and PALETTE."
  (etaf-view
   (column
    :class "etaf-showcase-metric"
    :flex-grow 1
    :flex-shrink 1
    :flex-basis '(220)
    :min-width '(200)
    :padding '(1 (12))
    :bgcolor (etaf-playground--showcase-palette-value palette tone)
    :border (etaf-playground--showcase-border palette)
    (text
     :color (etaf-playground--showcase-palette-value palette :color)
     (expr :value label))
    (text
     :face 'bold
     :color (etaf-playground--showcase-palette-value palette :accent-strong)
     (expr :value value)))))

(defun etaf-playground--showcase-nav (page palette on-page)
  "Return the Showcase navigation for PAGE, PALETTE, and ON-PAGE."
  (etaf-view
   (flex
    :class "etaf-showcase-navigation"
    :width 'stretch
    :flex-flow '(row wrap)
    :gap '(1 (10))
    :padding '(1 (16))
    :bgcolor (etaf-playground--showcase-palette-value palette :surface)
    :border (etaf-playground--showcase-border palette)
    (text :face 'bold :flex-shrink 0 "NAVIGATION")
    (expr :value
          (etaf-playground--showcase-button
           "Overview" 'showcase-nav-overview
           (lambda () (funcall on-page 'overview)) palette
           (eq page 'overview)))
    (expr :value
          (etaf-playground--showcase-button
           "Work items" 'showcase-nav-work-items
           (lambda () (funcall on-page 'work-items)) palette
           (eq page 'work-items)))
    (expr :value
          (etaf-playground--showcase-button
           "Theme" 'showcase-nav-theme
           (lambda () (funcall on-page 'theme)) palette
           (eq page 'theme)))
    (text
     :flex-grow 1
     :flex-basis '(180)
     :color (etaf-playground--showcase-palette-value palette :muted)
     "Keyboard: Tab, RET"))))

(defun etaf-playground--showcase-page-title (page)
  "Return the display title for Showcase PAGE."
  (or (cdr (assq page '((overview . "Overview")
                        (work-items . "Work items")
                        (theme . "Theme and semantics"))))
      "Overview"))

(defun etaf-playground--showcase-task-row
    (task selected-id palette on-select)
  "Return one interactive table row for TASK, SELECTED-ID, PALETTE, and ON-SELECT."
  (let ((id (plist-get task :id))
        (selected-p (equal (plist-get task :id) selected-id)))
    (etaf-view
     (row
      :key id
      :ref (intern (format "showcase-task-%s" id))
      :role 'button
      :tab-index 0
      :on-press (lambda () (funcall on-select id))
      :class (if selected-p "etaf-showcase-task selected"
               "etaf-showcase-task")
      :bgcolor (etaf-playground--showcase-palette-value
                palette (if selected-p :surface-alt :surface))
      :border (etaf-playground--showcase-border palette)
      (text :width '(80) (expr :value id))
      (text :width '(300) (expr :value (plist-get task :title)))
      (text :width '(140) (expr :value (plist-get task :owner)))
      (text :width '(120)
            :color (etaf-playground--showcase-palette-value
                    palette
                    (if (equal (plist-get task :status) "done")
                        :success :accent))
            (expr :value (capitalize (plist-get task :status))))))))

(defun etaf-playground--showcase-task-table
    (items selected-id palette on-select)
  "Return the task table for ITEMS, SELECTED-ID, PALETTE, and ON-SELECT."
  (etaf-view
   (column
    :class "etaf-showcase-table"
    (row
     :bgcolor (etaf-playground--showcase-palette-value palette :surface-alt)
     :border (etaf-playground--showcase-border palette)
     (text :face 'bold :width '(80) "ID")
     (text :face 'bold :width '(300) "TASK")
     (text :face 'bold :width '(140) "OWNER")
     (text :face 'bold :width '(120) "STATUS"))
    (expr :value
          (mapcar
           (lambda (task)
             (etaf-playground--showcase-task-row
              task selected-id palette on-select))
           items)))))

(defun etaf-playground--showcase-overview
    (palette controller notice actions)
  "Return the Showcase overview page.

PALETTE, CONTROLLER, NOTICE, and ACTIONS provide its live data and behavior."
  (let ((items (etaf-value (etaf-data-items controller)))
        (selected-count
         (length (etaf-value (etaf-data-selection controller)))))
    (etaf-view
     (column
      :class "etaf-showcase-section"
      (text :face 'bold "A complete text application in one View tree")
      (text
       :color (etaf-playground--showcase-palette-value palette :muted)
       "The shell, Flex cards, retained state, Data Controller, and events all share one model.")
      (flex
       :flex-flow '(row wrap)
       :gap '(1 (12))
       (expr :value
             (etaf-playground--showcase-metric
              "VISIBLE WORK ITEMS" (format "%d" (length items))
              :terracotta palette))
       (expr :value
             (etaf-playground--showcase-metric
              "SELECTED" (format "%d" selected-count) :sage palette))
       (expr :value
             (etaf-playground--showcase-metric
              "RUNTIME STATUS"
              (capitalize (symbol-name (etaf-value
                                        (etaf-data-status controller))))
              :blue palette)))
      (flex
       :flex-flow '(row wrap)
       :gap '(1 (12))
       (column
        :flex-grow 1
        :flex-shrink 1
        :flex-basis '(320)
        :min-width '(280)
        :padding '(1 (12))
        :bgcolor (etaf-playground--showcase-palette-value palette :surface)
        :border (etaf-playground--showcase-border palette)
        (text :face 'bold "Try the interaction path")
        (text :color (etaf-playground--showcase-palette-value palette :muted)
              "Open Work items, select a row, add a task, then toggle Theme.")
        (expr :value
              (etaf-playground--showcase-button
               "Open Work items" 'showcase-open-work-items
               (plist-get actions :open-work-items) palette)))
       (column
        :flex-grow 1
        :flex-shrink 1
        :flex-basis '(320)
        :min-width '(280)
        :padding '(1 (12))
        :bgcolor (etaf-playground--showcase-palette-value palette :violet)
        :border (etaf-playground--showcase-border palette)
        (text :face 'bold "Latest application feedback")
        (text
         :color (etaf-playground--showcase-palette-value palette :accent)
         (expr :value notice))))))))

(defun etaf-playground--showcase-work-items
    (palette controller filter selected-id notice actions)
  "Return the Showcase work-items page.

PALETTE, CONTROLLER, FILTER, SELECTED-ID, NOTICE, and ACTIONS provide its
live state."
  (let* ((items (etaf-value (etaf-data-items controller)))
         (page (etaf-value (etaf-data-page controller)))
         (page-size (etaf-value (etaf-data-page-size controller)))
         (total (etaf-value (etaf-data-total controller)))
         (last-page (max 1 (ceiling (/ (float total) page-size)))))
    (etaf-view
     (column
      :class "etaf-showcase-section"
      (flex
       :flex-flow '(row wrap)
       :gap '(1 (10))
       (column
        :flex-grow 1
        :flex-shrink 1
        :flex-basis '(360)
        (text :face 'bold "Work items")
        (text :color (etaf-playground--showcase-palette-value palette :muted)
              (expr :value (format "%d matching records · page %d/%d"
                                   total page last-page))))
       (expr :value
             (etaf-playground--showcase-button
              (format "Filter: %s" (capitalize (symbol-name filter)))
              'showcase-filter (plist-get actions :cycle-filter) palette
              (not (eq filter 'all))))
       (expr :value
             (etaf-playground--showcase-button
              "Add task" 'showcase-add-task
              (plist-get actions :add-task) palette)))
      (text :color (etaf-playground--showcase-palette-value palette :muted)
            (expr :value notice))
      (expr :value
            (etaf-playground--showcase-task-table
             items selected-id palette (plist-get actions :select-task)))
      (flex
       :flex-flow '(row wrap)
       :gap '(0 (12))
       (expr :value
             (etaf-playground--showcase-button
              "Previous" 'showcase-previous-page
              (plist-get actions :previous-page) palette))
       (expr :value
             (etaf-playground--showcase-button
              "Next" 'showcase-next-page
              (plist-get actions :next-page) palette))
       (expr :value
             (etaf-playground--showcase-button
              "Clear selection" 'showcase-clear-selection
              (plist-get actions :clear-selection) palette)))
      (column
       :padding '(1 (12))
       :bgcolor (etaf-playground--showcase-palette-value palette :surface)
       :border (etaf-playground--showcase-border palette)
       (text :face 'bold "Selected record")
       (text
        :color (etaf-playground--showcase-palette-value palette :accent)
        (expr :value
              (or (and selected-id
                       (format "%s · use the row key to keep identity stable"
                               selected-id))
                  "No row selected"))))))))

(defun etaf-playground--showcase-swatch-foreground (dark-p label palette)
  "Return a readable swatch foreground for DARK-P, LABEL, and PALETTE."
  (if (equal label "Surface")
      (etaf-playground--showcase-palette-value palette :color)
    (if dark-p
        (etaf-playground--showcase-palette-value palette :bgcolor)
      "#FFFFFF")))

(defun etaf-playground--showcase-swatch
    (label color foreground palette)
  "Return a color swatch for LABEL, COLOR, FOREGROUND, and PALETTE."
  (etaf-view
   (column
    :flex-grow 1
    :flex-shrink 1
    :flex-basis '(220)
    :min-width '(200)
    :height 3
    :padding '(1 (12))
    :bgcolor color
    :color foreground
    :border (etaf-playground--showcase-border palette)
    (text :face 'bold (expr :value label))
    (text (expr :value color)))))

(defun etaf-playground--showcase-theme (dark-p palette actions)
  "Return the Showcase theme page for DARK-P, PALETTE, and ACTIONS."
  (let ((colors (etaf-value palette)))
    (etaf-view
     (column
      :class "etaf-showcase-section"
      (text :face 'bold "Theme and semantics")
      (text :color (etaf-playground--showcase-palette-value palette :muted)
            "Theme is an inherited Context value; explicit Host properties remain local overrides.")
      (flex
       :flex-flow '(row wrap)
       :gap '(1 (10))
       (text :face 'bold (expr :value (if dark-p "Dark theme" "Light theme")))
       (expr :value
             (etaf-playground--showcase-button
              (if dark-p "Switch to light" "Switch to dark")
              'showcase-theme-toggle
              (plist-get actions :toggle-theme) palette)))
      (flex
       :flex-flow '(row wrap)
       :gap '(1 (12))
       (expr :value
             (mapcar
              (lambda (entry)
                (etaf-playground--showcase-swatch
                 (car entry) (cdr entry)
                 (etaf-playground--showcase-swatch-foreground
                  dark-p (car entry) palette)
                 palette))
              (list (cons "Surface" (plist-get colors :surface))
                    (cons "Accent" (plist-get colors :accent))
                    (cons "Success" (plist-get colors :success))
                    (cons "Warning" (plist-get colors :warning))
                    (cons "Danger" (plist-get colors :danger))
                    (cons "Muted" (plist-get colors :muted)))))
       (column
        :flex-grow 1
        :flex-shrink 1
        :flex-basis '(320)
        :min-width '(280)
        :padding '(1 (12))
        :bgcolor (etaf-playground--showcase-palette-value palette :surface)
        :border (etaf-playground--showcase-border palette)
        (text :face 'bold "Why this is useful")
        (text
         :color (etaf-playground--showcase-palette-value palette :muted)
         "The same Component grammar handles static structure, computed values, state, data, and interaction.")))))))

(defun etaf-playground--showcase-shell
    (page dark-p filter controller selected-id notice palette actions title)
  "Return the complete Showcase shell.

PAGE, DARK-P, FILTER, CONTROLLER, SELECTED-ID, NOTICE, PALETTE, ACTIONS,
and TITLE provide its live state and presentation."
  (etaf-view
   (column
    :class "etaf-showcase-root"
    :width 'stretch
    :height '(viewport-height)
    :color (etaf-playground--showcase-palette-value palette :color)
    :bgcolor (etaf-playground--showcase-palette-value palette :bgcolor)
    :border (etaf-playground--showcase-border palette)
    (flex
     :class "etaf-showcase-header"
     :width 'stretch
     :flex-flow '(row wrap)
     :gap '(1 (16))
     :padding '(1 (16))
     :bgcolor (etaf-playground--showcase-palette-value palette :surface)
     :border (etaf-playground--showcase-border palette)
     (column :flex-shrink 0 :flex-basis '(210)
             :bgcolor (etaf-playground--showcase-palette-value palette :surface)
             (text :face 'bold (expr :value title))
             (text :color (etaf-playground--showcase-palette-value
                           palette :muted)
                   "A runnable composition"))
     (column :flex-grow 1 :flex-shrink 1 :flex-basis '(420)
             :bgcolor (etaf-playground--showcase-palette-value palette :surface)
             (text :face 'bold
                   (expr :value (etaf-playground--showcase-page-title page)))
             (text :color (etaf-playground--showcase-palette-value
                           palette :muted)
                   (expr :value
                         (if dark-p "Dark semantic surface" "Light semantic surface"))))
     (expr :value
            (etaf-playground--showcase-button
            (if dark-p "Light" "Dark") 'showcase-header-theme-toggle
            (plist-get actions :toggle-theme) palette)))
    (column
     :width 'stretch
     :color (etaf-playground--showcase-palette-value palette :color)
     (expr :value
           (etaf-playground--showcase-nav
            page palette (plist-get actions :set-page)))
     (expr :value
           (cond
            ((eq page 'work-items)
             (etaf-playground--showcase-work-items
              palette controller filter selected-id notice actions))
            ((eq page 'theme)
             (etaf-playground--showcase-theme dark-p palette actions))
            (t
             (etaf-playground--showcase-overview
              palette controller notice actions)))))
    (flex
     :class "etaf-showcase-status"
     :width 'stretch
     :flex-flow '(row wrap)
     :gap '(0 (12))
     :padding '(0 (16))
     :color (etaf-playground--showcase-palette-value palette :muted)
     :bgcolor (etaf-playground--showcase-palette-value palette :surface)
     (text (expr :value (format "STATUS  %s" notice)))
     (text (expr :value (format "  ·  %s records" (etaf-value
                                                     (etaf-data-total controller)))))))))

;;;###autoload
(etaf-define-component etaf-playground-showcase (&key title)
  "Render a complex interactive ETAF application showcase."
  :setup
  (let* ((page (etaf-ref 'overview :name 'showcase-page))
         (dark-p (etaf-ref nil :name 'showcase-dark-theme))
         (filter (etaf-ref 'all :name 'showcase-filter))
         (selected-id (etaf-ref nil :name 'showcase-selected-id))
         (notice (etaf-ref "Ready · choose a page" :name 'showcase-notice))
         (next-id (etaf-ref 107 :name 'showcase-next-id))
         (source
          (etaf-data-memory-source
           '((:id "T-101" :title "Stabilize incremental commits"
              :owner "Ada" :status "open")
             (:id "T-102" :title "Verify Grid track sizing"
              :owner "Grace" :status "review")
             (:id "T-103" :title "Document the public View grammar"
              :owner "Lin" :status "done")
             (:id "T-104" :title "Exercise Context inheritance"
              :owner "Edsger" :status "open")
             (:id "T-105" :title "Measure native fallback behavior"
              :owner "Margaret" :status "review")
             (:id "T-106" :title "Polish keyboard focus paths"
              :owner "Alan" :status "open"))
           :id-key :id
           :name 'showcase-work-items))
         (controller
          (etaf-data-controller source :page-size 4))
         (palette
          (etaf-computed
           (lambda ()
             (etaf-playground--showcase-palette (etaf-value dark-p)))))
         (theme
          (etaf-computed
           (lambda ()
             (let ((colors (etaf-value palette)))
               (list :color (plist-get colors :color))))))
         (runtime (etaf-current-runtime))
         (last-rendered-dark-p nil)
         actions)
    (etaf-theme-provide theme)
    (etaf-on-mounted (lambda () (etaf-data-load controller)))
    (etaf-on-unmounted (lambda () (etaf-data-stop controller)))
    (etaf-on-updated
     (lambda ()
       (let ((current-dark-p (etaf-value dark-p)))
         (when (not (eq current-dark-p last-rendered-dark-p))
           (setq last-rendered-dark-p current-dark-p)
           (etaf-playground--showcase-schedule-viewport-sync
            (etaf-runtime-buffer runtime))))))
    (setq actions
          (list
           :set-page (lambda (next-page)
                       (setf (etaf-value page) next-page
                             (etaf-value notice)
                             (format "Opened %s"
                                     (etaf-playground--showcase-page-title
                                      next-page))))
           :open-work-items (lambda ()
                              (setf (etaf-value page) 'work-items
                                    (etaf-value notice) "Opened Work items"))
           :toggle-theme (lambda ()
                           (setf (etaf-value dark-p) (not (etaf-value dark-p))
                                 (etaf-value notice)
                                 (if (etaf-value dark-p)
                                     "Dark theme enabled"
                                   "Light theme enabled")))
           :add-task (lambda ()
                       (let* ((number (etaf-value next-id))
                              (id (format "T-%d" number)))
                         (cl-incf (etaf-value next-id))
                         (etaf-data-mutate
                          controller 'insert
                          (list :id id
                                :title "New task from the interaction path"
                                :owner "You"
                                :status "open"))
                         (setf (etaf-value notice)
                               (format "Added %s" id))))
           :cycle-filter (lambda ()
                           (let ((next (pcase (etaf-value filter)
                                         ('all 'open)
                                         ('open 'review)
                                         (_ 'all))))
                             (setf (etaf-value filter) next)
                             (etaf-data-set-query
                              controller
                              (pcase next
                                ('all nil)
                                (_ (symbol-name next))))
                             (etaf-data-load controller)
                             (setf (etaf-value notice)
                                   (format "Filter: %s"
                                           (capitalize (symbol-name next))))))
           :previous-page (lambda ()
                            (etaf-data-previous-page controller)
                            (etaf-data-load controller)
                            (setf (etaf-value notice) "Moved to the previous page"))
           :next-page (lambda ()
                        (etaf-data-next-page controller)
                        (etaf-data-load controller)
                        (setf (etaf-value notice) "Moved to the next page"))
           :clear-selection (lambda ()
                             (etaf-data-clear-selection controller)
                             (setf (etaf-value selected-id) nil
                                   (etaf-value notice) "Selection cleared"))
           :select-task (lambda (id)
                          (etaf-data-select controller id)
                          (setf (etaf-value selected-id) id
                                (etaf-value notice)
                                (format "Selected %s" id)))))
    (lambda ()
      (etaf-playground--showcase-shell
       (etaf-value page) (etaf-value dark-p) (etaf-value filter)
       controller (etaf-value selected-id) (etaf-value notice)
       palette actions title))))

;;;###autoload
(defun etaf-playground-view ()
  "Return the core ETAF playground View without side effects."
  (etaf-view
   (column
    :class "etaf-playground-root"
    :width 'stretch
    :padding '(1 (16))
    :color "#252A2E"
    :bgcolor "#F8F5EE"
    (text :face 'bold :color "#7B301F" "ETAF Playground")
    (text :color "#66706A"
          "One grammar: Hosts, Components, props, children, and expr.")
    (etaf-playground-counter :title "Reactive counter")
    (text :color "#66706A"
          "Press + or - through the public event dispatch path."))))

;;;###autoload
(defun etaf-playground-ui-view ()
  "Return a View demonstrating the optional official `etaf-ui' catalog."
  (require 'etaf-ui)
  (etaf-view
   (column
    :width 'stretch
    :padding '(1 (16))
    :color "#252A2E"
    :bgcolor "#F8F5EE"
    (etaf-panel :title "Official Components"
     (etaf-button :label "A public Component"
                  :on-press (lambda () (message "ETAF UI button pressed")))
     (etaf-checkbox :label "Controlled checkbox"
                    :on-change (lambda (value)
                                 (message "Checkbox value: %s" value))))
    (etaf-playground-counter :title "Core counter"))))

;;;###autoload
(defun etaf-playground-showcase-view ()
  "Return the complex ETAF Showcase View without side effects."
  (etaf-view (etaf-playground-showcase :title "ETAF Showcase")))

;;;###autoload
(defun etaf-playground-open (&optional buffer-name)
  "Mount the core playground in BUFFER-NAME and return its buffer."
  (interactive)
  (etaf-mount (or buffer-name etaf-playground-buffer-name)
              (etaf-playground-view)))

;;;###autoload
(defun etaf-playground-open-ui (&optional buffer-name)
  "Mount the playground with the catalog in BUFFER-NAME."
  (interactive)
  (etaf-mount (or buffer-name etaf-playground-buffer-name)
              (etaf-playground-ui-view)))

;;;###autoload
(defun etaf-playground-open-showcase (&optional buffer-name)
  "Mount the interactive Showcase in BUFFER-NAME and return its buffer.

Use the visible navigation and buttons with the mouse or keyboard.  The
Showcase demonstrates responsive Flex layout, Context theme defaults,
reactive state, Data Controller updates, stable row keys, and public event
dispatch."
  (interactive)
  (let* ((buffer
          (etaf-mount (or buffer-name etaf-playground-showcase-buffer-name)
                      (etaf-playground-showcase-view)))
         (window (or (get-buffer-window buffer t)
                     (progn
                       (pop-to-buffer buffer)
                       (get-buffer-window buffer t)))))
    (when (window-live-p window)
      (etaf-playground--showcase-sync-viewport buffer)
      (etaf-playground--showcase-schedule-viewport-sync buffer))
    buffer))

;;;###autoload
(defun etaf-playground-close (&optional buffer-name)
  "Unmount and kill the playground BUFFER-NAME, returning its buffer."
  (interactive)
  (let* ((name (or buffer-name etaf-playground-buffer-name))
         (buffer (get-buffer name)))
    (when-let ((runtime (and buffer (etaf-runtime-for-buffer buffer))))
      (etaf-unmount runtime))
    (when buffer
      (kill-buffer buffer))
    buffer))

(provide 'etaf-playground)

;;; etaf-playground.el ends here
