;;; research-shelf-m0a-evidence-tests.el --- Research Shelf M0a tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(defvar etaf-playground-m0a-evidence-schema)
(declare-function etaf-playground-m0a-capture-baseline
                  "../scripts/research-shelf-m0a-evidence")
(declare-function etaf-playground-m0a-capture-baseline-batch
                  "../scripts/research-shelf-m0a-evidence")
(load-file (expand-file-name "scripts/research-shelf-m0a-evidence.el"
                            default-directory))

(defmacro etaf-playground-m0a-test--with-baseline (variable &rest body)
  "Bind VARIABLE to a fresh Research Shelf baseline while running BODY."
  (declare (indent 1))
  `(let ((database (make-temp-file "research-shelf-m0a-" nil ".sqlite"))
         (buffer (generate-new-buffer-name " *research-shelf-m0a*")))
     (unwind-protect
         (let ((,variable
                (etaf-playground-m0a-capture-baseline database buffer)))
           ,@body)
       (when (get-buffer buffer) (kill-buffer buffer))
       (when (file-exists-p database) (delete-file database)))))

(ert-deftest etaf-playground-m0a-schema-separates-evidence-lanes ()
  "Define package-local semantic/trace evidence without conflating GUI timing."
  (dolist (key '(:semantic :text-properties :identity :lifecycle :sqlite
                           :performance :gui-first-paint))
    (should (plist-member etaf-playground-m0a-evidence-schema key)))
  (should
   (eq 'observed-gap
       (plist-get
        (plist-get etaf-playground-m0a-evidence-schema :gui-first-paint)
        :status))))

(ert-deftest etaf-playground-m0a-baseline-captures-five-current-contracts ()
  "Capture semantic, text/property, identity, lifecycle, and SQLite evidence."
  (etaf-playground-m0a-test--with-baseline baseline
    (should (= 64 (length (plist-get (plist-get baseline :text-properties)
                                     :text-sha256))))
    (should (> (plist-get (plist-get baseline :text-properties)
                          :property-run-count)
               0))
    (should (> (plist-get (plist-get baseline :semantic) :identity-count) 0))
    (should (memq 'research-shelf-row-2
                  (plist-get (plist-get baseline :identity) :handler-refs)))
    (should (equal '(mounted unmounted buffer-killed)
                   (mapcar (lambda (entry) (plist-get entry :event))
                           (plist-get baseline :lifecycle))))
    (should (equal 'sqlite
                   (plist-get (plist-get baseline :sqlite) :provider)))
    (should (= 256 (plist-get (plist-get baseline :sqlite) :total)))
    (should (equal '(1 2 3 4 5 6 7 8)
                   (plist-get (plist-get baseline :sqlite) :item-ids)))))

(ert-deftest etaf-playground-m0a-performance-records-observed-public-fields ()
  "Record fields actually obtainable for every current scenario report."
  (etaf-playground-m0a-test--with-baseline baseline
    (dolist (scenario
             (plist-get (plist-get baseline :performance) :scenario-matrix))
      (let ((performance (plist-get scenario :public-report-fields)))
        (dolist (field '(operation-id operation-kind elapsed-ms
                                     generation-before generation-after
                                     provider-stages gc-count gc-duration-ms))
          (should (eq 'observed (plist-get (cdr (assq field performance))
                                           :status))))
        (dolist (field '(tp-text-operations tp-property-operations
                                           tp-reconciled-objects
                                           tp-created-objects
                                           tp-removed-objects tp-moved-objects
                                           tp-full-root tp-scope-count
                                           tp-scope-fallback dirty-count
                                           patch-count))
          (should (memq (plist-get (cdr (assq field performance)) :status)
                        '(observed observed-gap))))))))

(ert-deftest etaf-playground-m0a-performance-observes-required-work-fields ()
  "Observe current cost, reactive turn, and semantic work for every scenario."
  (etaf-playground-m0a-test--with-baseline baseline
    (dolist (scenario
             (plist-get (plist-get baseline :performance) :scenario-matrix))
      (let ((performance (plist-get scenario :public-report-fields)))
        (dolist (field '(cost-class changed-sources queued-effects
                                   evaluated-effects turn-count turn-index
                                   turn-epoch semantic-nodes-visited
                                   semantic-nodes-changed
                                   semantic-nodes-reused semantic-nodes-created
                                   semantic-nodes-removed
                                   ebox-nodes-materialized full-path-reason))
          (should (eq 'observed
                      (plist-get (cdr (assq field performance)) :status))))
        (dolist (field '(turn-count semantic-nodes-visited
                                    semantic-nodes-changed
                                    semantic-nodes-reused semantic-nodes-created
                                    semantic-nodes-removed
                                    ebox-nodes-materialized))
          (should (natnump
                   (plist-get (cdr (assq field performance)) :value))))))))

(ert-deftest etaf-playground-m0a-performance-observes-tp-zero-work ()
  "Distinguish a non-participating TP stage from missing observation."
  (etaf-playground-m0a-test--with-baseline baseline
    (dolist (scenario
             (plist-get (plist-get baseline :performance) :scenario-matrix))
      (let ((performance (plist-get scenario :public-report-fields)))
        (dolist (field '(tp-text-operations tp-property-operations
                                           tp-reconciled-objects
                                           tp-created-objects
                                           tp-removed-objects tp-moved-objects))
          (should (eq 'observed
                      (plist-get (cdr (assq field performance)) :status)))
          (should (natnump
                   (plist-get (cdr (assq field performance)) :value))))))))

(ert-deftest etaf-playground-m0a-performance-work-counters-are-self-consistent ()
  "Lock the harness counter identities without imposing future budgets."
  (etaf-playground-m0a-test--with-baseline baseline
    (dolist (scenario
             (plist-get (plist-get baseline :performance) :scenario-matrix))
      (let* ((fields (plist-get scenario :public-report-fields))
             (value (lambda (field)
                      (plist-get (cdr (assq field fields)) :value)))
             (changed (funcall value 'changed-sources))
             (queued (funcall value 'queued-effects))
             (evaluated (funcall value 'evaluated-effects))
             (visited (funcall value 'semantic-nodes-visited)))
        (should (= (plist-get changed :count)
                   (length (plist-get changed :ids))))
        (should (= (plist-get queued :count)
                   (length (plist-get queued :ids))))
        (should (= (plist-get evaluated :count)
                   (length (plist-get evaluated :ids))))
        (should (= (funcall value 'turn-count)
                   (length (funcall value 'turn-index))))
        (should (= (funcall value 'turn-count)
                   (length (funcall value 'turn-epoch))))
        (should (= visited
                   (+ (funcall value 'semantic-nodes-changed)
                      (funcall value 'semantic-nodes-reused)
                      (funcall value 'semantic-nodes-created))))
        (should (or (eq 'not-full-path
                        (funcall value 'full-path-reason))
                    (eq 'full (funcall value 'cost-class))))))))

(ert-deftest etaf-playground-m0a-performance-covers-required-scenario-matrix ()
  "Cover Data, style, viewport, and dependency-only current paths."
  (etaf-playground-m0a-test--with-baseline baseline
    (let ((matrix
            (plist-get (plist-get baseline :performance) :scenario-matrix)))
      (should
       (equal '(data-mutation semantic-style viewport-scroll data-load-error
                              dependency-only scroll)
              (mapcar (lambda (scenario) (plist-get scenario :category))
                      matrix)))
      (dolist (scenario matrix)
        (should (eq 'm0a-trace (plist-get scenario :operation-kind)))
        (should (stringp (plist-get scenario :operation-label)))
        (should (eq 'observed-gap
                    (plist-get (plist-get scenario :gui-first-paint)
                               :status)))))))

(ert-deftest etaf-playground-m0a-performance-observes-allocation-and-metrics ()
  "Observe harness allocation and honest candidate-index metrics."
  (etaf-playground-m0a-test--with-baseline baseline
    (let ((matrix
           (plist-get (plist-get baseline :performance) :scenario-matrix)))
      (dolist (scenario matrix)
        (let* ((fields (plist-get scenario :public-report-fields))
               (allocation (cdr (assq 'allocation fields))))
          (should (eq 'observed (plist-get allocation :status)))
          (should (eq 'memory-use-counts
                      (plist-get (plist-get allocation :value) :api)))
          (should (listp (plist-get (plist-get allocation :value) :delta)))))
      (let* ((mutation (car matrix))
             (fields (plist-get mutation :public-report-fields)))
        (dolist (field '(candidate-index-node-visits
                         candidate-index-node-copies
                         candidate-effect-index-visits
                         candidate-source-index-visits
                         committed-generation-delta))
          (should (eq 'observed
                      (plist-get (cdr (assq field fields)) :status))))))))

(ert-deftest etaf-playground-m0a-load-error-and-scroll-lock-current-facts ()
  "Lock isolated load-error facts and a real advancing public scroll owner."
  (etaf-playground-m0a-test--with-baseline baseline
    (let* ((matrix
            (plist-get (plist-get baseline :performance) :scenario-matrix))
           (load-error
            (seq-find (lambda (scenario)
                        (eq 'data-load-error
                            (plist-get scenario :category)))
                      matrix))
           (scroll
            (seq-find (lambda (scenario)
                        (eq 'scroll (plist-get scenario :category)))
                      matrix))
           (load-fields (plist-get load-error :public-report-fields)))
      (should (symbolp (plist-get (plist-get load-error :result) :condition)))
      (should
       (= (plist-get (cdr (assq 'generation-before load-fields)) :value)
          (plist-get (cdr (assq 'generation-after load-fields)) :value)))
      (should (plist-get (plist-get scroll :current-facts)
                         :region-id-present))
      (should (> (plist-get (plist-get scroll :current-facts) :offset-after)
                 (plist-get (plist-get scroll :current-facts)
                            :offset-before))))))

(ert-deftest etaf-playground-m0a-baseline-stable-projections-are-reproducible ()
  "Reproduce stable semantic/text/identity/SQLite projections twice."
  (etaf-playground-m0a-test--with-baseline first
    (etaf-playground-m0a-test--with-baseline second
      (dolist (key '(:semantic :text-properties :identity :lifecycle :sqlite))
        (should (equal (plist-get first key) (plist-get second key)))))))

(ert-deftest etaf-playground-m0a-batch-writes-semantic-evidence-summary ()
  "Persist raw package-local evidence plus a machine-readable summary."
  (let* ((directory (make-temp-file "m0a-semantic-output-" t))
         (output (expand-file-name "semantic.eld" directory))
         (metadata (expand-file-name "semantic.json" directory))
         (process-environment (copy-sequence process-environment)))
    (unwind-protect
        (progn
          (setenv "ETAF_M0A_SEMANTIC_OUTPUT" output)
          (setenv "ETAF_M0A_SEMANTIC_METADATA" metadata)
          (should (etaf-playground-m0a-capture-baseline-batch))
          (should (> (file-attribute-size (file-attributes output)) 0))
          (with-temp-buffer
            (insert-file-contents metadata)
            (let ((record
                   (json-parse-buffer :object-type 'plist
                                      :array-type 'list)))
              (should (= 6 (plist-get record :scenario_count)))
              (should (= 1 (plist-get record :schema_version)))
              (should (eq t (plist-get record
                                       :required_work_fields_observed))))))
      (delete-directory directory t))))

(provide 'research-shelf-m0a-evidence-tests)
;;; research-shelf-m0a-evidence-tests.el ends here
