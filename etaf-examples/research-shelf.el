;;; research-shelf.el --- Research Shelf application -*- lexical-binding: t; -*-

;;; Commentary:

;; This deliberately compact companion keeps the small application's complete
;; behavior in one file.  The sections make the boundaries visible without
;; introducing a feature directory.  The neighboring .etaf and .ecss files
;; remain the Playground's inert authoring sources.

;;; Code:

(require 'cl-lib)
(require 'etaf)
(require 'etaf-ui)
(require 'etaf-sqlite)
(require 'etaf-theme-tp)
(require 'etaf-playground)

;;; ---------------------------------------------------------------------------
;;; DATA / SQLITE SOURCE
;;; ---------------------------------------------------------------------------

(defcustom etaf-research-shelf-database-file
  (expand-file-name "research-shelf.sqlite" user-emacs-directory)
  "SQLite file used by the Research Shelf application."
  :type 'file
  :group 'etaf)

(defcustom etaf-research-shelf-fixture-size 256
  "Minimum deterministic records installed in the Playground database."
  :type 'natnum
  :group 'etaf)

(defcustom etaf-research-shelf-page-size 12
  "Number of records shown on one Research Shelf page."
  :type 'positive-integer
  :group 'etaf)

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
  "Return deterministic generated record ID at INDEX."
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
  "Return the deterministic fixture set sized by the user configuration."
  (let* ((target (max 0 etaf-research-shelf-fixture-size))
         (base (copy-tree etaf-research-shelf-seed-records))
         (base-count (length base)))
    (if (<= target base-count)
        (cl-subseq base 0 target)
      (append base
              (cl-loop for id from (1+ base-count) to target
                       for index from 0
                       collect (etaf-research-shelf--generated-record id index))))))

(defun etaf-research-shelf--database ()
  "Return the typed Research Shelf SQLite database description."
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

;;; ---------------------------------------------------------------------------
;;; THEME / PALETTE CONTRACT
;;; ---------------------------------------------------------------------------

(etaf-theme-define-palette etaf-research-shelf-ink
  :fg ("#172033" . "#F4F7FF"))
(etaf-theme-define-palette etaf-research-shelf-paper
  :bg ("#F7F3EA" . "#111827"))
(etaf-theme-define-palette etaf-research-shelf-panel
  :bg ("#FFFDF8" . "#182235"))
(etaf-theme-define-palette etaf-research-shelf-line
  :border ("#D9D4C9" . "#34435A"))
(etaf-theme-define-palette etaf-research-shelf-muted
  :fg ("#6D7482" . "#AAB5C8"))
(etaf-theme-define-palette etaf-research-shelf-accent
  :fg ("#3657D6" . "#8EA7FF"))
(etaf-theme-define-palette etaf-research-shelf-mint
  :fg ("#3E9B8F" . "#76D6C3")
  :bg ("#DCEBDD" . "#1B4721"))
(etaf-theme-define-palette etaf-research-shelf-coral
  :fg ("#D86B5D" . "#FF9A8E"))
(etaf-theme-define-palette etaf-research-shelf-amber
  :fg ("#C58A3A" . "#F0C36A"))
(etaf-theme-define-palette etaf-research-shelf-soft
  :bg ("#F1EEE7" . "#202C42"))

(defconst etaf-research-shelf--palette-bindings
  '(:ink (etaf-research-shelf-ink . :fg)
    :paper (etaf-research-shelf-paper . :bg)
    :panel (etaf-research-shelf-panel . :bg)
    :line (etaf-research-shelf-line . :border)
    :muted (etaf-research-shelf-muted . :fg)
    :accent (etaf-research-shelf-accent . :fg)
    :mint (etaf-research-shelf-mint . :fg)
    :mint-bg (etaf-research-shelf-mint . :bg)
    :coral (etaf-research-shelf-coral . :fg)
    :amber (etaf-research-shelf-amber . :fg)
    :soft (etaf-research-shelf-soft . :bg))
  "Mapping from product roles to the optional TP palette adapter.")

(defun etaf-research-shelf--theme (model)
  "Return MODEL's current semantic product palette."
  (etaf-theme-from-tp-palettes
   etaf-research-shelf--palette-bindings
   (if (etaf-value (plist-get model :dark)) 'dark 'light)))

(defun etaf-research-shelf--theme-defaults (model)
  "Return MODEL palette plus the public ETAF UI semantic token contract."
  (let* ((palette (etaf-research-shelf--theme model))
         (ink (plist-get palette :ink))
         (paper (plist-get palette :paper))
         (panel (plist-get palette :panel))
         (line (plist-get palette :line))
         (muted (plist-get palette :muted))
         (accent (plist-get palette :accent))
         (mint (plist-get palette :mint))
         (mint-bg (plist-get palette :mint-bg))
         (coral (plist-get palette :coral))
         (soft (plist-get palette :soft)))
    (append
     palette
     (list
      :ui-fg ink :ui-bg paper :ui-border line :ui-muted-fg muted
      :ui-danger-fg coral :ui-success-fg mint
      :ui-disabled-fg muted :ui-disabled-bg soft
      :ui-disabled-border line
      :ui-button-primary-fg paper :ui-button-primary-bg accent
      :ui-button-primary-border accent
      :ui-button-secondary-fg ink :ui-button-secondary-bg mint-bg
      :ui-button-secondary-border mint
      :ui-button-ghost-fg ink :ui-button-ghost-bg panel
      :ui-button-ghost-border line
      :ui-checkbox-enabled-fg ink :ui-checkbox-enabled-bg mint-bg
      :ui-checkbox-enabled-border mint
      :ui-checkbox-disabled-fg muted :ui-checkbox-disabled-bg soft
      :ui-checkbox-disabled-border line
      :ui-table-border line :ui-table-selected-fg mint
      :ui-table-selected-bg mint-bg
      :ui-data-grid-error-fg coral :ui-pagination-muted-fg muted
      :ui-panel-fg ink :ui-panel-bg panel :ui-panel-border line))))

;;; ---------------------------------------------------------------------------
;;; STATE / DATA CONTROLLER / ACTIONS
;;; ---------------------------------------------------------------------------

(defun etaf-research-shelf--item-id (row)
  "Return stable identity for a reading ROW."
  (plist-get row :id))

(defun etaf-research-shelf--create-model (&optional initial-result database)
  "Create the Research Shelf model from DATABASE and INITIAL-RESULT.
DATABASE is bootstrapped by the root adapter exactly once before the App is
constructed.  When omitted, initialize it for direct programmatic callers."
  (let* ((database (or database (etaf-research-shelf--ensure-database)))
         (controller
          (etaf-data-controller
           (etaf-sqlite-source database)
           :page-size etaf-research-shelf-page-size
           :initial-result initial-result
           :auto-load nil :item-key #'etaf-research-shelf--item-id
           :name 'etaf-research-shelf))
         (filter (etaf-ref 'all :name 'research-shelf-filter))
         (dark (etaf-ref nil :name 'research-shelf-dark-theme))
         (toast (etaf-ref (if initial-result
                              "✓ SQLite shelf ready"
                            "Ready to read.")
                          :name 'research-shelf-toast)))
    (list :database database
          :database-file etaf-research-shelf-database-file
          :controller controller :filter filter :dark dark :toast toast)))

(defun etaf-research-shelf--controller (model)
  "Return MODEL's Data Controller."
  (plist-get model :controller))

(defun etaf-research-shelf--query (filter)
  "Translate a product FILTER into an allowlisted equality query."
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
    (etaf-research-shelf--load
     model (format "Showing %s" (capitalize (symbol-name filter))))))

(defun etaf-research-shelf--set-page-size (model page-size)
  "Apply PAGE-SIZE to MODEL and reload from page one."
  (unless (and (integerp page-size) (<= 1 page-size 100))
    (user-error "Rows per page must be an integer from 1 to 100"))
  (let ((controller (etaf-research-shelf--controller model)))
    (etaf-data-set-page-size controller page-size)
    (etaf-data-set-page controller 1)
    (etaf-research-shelf--load
     model (format "Showing %d rows per page" page-size))))

(defun etaf-research-shelf--selected (model)
  "Return MODEL's selected item through the Data Controller identity contract."
  (etaf-data-selected-item (etaf-research-shelf--controller model)))

(defun etaf-research-shelf--mutate (model operation payload message)
  "Apply OPERATION PAYLOAD for MODEL and show MESSAGE on success."
  (let ((controller (etaf-research-shelf--controller model)))
    (condition-case err
        (prog1
            (etaf-data-mutate controller operation payload)
          (setf (etaf-value (plist-get model :toast)) message))
      (error
       (setf (etaf-value (plist-get model :toast))
             (format "⚠ Could not save: %s" (error-message-string err)))))))

(defun etaf-research-shelf--update-selected (model fields message)
  "Update selected MODEL record with FIELDS and show MESSAGE."
  (when-let* ((row (etaf-research-shelf--selected model)))
    (etaf-research-shelf--mutate
     model 'update
     (append (list :id (plist-get row :id)) fields)
     message)))

(defun etaf-research-shelf--advance-item (model item)
  "Advance ITEM in MODEL by ten percent without changing selection."
  (let ((next (min 100 (+ 10 (or (plist-get item :progress) 0)))))
    (etaf-research-shelf--mutate
     model 'update
     (list :id (plist-get item :id) :progress next
           :status (if (= next 100) "finished" "reading") :updated "Just now")
     "✓ Progress saved")))

(defun etaf-research-shelf--star-item (model item starred)
  "Set ITEM's STARRED value in MODEL without changing selection."
  (etaf-research-shelf--mutate
   model 'update
   (list :id (plist-get item :id) :starred (if starred 1 0) :updated "Just now")
   (if starred "★ Starred locally" "Removed star")))

;; Named Actions expose reusable application commands.  Simple local controls
;; can call ordinary business functions directly, as the filter button does.
(etaf-action-define etaf-research-shelf-reload (runtime model)
  "Reload MODEL's data source."
  (ignore runtime)
  (etaf-research-shelf--load model "✓ Library reloaded"))

(etaf-action-define etaf-research-shelf-page-size (runtime model page-size)
  "Apply MODEL's page size from the controlled number input."
  (ignore runtime)
  (etaf-research-shelf--set-page-size model page-size))

(etaf-action-define etaf-research-shelf-add (runtime model)
  "Insert a new reading into MODEL."
  (ignore runtime)
  (etaf-research-shelf--mutate
   model 'insert
   '(:title "New reading" :author "You" :kind "Notes"
     :status "unread" :progress 0 :priority "Medium"
     :starred 0 :note "A new note waiting for your attention."
     :updated "Just now")
   "✓ Added to your shelf"))

(etaf-action-define etaf-research-shelf-progress (runtime model)
  "Advance the selected reading by ten percent."
  (ignore runtime)
  (when-let* ((current (etaf-research-shelf--selected model)))
    (etaf-research-shelf--advance-item model current)))

(etaf-action-define etaf-research-shelf-finish (runtime model)
  "Mark the selected reading finished."
  (ignore runtime)
  (etaf-research-shelf--update-selected
   model '(:progress 100 :status "finished" :updated "Just now")
   "✓ Marked finished"))

(etaf-action-define etaf-research-shelf-star (runtime model)
  "Toggle the selected reading's star."
  (ignore runtime)
  (when-let* ((current (etaf-research-shelf--selected model)))
    (etaf-research-shelf--star-item
     model current (not (= 1 (or (plist-get current :starred) 0))))))

(etaf-action-define etaf-research-shelf-archive (runtime model)
  "Archive the selected reading."
  (ignore runtime)
  (etaf-research-shelf--update-selected
   model '(:status "archived" :updated "Just now") "↗ Archived"))

;;; ---------------------------------------------------------------------------
;;; VIEW / COMPONENTS / COMPOSITION
;;; ---------------------------------------------------------------------------

(etaf-define-component etaf-research-shelf-item-star (&key item)
  "Star ITEM through the consuming App's model."
  :setup
  (etaf-inject 'research-shelf-model nil t)
  :render
  (let ((model (etaf-state))
        (record item))
    (etaf-view
     (etaf-checkbox
      :label "★" :aria-label "Star reading"
      :checked (= 1 (or (plist-get record :starred) 0))
      :on-change
      (lambda (next)
        (etaf-research-shelf--star-item model record next))))))

(etaf-define-component etaf-research-shelf-item-advance (&key item)
  "Advance ITEM through the consuming App's model."
  :setup
  (etaf-inject 'research-shelf-model nil t)
  :render
  (let ((model (etaf-state))
        (record item))
    (etaf-view
     (etaf-button
      :label "+10%" :aria-label "Advance reading" :variant 'ghost
      :disabled
      (or (not (null (member (plist-get record :status) '("finished" "archived"))))
          (>= (or (plist-get record :progress) 0) 100))
      :on-press
      (lambda () (etaf-research-shelf--advance-item model record))))))

(defun etaf-research-shelf-star-cell (row)
  "Return ROW's star control at the consuming list's Context."
  (etaf-view (etaf-research-shelf-item-star :item row)))

(defun etaf-research-shelf-advance-cell (row)
  "Return ROW's progress control at the consuming list's Context."
  (etaf-view (etaf-research-shelf-item-advance :item row)))

(defconst etaf-research-shelf--grid-columns
  '((:key :title :label "Title" :width 21)
    (:key :author :label "Author" :width 12)
    (:key :status :label "Status" :width 10)
    (:key :progress :label "Progress" :width 8)
    (:key :kind :label "Kind" :width 7)
    (:key :starred :label "Star" :width 6
     :cell etaf-research-shelf-star-cell)
    (:key :advance :label "Advance" :width 8
     :cell etaf-research-shelf-advance-cell))
  "Compact DataGrid columns for the Research Shelf list.")

(defun etaf-research-shelf--status-label (status)
  "Return a readable status label for STATUS."
  (pcase status
    ("reading" "◷ In progress")
    ("finished" "✓ Finished")
    ("archived" "↗ Archived")
    (_ "○ Unread")))

(defun etaf-research-shelf--filter-label (form key fallback)
  "Return the static FILTER label from FORM for KEY, or FALLBACK."
  (let ((entry
         (etaf-playground-static-child
          form 'research-shelf-filter-spec)))
    (or (and entry (eq (plist-get (cdr entry) :key) key)
             (plist-get (cdr entry) :label))
        (let ((entry (cl-find-if
                      (lambda (item)
                        (and (consp item)
                             (eq (car item) 'research-shelf-filter-spec)
                             (eq (plist-get (cdr item) :key) key)))
                      (cdr form))))
          (or (and entry (plist-get (cdr entry) :label)) fallback)))))

(etaf-define-component etaf-research-shelf-filter-button
    (&key filter-key fallback)
  "Render one filter Button from inherited model and static filter Context."
  :setup
  (list :model (etaf-inject 'research-shelf-model nil t)
        :form (etaf-inject 'research-shelf-filters nil t))
  :render
  (let* ((state (etaf-state))
         (model (plist-get state :model))
         (form (plist-get state :form))
         (key filter-key)
         (label (etaf-research-shelf--filter-label form key fallback)))
    (etaf-view
     (etaf-button
      :label (if (eq key (etaf-value (plist-get model :filter)))
                 (concat "● " label)
               label)
      :variant (if (eq key (etaf-value (plist-get model :filter)))
                   'secondary 'ghost)
      :on-press (lambda () (etaf-research-shelf--set-filter model key))))))

(etaf-define-component etaf-research-shelf-filter-rail ()
  "Render the Research Shelf filter rail from inherited Context."
  :setup
  (etaf-inject 'research-shelf-model nil t)
  :view
  (column :class "research-shelf-filter-rail"
          :width 'stretch :min-width 0
          :flex-grow 1 :flex-shrink 1 :flex-basis '(220)
          :padding '(1 1)
          :border (etaf-theme-token :line)
          :color (etaf-theme-token :ink)
          :bgcolor (etaf-theme-token :panel)
   (text :font-weight 'bold "Library")
   (text :color (etaf-theme-token :muted) "VIEWS")
   (etaf-research-shelf-filter-button
    :filter-key 'all :fallback "All" :ref 'research-shelf-filter-all)
   (etaf-research-shelf-filter-button
    :filter-key 'reading :fallback "In progress"
    :ref 'research-shelf-filter-reading)
   (etaf-research-shelf-filter-button
    :filter-key 'unread :fallback "Unread"
    :ref 'research-shelf-filter-unread)
   (etaf-research-shelf-filter-button
    :filter-key 'finished :fallback "Finished"
    :ref 'research-shelf-filter-finished)
   (etaf-research-shelf-filter-button
    :filter-key 'starred :fallback "★ Starred"
    :ref 'research-shelf-filter-starred)
   (box :height 1)
   (text :color (etaf-theme-token :muted) "STORAGE")
   (text
    (expr (file-name-nondirectory (plist-get (etaf-state) :database-file))))
   (etaf-button
    :label "↻ Reload library" :ref 'research-shelf-reload :variant 'ghost
    :on-press
    (let ((model (etaf-state)))
      (lambda ()
        (etaf-dispatch 'etaf-research-shelf-reload model))))))

(etaf-define-component etaf-research-shelf-reading-list ()
  "Render the Research Shelf reading list from inherited Context."
  :setup
  (list :model (etaf-inject 'research-shelf-model nil t)
        :form (etaf-inject 'research-shelf-library nil t))
  :view
  (column :class "research-shelf-list" :width 'stretch :min-width 0
          :flex-grow 4 :flex-shrink 1 :flex-basis '(620)
          :padding '(1 2)
          :border (etaf-theme-token :line)
          :bgcolor (etaf-theme-token :panel)
   (flex :width 'stretch :flex-wrap 'wrap
         :align-items 'center :gap '(1 (8))
    (column :flex-grow 1 :flex-shrink 1 :flex-basis '(0) :min-width 0
     (text :font-weight 'bold
      (expr (etaf-playground-static-value
             (plist-get (etaf-state) :form) :title "Reading queue")))
     (text :color (etaf-theme-token :muted)
      (expr
       (format
        "%d items · SQLite-backed"
        (or (etaf-value
             (etaf-data-total
              (etaf-research-shelf--controller
               (plist-get (etaf-state) :model))))
            0)))))
    (etaf-number-input
     :label "Rows"
     :value
     (etaf-value
      (etaf-data-page-size
       (etaf-research-shelf--controller
        (plist-get (etaf-state) :model))))
     :ref 'research-shelf-page-size :min 1 :max 100
     :on-change
     (let ((model (plist-get (etaf-state) :model)))
       (lambda (next)
         (etaf-dispatch 'etaf-research-shelf-page-size model next))))
    (etaf-button
     :label "＋ Add reading" :ref 'research-shelf-add :variant 'secondary
     :on-press
     (let ((model (plist-get (etaf-state) :model)))
       (lambda ()
         (etaf-dispatch 'etaf-research-shelf-add model)))))
   (etaf-data-grid
    :controller
    (etaf-research-shelf--controller (plist-get (etaf-state) :model))
    :columns etaf-research-shelf--grid-columns
    :row-key #'etaf-research-shelf--item-id
    :row-ref
    (lambda (row)
      (intern (format "research-shelf-row-%s"
                      (etaf-research-shelf--item-id row))))
    :on-row-press
    (let ((controller
           (etaf-research-shelf--controller
            (plist-get (etaf-state) :model))))
      (lambda (row)
        (etaf-data-select-one controller
                              (etaf-research-shelf--item-id row))))
    :loading-label "◷ Loading library…"
    :error-label "⚠ Could not read the shelf. Use Reload.")
   (etaf-pagination
    :controller
    (etaf-research-shelf--controller (plist-get (etaf-state) :model))
    :previous-ref 'research-shelf-page-previous
    :next-ref 'research-shelf-page-next
    :color (etaf-theme-token :ink))))

(etaf-define-component etaf-research-shelf-detail-inspector ()
  "Render the Research Shelf detail inspector from inherited Context."
  :setup
  (list :model (etaf-inject 'research-shelf-model nil t)
        :form (etaf-inject 'research-shelf-detail nil t))
  :view
  (column :class "research-shelf-detail" :width 'stretch :min-width 0
          :flex-grow 2 :flex-shrink 1 :flex-basis '(340)
          :padding '(2 2)
          :border (etaf-theme-token :line)
          :bgcolor (etaf-theme-token :panel)
   (text :color (etaf-theme-token :accent)
    (expr (etaf-playground-static-value
           (plist-get (etaf-state) :form) :title "Selected item")))
   (text :font-weight 'bold
    (expr
     (if-let* ((row
                (etaf-research-shelf--selected
                 (plist-get (etaf-state) :model))))
         (plist-get row :title)
       "Choose a record")))
   (text :color (etaf-theme-token :muted)
    (expr
     (if-let* ((row
                (etaf-research-shelf--selected
                 (plist-get (etaf-state) :model))))
         (format "%s · %s" (plist-get row :author) (plist-get row :kind))
       "Select one row to inspect it.")))
   (box :height 1)
   (text :font-weight 'bold
    (expr
     (if-let* ((row
                (etaf-research-shelf--selected
                 (plist-get (etaf-state) :model))))
         (etaf-research-shelf--status-label (plist-get row :status))
       "○ No selection")))
   (text
    (expr
     (if-let* ((row
                (etaf-research-shelf--selected
                 (plist-get (etaf-state) :model))))
         (format "Progress  %d%%  ·  Priority %s"
                 (or (plist-get row :progress) 0)
                 (plist-get row :priority))
       "Progress  —  ·  Priority —")))
   (text :color (etaf-theme-token :accent)
    (expr
     (let* ((row
             (etaf-research-shelf--selected
              (plist-get (etaf-state) :model)))
            (progress (or (and row (plist-get row :progress)) 0))
            (filled (max 0 (min 10 (/ progress 10)))))
       (format "%s %s" (make-string filled ?█)
               (make-string (- 10 filled) ?░)))))
   (box :height 1)
   (text :color (etaf-theme-token :muted)
    (expr
     (if-let* ((row
                (etaf-research-shelf--selected
                 (plist-get (etaf-state) :model))))
         (concat "“" (or (plist-get row :note) "No note yet.") "”")
       "Your notes and actions will appear here.")))
   (box :height 1)
   (etaf-research-shelf-detail-actions)))

(etaf-define-component etaf-research-shelf-detail-actions ()
  "Render selected-record actions from the inherited Research Shelf model."
  :setup
  (etaf-inject 'research-shelf-model nil t)
  :view
  (flex :width 'stretch :flex-wrap 'wrap :gap '(1 (6))
   (etaf-button
    :label "+ 10%" :ref 'research-shelf-progress :variant 'secondary
    :disabled
    (let* ((row (etaf-research-shelf--selected (etaf-state)))
           (progress (or (and row (plist-get row :progress)) 0)))
      (or (null row) (equal (plist-get row :status) "archived")
          (>= progress 100)))
    :on-press
    (let ((model (etaf-state)))
      (lambda ()
        (etaf-dispatch 'etaf-research-shelf-progress model))))
   (etaf-button
    :label "✓ Finish" :ref 'research-shelf-finish :variant 'secondary
    :disabled
    (let ((row (etaf-research-shelf--selected (etaf-state))))
      (or (null row)
          (not (null (member (plist-get row :status)
                             '("finished" "archived"))))))
    :on-press
    (let ((model (etaf-state)))
      (lambda ()
        (etaf-dispatch 'etaf-research-shelf-finish model))))
   (etaf-button
    :label "★ Star" :ref 'research-shelf-star :variant 'ghost
    :disabled (null (etaf-research-shelf--selected (etaf-state)))
    :on-press
    (let ((model (etaf-state)))
      (lambda ()
        (etaf-dispatch 'etaf-research-shelf-star model))))
   (etaf-button
    :label "Archive" :ref 'research-shelf-archive :variant 'ghost
    :disabled
    (let ((row (etaf-research-shelf--selected (etaf-state))))
      (or (null row) (equal (plist-get row :status) "archived")))
    :on-press
    (let ((model (etaf-state)))
      (lambda ()
        (etaf-dispatch 'etaf-research-shelf-archive model))))))

(etaf-define-component etaf-research-shelf-header ()
  "Render the default `header' slot from App Context."
  :setup
  (list :model (etaf-inject 'research-shelf-model nil t)
        :root (etaf-inject 'research-shelf-root-spec nil t)
        :header (etaf-inject 'research-shelf-header-spec nil t))
  :view
  (flex :class "research-shelf-header" :width 'stretch :min-width 0
        :flex-wrap 'wrap :align-items 'center :gap '(1 (10))
   (column :flex-grow 1 :flex-shrink 1 :flex-basis '(0) :min-width 0
    (text :color (etaf-theme-token :accent)
     (expr (etaf-playground-static-value
            (plist-get (etaf-state) :header) :eyebrow "Research Shelf")))
    (text :font-weight 'bold
     (expr (etaf-playground-static-value
            (plist-get (etaf-state) :root) :title "Research Shelf")))
    (text :color (etaf-theme-token :muted)
     (expr (etaf-playground-static-value
            (plist-get (etaf-state) :root) :subtitle
            "A quiet place for unfinished ideas"))))
   (column :width 'max-content :min-width 0
           :flex-grow 0 :flex-shrink 0
    (etaf-checkbox
     :label "Dark" :ref 'research-shelf-theme-toggle
     :checked (plist-get (plist-get (etaf-state) :model) :dark)
     :on-change
     (let ((model (plist-get (etaf-state) :model)))
       (lambda (value)
         (setf (etaf-value (plist-get model :dark)) value)
         (setf (etaf-value (plist-get model :toast))
               (if value "Dark theme" "Light theme"))))))))

(etaf-define-component etaf-research-shelf-footer ()
  "Render the default `footer' slot from App Context."
  :setup
  (list :model (etaf-inject 'research-shelf-model nil t)
        :footer (etaf-inject 'research-shelf-footer-spec nil t))
  :view
  (flex :class "research-shelf-footer" :width 'stretch
        :flex-wrap 'wrap :gap '(1 (8))
   (column :flex-grow 1 :flex-shrink 1 :flex-basis '(0) :min-width 0
    (text
     (expr
      (etaf-value (plist-get (plist-get (etaf-state) :model) :toast))))
    (text :color (etaf-theme-token :muted)
     (expr (etaf-playground-static-value
            (plist-get (etaf-state) :footer)
            :label "SQLite · saved locally"))))
   (text :color (etaf-theme-token :muted)
    (expr (file-name-nondirectory
           (plist-get (plist-get (etaf-state) :model) :database-file))))))

(etaf-define-component etaf-research-shelf-shell ()
  "Pure responsive layout shell with named content slots.
The App supplies `header', `filters', `library', `detail', and `footer'; each
slot has a reusable built-in fallback for direct composition."
  :view
  (column
         :class "research-shelf-shell" :width '(viewport)
          :height '(viewport-height)
          :color (etaf-theme-token :ink)
          :bgcolor (etaf-theme-token :paper)
   (slot :name 'header
         (etaf-research-shelf-header))
   (flex
          :class "research-shelf-workspace" :width 'stretch
         :flex-wrap 'wrap :align-items 'stretch :align-content 'start
         :gap '(1 (6))
    (slot :name 'filters
          (etaf-research-shelf-filter-rail))
    (slot :name 'library
          (etaf-research-shelf-reading-list))
    (slot :name 'detail
          (etaf-research-shelf-detail-inspector)))
   (slot :name 'footer
         (etaf-research-shelf-footer))))

(etaf-define-component etaf-research-shelf-app
    (&key static-form initial-result database)
  "Own Research Shelf state and fill the pure Shell's named slots."
  :setup
  (let* ((static-form (etaf-current-prop :static-form))
         (initial-result (etaf-current-prop :initial-result))
         (database (or (etaf-current-prop :database)
                       (etaf-research-shelf--ensure-database)))
         (model (etaf-research-shelf--create-model initial-result database))
         (theme (etaf-computed
                 (lambda ()
                   (etaf-research-shelf--theme-defaults model))
                 :name 'research-shelf-theme))
         (header
          (etaf-playground-static-child
           static-form 'research-shelf-header-spec))
         (filters
          (etaf-playground-static-child
           static-form 'research-shelf-filter-specs))
         (content
          (etaf-playground-static-child
           static-form 'research-shelf-content-spec))
         (library
          (etaf-playground-static-child
           content 'research-shelf-library-spec))
         (detail
          (etaf-playground-static-child
           content 'research-shelf-detail-spec)))
    (unless initial-result
      (etaf-on-mounted
       (lambda ()
         (etaf-research-shelf--load model "✓ SQLite shelf ready"))))
    (etaf-theme-provide theme)
    (etaf-provide 'research-shelf-model model)
    (etaf-provide 'research-shelf-root-spec static-form)
    (etaf-provide 'research-shelf-header-spec header)
    (etaf-provide 'research-shelf-filters filters)
    (etaf-provide 'research-shelf-library library)
    (etaf-provide 'research-shelf-detail detail)
    (etaf-provide 'research-shelf-footer-spec
                  (etaf-playground-static-child
                   static-form 'research-shelf-footer-spec))
    nil)
  :view
  ;; These are real ETAF named slot inputs; the `.etaf' manifest remains inert
  ;; configuration and never pretends to be View syntax.
  (etaf-research-shelf-shell
   (slot :name 'header (etaf-research-shelf-header))
   (slot :name 'filters (etaf-research-shelf-filter-rail))
   (slot :name 'library (etaf-research-shelf-reading-list))
   (slot :name 'detail (etaf-research-shelf-detail-inspector))
   (slot :name 'footer (etaf-research-shelf-footer))))

;;; ---------------------------------------------------------------------------
;;; ROOT / PLAYGROUND REGISTRATION
;;; ---------------------------------------------------------------------------

(defun etaf-research-shelf-root (static-form &optional ecss-form)
  "Consume validated STATIC-FORM and ECSS-FORM as one root View."
  (unless (eq (car static-form) 'research-shelf-shell)
    (error "Unsupported Research Shelf static root: %S" static-form))
  ;; ECSS styles are scoped to a Component.  Attach the same validated
  ;; companion stylesheet to each owning Component instead of relying on
  ;; selectors crossing a nested Component boundary.
  (dolist (component '(etaf-research-shelf-shell
                       etaf-research-shelf-header
                       etaf-research-shelf-filter-rail
                       etaf-research-shelf-reading-list
                       etaf-research-shelf-detail-inspector
                       etaf-research-shelf-footer))
    (etaf-component-set-styles component ecss-form))
  (let* ((database (etaf-research-shelf--ensure-database))
         (initial-result
          (condition-case nil
              (etaf-data-source-load-page
               (etaf-sqlite-source database)
               nil 1 etaf-research-shelf-page-size)
            (error nil))))
    (lambda ()
      (etaf-view
       (etaf-research-shelf-app
        :static-form static-form
        :initial-result initial-result
        :database database)))))

(etaf-playground-register-example
 "research-shelf"
 :root #'etaf-research-shelf-root
 :feature 'etaf-research-shelf
 :reload-on-refresh t)

;;;###autoload
(defun etaf-research-shelf-open (&optional buffer-name)
  "Mount the Research Shelf, optionally displaying it in BUFFER-NAME."
  (interactive)
  (if buffer-name
      (etaf-playground-open-example "research-shelf" buffer-name)
    (etaf-playground-open-example "research-shelf")))

(provide 'etaf-research-shelf)
;;; research-shelf.el ends here
