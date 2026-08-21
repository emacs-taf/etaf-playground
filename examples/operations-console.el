;;; operations-console.el --- one complete ETAF application example -*- lexical-binding: t; -*-

;;; Commentary:

;; This single-file sample shows the public development path: `:view'
;; props/slots/styles, `:setup' state, a normal composable, `expr' for
;; dynamic Views, Context/Theme, callbacks/Actions/Behaviors, Data, Resource
;; cleanup, and public open/close commands.

;;; Code:

(require 'cl-lib)
(require 'etaf)
(require 'etaf-ui)

(defconst etaf-operations-console-buffer "*ETAF Operations Console*"
  "Default buffer used by `etaf-operations-console-open'.")

(defvar etaf-operations-console-cleanup-count 0
  "Observable count of composable cleanup calls for review and tests.")

;;; Pure `:view' Component: props, named/default slots, and `:styles'.

(etaf-define-component etaf-operations-console-card (&key title)
  "Render a styled card with explicit named and default slot outlets."
  :styles
  (styles
   ("&" :width stretch :border ((1) solid "#687386") :padding (1 2))
   (".operations-console-card-title" :face bold))
  :view
  (column :class "operations-console-card"
   (text :class "operations-console-card-title"
         (expr :value title))
   (slot :name 'header)
   (slot (label :text "This card has no default content."))))

;;; A normal Elisp composable called synchronously from Component `:setup'.

(defun etaf-operations-console-use-counter (name initial-value)
  "Create isolated counter state and effects for NAME and INITIAL-VALUE."
  (let* ((count (etaf-ref initial-value :name name))
         (double (etaf-computed (lambda () (* 2 (etaf-value count)))
                                :name (intern (format "%s-double" name))))
         (updates (etaf-ref 0 :name (intern (format "%s-updates" name))))
         (audit-text (format "effect saw %d" (* 2 (or initial-value 0))))
         (audit (etaf-ref audit-text
                          :name (intern (format "%s-audit" name)))))
    (etaf-watch count
                (lambda (_new _old) (cl-incf (etaf-value updates)))
                :immediate nil :name (intern (format "%s-watch" name)))
    (etaf-watch-effect
     (lambda ()
       (let ((value (etaf-value double)))
         (let ((next (format "effect saw %d" value)))
           (unless (equal next audit-text)
             (setq audit-text next)
             (setf (etaf-value audit) next)))))
     :name (intern (format "%s-effect" name)))
    (etaf-on-scope-dispose
     (lambda () (cl-incf etaf-operations-console-cleanup-count)))
    (list :name name :count count :double double :updates updates
          :audit audit)))

(defun etaf-operations-console-counter-ref (name operation)
  "Return a stable interactive ref for counter NAME and OPERATION."
  (intern (format "operations-console-%s-%s" name operation)))

;;; Stateful Component: its render closure retains the composable instance.

(etaf-define-component etaf-operations-console-counter (&key name initial-value)
  "Render one isolated counter Component instance."
  :setup
  (let* ((instance-name name)
         (initial initial-value)
         (state (etaf-operations-console-use-counter
                 (intern (format "operations-console-%s" instance-name)) initial))
         (count (plist-get state :count))
         (double (plist-get state :double))
         (updates (plist-get state :updates))
         (audit (plist-get state :audit))
         (increment (lambda () (cl-incf (etaf-value count))))
         (reset (lambda () (setf (etaf-value count) initial))))
    (lambda ()
      (etaf-view
       (operations-console-card
        :title (format "Counter %s" instance-name)
        (slot :name 'header
              (label :text "State belongs to this Component instance."))
        (label :text (format "Value: %d · Double: %d"
                             (etaf-value count) (etaf-value double)))
        (label :text (format "Watch updates: %d · Audit: %s"
                             (etaf-value updates) (etaf-value audit)))
         (flex :gap '(0 (8))
         (button :label "Increment"
                 :ref (etaf-operations-console-counter-ref instance-name "increment")
                 :on-press increment)
         (button :label "Reset"
                 :ref (etaf-operations-console-counter-ref instance-name "reset")
                 :on-press reset))
        (expr
         :value
         (when (> (etaf-value count) 0)
           (etaf-view
            (text "Dynamic child is visible after Increment.")))))))))

;;; Context and Theme: the child consumes a value provided by the shell.

;;; Named Action: state is passed explicitly, so no hidden global app state.

(etaf-action-define etaf-operations-console-named-note (runtime target)
  "Publish a message through a named Action."
  (ignore runtime)
  (setf (etaf-value target) "Named Action: pressed"))

;;; Behavior reuse: ordinary Elisp returns semantic interaction bundles.

(defun etaf-operations-console-use-toggle-behaviors (toggle message)
  "Return reusable focus and toggle Behaviors for TOGGLE and MESSAGE."
  (list
   (etaf-focusable)
   (etaf-toggleable
    :value toggle
    :on-change
    (lambda (value)
      (setf (etaf-value toggle) value
            (etaf-value message)
            (if value "Behavior toggle: on" "Behavior toggle: off"))))))

(etaf-define-component etaf-operations-console-action-panel ()
  "Show a local callback, a named Action, and reusable Behaviors."
  :setup
  (let* ((message (etaf-ref "Callback action pending" :name 'operations-console-message))
         (toggle (etaf-ref nil :name 'operations-console-toggle))
         ;; Behavior installers use function identity.  Construct this
         ;; reusable bundle once in setup so state renders retain it.
         (behaviors (etaf-operations-console-use-toggle-behaviors toggle message))
         (local-callback
          (lambda () (setf (etaf-value message) "Local callback: pressed")))
         (named-callback
          (lambda () (etaf-dispatch 'etaf-operations-console-named-note message))))
    (lambda ()
      (etaf-view
       (operations-console-card
        :title "Events, Actions, and Behaviors"
        (column :width 'stretch
         (label :text (etaf-value message)))
        (flex :gap '(0 (8))
         (button :label "Local callback"
                 :ref 'operations-console-local-callback
                 :on-press local-callback)
         (button :label "Named Action"
                 :ref 'operations-console-named-action
                 :on-press named-callback)
         (button
          :label (if (etaf-value toggle) "Behavior: on" "Behavior: off")
          :ref 'operations-console-behavior-toggle
          :use behaviors)))))))

;;; Application model: detached resources are ready before the first render.

(defun etaf-operations-console-create-model ()
  "Create and load the external model before mounting the application."
  (let* ((source (etaf-data-memory-source
                  '((:id 1 :name "Ada" :status "open")
                    (:id 2 :name "Grace" :status "review")
                    (:id 3 :name "Lin" :status "done"))
                  :id-key :id :name 'operations-console-records))
         (controller (etaf-data-controller
                      source :page-size 3 :name 'operations-console-controller))
         (fail-next (etaf-ref nil :name 'operations-console-fail-next))
         (cleanups (etaf-ref 0 :name 'operations-console-resource-cleanups))
         (health (etaf-ref "All systems nominal"
                           :name 'operations-console-health-status))
         (activity (etaf-ref "Theme provider promoted"
                             :name 'operations-console-activity))
         (trail (etaf-ref "Surface mounted · Data controller loaded"
                          :name 'operations-console-event-trail))
         (throughput (etaf-ref 2400 :name 'operations-console-throughput))
         (generation 0))
    (etaf-data-load controller)
    (let ((resource
           (etaf-resource
            (lambda ()
              (cl-incf generation)
              (if (etaf-value fail-next)
                  (progn
                    (setf (etaf-value fail-next) nil)
                    (error "Example load failed"))
                (etaf-resource-result
                 (format "Loaded value %d" generation)
                 :cleanup (lambda () (cl-incf (etaf-value cleanups))))))
            :immediate t :name 'operations-console-resource)))
      (list :controller controller :resource resource
            :fail-next fail-next :cleanups cleanups
            :health health :activity activity :trail trail
            :throughput throughput
            :health-check
            (lambda ()
              (setf (etaf-value health) "Health check complete"
                    (etaf-value activity) "Health check completed"
                    (etaf-value trail) "Health check · all owned surfaces responded"))
            :show-trail
            (lambda ()
              (setf (etaf-value activity) "Event trail focused"
                    (etaf-value trail) "Event trail opened for inspection"))))))

(defun etaf-operations-console-dispose-model (model)
  "Stop MODEL's Data Controller and dispose its Resource."
  (etaf-data-stop (plist-get model :controller))
  (etaf-resource-dispose (plist-get model :resource)))

(defun etaf-operations-console-data-status (selection items)
  "Return visible status derived from SELECTION and ITEMS."
  (let ((selected (cl-find (car selection) items :key
                           (lambda (row) (plist-get row :id))
                           :test #'equal)))
    (if selected
        (format "Selected %s" (plist-get selected :name))
      "Rows loaded from the public controller.")))

;;; Data Controller + official `data-grid'.

(etaf-define-component etaf-operations-console-data-panel (&key model)
  "Render MODEL's loaded Data Controller and interactive DataGrid."
  :setup
  (let* ((controller (plist-get model :controller))
         (view-state
          (etaf-computed
           (lambda ()
             (let ((selection (etaf-value (etaf-data-selection controller)))
                   (items (etaf-value (etaf-data-items controller))))
               (list :selected (car selection)
                     :status (etaf-operations-console-data-status selection items))))
           :name 'operations-console-data-view-state))
         (row-key (lambda (row) (plist-get row :id)))
         (row-ref (lambda (row)
                    (intern (format "operations-console-row-%s"
                                    (plist-get row :id)))))
         (row-press (lambda (row)
                      (etaf-data-select-one controller (plist-get row :id))))
         (clear-selection
          (lambda () (etaf-data-clear-selection controller))))
    (lambda ()
      (let ((state (etaf-value view-state)))
        (etaf-view
         (operations-console-card
          :title "Data Controller and DataGrid"
          (label :text (plist-get state :status))
          (data-grid
           :controller controller
           :columns '((:key :id :label "ID" :width 5)
                      (:key :name :label "NAME" :width 20)
                      (:key :status :label "STATUS" :width 10))
           :row-key row-key
           :row-ref row-ref
           :selected-key (plist-get state :selected)
           :on-row-press row-press)
          (button :label "Clear selection"
                  :ref 'operations-console-clear-selection
                  :on-press clear-selection)))))))

;;; Resource + explicit error boundary: load, reload, cleanup, and recovery.

(etaf-define-component etaf-operations-console-resource-panel (&key model)
  "Render MODEL's Resource with reload, failure, and cleanup feedback."
  :setup
  (let* ((instance-model model)
         (fail-next (plist-get instance-model :fail-next))
         (cleanups (plist-get instance-model :cleanups))
         (boundary (etaf-ref "No boundary run yet."
                             :name 'operations-console-boundary))
         (resource (plist-get instance-model :resource))
         (fail-change (lambda (value) (setf (etaf-value fail-next) value)))
         (reload (lambda () (etaf-resource-load resource)))
         (run-boundary
          (lambda ()
            (setf (etaf-value boundary)
                  (etaf-error-boundary-run
                   (lambda () (error "Handled sample"))
                   (lambda (condition)
                     (format "Handled: %s"
                             (error-message-string condition))))))))
    (lambda ()
      (etaf-view
       (operations-console-card
        :title "Resource and Error Boundary"
        (label :text (format "Status: %s"
                             (etaf-resource-status resource)))
        (label :text (or (etaf-resource-value resource)
                         (when-let ((condition (etaf-resource-error resource)))
                           (format "Error: %s"
                                   (error-message-string condition)))))
        (label :text (format "Cleanup calls: %d"
                             (etaf-value cleanups)))
        (checkbox :label "Fail next load"
                  :ref 'operations-console-fail-next
                  :checked (etaf-value fail-next)
                  :on-change fail-change)
        (flex :gap '(0 (8))
         (button :label "Reload resource"
                 :ref 'operations-console-resource-reload
                 :on-press reload)
         (button :label "Run handled boundary"
                 :ref 'operations-console-error-boundary
                 :on-press run-boundary))
        (label :text (etaf-value boundary)))))))

;;; Page composition and navigation views.

(defun etaf-operations-console-static-child (form tag)
  "Return the first static child named TAG from FORM.
The static `.etaf' form is the composition authority; the companion only
fills these safe named slots with reactive Views."
  (cl-find-if (lambda (entry)
                (and (consp entry) (eq (car entry) tag)))
              (cdr form)))

(defun etaf-operations-console-static-value (form key default)
  "Return keyword KEY from static FORM, or DEFAULT.
Keyword values are inert data; executable behavior never comes from `.etaf'."
  (let ((tail (member key (cdr form))))
    (if tail (cadr tail) default)))

(defun etaf-operations-console-static-child-value (form tag key default)
  "Return KEY from child TAG in static FORM, or DEFAULT.
The helper keeps `.etaf' consumption at one validated data boundary instead
of scattering plist reads through the application renderer."
  (etaf-operations-console-static-value
   (or (etaf-operations-console-static-child form tag) nil)
   key default))

(defun etaf-operations-console-static-child-by-value (form tag key value)
  "Return the child TAG whose KEY equals VALUE in static FORM."
  (cl-find-if (lambda (entry)
                (and (consp entry)
                     (eq (car entry) tag)
                     (equal (plist-get (cdr entry) key) value)))
              (cdr form)))

(defun etaf-operations-console-hero-view (model hero-form)
  "Return the visual hero for MODEL using static HERO-FORM copy."
  (let ((eyebrow (etaf-operations-console-static-value
                  hero-form :eyebrow "TUESDAY / 09:42 / LIVE REVIEW"))
        (title (etaf-operations-console-static-value
                hero-form :title "Make complex state feel calm.")))
    (etaf-view
     (column :class "operations-console-hero" :width 'stretch
          :padding '(2 3) :border "#17374A"
          :bgcolor "#17374A" :color "#F6F1E8"
      (column :width 'stretch
       (label :text eyebrow :face 'bold)
       (label :text title :face 'bold)
       (label :text "A single surface for components, context, behavior, data, and recovery — designed to make every ETAF update visible and explainable.")
       (flex :width 'stretch :gap '(1 (8))
        (button :label "Run health check"
                :ref 'operations-console-health-check
                :on-press (plist-get model :health-check))
        (button :label "View event trail"
                :ref 'operations-console-show-trail
                :on-press (plist-get model :show-trail))))))))

(etaf-define-component etaf-operations-console-metric
    (&key label value delta color)
  "Render one KPI metric with a retained Component owner."
  :setup
  (lambda ()
    (etaf-view
     (column :class "operations-console-metric" :width 'stretch
             :padding '(1 2) :border (etaf-current-prop :color)
             :bgcolor (etaf-theme-value
                       :surface "#FFFDF8")
             :color (etaf-theme-value :color "#142235")
       (label :text (etaf-current-prop :label))
       (label :text (etaf-current-prop :value) :face 'bold)
       (label :text (etaf-current-prop :delta)
              :color (etaf-theme-value
                      :success "#3E9B72"))))))

(defun etaf-operations-console-metric-strip-view (model)
  "Return the four-card KPI strip for MODEL."
  (etaf-view
   (grid :width 'stretch :grid-template-columns '(1fr 1fr 1fr 1fr)
         :gap '(1 (8))
    (operations-console-metric
     :label "Throughput"
     :value (format "%dk" (/ (etaf-value (plist-get model :throughput)) 1000))
     :delta "↑ 18% this week"
     :color (etaf-theme-value :teal "#2E8B83"))
    (operations-console-metric
     :label "Active flows" :value "18" :delta "+3 since 08:00"
     :color (etaf-theme-value :coral "#E26D5A"))
    (operations-console-metric
     :label "Response" :value "42ms" :delta "p95 within target"
     :color (etaf-theme-value :amber "#D99A3D"))
    (operations-console-metric
     :label "Reliability" :value "99.8%" :delta "steady"
     :color (etaf-theme-value :success "#3E9B72")))))

(defun etaf-operations-console-activity-view (model)
  "Return the reactive Activity stream card for MODEL."
  (etaf-view
   (column :class "operations-console-card" :width 'stretch
        :padding '(1 2) :border (etaf-theme-value
                                  :line "#C8C1B6")
        :bgcolor (etaf-theme-value :surface "#FFFDF8")
    (flex :width 'stretch :align-items 'center
     (column :width 'stretch :flex-grow 1 :flex-shrink 1 :min-width 0
      (label :text "Activity stream" :face 'bold)
      (label :text "Reactive events, rendered as a readable story."))
     (label :text "4 EVENTS" :color
            (etaf-theme-value :teal "#2E8B83")))
    (label :text (format "↗  %s" (etaf-value (plist-get model :activity))))
    (label :text "◆  Counter alpha crossed 2k · one Component-owned update")
    (label :text "✓  Resource boundary recovered · shell stayed mounted"))))

(defun etaf-operations-console-capability-view ()
  "Return the static capability map card."
  (etaf-view
   (column :class "operations-console-card" :width 'stretch
        :padding '(1 2) :border (etaf-theme-value
                                  :line "#C8C1B6")
        :bgcolor (etaf-theme-value :surface "#FFFDF8")
    (flex :width 'stretch :align-items 'center
     (column :width 'stretch :flex-grow 1 :flex-shrink 1 :min-width 0
      (label :text "Capability map" :face 'bold)
      (label :text "What this surface is proving."))
     (label :text "ETAF" :color
            (etaf-theme-value :teal "#2E8B83")))
    (label :text "✓  Component ownership · props, slots, setup, retained identity")
    (label :text "✓  Context + Theme · provider defaults and dark mode")
    (label :text "✓  Behavior + Actions · keyboard-ready stable refs")
    (label :text "✓  Data + Resource · selection, failure, boundary, cleanup"))))

(defun etaf-operations-console-timeline-view (model)
  "Return the event trail card for MODEL."
  (etaf-view
   (column :class "operations-console-card" :width 'stretch
        :padding '(1 2) :border (etaf-theme-value
                                  :line "#C8C1B6")
        :bgcolor (etaf-theme-value :surface "#FFFDF8")
    (flex :width 'stretch :align-items 'center
     (column :width 'stretch :flex-grow 1 :flex-shrink 1 :min-width 0
      (label :text "Event trail" :face 'bold)
      (label :text "Every meaningful action leaves a compact, inspectable trace."))
     (button :label "Clear trail" :ref 'operations-console-clear-trail
             :on-press (lambda ()
                         (setf (etaf-value (plist-get model :trail))
                               "Trail cleared · new actions append here"))))
    (label :text (format "●  %s" (etaf-value (plist-get model :trail)))))))

;; These wrappers make the HTML sections real ETAF Components.  The plain
;; `*-view' helpers stay small and readable, while the Component boundary
;; gives every dynamic `expr' a reviewed semantic owner.
(etaf-define-component etaf-operations-console-hero (&key model hero-form)
  "Render the operations hero as a retained Component."
  :setup
  (lambda () (etaf-operations-console-hero-view
              (etaf-current-prop :model)
              (etaf-current-prop :hero-form))))

(etaf-define-component etaf-operations-console-metric-strip (&key model)
  "Render the operations KPI strip as a retained Component."
  :setup
  (lambda () (etaf-operations-console-metric-strip-view
              (etaf-current-prop :model))))

(etaf-define-component etaf-operations-console-activity (&key model)
  "Render the reactive activity card as a retained Component."
  :setup
  (lambda () (etaf-operations-console-activity-view
              (etaf-current-prop :model))))

(etaf-define-component etaf-operations-console-capabilities ()
  "Render the static capability map as a reusable Component."
  :setup
  (lambda () (etaf-operations-console-capability-view)))

(etaf-define-component etaf-operations-console-timeline (&key model)
  "Render the event trail as a retained Component."
  :setup
  (lambda () (etaf-operations-console-timeline-view
              (etaf-current-prop :model))))

(defun etaf-operations-console-overview-page (model main-form)
  "Return the Overview page View for MODEL using MAIN-FORM sections."
  (let* ((overview-form (etaf-operations-console-static-child
                         main-form 'overview))
         (hero-form (etaf-operations-console-static-child
                     overview-form 'hero)))
    (etaf-view
     (column :class "operations-console-page" :width 'stretch
      (operations-console-hero :model model :hero-form hero-form)
      (operations-console-metric-strip :model model)
      (grid :width 'stretch :grid-template-columns '(5fr 3fr)
            :gap '(1 (12))
            (operations-console-activity :model model)
            (operations-console-capabilities))
      (operations-console-timeline :model model)
      (grid :width 'stretch :grid-template-columns '(1fr 1fr)
            :gap '(1 (12))
            (operations-console-counter :name "alpha" :initial-value 0)
            (operations-console-counter :name "beta" :initial-value 10)
            (operations-console-action-panel))))))

(defun etaf-operations-console-data-page (model)
  "Return the Data page View for MODEL."
  (etaf-view
   (column :class "operations-console-page" :width 'stretch
    (operations-console-data-panel :model model))))

(defun etaf-operations-console-resource-page (model)
  "Return the Resource page View for MODEL."
  (etaf-view
   (column :class "operations-console-page" :width 'stretch
    (operations-console-resource-panel :model model))))

(etaf-define-component etaf-operations-console-overview-surface
    (&key model main-form)
  "Own the material Overview page surface."
  :setup
  (lambda ()
    (etaf-operations-console-overview-page
     (etaf-current-prop :model)
     (etaf-current-prop :main-form))))

(etaf-define-component etaf-operations-console-data-surface (&key model)
  "Own the material Data page surface."
  :setup
  (lambda ()
    (etaf-operations-console-data-page (etaf-current-prop :model))))

(etaf-define-component etaf-operations-console-resource-surface (&key model)
  "Own the material Resource page surface."
  :setup
  (lambda ()
              (etaf-operations-console-resource-page (etaf-current-prop :model))))

(defun etaf-operations-console-page-view (page model main-form)
  "Return the selected page Component call for PAGE, MODEL, and MAIN-FORM.
The function is called from an `expr' Range, so the page signal belongs to
the retained route owner while the structural forms remain ordinary compiled
View calls."
  (pcase page
    ('data
     (etaf-view (operations-console-data-surface :model model)))
    ('resource
     (etaf-view (operations-console-resource-surface :model model)))
    (_
     (etaf-view
      (operations-console-overview-surface
       :model model :main-form main-form)))))

(etaf-define-component etaf-operations-console-page-router
    (&key page-ref model main-form)
  "Render the current material page from PAGE-REF and MODEL.
The page signal is read by this retained router Component, not by the root
shell, so navigation does not invalidate the whole application generation."
  :setup
  (lambda ()
    ;; Keep one material Host as the route owner's layout anchor.  Page
    ;; surfaces are Components, so the route never injects a raw View through
    ;; an unowned expr and the containing-block width remains explicit.
    (let ((model (etaf-current-prop :model))
          (main-form (etaf-current-prop :main-form))
          (page-ref (etaf-current-prop :page-ref)))
      (etaf-view
       (fragment
        (column :class "operations-console-page-router" :width 'stretch
         :ref 'operations-console-page-slot
         (expr
          :value
          (etaf-operations-console-page-view
           (etaf-value page-ref) model main-form))))))))

;;; Root shell: Context provider, two composable instances, and viewport.

(etaf-define-component etaf-operations-console-shell
    (&key model static-form page-ref)
  "Compose the complete public ETAF application."
  :styles
  (styles
   (".operations-console-shell" :width stretch :padding (1 2))
   (".operations-console-shell-header" :width stretch :padding (1 2))
   (".operations-console-nav" :padding (0 2)
    :border ((1) solid "#687386"))
   (".operations-console-main" :width stretch :padding (1 2))
   (".operations-console-page" :width stretch)
   (".operations-console-status" :width stretch :padding (0 2)
    :border ((1) solid "#687386")))
  :setup
  (let* ((instance-model model)
         (page-cell page-ref)
         (title (etaf-operations-console-static-value
                 static-form :title "Operations Console"))
         (kicker (etaf-operations-console-static-value
                  static-form :kicker "ETAF / reference workspace"))
         (header-form (etaf-operations-console-static-child static-form 'header))
         (navigation-form
          (etaf-operations-console-static-child static-form 'navigation))
         (main-form (etaf-operations-console-static-child static-form 'main))
         (status-form (etaf-operations-console-static-child static-form 'status))
         (brand-form (etaf-operations-console-static-child header-form 'brand))
         (summary-form (etaf-operations-console-static-child header-form 'summary))
         (theme-control-form
          (etaf-operations-console-static-child header-form 'theme-control))
         (overview-tab
          (etaf-operations-console-static-child-by-value
           navigation-form 'tab :key "overview"))
         (data-tab
          (etaf-operations-console-static-child-by-value
           navigation-form 'tab :key "data"))
         (resource-tab
          (etaf-operations-console-static-child-by-value
           navigation-form 'tab :key "resource"))
         (brand-mark (etaf-operations-console-static-value
                      brand-form :mark "OC"))
         (brand-name (etaf-operations-console-static-value
                      brand-form :name title))
         (summary-status (etaf-operations-console-static-value
                          summary-form :status "All systems nominal"))
         (theme-label (etaf-operations-console-static-value
                       theme-control-form :label "Theme"))
         (overview-label (etaf-operations-console-static-value
                          overview-tab :label "Overview"))
         (data-label (etaf-operations-console-static-value
                      data-tab :label "Data"))
         (resource-label (etaf-operations-console-static-value
                          resource-tab :label "Resource"))
         (dark (etaf-ref nil :name 'operations-console-dark-theme))
         (theme (etaf-computed
                 (lambda ()
                   (if (etaf-value dark)
                       '(:color "#EDF2F4" :bgcolor "#111923"
                         :surface "#182433" :line "#344455"
                         :teal "#61C6BA" :coral "#FF957F"
                         :amber "#EFC06C" :success "#73D29D")
                     '(:color "#142235" :bgcolor "#F6F1E8"
                       :surface "#FFFDF8" :line "#C8C1B6"
                       :teal "#2E8B83" :coral "#E26D5A"
                       :amber "#D99A3D" :success "#3E9B72"))))))
    (unless (and header-form navigation-form main-form status-form
                 brand-form summary-form theme-control-form
                 overview-tab data-tab resource-tab)
      (error "Invalid Operations Console shell composition: %S" static-form))
    (etaf-provide 'operations-console-theme theme)
    (etaf-theme-provide theme)
    (etaf-on-unmounted
     (lambda () (etaf-operations-console-dispose-model instance-model)))
    (lambda ()
      (etaf-view
       (column :class "operations-console-shell" :width 'stretch
               :height '(viewport-height)
        (column :class "operations-console-shell-header" :width 'stretch
         (flex :width 'stretch :align-items 'center
          (column :width 'stretch :flex-grow 1 :flex-shrink 1 :min-width 0
           (label :face 'bold :text (format "%s  %s" brand-mark brand-name))
           (label :text kicker))
          (label :text (format "●  %s" summary-status)
                 :color (etaf-theme-value
                         :success "#3E9B72")))
         (label :text "A calm reference surface for complex state, ownership, and recovery."))
        (flex :class "operations-console-nav" :width 'max-content
         :ref 'operations-console-nav
         :align-items 'center :gap '(0 (8))
         (button :label overview-label :ref 'operations-console-nav-overview
                 :on-press (lambda () (setf (etaf-value page-cell) 'overview)))
         (button :label data-label :ref 'operations-console-nav-data
                 :on-press (lambda () (setf (etaf-value page-cell) 'data)))
         (button :label resource-label :ref 'operations-console-nav-resource
                 :on-press (lambda () (setf (etaf-value page-cell) 'resource)))
         (checkbox :label theme-label :ref 'operations-console-theme-toggle
                   :checked (etaf-value dark)
                   :color (etaf-theme-value :color "#252A2E")
                   :bgcolor (etaf-theme-value :bgcolor "#F8F5EE")
                   :on-change (lambda (value)
                                (setf (etaf-value dark) value)))
         ;; Reserve the small status slot explicitly so a theme flip changes
         ;; paint/content inside the control bar without reflowing its parent.
         (label :width 12
                :text (if (etaf-value dark) "Theme: Dark" "Theme: Light")))
        (column :class "operations-console-main" :width 'stretch
                :flex-grow 1 :flex-shrink 1 :ref 'operations-console-main
         (operations-console-page-router :page-ref page-cell
                                         :model instance-model
                                         :main-form main-form))
        (column :class "operations-console-status" :width 'stretch
                :flex-shrink 0 :ref 'operations-console-status
         (label :text (or (etaf-operations-console-static-value
                           status-form :label nil)
                          "Ready for review"))))))))

;;; Public View/open/close entry points.

(defun etaf-operations-console-view (model static-form page-ref)
  "Return the root View for MODEL, STATIC-FORM, and stable PAGE-REF."
  (etaf-view (operations-console-shell :model model :static-form static-form
                                  :page-ref page-ref)))

(defun etaf-operations-console-root (static-form)
  "Consume validated STATIC-FORM and return one owned application root View."
  (unless (equal static-form
                 '(operations-console-shell
                   :title "Operations Console"
                   :kicker "ETAF / reference workspace"
                   (header
                    (brand :mark "OC" :name "Operations Console")
                    (summary :status "All systems nominal")
                    (theme-control :label "Theme"))
                   (navigation
                    (tab :key "overview" :label "Overview" :index "01")
                    (tab :key "data" :label "Data desk" :index "02")
                    (tab :key "resource" :label "Resource lab" :index "03"))
                   (main
                    (overview
                     (hero :eyebrow "Tuesday / 09:42 / live review"
                            :title "Make complex state feel calm.")
                     (metric-strip
                      (metric :key "throughput" :label "Throughput")
                      (metric :key "flows" :label "Active flows")
                      (metric :key "response" :label "Response")
                      (metric :key "reliability" :label "Reliability"))
                     (workspace
                      (activity-panel :title "Activity stream")
                      (capability-panel :title "Capability map"))
                     (timeline :title "Event trail"))
                    (data :title "Data desk")
                    (resource :title "Resource lab"))
                   (status :label "Ready for review")))
    (error "Unsupported Operations Console static root: %S" static-form))
  (let ((model (etaf-operations-console-create-model))
        (page (etaf-ref 'overview :name 'operations-console-page)))
    (lambda ()
      (etaf-operations-console-view
       model static-form page))))

;;;###autoload
(defun etaf-operations-console-open (&optional buffer-name)
  "Open the canonical Playground pair in BUFFER-NAME."
  (interactive)
  (require 'etaf-playground)
  (etaf-playground-open (or buffer-name etaf-operations-console-buffer)))

;;;###autoload
(defun etaf-operations-console-close (&optional buffer-name)
  "Unmount and kill the application buffer named BUFFER-NAME."
  (interactive)
  (let* ((name (or buffer-name etaf-operations-console-buffer))
         (runtime (etaf-runtime-for-buffer name))
         (buffer (get-buffer name)))
    (when runtime (etaf-unmount runtime))
    (when (buffer-live-p buffer) (kill-buffer buffer))
    buffer))

(provide 'etaf-operations-console)

;;; operations-console.el ends here
