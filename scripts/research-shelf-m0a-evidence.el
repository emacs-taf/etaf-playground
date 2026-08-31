;;; research-shelf-m0a-evidence.el --- Research Shelf M0a evidence -*- lexical-binding: t; -*-

;;; Commentary:
;; Reproducible current-behavior evidence for Research Shelf.  Missing target
;; observability is represented as `observed-gap'; no target counter is
;; synthesized from elapsed time or inferred from unrelated provider fields.

;;; Code:
(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'etaf-playground)
(require 'etaf-performance)

(defvar etaf-research-shelf-database-file)
(defvar etaf-research-shelf-fixture-size)
(defvar etaf-research-shelf-page-size)
(declare-function etaf-research-shelf--database "../examples/research-shelf")
(declare-function etaf-sqlite-source "etaf-sqlite")

(etaf-define-component etaf-playground-m0a-dependency-fixture (&key source)
  "Observe SOURCE while retaining equal semantic output."
  :view (text (expr (progn (etaf-value source) "same"))))

(defvar etaf-playground-m0a--database-label nil
  "Dynamic database basename redacted from reproducible evidence.")

(defvar etaf-playground-m0a--property-identities nil
  "Dynamic map used to canonicalize publication-local property identities.")

(defvar etaf-playground-m0a--next-property-identity 0
  "Next canonical property identity in the current evidence capture.")

(defconst etaf-playground-m0a--package-root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Absolute etaf-playground package root used by M0a evidence.")

(defconst etaf-playground-m0a-evidence-schema
  '(:schema-version 1
    :evidence-mode observed-baseline
    :semantic
    (generation root-semantic-id identity-count handler-refs host-refs)
    :text-properties
    (text-sha256 property-runs-sha256 property-run-count property-names)
    :identity (range-identity-count handler-refs host-refs)
    :lifecycle (mounted unmounted buffer-killed)
    :sqlite (provider total item-ids result-sha256)
    :performance
    (operation-id operation-kind elapsed-ms generation-before generation-after
                  provider-stages gc-count gc-duration-ms tp-text-operations
                  tp-property-operations tp-reconciled-objects
                  tp-created-objects tp-removed-objects tp-moved-objects
                  tp-full-root tp-scope-count tp-scope-fallback dirty-count
                  patch-count cost-class changed-sources queued-effects
                  evaluated-effects turn-count turn-index turn-epoch
                  semantic-nodes-visited semantic-nodes-changed
                  semantic-nodes-reused
                  semantic-nodes-created semantic-nodes-removed
                  ebox-nodes-materialized full-path-reason
                  candidate-index-node-visits candidate-index-node-copies
                  candidate-effect-index-visits candidate-source-index-visits
                  committed-generation-delta allocation)
    :gui-first-paint
    (:status observed-gap
     :reason no-action-start-to-forced-redisplay-complete-marker
     :activation before-performance-complete))
  "Versioned package-local M0a semantic and trace evidence schema.")

(defun etaf-playground-m0a--sha256 (value)
  "Return a stable SHA-256 digest for printed VALUE."
  (secure-hash 'sha256 (encode-coding-string (prin1-to-string value) 'utf-8)))

(defun etaf-playground-m0a--canonical-property-identity (value)
  "Return a stable encounter-order identity for publication-local VALUE."
  (or (gethash value etaf-playground-m0a--property-identities)
      (puthash value
               (prog1 etaf-playground-m0a--next-property-identity
                 (setq etaf-playground-m0a--next-property-identity
                       (1+ etaf-playground-m0a--next-property-identity)))
               etaf-playground-m0a--property-identities)))

(defun etaf-playground-m0a--canonical-paint-value (value)
  "Canonicalize publication-local TP paint slot symbols in VALUE."
  (cond
   ((and (symbolp value)
         (string-match-p "\\`tp-paint-slot-[0-9]+\\'" (symbol-name value)))
    (list 'tp-paint-slot
          (etaf-playground-m0a--canonical-property-identity value)))
   ((consp value)
    (cons (etaf-playground-m0a--canonical-paint-value (car value))
          (etaf-playground-m0a--canonical-paint-value (cdr value))))
   (t value)))

