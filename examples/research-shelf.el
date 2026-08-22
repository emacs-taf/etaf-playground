;;; research-shelf.el --- SQLite-backed research library -*- lexical-binding: t; -*-

;;; Commentary:
;; A useful ETAF application: a small reading/research shelf whose records
;; survive unmounts because the Data Controller is backed by etaf-sqlite.

;;; Code:
(require 'cl-lib)
(require 'subr-x)
(require 'etaf)
(require 'etaf-ui)
(require 'etaf-sqlite)
(require 'etaf-playground)
(require 'face-remap)

(defcustom etaf-research-shelf-database-file
  (expand-file-name "research-shelf.sqlite" user-emacs-directory)
  "SQLite file used by the Research Shelf application."
  :type 'file
  :group 'etaf)

(defcustom etaf-research-shelf-fixture-size 256
  "Minimum deterministic records installed in the Playground database.

The example deliberately uses a realistic fixture size so pagination, SQLite
counting, DataGrid Range updates, and repeated selection exercise more than a
toy four-row surface.  Tests and small teaching fixtures may bind this to a
smaller value."
  :type 'natnum
  :group 'etaf)

(defcustom etaf-research-shelf-page-size 12
  "Number of records shown on one Research Shelf page."
  :type 'positive-integer
  :group 'etaf)

(defconst etaf-research-shelf--grid-columns
  '((:key :title :label "Title" :width 21)
    (:key :author :label "Author" :width 12)
    (:key :status :label "Status" :width 10)
    (:key :progress :label "Progress" :width 8)
    (:key :kind :label "Kind" :width 7))
  "Compact DataGrid columns that remain readable in a wrapped workspace.")

(defconst etaf-research-shelf-seed-records
  '((:id 1 :title "The Shape of Tools" :author "M. Abramson"
         :kind "Essay" :status "reading" :progress 64 :priority "High"
         :starred 1 :note "The best tools make attention feel larger, not more fragmented." :updated "Today")
    (:id 2 :title "Ways of Seeing" :author "John Berger"
         :kind "Book" :status "unread" :progress 0 :priority "Medium"
         :starred 0 :note "Look again at the relationship between image and power." :updated "Yesterday")
    (:id 3 :title "The Cathedral and the Bazaar" :author "Eric S. Raymond"
         :kind "Paper" :status "finished" :progress 100 :priority "Low"
         :starred 1 :note "A useful contrast between closed and open production." :updated "Mon")
    (:id 4 :title "Designing for Calm" :author "A. Ito"
         :kind "Notes" :status "reading" :progress 32 :priority "High"
         :starred 0 :note "Reduce decisions before asking for attention." :updated "Sun")
    (:id 5 :title "The Craftsman" :author "Richard Sennett"
         :kind "Book" :status "unread" :progress 0 :priority "Medium"
         :starred 1 :note "A long-form companion for making and revising." :updated "Sat")
    (:id 6 :title "How Buildings Learn" :author "Stewart Brand"
         :kind "Book" :status "reading" :progress 78 :priority "Medium"
         :starred 0 :note "Change is a property of useful systems." :updated "Fri")
    (:id 7 :title "The Interface Is the Message" :author "N. Hara"
         :kind "Essay" :status "finished" :progress 100 :priority "Low"
         :starred 0 :note "A short note on visible constraints." :updated "Thu")
    (:id 8 :title "Notes on Attention" :author "Simone Weil"
         :kind "Notes" :status "unread" :progress 0 :priority "High"
         :starred 1 :note "Attention is not force; it is patient availability." :updated "Wed"))
  "Seed records installed into a new Research Shelf database once.")

(defconst etaf-research-shelf--generated-titles
  '("A Pattern Language" "The Craftsman" "How Buildings Learn"
    "The Interface Is the Message" "Notes on Attention"
    "Ways of Making" "The Timeless Way of Building"
    "Designing for the Real World" "The Practice of Everyday Life"
    "Small Tools, Large Consequences")
  "Stable title vocabulary for generated fixture records.")

(defconst etaf-research-shelf--generated-authors
  '("C. Alexander" "Richard Sennett" "Stewart Brand" "N. Hara"
    "Simone Weil" "M. Ito" "A. Ito" "V. Papanek" "M. de Certeau"
    "You")
  "Stable author vocabulary for generated fixture records.")

(defun etaf-research-shelf--generated-record (id index)
  "Return deterministic generated fixture record ID at INDEX."
  (let* ((status (nth (mod index 4) '("reading" "unread" "finished" "reading")))
         (progress (pcase status
                     ("finished" 100)
                     ("reading" (+ 10 (* 8 (mod index 12))))
                     (_ 0)))
         (kind (nth (mod index 4) '("Essay" "Book" "Paper" "Notes"))))
    (list :id id
          :title (format "%s · %03d"
                         (nth (mod index (length etaf-research-shelf--generated-titles))
                              etaf-research-shelf--generated-titles)
                         (1+ index))
          :author (nth (mod index (length etaf-research-shelf--generated-authors))
                       etaf-research-shelf--generated-authors)
          :kind kind :status status :progress progress
          :priority (nth (mod index 3) '("High" "Medium" "Low"))
          :starred (if (zerop (% index 5)) 1 0)
          :note (format "Generated fixture note %03d for paging and update checks."
                        (1+ index))
          :updated (format "D-%03d" (1+ index)))))

(defun etaf-research-shelf--fixture-records ()
  "Return the deterministic fixture set sized by `...-fixture-size'."
  (let* ((target (max 0 etaf-research-shelf-fixture-size))
         (base (copy-tree etaf-research-shelf-seed-records))
         (base-count (length base)))
    (if (<= target base-count)
        (cl-subseq base 0 target)
      (append base
              (cl-loop for id from (1+ base-count) to target
                       for index from 0
                       collect (etaf-research-shelf--generated-record id index))))))

(defun etaf-research-shelf--static-child (form tag)
  "Return the first child named TAG from static FORM."
  (cl-find-if (lambda (entry) (and (consp entry) (eq (car entry) tag)))
              (cdr form)))

(defun etaf-research-shelf--static-value (form key default)
  "Return KEY from static FORM, or DEFAULT."
  (or (plist-get (cdr form) key) default))

(defun etaf-research-shelf--database ()
  "Return the configured typed Research Shelf database description."
  (etaf-sqlite-database
   etaf-research-shelf-database-file
   (etaf-sqlite-table
    'reading_items
    (list (etaf-sqlite-column :id "id" :type 'integer :primary t)
          (etaf-sqlite-column :title "title" :type 'text)
          (etaf-sqlite-column :author "author" :type 'text)
          (etaf-sqlite-column :kind "kind" :type 'text)
          (etaf-sqlite-column :status "status" :type 'text)
          (etaf-sqlite-column :progress "progress" :type 'integer)
          (etaf-sqlite-column :priority "priority" :type 'text)
          (etaf-sqlite-column :starred "starred" :type 'integer)
          (etaf-sqlite-column :note "note" :type 'text)
          (etaf-sqlite-column :updated "updated" :type 'text))
   :id)))

(defun etaf-research-shelf--ensure-database ()
  "Initialize SQLite and top up the deterministic Playground fixture.

Existing records are preserved.  Missing fixture rows receive fresh IDs so a
user's prior local additions cannot collide with the generated dataset."
  (let* ((database (etaf-research-shelf--database))
         (source (etaf-sqlite-source database))
         (load (plist-get source :load))
         (mutate (plist-get source :mutate))
         (target-records (etaf-research-shelf--fixture-records))
         (target (length target-records)))
    (etaf-sqlite-initialize database)
    (let* ((current (funcall load nil 1 (max 1 target)))
           (total (plist-get current :total))
           (existing-items (plist-get current :items))
           (next-id (1+ (if existing-items
                            (apply #'max
                                   (mapcar (lambda (row)
                                             (or (plist-get row :id) 0))
                                           existing-items))
                          0))))
      (when (< total target)
        (dolist (record (nthcdr total target-records))
          (let ((copy (copy-sequence record)))
            (plist-put copy :id next-id)
            (funcall mutate 'insert copy)
            (setq next-id (1+ next-id))))))
    database))

(defun etaf-research-shelf--create-model ()
  "Create the application model and its SQLite-backed Data Controller."
  (let* ((database (etaf-research-shelf--ensure-database))
         (controller
          (etaf-data-controller
           (etaf-sqlite-source database)
           :page-size etaf-research-shelf-page-size
           :auto-load nil :name 'etaf-research-shelf))
         (filter (etaf-ref 'all :name 'research-shelf-filter))
         (dark (etaf-ref nil :name 'research-shelf-dark-theme))
         (toast (etaf-ref "Ready to read." :name 'research-shelf-toast))
         (next-id (etaf-ref
                   (let* ((load (plist-get (etaf-sqlite-source database) :load))
                          (items (plist-get
                                  (funcall load nil 1
                                           (max 1 etaf-research-shelf-fixture-size))
                                  :items)))
                     (1+ (if items
                             (apply #'max
                                    (mapcar (lambda (row)
                                              (or (plist-get row :id) 0))
                                            items))
                           0)))
                   :name 'research-shelf-next-id)))
    (list :database database :database-file etaf-research-shelf-database-file
          :controller controller :filter filter :dark dark :toast toast
          :next-id next-id)))

(defun etaf-research-shelf--controller (model)
  "Return MODEL's Data Controller."
  (plist-get model :controller))

(defun etaf-research-shelf--query (filter)
  "Translate FILTER into an allowlisted SQLite equality query."
  (pcase filter
    ('reading '(:status "reading"))
    ('unread '(:status "unread"))
    ('finished '(:status "finished"))
    ('starred '(:starred 1))
    (_ nil)))

(defun etaf-research-shelf--load (model &optional message)
  "Load MODEL and expose a visible success/error MESSAGE."
  (let ((controller (etaf-research-shelf--controller model)))
    (condition-case err
        (progn
          (etaf-data-load controller)
          (setf (etaf-value (plist-get model :toast))
                (or message "✓ Saved locally")))
      (error
       (setf (etaf-value (plist-get model :toast))
             (format "⚠ Storage issue: %s" (error-message-string err)))))))

(defun etaf-research-shelf--set-filter (model filter)
  "Set MODEL FILTER and reload the SQLite-backed list."
  (let ((controller (etaf-research-shelf--controller model)))
    (setf (etaf-value (plist-get model :filter)) filter)
    (etaf-data-set-query controller (etaf-research-shelf--query filter))
    (etaf-data-set-page controller 1)
    (etaf-research-shelf--load model
                               (format "Showing %s"
                                       (capitalize (symbol-name filter))))))

(defun etaf-research-shelf--change-page-size (model)
  "Prompt for MODEL's page size, validate it, and reload from page one."
  (let* ((controller (etaf-research-shelf--controller model))
         (current (etaf-value (etaf-data-page-size controller)))
         (next (read-number "Rows per page (1–100): " current)))
    (unless (and (integerp next) (<= 1 next 100))
      (user-error "Rows per page must be an integer from 1 to 100"))
    (etaf-data-set-page-size controller next)
    (etaf-data-set-page controller 1)
    (etaf-research-shelf--load
     model (format "Showing %d rows per page" next))))

(defun etaf-research-shelf--items (model)
  "Return loaded items for MODEL."
  (etaf-value (etaf-data-items (etaf-research-shelf--controller model))))

(defun etaf-research-shelf--selected (model)
  "Return the selected item in MODEL, or nil."
  (let* ((controller (etaf-research-shelf--controller model))
         (id (car (etaf-value (etaf-data-selection controller)))))
    (cl-find id (etaf-research-shelf--items model)
             :key (lambda (row) (plist-get row :id)) :test #'equal)))

(defun etaf-research-shelf--mutate (model operation payload message)
  "Apply SQLite OPERATION PAYLOAD for MODEL.
Show MESSAGE on success, or preserve the resulting error state."
  (let ((controller (etaf-research-shelf--controller model)))
    (condition-case err
        (progn
          (etaf-data-mutate controller operation payload)
          (setf (etaf-value (plist-get model :toast)) message))
      (error
       (setf (etaf-value (plist-get model :toast))
             (format "⚠ Could not save: %s" (error-message-string err)))))))

(defun etaf-research-shelf--update-selected (model fields message)
  "Update selected MODEL record with FIELDS and show MESSAGE."
  (when-let ((row (etaf-research-shelf--selected model)))
    (etaf-research-shelf--mutate
     model 'update
     (append (list :id (plist-get row :id)) fields)
     message)))

(defun etaf-research-shelf--theme (model)
  "Return MODEL's current palette."
  (if (etaf-value (plist-get model :dark))
      '(:ink "#F4F7FF" :paper "#111827" :panel "#182235" :line "#34435A"
        :muted "#AAB5C8" :accent "#8EA7FF" :mint "#76D6C3" :coral "#FF9A8E"
        :amber "#F0C36A" :soft "#202C42")
    '(:ink "#172033" :paper "#F7F3EA" :panel "#FFFDF8" :line "#D9D4C9"
      :muted "#6D7482" :accent "#3657D6" :mint "#3E9B8F" :coral "#D86B5D"
      :amber "#C58A3A" :soft "#F1EEE7")))

(defun etaf-research-shelf--color (model key)
  "Return palette KEY for MODEL."
  (plist-get (etaf-research-shelf--theme model) key))

(defun etaf-research-shelf--apply-buffer-palette (palette)
  "Paint the GUI buffer's unused viewport columns with PALETTE.

Ebox intentionally reserves a couple of rightmost display columns so a safe
layout never becomes a continuation line.  Those columns contain no text
properties, so the buffer's default face must carry the same product surface
color or the frame edge exposes Emacs's unrelated default background."
  (when (and (display-graphic-p) (fboundp 'face-remap-set-base))
    (face-remap-set-base
     'default
     (list :foreground (plist-get palette :ink)
           :background (plist-get palette :paper)))))

(defun etaf-research-shelf--status-label (status)
  "Return a readable status label for STATUS."
  (pcase status
    ("reading" "◷ In progress")
    ("finished" "✓ Finished")
    ("archived" "↗ Archived")
    (_ "○ Unread")))

(defun etaf-research-shelf--filter-label (model form key fallback)
  "Return MODEL's active-aware label for KEY from static FILTER FORM."
  (let* ((entry (cl-find-if
                 (lambda (item) (and (consp item) (eq (car item) 'filter)
                                     (eq (plist-get (cdr item) :key) key)))
                 (cdr form)))
         (label (or (and entry (plist-get (cdr entry) :label)) fallback)))
    (if (eq key (etaf-value (plist-get model :filter)))
        (concat "● " label)
      label)))

(defun etaf-research-shelf--button-style (palette variant disabled)
  "Return style props for PALETTE, VARIANT, and DISABLED button state.

The public `button' Component owns native interaction state; this small
adapter only maps the app palette to its ordinary presentation props so ghost
buttons do not fall back to a light-theme paper surface in dark mode."
  (let ((secondary (eq variant 'secondary)))
    (list :color (plist-get palette (if disabled :muted
                                     (if secondary :paper :ink)))
          :bgcolor (plist-get palette (if disabled :soft
                                       (if secondary :mint :panel)))
          :border (plist-get palette (if secondary :mint :line))
          :face (if (and secondary (not disabled)) 'bold 'normal))))

(etaf-define-component etaf-research-shelf-button
    (&key theme label ref variant disabled on-press)
  "Compose the public Button with the Research Shelf theme palette."
  :setup
  (lambda ()
    (let* ((theme (etaf-current-prop :theme))
           (label (etaf-current-prop :label))
           (ref (etaf-current-prop :ref))
           (variant (etaf-current-prop :variant))
           (disabled (etaf-current-prop :disabled))
           (on-press (etaf-current-prop :on-press))
           (style (etaf-research-shelf--button-style
                   theme variant disabled)))
      (etaf-view
       (button :label label :ref ref :variant variant :disabled disabled
               :on-press on-press
               :color (plist-get style :color)
               :bgcolor (plist-get style :bgcolor)
               :border (plist-get style :border)
               :face (plist-get style :face))))))

(defun etaf-research-shelf--filter-view (model form)
  "Return the filter rail from MODEL and static FILTER FORM."
  (etaf-view
     (column :class "research-shelf-filter-rail" :width 'stretch :min-width 0
             :flex-grow 1 :flex-shrink 1 :flex-basis '(220)
             :padding '(1 1)
             :border (etaf-research-shelf--color model :line)
             :color (etaf-research-shelf--color model :ink)
             :bgcolor (etaf-research-shelf--color model :panel)
      (label :text "Library" :face 'bold
             :color (etaf-research-shelf--color model :ink)
             :bgcolor (etaf-research-shelf--color model :panel))
      (label :text "VIEWS" :color (etaf-research-shelf--color model :muted)
             :bgcolor (etaf-research-shelf--color model :panel))
      (etaf-research-shelf-button
       :theme (etaf-research-shelf--theme model)
       :label (etaf-research-shelf--filter-label model form 'all "All")
       :ref 'research-shelf-filter-all
       :variant (if (eq (etaf-value (plist-get model :filter)) 'all)
                    'secondary 'ghost)
       :on-press (lambda () (etaf-research-shelf--set-filter model 'all)))
      (etaf-research-shelf-button
       :theme (etaf-research-shelf--theme model)
       :label (etaf-research-shelf--filter-label
               model form 'reading "In progress")
       :ref 'research-shelf-filter-reading
       :variant (if (eq (etaf-value (plist-get model :filter)) 'reading)
                    'secondary 'ghost)
       :on-press (lambda () (etaf-research-shelf--set-filter model 'reading)))
      (etaf-research-shelf-button
       :theme (etaf-research-shelf--theme model)
       :label (etaf-research-shelf--filter-label
               model form 'unread "Unread")
       :ref 'research-shelf-filter-unread
       :variant (if (eq (etaf-value (plist-get model :filter)) 'unread)
                    'secondary 'ghost)
       :on-press (lambda () (etaf-research-shelf--set-filter model 'unread)))
      (etaf-research-shelf-button
       :theme (etaf-research-shelf--theme model)
       :label (etaf-research-shelf--filter-label
               model form 'finished "Finished")
       :ref 'research-shelf-filter-finished
       :variant (if (eq (etaf-value (plist-get model :filter)) 'finished)
                    'secondary 'ghost)
       :on-press (lambda () (etaf-research-shelf--set-filter model 'finished)))
      (etaf-research-shelf-button
       :theme (etaf-research-shelf--theme model)
       :label (etaf-research-shelf--filter-label
               model form 'starred "★ Starred")
       :ref 'research-shelf-filter-starred
       :variant (if (eq (etaf-value (plist-get model :filter)) 'starred)
                    'secondary 'ghost)
       :on-press (lambda () (etaf-research-shelf--set-filter model 'starred)))
      (spacer :height 1)
      (label :text "STORAGE" :color (etaf-research-shelf--color model :muted)
             :bgcolor (etaf-research-shelf--color model :panel))
      (label :text (file-name-nondirectory
                    (plist-get model :database-file))
             :color (etaf-research-shelf--color model :ink)
             :bgcolor (etaf-research-shelf--color model :panel))
      (etaf-research-shelf-button
       :theme (etaf-research-shelf--theme model)
       :label "↻ Reload library" :ref 'research-shelf-reload
       :variant 'ghost
       :on-press (lambda () (etaf-research-shelf--load model "✓ Library reloaded"))))))

(defun etaf-research-shelf--reading-list-view (model form)
  "Return the main reading list for MODEL and static MAIN FORM."
  (let ((controller (etaf-research-shelf--controller model)))
    (etaf-view
     (column :class "research-shelf-list" :width 'stretch :min-width 0
             :flex-grow 4 :flex-shrink 1 :flex-basis '(620)
             :padding '(1 2)
             :border (etaf-research-shelf--color model :line)
             :color (etaf-research-shelf--color model :ink)
             :bgcolor (etaf-research-shelf--color model :panel)
      (flex :width 'stretch :flex-wrap 'wrap :align-items 'center :gap '(1 (8))
       (column :flex-grow 1 :flex-shrink 1 :flex-basis '(0) :min-width 0
        (label :text (etaf-research-shelf--static-value form :title
                                                          "Reading queue")
               :face 'bold
               :color (etaf-research-shelf--color model :ink)
               :bgcolor (etaf-research-shelf--color model :panel))
        (label :text (format "%d items · SQLite-backed"
                            (or (etaf-value (etaf-data-total controller)) 0))
               :color (etaf-research-shelf--color model :muted)
               :bgcolor (etaf-research-shelf--color model :panel)))
      (etaf-research-shelf-button
        :theme (etaf-research-shelf--theme model)
        :label (format "Rows %d ✎"
                       (etaf-value (etaf-data-page-size controller)))
        :ref 'research-shelf-page-size
        :variant 'ghost
        :on-press (lambda ()
                    (etaf-research-shelf--change-page-size model)))
      (etaf-research-shelf-button
        :theme (etaf-research-shelf--theme model)
        :label "＋ Add reading" :ref 'research-shelf-add
        :variant 'secondary
        :on-press
        (lambda ()
          (let ((id (etaf-value (plist-get model :next-id))))
            (etaf-research-shelf--mutate
             model 'insert
             (list :id id :title (format "New reading %d" id)
                   :author "You" :kind "Notes" :status "unread"
                   :progress 0 :priority "Medium" :starred 0
                   :note "A new note waiting for your attention."
                   :updated "Just now")
             "✓ Added to your shelf")
            (setf (etaf-value (plist-get model :next-id)) (1+ id))))))
      (data-grid
       :controller controller
       :columns etaf-research-shelf--grid-columns
       :row-key (lambda (row) (plist-get row :id))
       :row-ref (lambda (row)
                  (intern (format "research-shelf-row-%s"
                                  (plist-get row :id))))
       :row-selected-p
       (lambda (row)
         (etaf-data-selected-p controller (plist-get row :id)))
       :on-row-press
       (lambda (row)
         (etaf-data-select-one controller (plist-get row :id)))
       :loading-label "◷ Loading library…"
       :error-label "⚠ Could not read the shelf. Use Reload.")
      (etaf-pagination :controller controller
       :previous-ref 'research-shelf-page-previous
       :next-ref 'research-shelf-page-next
       :color (etaf-research-shelf--color model :ink)
       :bgcolor (etaf-research-shelf--color model :panel))))))

(defun etaf-research-shelf--detail-view (model form)
  "Return the selected record inspector for MODEL and static FORM."
  (etaf-view
   (column :class "research-shelf-detail" :width 'stretch :min-width 0
           :flex-grow 2 :flex-shrink 1 :flex-basis '(340)
           :padding '(2 2)
           :border (etaf-research-shelf--color model :line)
           :color (etaf-research-shelf--color model :ink)
           :bgcolor (etaf-research-shelf--color model :panel)
    (label :text (etaf-research-shelf--static-value form :title
                                                     "Selected item")
           :color (etaf-research-shelf--color model :accent)
           :bgcolor (etaf-research-shelf--color model :panel))
    (text :face 'bold
     (expr :value
           (if-let ((row (etaf-research-shelf--selected model)))
               (plist-get row :title)
             "Choose a record")))
    (text :color (etaf-research-shelf--color model :muted)
     (expr :value
           (if-let ((row (etaf-research-shelf--selected model)))
               (format "%s · %s" (plist-get row :author)
                       (plist-get row :kind))
             "Select one row to inspect it.")))
    (spacer :height 1)
    (text :face 'bold
     (expr :value
           (if-let ((row (etaf-research-shelf--selected model)))
               (etaf-research-shelf--status-label (plist-get row :status))
             "○ No selection")))
    (text
     (expr :value
           (if-let ((row (etaf-research-shelf--selected model)))
               (format "Progress  %d%%  ·  Priority %s"
                       (or (plist-get row :progress) 0)
                       (plist-get row :priority))
             "Progress  —  ·  Priority —")))
    (text :color (etaf-research-shelf--color model :accent)
     (expr :value
           (let* ((row (etaf-research-shelf--selected model))
                  (progress (or (and row (plist-get row :progress)) 0))
                  (filled (max 0 (min 10 (/ progress 10)))))
             (format "%s %s" (make-string filled ?█)
                     (make-string (- 10 filled) ?░)))))
    (spacer :height 1)
    (text :color (etaf-research-shelf--color model :muted)
     (expr :value
           (if-let ((row (etaf-research-shelf--selected model)))
               (concat "“" (or (plist-get row :note) "No note yet.") "”")
             "Your notes and actions will appear here.")))
    (spacer :height 1)
    (etaf-research-shelf-detail-actions :model model))))

(etaf-define-component etaf-research-shelf-detail-actions (&key model)
  "Render stable selected-record actions for MODEL."
  :setup
  (let ((model (etaf-current-prop :model)))
    (lambda ()
      (let* ((theme (etaf-research-shelf--theme model))
             (row (etaf-research-shelf--selected model))
             (progress (or (and row (plist-get row :progress)) 0))
             (finished (and row (equal (plist-get row :status) "finished")))
             (archived (and row (equal (plist-get row :status) "archived"))))
        (etaf-view
         (flex :width 'stretch :flex-wrap 'wrap :gap '(1 (6))
          (etaf-research-shelf-button
           :theme theme :label "+ 10%" :ref 'research-shelf-progress
           :variant 'secondary
           :disabled (or (null row) archived (>= progress 100))
           :on-press
           (lambda ()
             (when-let* ((current (etaf-research-shelf--selected model))
                         (value (or (plist-get current :progress) 0)))
               (etaf-research-shelf--update-selected
                model (list :progress (min 100 (+ value 10))
                            :status (if (>= (+ value 10) 100)
                                        "finished" "reading")
                            :updated "Just now")
                "✓ Progress saved"))))
          (etaf-research-shelf-button
           :theme theme :label "✓ Finish" :ref 'research-shelf-finish
           :variant 'secondary :disabled (or (null row) finished archived)
           :on-press
           (lambda ()
             (etaf-research-shelf--update-selected
              model '(:progress 100 :status "finished" :updated "Just now")
              "✓ Marked finished")))
          (etaf-research-shelf-button
           :theme theme :label "★ Star" :ref 'research-shelf-star
           :variant 'ghost :disabled (null row)
           :on-press
           (lambda ()
             (when-let ((current (etaf-research-shelf--selected model)))
               (let ((current-starred
                      (= 1 (or (plist-get current :starred) 0))))
                 (etaf-research-shelf--update-selected
                  model (list :starred (if current-starred 0 1)
                              :updated "Just now")
                  (if current-starred
                      "Removed star" "★ Starred locally"))))))
          (etaf-research-shelf-button
           :theme theme :label "Archive" :ref 'research-shelf-archive
           :variant 'ghost :disabled (or (null row) archived)
           :on-press
           (lambda ()
             (etaf-research-shelf--update-selected
              model '(:status "archived" :updated "Just now")
              "↗ Archived")))))))))

(etaf-define-component etaf-research-shelf-filter-rail
    (&key model static-form)
  "Render the reusable Research Shelf filter rail.

The rail is a Component boundary so its button Components remain ordinary
structural children instead of leaking through a direct material `expr'."
  :setup
  (let ((model (etaf-current-prop :model))
        (static-form (etaf-current-prop :static-form)))
    (lambda () (etaf-research-shelf--filter-view model static-form))))

(etaf-define-component etaf-research-shelf-reading-list
    (&key model static-form)
  "Render the reusable Research Shelf reading list."
  :setup
  (let ((model (etaf-current-prop :model))
        (static-form (etaf-current-prop :static-form)))
    (lambda () (etaf-research-shelf--reading-list-view model static-form))))

(etaf-define-component etaf-research-shelf-detail-inspector
    (&key model static-form)
  "Render the reusable Research Shelf detail inspector."
  :setup
  (let ((model (etaf-current-prop :model))
        (static-form (etaf-current-prop :static-form)))
    (lambda () (etaf-research-shelf--detail-view model static-form))))

(etaf-define-component etaf-research-shelf-shell (&key model static-form)
  "Compose the SQLite-backed Research Shelf application."
  :styles
  (styles
   (".research-shelf-shell" :width stretch)
   (".research-shelf-header" :width stretch :padding (1 0))
   (".research-shelf-filter-rail" :width stretch)
   (".research-shelf-list" :width stretch)
   (".research-shelf-detail" :width stretch)
   (".research-shelf-footer" :width stretch :padding (0 1)))
  :setup
  (let ((model (etaf-current-prop :model))
        (static-form (etaf-current-prop :static-form)))
    (etaf-on-unmounted
     (lambda ()
       (etaf-data-stop (etaf-research-shelf--controller model))
       (when (and (display-graphic-p)
                  (fboundp 'face-remap-set-base))
         (face-remap-set-base 'default 'default))))
    (lambda ()
      (let* ((header (etaf-research-shelf--static-child static-form 'header))
             (filters (etaf-research-shelf--static-child static-form 'filters))
             (main (etaf-research-shelf--static-child static-form 'main))
             (library (etaf-research-shelf--static-child main 'library))
             (detail (etaf-research-shelf--static-child main 'detail))
             (dark (etaf-value (plist-get model :dark)))
             (palette (etaf-research-shelf--theme model)))
        (etaf-research-shelf--apply-buffer-palette palette)
        (etaf-view
         (column :class "research-shelf-shell" :width '(viewport)
                 :height '(viewport-height)
                 :color (plist-get palette :ink)
                 :bgcolor (plist-get palette :paper)
          (flex :class "research-shelf-header" :width 'stretch
                :flex-wrap 'wrap
                :align-items 'center :gap '(1 (10))
           (column :flex-grow 1 :flex-shrink 1 :flex-basis '(0) :min-width 0
            (label :text (etaf-research-shelf--static-value
                          header :eyebrow "Research Shelf")
                   :color (plist-get palette :accent)
                   :bgcolor (plist-get palette :paper))
            (label :text (etaf-research-shelf--static-value
                          static-form :title "Research Shelf") :face 'bold
                   :color (plist-get palette :ink)
                   :bgcolor (plist-get palette :paper))
            (label :text (etaf-research-shelf--static-value
                          static-form :subtitle "A quiet place for unfinished ideas")
                   :color (plist-get palette :muted)
                   :bgcolor (plist-get palette :paper)))
           (checkbox :label "Dark" :ref 'research-shelf-theme-toggle
                     :checked dark
                     :on-change (lambda (value)
                                  (setf (etaf-value (plist-get model :dark)) value)
                                  (etaf-research-shelf--apply-buffer-palette
                                   (etaf-research-shelf--theme model))
                                  (setf (etaf-value (plist-get model :toast))
                                        (if value "Dark theme" "Light theme")))))
          (flex :class "research-shelf-workspace" :width 'stretch
                :flex-wrap 'wrap :align-items 'stretch :align-content 'start
                :gap '(1 (6)) :color (plist-get palette :ink)
                :bgcolor (plist-get palette :paper)
           (etaf-research-shelf-filter-rail :model model :static-form filters)
           (etaf-research-shelf-reading-list :model model :static-form library)
           (etaf-research-shelf-detail-inspector :model model :static-form detail))
          (flex :class "research-shelf-footer" :width 'stretch
                :flex-wrap 'wrap :gap '(1 (8))
           (column :flex-grow 1 :flex-shrink 1 :flex-basis '(0) :min-width 0
            (label :text (or (etaf-value (plist-get model :toast)) "Ready")
                   :color (plist-get palette :ink)
                   :bgcolor (plist-get palette :paper)))
           (label :text (file-name-nondirectory
                         (plist-get model :database-file))
                  :color (plist-get palette :muted)
                  :bgcolor (plist-get palette :paper)))))))))

(defun etaf-research-shelf-root (static-form)
  "Consume validated STATIC-FORM and return one owned application root View."
  (unless (eq (car static-form) 'research-shelf-shell)
    (error "Unsupported Research Shelf static root: %S" static-form))
  (let ((model (etaf-research-shelf--create-model)))
    ;; Load before the first retained generation.  A DataGrid that is created
    ;; empty and populated from an on-mounted callback has no committed
    ;; material artifact to use as its first incremental anchor.
    (etaf-research-shelf--load model "✓ SQLite shelf ready")
    (lambda ()
      (etaf-view
       (research-shelf-shell :model model :static-form static-form)))))

;;;###autoload
(defun etaf-research-shelf-open (&optional buffer-name)
  "Mount and optionally display the Research Shelf application in BUFFER-NAME."
  (interactive)
  (let* ((name (or buffer-name "*ETAF Research Shelf*"))
         ;; Put the target in its real GUI window before the first Ebox
         ;; projection so `(viewport)' resolves against the user's frame.
         (buffer (get-buffer-create name)))
    (when (called-interactively-p 'interactive)
      (switch-to-buffer buffer))
    (etaf-mount buffer
                (etaf-research-shelf-root
                 (etaf-playground-read-static "research-shelf")))))

(provide 'etaf-research-shelf)
;;; research-shelf.el ends here