(defun etaf-playground-m0a--stable-property-value (value &optional property)
  "Return reproducible evidence for text property VALUE under PROPERTY."
  (cond
   ((memq property '(ebox-content ebox-content-owner ebox-content-owners
                                  ebox-bb ebox-bl ebox-br ebox-bt
                                  ebox-pb ebox-pl ebox-pr ebox-pt
                                  ebox-region-id ebox-scroll-region-id))
    (if (consp value)
        (mapcar #'etaf-playground-m0a--canonical-property-identity value)
      (etaf-playground-m0a--canonical-property-identity value)))
   ((eq property 'face)
    (etaf-playground-m0a--canonical-paint-value value))
   ((and (symbolp value)
         (string-match-p "\\`tp-paint-slot-[0-9]+\\'" (symbol-name value)))
    (list 'tp-paint-slot
          (etaf-playground-m0a--canonical-property-identity value)))
   ((stringp value)
    (if etaf-playground-m0a--database-label
        (replace-regexp-in-string
         (regexp-quote etaf-playground-m0a--database-label)
         "<database>" value t t)
      value))
   ((or (null value) (numberp value) (symbolp value)) value)
   ((and (consp value)
         (not (seq-some (lambda (item)
                          (or (functionp item) (markerp item)
                              (recordp item) (hash-table-p item)))
                        (flatten-tree value))))
    value)
   ((functionp value) '<function>)
   ((markerp value) '<marker>)
   ((hash-table-p value) '<hash-table>)
   ((recordp value) (list '<record> (type-of value)))
   (t (list '<opaque> (type-of value)))))

(defun etaf-playground-m0a--property-runs (buffer)
  "Return normalized text-property runs from BUFFER."
  (with-current-buffer buffer
    (let ((position (point-min))
          (etaf-playground-m0a--property-identities
           (make-hash-table :test #'equal))
          (etaf-playground-m0a--next-property-identity 0)
          runs)
      (while (< position (point-max))
        (let* ((next (or (next-property-change position nil (point-max))
                         (point-max)))
               (properties (text-properties-at position))
               normalized)
          (while properties
            (let ((property (pop properties))
                  (value (pop properties)))
              (push (cons property
                          (etaf-playground-m0a--stable-property-value
                           value property))
                    normalized)))
          (push (list :start (1- position) :end (1- next)
                      :properties
                      (sort normalized
                            (lambda (left right)
                              (string< (symbol-name (car left))
                                       (symbol-name (car right))))))
                runs)
          (setq position next)))
      (nreverse runs))))

(defun etaf-playground-m0a--stable-refs (entries)
  "Return stable symbol/string/number keys from public ENTRIES."
  (sort
   (delq nil
         (mapcar (lambda (entry)
                   (let ((key (car entry)))
                     (and (or (symbolp key) (stringp key) (numberp key)) key)))
                 entries))
   (lambda (left right) (string< (format "%S" left) (format "%S" right)))))

(defun etaf-playground-m0a--semantic-evidence (runtime)
  "Return stable public semantic/identity evidence for RUNTIME."
  (let* ((generation (etaf-runtime-current-generation runtime))
         (identity-index (etaf-generation-identity-index generation))
         (range-count 0))
    (maphash (lambda (identity _semantic-id)
               (when (eq (car-safe identity) 'range)
                 (setq range-count (1+ range-count))))
             identity-index)
    (list :generation (etaf-runtime-generation runtime)
          :root-semantic-id (etaf-generation-root-semantic-id generation)
          :identity-count (hash-table-count identity-index)
          :range-identity-count range-count
          :handler-refs
          (etaf-playground-m0a--stable-refs
           (etaf-runtime-handler-entries runtime))
          :host-refs
          (etaf-playground-m0a--stable-refs
           (etaf-runtime-host-props-entries runtime)))))

(defun etaf-playground-m0a--text-evidence (buffer)
  "Return stable text and text-property evidence from BUFFER."
  (with-current-buffer buffer
    (let* ((text (substring-no-properties (buffer-string)))
           (text (if etaf-playground-m0a--database-label
                     (replace-regexp-in-string
                      (regexp-quote etaf-playground-m0a--database-label)
                      "<database>" text t t)
                   text))
           (runs (etaf-playground-m0a--property-runs buffer))
           names)
      (dolist (run runs)
        (dolist (entry (plist-get run :properties))
          (cl-pushnew (car entry) names)))
      (list :text-sha256 (etaf-playground-m0a--sha256 text)
            :text-length (length text)
            :property-runs-sha256 (etaf-playground-m0a--sha256 runs)
            :property-run-count (length runs)
            :property-names
            (sort names (lambda (left right)
                          (string< (symbol-name left) (symbol-name right))))))))

(defun etaf-playground-m0a--sqlite-evidence ()
  "Return stable Research Shelf SQLite result evidence."
  (let* ((source (etaf-sqlite-source (etaf-research-shelf--database)))
         (result (etaf-data-source-load-page source nil 1 8))
         (items (plist-get result :items))
         (canonical
          (mapcar
           (lambda (item)
             (mapcar (lambda (key) (cons key (plist-get item key)))
                     '(:id :title :author :kind :status :progress :priority
                           :starred :note :updated)))
           items)))
    (list :provider (plist-get source :provider)
          :total (plist-get result :total)
          :item-ids (mapcar (lambda (item) (plist-get item :id)) items)
          :result-sha256 (etaf-playground-m0a--sha256 canonical))))

(defun etaf-playground-m0a--metadata-field (operation keys)
  "Return `(FOUND . VALUE)' for the first of KEYS in OPERATION stages."
  (catch 'found
    (dolist (stage (etaf-performance-operation-stages operation))
      (let ((metadata (etaf-performance-stage-metadata stage)))
        (dolist (key keys)
          (when (plist-member metadata key)
            (throw 'found (cons t (plist-get metadata key)))))))
    (cons nil nil)))

(defun etaf-playground-m0a--observed (value)
  "Return an observed evidence cell for VALUE."
  (list :status 'observed :value value))

(defun etaf-playground-m0a--gap (reason)
  "Return an observed-gap evidence cell with REASON."
  (list :status 'observed-gap :reason reason))

(defun etaf-playground-m0a--metadata-evidence (operation name keys)
  "Return NAME evidence read from OPERATION metadata using KEYS."
  (let ((found (etaf-playground-m0a--metadata-field operation keys)))
    (cons name
          (if (car found)
              (etaf-playground-m0a--observed (cdr found))
            (etaf-playground-m0a--gap 'not-in-public-report)))))

(defun etaf-playground-m0a--metadata-present-p (operation keys)
  "Return non-nil when OPERATION reports a non-nil value under KEYS."
  (let ((found (etaf-playground-m0a--metadata-field operation keys)))
    (and (car found) (cdr found))))

(defun etaf-playground-m0a--zeroable-metadata-evidence
    (operation name keys provider)
  "Return numeric NAME from OPERATION KEYS, observing zero without PROVIDER.

The zero is not a synthesized span: the ordered public provider-stage list is
the observation that PROVIDER did not participate in the operation."
  (let ((found (etaf-playground-m0a--metadata-field operation keys)))
    (cons name
          (cond
           ((car found) (etaf-playground-m0a--observed (cdr found)))
           ((not (seq-some
                  (lambda (stage)
                    (eq provider (etaf-performance-stage-provider stage)))
                  (etaf-performance-operation-stages operation)))
            (append (etaf-playground-m0a--observed 0)
                    (list :basis 'provider-stage-absent)))
           (t (etaf-playground-m0a--gap 'provider-stage-omits-counter))))))

(defun etaf-playground-m0a-performance-evidence (operation &optional allocation)
  "Return current public report fields and explicit gaps for OPERATION.
ALLOCATION is the harness-owned before/after allocation observation."
  (append
   (list
    (cons 'operation-id
          (etaf-playground-m0a--observed
           (etaf-performance-operation-id operation)))
    (cons 'operation-kind
          (etaf-playground-m0a--observed
           (etaf-performance-operation-kind operation)))
    (cons 'elapsed-ms
          (etaf-playground-m0a--observed
           (etaf-performance-operation-elapsed operation)))
    (cons 'generation-before
          (etaf-playground-m0a--observed
           (etaf-performance-operation-generation-before operation)))
    (cons 'generation-after
          (etaf-playground-m0a--observed
           (etaf-performance-operation-generation-after operation)))
    (cons 'provider-stages
          (etaf-playground-m0a--observed
           (mapcar (lambda (stage)
                     (cons (etaf-performance-stage-category stage)
                           (etaf-performance-stage-name stage)))
                   (etaf-performance-operation-stages operation))))
    (cons 'gc-count
          (etaf-playground-m0a--observed
           (etaf-performance-operation-gc-count operation)))
    (cons 'gc-duration-ms
          (etaf-playground-m0a--observed
           (etaf-performance-operation-gc-elapsed operation))))
   (mapcar
    (lambda (spec)
      (etaf-playground-m0a--zeroable-metadata-evidence
       operation (car spec) (cdr spec) 'tp))
    '((tp-text-operations :tp-text-operations :text-operations)
      (tp-property-operations :tp-property-operations :property-operations)
      (tp-reconciled-objects :reconciled-objects)
      (tp-created-objects :created-objects)
      (tp-removed-objects :removed-objects)
      (tp-moved-objects :moved-objects)))
   (mapcar
    (lambda (spec)
      (etaf-playground-m0a--metadata-evidence operation (car spec) (cdr spec)))
    '((tp-full-root :tp-full-root :full-root)
      (tp-scope-count :tp-scope-count :scope-count)
      (tp-scope-fallback :tp-scope-fallback :scope-fallback)
      (dirty-count :dirty-count)
      (patch-count :patch-count)))
   (list
    (cons 'allocation
          (if allocation
              (etaf-playground-m0a--observed allocation)
            (etaf-playground-m0a--gap 'not-measured-by-caller))))))

(defun etaf-playground-m0a--work-probe-create ()
  "Return empty operation-local current-work instrumentation."
  (list :changed-sources (make-hash-table :test #'eql)
        :queued-effects (make-hash-table :test #'eql)
        :evaluated-effects nil :turns nil
        :semantic-nodes-visited 0 :semantic-nodes-changed 0
        :semantic-nodes-reused 0 :semantic-nodes-created 0
        :semantic-nodes-removed 0 :ebox-nodes-materialized 0
        :full-generation-p nil))

(defun etaf-playground-m0a--probe-increment (probe key &optional amount)
  "Increment PROBE numeric KEY by AMOUNT, defaulting to one."
  (plist-put probe key (+ (or (plist-get probe key) 0) (or amount 1))))

(defun etaf-playground-m0a--probe-semantic-generation
    (probe runtime base generation)
  "Record exact candidate classifications for RUNTIME into PROBE.
BASE and GENERATION are the committed generations bracketing the candidate."
  (let ((candidate (etaf-runtime-candidate-graph-nodes runtime))
        (removed (etaf-runtime-candidate-removed-semantic-ids runtime)))
    (when (hash-table-p candidate)
      (maphash
       (lambda (semantic-id semantic)
         (etaf-playground-m0a--probe-increment
          probe :semantic-nodes-visited)
         (let ((old (and base
                         (etaf--pvec-get
                          (etaf-generation-semantic-nodes base) semantic-id))))
           (cond
            ((null old)
             (etaf-playground-m0a--probe-increment
              probe :semantic-nodes-created))
            ((equal-including-properties old semantic)
             (etaf-playground-m0a--probe-increment
              probe :semantic-nodes-reused))
            (t
             (etaf-playground-m0a--probe-increment
              probe :semantic-nodes-changed)))))
       candidate))
    (etaf-playground-m0a--probe-increment
     probe :semantic-nodes-removed (length removed))
    (when (etaf-runtime-candidate-full-rebuild-p runtime)
      (plist-put probe :full-generation-p t))
    generation))

(defun etaf-playground-m0a--call-with-work-probe (runtime function)
  "Call FUNCTION with operation-local current-work counters for RUNTIME.
Return `(RESULT . PROBE)'.  Counters observe existing internal boundaries;
they neither alter scheduling nor add a product reporting contract."
  (let* ((probe (etaf-playground-m0a--work-probe-create))
         (route-scheduler (symbol-function 'etaf--runtime-route-scheduler))
         (enqueue-effect (symbol-function 'etaf--runtime-enqueue-effect))
         (record-effect (symbol-function
                         'etaf--runtime-record-effect-input-version))
         (component-turn (symbol-function 'etaf--runtime-component-overlay))
         (root-turn (symbol-function 'etaf--runtime-render-root-turn))
         (build-generation (symbol-function 'etaf--runtime-build-generation))
         (text-node (symbol-function 'etaf--ebox-text-node))
         (box-node (symbol-function 'etaf--ebox-box-node))
         result)
    (cl-letf
        (((symbol-function 'etaf--runtime-route-scheduler)
          (lambda (route source)
            (when (= (etaf-runtime-route-mount-epoch route)
                     (etaf-runtime-mount-epoch runtime))
              (puthash (etaf-reactive-source-id source) t
                       (plist-get probe :changed-sources)))
            (funcall route-scheduler route source)))
         ((symbol-function 'etaf--runtime-enqueue-effect)
          (lambda (owner effect-id)
            (let ((new-p (and (eq owner runtime)
                              (not (gethash
                                    effect-id
                                    (etaf-runtime-dirty-effect-ids owner))))))
              (prog1 (funcall enqueue-effect owner effect-id)
                (when new-p
                  (puthash effect-id t (plist-get probe :queued-effects)))))))
         ((symbol-function 'etaf--runtime-record-effect-input-version)
          (lambda (owner generation effect-id)
            (when (eq owner runtime)
              (push effect-id (plist-get probe :evaluated-effects)))
            (funcall record-effect owner generation effect-id)))
         ((symbol-function 'etaf--runtime-component-overlay)
          (lambda (owner)
            (when (eq owner runtime)
              (push (list :kind 'component-overlay
                          :epoch (etaf-runtime-generation owner))
                    (plist-get probe :turns)))
            (funcall component-turn owner)))
         ((symbol-function 'etaf--runtime-render-root-turn)
          (lambda (owner &optional force-components-p)
            (when (eq owner runtime)
              (push (list :kind 'root
                          :epoch (etaf-runtime-generation owner))
                    (plist-get probe :turns)))
            (funcall root-turn owner force-components-p)))
         ((symbol-function 'etaf--runtime-build-generation)
          (lambda (owner &optional base)
            (let ((generation (funcall build-generation owner base)))
              (when (eq owner runtime)
                (etaf-playground-m0a--probe-semantic-generation
                 probe owner base generation))
              generation)))
         ((symbol-function 'etaf--ebox-text-node)
          (lambda (&rest args)
            (etaf-playground-m0a--probe-increment
             probe :ebox-nodes-materialized)
            (apply text-node args)))
         ((symbol-function 'etaf--ebox-box-node)
          (lambda (&rest args)
            (etaf-playground-m0a--probe-increment
             probe :ebox-nodes-materialized)
            (apply box-node args))))
      (setq result (funcall function)))
    (cons result probe)))

(defun etaf-playground-m0a--probe-set-value (table)
  "Return sorted numeric keys observed in hash TABLE."
  (let (values)
    (maphash (lambda (key _value) (push key values)) table)
    (sort values #'<)))

(defun etaf-playground-m0a--work-evidence
    (operation category probe)
  "Return M0a current-work evidence for OPERATION, CATEGORY, and PROBE."
  (let* ((turns (nreverse (plist-get probe :turns)))
         (changed
          (etaf-playground-m0a--probe-set-value
           (plist-get probe :changed-sources)))
         (queued
          (etaf-playground-m0a--probe-set-value
           (plist-get probe :queued-effects)))
         (evaluated (nreverse (plist-get probe :evaluated-effects)))
         (public-full-p
          (etaf-playground-m0a--metadata-present-p
           operation '(:tp-full-root :full-root :full-rerender)))
         (full-p (or (plist-get probe :full-generation-p) public-full-p))
         (cost-class
          (cond
           (full-p 'full)
           ((eq category 'data-mutation) "scope(collection)")
           ((memq category '(semantic-style viewport-scroll scroll))
            "scope(subtree/owners)")
           ((or changed
                (> (etaf-performance-operation-generation-after operation)
                   (etaf-performance-operation-generation-before operation)))
            'delta)
           (t 'no-op)))
         (full-reason
          (if full-p
              (or (cdr (etaf-playground-m0a--metadata-field
                        operation '(:native-fallback-reason
                                    :full-path-reason :fallback-reason)))
                  (and (plist-get probe :full-generation-p)
                       'runtime-candidate-full-rebuild)
                  (and public-full-p 'public-full-root-publication))
            'not-full-path)))
    (list
     (cons 'cost-class (etaf-playground-m0a--observed cost-class))
     (cons 'changed-sources
           (etaf-playground-m0a--observed
            (list :count (length changed) :ids changed)))
     (cons 'queued-effects
           (etaf-playground-m0a--observed
            (list :count (length queued) :ids queued)))
     (cons 'evaluated-effects
           (etaf-playground-m0a--observed
            (list :count (length evaluated) :ids evaluated)))
     (cons 'turn-count
           (etaf-playground-m0a--observed (length turns)))
     (cons 'turn-index
           (etaf-playground-m0a--observed
            (number-sequence 1 (length turns))))
     (cons 'turn-epoch
           (etaf-playground-m0a--observed
            (mapcar (lambda (turn) (plist-get turn :epoch)) turns)))
     (cons 'semantic-nodes-visited
           (etaf-playground-m0a--observed
            (plist-get probe :semantic-nodes-visited)))
     (cons 'semantic-nodes-changed
           (etaf-playground-m0a--observed
            (plist-get probe :semantic-nodes-changed)))
     (cons 'semantic-nodes-reused
           (etaf-playground-m0a--observed
            (plist-get probe :semantic-nodes-reused)))
     (cons 'semantic-nodes-created
           (etaf-playground-m0a--observed
            (plist-get probe :semantic-nodes-created)))
     (cons 'semantic-nodes-removed
           (etaf-playground-m0a--observed
            (plist-get probe :semantic-nodes-removed)))
     (cons 'ebox-nodes-materialized
           (etaf-playground-m0a--observed
            (plist-get probe :ebox-nodes-materialized)))
     (cons 'full-path-reason
           (etaf-playground-m0a--observed full-reason)))))

(defun etaf-playground-m0a--allocation-observation (before after)
  "Return raw BEFORE/AFTER `memory-use-counts' plus numeric deltas."
  (list :api 'memory-use-counts
        :before before :after after
        :delta
        (cl-mapcar (lambda (left right)
                     (and (numberp left) (numberp right) (- right left)))
                   before after)))

(defun etaf-playground-m0a--candidate-metric-evidence
    (runtime generation-before generation-after)
  "Return candidate metrics for RUNTIME from GENERATION-BEFORE to GENERATION-AFTER."
  (let ((names '(candidate-index-node-visits candidate-index-node-copies
                                             candidate-effect-index-visits
                                             candidate-source-index-visits)))
    (if (<= generation-after generation-before)
        (mapcar (lambda (name)
                  (cons name
                        (etaf-playground-m0a--gap
                         'no-candidate-generation-in-operation)))
                names)
      (let ((metrics (etaf-runtime-candidate-generation-metrics runtime)))
        (if (null metrics)
            (mapcar (lambda (name)
                      (cons name
                            (etaf-playground-m0a--gap
                             'candidate-metrics-unavailable)))
                    names)
          (list
           (cons 'candidate-index-node-visits
                 (etaf-playground-m0a--observed
                  (etaf--generation-metrics-node-visits metrics)))
           (cons 'candidate-index-node-copies
                 (etaf-playground-m0a--observed
                  (etaf--generation-metrics-node-copies metrics)))
           (cons 'candidate-effect-index-visits
                 (etaf-playground-m0a--observed
                  (etaf--generation-metrics-effect-visits metrics)))
           (cons 'candidate-source-index-visits
                 (etaf-playground-m0a--observed
                  (etaf--generation-metrics-source-visits metrics)))))))))

(defun etaf-playground-m0a--trace-operation
    (runtime scenario category function)
  "Run FUNCTION as SCENARIO on RUNTIME and return CATEGORY evidence."
  (let* ((before (car (etaf-performance-records)))
         (before-id (and before (etaf-performance-operation-id before)))
         (allocation-before (memory-use-counts))
         (observed
          (etaf-playground-m0a--call-with-work-probe
           runtime
           (lambda ()
             (etaf-performance-call-operation
              runtime 'm0a-trace scenario function))))
         (result (car observed))
         (probe (cdr observed))
         (allocation-after (memory-use-counts)))
    (let ((operation (car (etaf-performance-records))))
      (unless (and operation
                   (not (equal before-id
                               (etaf-performance-operation-id operation)))
                   (equal scenario
                          (etaf-performance-operation-label operation)))
        (error "M0a scenario %s did not emit one public operation" scenario))
      (let* ((generation-before
              (etaf-performance-operation-generation-before operation))
             (generation-after
              (etaf-performance-operation-generation-after operation))
             (fields
              (append
               (etaf-playground-m0a-performance-evidence
                operation
                (etaf-playground-m0a--allocation-observation
                 allocation-before allocation-after))
               (etaf-playground-m0a--work-evidence
                operation category probe)
               (etaf-playground-m0a--candidate-metric-evidence
                runtime generation-before generation-after)
               (list
                (cons 'committed-generation-delta
                      (etaf-playground-m0a--observed
                       (- generation-after generation-before)))))))
        (list :scenario-id (intern scenario)
              :category category
              :operation-label (etaf-performance-operation-label operation)
              :operation-kind (etaf-performance-operation-kind operation)
              :result result
              :public-report-fields fields
              :gui-first-paint
              (plist-get etaf-playground-m0a-evidence-schema
                         :gui-first-paint))))))

(defun etaf-playground-m0a--dependency-only-scenario ()
  "Capture one equal-output dependency-only scenario."
  (let ((buffer (generate-new-buffer-name " *etaf-m0a-dependency*"))
        (source (etaf-ref 0)) runtime evidence)
    (unwind-protect
        (progn
          (etaf-mount
           buffer
           (etaf-view
            (etaf-playground-m0a-dependency-fixture :source source)))
          (setq runtime (etaf-runtime-for-buffer buffer))
          (etaf-performance-clear)
          (etaf-performance-start runtime)
          (setq evidence
                (etaf-playground-m0a--trace-operation
                 runtime "dependency-only" 'dependency-only
                 (lambda () (setf (etaf-value source) 1))))
          (etaf-performance-stop runtime))
      (when (and runtime (etaf-runtime-mounted-p runtime))
        (ignore-errors (etaf-performance-stop runtime))
        (etaf-unmount runtime))
      (when (get-buffer buffer) (kill-buffer buffer)))
    evidence))

(defun etaf-playground-m0a--scroll-property-position (buffer)
  "Return a BUFFER position carrying an Ebox scroll-window identity."
  (with-current-buffer buffer
    (let ((position (point-min)) found)
      (while (and (< position (point-max)) (not found))
        (when (get-text-property position 'ebox-scroll-window)
          (setq found position))
        (setq position
              (or (next-single-property-change
                   position 'ebox-scroll-window nil (point-max))
                  (point-max))))
      found)))

(defun etaf-playground-m0a--scroll-scenario ()
  "Capture one real public scroll operation."
  (let ((buffer (generate-new-buffer-name " *etaf-m0a-scroll*"))
        runtime evidence)
    (unwind-protect
        (progn
          (etaf-mount
           buffer
           (etaf-view
            (column :height 3 :overflow 'scroll
              (box "line-1") (box "line-2") (box "line-3")
              (box "line-4") (box "line-5") (box "line-6"))))
          (setq runtime (etaf-runtime-for-buffer buffer))
          (let* ((position (etaf-playground-m0a--scroll-property-position
                            buffer))
                 (region-id
                  (and position
                       (with-current-buffer buffer
                         (get-text-property position 'ebox-scroll-window))))
                 (before (and region-id
                              (plist-get (ebox-scroll-state region-id)
                                         :scroll-offset))))
            (unless (and position region-id (numberp before))
              (error "M0a scroll fixture did not publish a scroll owner"))
            (etaf-performance-clear)
            (etaf-performance-start runtime)
            (setq evidence
                  (etaf-playground-m0a--trace-operation
                   runtime "public-scroll" 'scroll
                   (lambda ()
                     (with-current-buffer buffer
                       (goto-char position)
                       (ebox-scroll-down 1)))))
            (let ((after (plist-get (ebox-scroll-state region-id)
                                    :scroll-offset)))
              (unless (> after before)
                (error "M0a public scroll did not advance its owner"))
              (setq evidence
                    (plist-put evidence :current-facts
                               (list :region-id-present t
                                     :offset-before before
                                     :offset-after after))))
            (etaf-performance-stop runtime)))
      (when (and runtime (etaf-runtime-mounted-p runtime))
        (ignore-errors (etaf-performance-stop runtime))
        (etaf-unmount runtime))
      (when (get-buffer buffer) (kill-buffer buffer)))
    evidence))

(defun etaf-playground-m0a--load-app ()
  "Load the Research Shelf companion from the package root."
  (unless (featurep 'etaf-research-shelf)
    (load-file (expand-file-name "examples/research-shelf.el"
                                etaf-playground-m0a--package-root))))

(defun etaf-playground-m0a-capture-baseline (database buffer)
  "Capture one complete deterministic baseline using DATABASE and BUFFER."
  (etaf-playground-m0a--load-app)
  (let ((default-directory etaf-playground-m0a--package-root)
        (etaf-research-shelf-database-file database)
        (etaf-research-shelf-fixture-size 256)
        (etaf-research-shelf-page-size 12)
        (etaf-playground-m0a--database-label
         (file-name-nondirectory database))
        runtime semantic text sqlite lifecycle result matrix)
    (unwind-protect
        (progn
          (etaf-playground-mount-example
           buffer "research-shelf" nil
           '(:viewport-width 1400 :viewport-height 80))
          (setq runtime (etaf-runtime-for-buffer buffer)
                lifecycle (list (list :event 'mounted
                                      :runtime-mounted t :buffer-live t)))
          (etaf-performance-clear)
          (etaf-performance-start runtime)
          (etaf-dispatch-event runtime 'research-shelf-row-1 'press)
          (push
           (etaf-playground-m0a--trace-operation
            runtime "data-mutation" 'data-mutation
            (lambda ()
              (etaf-dispatch-event runtime 'research-shelf-progress 'press)))
           matrix)
          (push
           (etaf-playground-m0a--trace-operation
            runtime "semantic-style-theme" 'semantic-style
            (lambda ()
              (etaf-dispatch-event
               runtime 'research-shelf-theme-toggle 'press)))
           matrix)
          (push
           (etaf-playground-m0a--trace-operation
            runtime "viewport-resize" 'viewport-scroll
            (lambda ()
              (ebox-rerender-buffer-with-context (get-buffer buffer) 720 80)))
           matrix)
          (setq semantic (etaf-playground-m0a--semantic-evidence runtime)
                text (etaf-playground-m0a--text-evidence buffer)
                sqlite (etaf-playground-m0a--sqlite-evidence))
          (delete-file database)
          (let ((controller
                 (etaf-data-controller
                  (etaf-sqlite-source (etaf-research-shelf--database))
                  :auto-load nil :name 'm0a-load-error)))
            (unwind-protect
                (push
                 (etaf-playground-m0a--trace-operation
                  runtime "data-load-error" 'data-load-error
                  (lambda ()
                    (condition-case condition
                        (etaf-data-load controller)
                      (error (list :condition (car condition))))))
                 matrix)
              (etaf-data-stop controller)))
          (etaf-performance-stop runtime)
          (etaf-playground-close buffer)
          (setq lifecycle
                (append lifecycle
                        (list (list :event 'unmounted :runtime-mounted nil)
                              (list :event 'buffer-killed :buffer-live nil))))
          (setq result
                (list :schema-version 1
                      :semantic semantic :text-properties text
                      :identity
                      (list :range-identity-count
                            (plist-get semantic :range-identity-count)
                            :handler-refs (plist-get semantic :handler-refs)
                            :host-refs (plist-get semantic :host-refs))
                      :lifecycle lifecycle :sqlite sqlite
                      :performance
                      (list
                       :scenario-matrix
                       (append
                        (nreverse matrix)
                        (list
                         (etaf-playground-m0a--dependency-only-scenario)
                         (etaf-playground-m0a--scroll-scenario))))
                      :gui-first-paint
                      (plist-get etaf-playground-m0a-evidence-schema
                                 :gui-first-paint))))
      (when (and runtime (etaf-runtime-mounted-p runtime))
        (ignore-errors (etaf-performance-stop runtime))
        (ignore-errors (etaf-unmount runtime)))
      (when (get-buffer buffer)
        (kill-buffer buffer)))
    result))

(defconst etaf-playground-m0a--required-work-fields
  '(cost-class changed-sources queued-effects evaluated-effects turn-count
               turn-index turn-epoch semantic-nodes-visited
               semantic-nodes-changed semantic-nodes-reused
               semantic-nodes-created semantic-nodes-removed
               ebox-nodes-materialized full-path-reason
               tp-text-operations tp-property-operations
               tp-reconciled-objects tp-created-objects
               tp-removed-objects tp-moved-objects allocation)
  "Fields that every representative M0a operation must actually observe.")

(defun etaf-playground-m0a--required-work-observed-p (baseline)
  "Return non-nil when every representative operation in BASELINE is observed."
  (cl-every
   (lambda (scenario)
     (let ((fields (plist-get scenario :public-report-fields)))
       (cl-every
        (lambda (name)
          (eq 'observed (plist-get (cdr (assq name fields)) :status)))
        etaf-playground-m0a--required-work-fields)))
   (plist-get (plist-get baseline :performance) :scenario-matrix)))

(defun etaf-playground-m0a-capture-baseline-batch ()
  "Write a fresh semantic/trace baseline and JSON metadata from environment.
`ETAF_M0A_SEMANTIC_OUTPUT' names the raw printed Lisp artifact and
`ETAF_M0A_SEMANTIC_METADATA' names its machine-readable summary."
  (let ((output (or (getenv "ETAF_M0A_SEMANTIC_OUTPUT")
                    (error "ETAF_M0A_SEMANTIC_OUTPUT is not configured")))
        (metadata (or (getenv "ETAF_M0A_SEMANTIC_METADATA")
                      (error "ETAF_M0A_SEMANTIC_METADATA is not configured")))
        (database (make-temp-file "research-shelf-m0a-batch-" nil ".sqlite"))
        (buffer (generate-new-buffer-name " *research-shelf-m0a-batch*")))
    (unwind-protect
        (let* ((baseline
                (etaf-playground-m0a-capture-baseline database buffer))
               (matrix
                (plist-get (plist-get baseline :performance)
                           :scenario-matrix))
               (observed-p
                (etaf-playground-m0a--required-work-observed-p baseline)))
          (unless observed-p
            (error "M0a semantic evidence has unobserved required work"))
          (make-directory (file-name-directory output) t)
          (make-directory (file-name-directory metadata) t)
          (with-temp-file output
            (let ((print-circle t) (print-length nil) (print-level nil))
              (prin1 baseline (current-buffer))
              (insert "\n")))
          (with-temp-file metadata
            (insert
             (json-serialize
              `((schema_version . 1)
                (scenario_count . ,(length matrix))
                (required_work_fields_observed . t)
                (semantic_artifact . ,(file-name-nondirectory output)))))
            (insert "\n"))
          (princ (format "semantic-evidence-scenarios=%d required-work=observed\n"
                         (length matrix)))
          t)
      (when (get-buffer buffer) (kill-buffer buffer))
      (when (file-exists-p database) (delete-file database)))))

(provide 'research-shelf-m0a-evidence)
;;; research-shelf-m0a-evidence.el ends here
