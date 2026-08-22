;;; etaf-playground-tests.el --- Research Shelf pair contract -*- lexical-binding: t; -*-

;;; Commentary:
;; These tests exercise the generic pair boundary and one real application.
;; The framework tests never reach into the application's model; application
;; tests drive only public refs/events and observe the rendered surface.

;;; Code:
(require 'cl-lib)
(require 'ert)
(require 'etaf-playground)

(defun etaf-playground-test--ensure-app-loaded ()
  "Load the same-basename Research Shelf companion for test setup."
  (unless (featurep 'etaf-research-shelf)
    (load-file (expand-file-name "examples/research-shelf.el"
                                default-directory))))

(defun etaf-playground-test--text (buffer)
  "Return BUFFER's plain rendered text."
  (with-current-buffer buffer
    (substring-no-properties (buffer-string))))

(defun etaf-playground-test--close (buffer)
  "Close BUFFER when it exists."
  (when (get-buffer buffer)
    (etaf-playground-close buffer)))

(defmacro etaf-playground-test--with-app (variables &rest body)
  "Run BODY with VARIABLES.
VARIABLES is a `(BUFFER DATABASE)' list; the macro creates a temporary SQLite
database and mounts a test buffer before running BODY."
  (declare (indent 1))
  (let ((buffer (car variables))
        (database (cadr variables)))
    (unless (and (symbolp buffer) (symbolp database))
      (error "Expected (BUFFER DATABASE) variables, got %S" variables))
    `(let* ((,database (make-temp-file "etaf-research-shelf-" nil ".sqlite"))
            (,buffer " *etaf-research-shelf-test*"))
       (ignore ,database)
       (etaf-playground-test--ensure-app-loaded)
     (unwind-protect
         (let ((etaf-research-shelf-database-file ,database))
             (ignore etaf-research-shelf-database-file)
             ,@body)
         (etaf-playground-test--close ,buffer)
         (when (file-exists-p ,database)
           (delete-file ,database))))))

(ert-deftest etaf-playground-manifest-describes-one-pair ()
  "Expose one reviewed pair through a generic manifest."
  (should (equal '("research-shelf") etaf-playground-example-names))
  (should (= 1 (length etaf-playground-scenario-manifest)))
  (let ((entry (car etaf-playground-scenario-manifest))
        (framework (with-temp-buffer
                     (insert-file-contents "etaf-playground.el")
                     (buffer-string)))
        (catalog (with-temp-buffer
                   (insert-file-contents "etaf-playground-catalog.el")
                   (buffer-string)))
        (makefile (with-temp-buffer
                    (insert-file-contents "Makefile")
                    (buffer-string))))
    (dolist (key '(:pair :root-component :companion-feature :static-tags
                   :capabilities :refs :gui-checkpoints :performance))
      (should (plist-member entry key)))
    (should (string-match-p
             "EXAMPLE_EL := examples/research-shelf.el" makefile))
    (should-not (string-match-p "wildcard examples" makefile))
    (should-not (string-match-p "require.*etaf-sqlite" framework))
    (should-not (string-match-p "research-shelf" framework))
    (should-not (string-match-p "operations-console" framework))
    (should (string-match-p "research-shelf" catalog))))

(ert-deftest etaf-playground-compile-builds-the-dependency-graph ()
  "Integration builds must compile the framework's dependency graph first."
  (let ((makefile (with-temp-buffer
                    (insert-file-contents "Makefile")
                    (buffer-string))))
    (dolist (dependency '("$(MAKE) -C ../ecss compile"
                          "$(MAKE) -C ../tp compile"
                          "$(MAKE) -C ../ebox compile"
                          "$(MAKE) -C ../etaf compile"
                          "$(MAKE) -C ../etaf-ui compile"
                          "$(MAKE) -C ../etaf-sqlite compile"))
      (should (string-match-p (regexp-quote dependency) makefile)))))

(ert-deftest etaf-playground-static-reader-is-inert-and-strict ()
  "Read pair structure as inert data and reject executable AST nodes."
  (let* ((form (etaf-playground-read-static "research-shelf"))
         (tags (plist-get (etaf-playground-scenario "research-shelf")
                          :static-tags)))
    (should (equal (car form) 'research-shelf-shell))
    (should (equal (plist-get (cdr form) :title) "Research Shelf"))
    (should (equal (mapcar #'car
                           (cl-remove-if-not #'consp (cdr form)))
                   '(header filters main footer)))
    (let* ((filters (cl-find-if
                     (lambda (entry) (and (consp entry)
                                          (eq (car entry) 'filters)))
                     (cdr form)))
           (all-filter (cl-find-if
                        (lambda (entry) (and (consp entry)
                                             (eq (car entry) 'filter)
                                             (eq (plist-get (cdr entry) :key)
                                                 'all)))
                        (cdr filters))))
      (should all-filter))
    (dolist (unsafe '((lambda () 1) (eval '(message "x"))
                      (etaf--private) (ebox--private) (shell-command "x")))
      (should-error (etaf-playground--validate-static-node unsafe tags)
                    :type 'error))))

(ert-deftest etaf-playground-pair-mounts-sqlite-backed-surface ()
  "Mounting the pair initializes SQLite and renders the real app shell."
  (etaf-playground-test--with-app (buffer database)
    (etaf-playground-open buffer)
    (should (etaf-runtime-p (etaf-runtime-for-buffer buffer)))
    (should (file-exists-p database))
    (let ((text (etaf-playground-test--text buffer))
          (runtime (etaf-runtime-for-buffer buffer)))
      (should (string-match-p "Research Shelf" text))
      (should (string-match-p "8 items · SQLite-backed" text))
      (should (string-match-p "The Shape of Tools" text))
      (dolist (ref '(research-shelf-filter-all research-shelf-filter-reading
                     research-shelf-filter-unread research-shelf-filter-finished
                     research-shelf-filter-starred research-shelf-reload
                     research-shelf-add research-shelf-page-next
                     research-shelf-theme-toggle))
        (should (etaf-runtime-handler-for runtime ref))))))

(ert-deftest etaf-playground-row-selection-is-repeatable ()
  "Repeated DataGrid row presses replace one selected identity."
  (etaf-playground-test--with-app (buffer database)
    (etaf-playground-open buffer)
    (let ((runtime (etaf-runtime-for-buffer buffer)))
      (dolist (entry '((research-shelf-row-1 research-shelf-row-2
                        "The best tools make attention feel larger")
                       (research-shelf-row-2 research-shelf-row-1
                        "Look again at the relationship between image and power")
                       (research-shelf-row-1 research-shelf-row-2
                        "The best tools make attention feel larger")
                       (research-shelf-row-2 research-shelf-row-1
                        "Look again at the relationship between image and power")))
        (let ((selected (nth 0 entry))
              (other (nth 1 entry))
              (detail (nth 2 entry)))
          (should (etaf-runtime-handler-for runtime selected))
          (etaf-focus runtime selected)
          (etaf-dispatch-event runtime selected 'press)
          (let ((text (etaf-playground-test--text buffer)))
            (should (string-match-p (regexp-quote detail) text)))
          (should (string-match-p
                   "selected"
                   (plist-get (etaf-runtime-host-props-for runtime selected)
                              :class)))
          (should-not (string-match-p
                       "selected"
                       (plist-get (etaf-runtime-host-props-for runtime other)
                                  :class))))))))

(ert-deftest etaf-playground-filters-and-pagination-reload-data ()
  "Filter and pager refs drive the SQLite-backed Data Controller."
  (etaf-playground-test--with-app (buffer database)
    (etaf-playground-open buffer)
    (let ((runtime (etaf-runtime-for-buffer buffer)))
      (etaf-dispatch-event runtime 'research-shelf-filter-reading 'press)
      (let ((text (etaf-playground-test--text buffer)))
        (should (string-match-p "Showing Reading" text))
        (should (string-match-p "Designing for Calm" text))
        (should-not (string-match-p "Ways of Seeing" text)))
      (etaf-dispatch-event runtime 'research-shelf-filter-all 'press)
      (etaf-dispatch-event runtime 'research-shelf-page-next 'press)
      (should (string-match-p "Page 2 / 2"
                              (etaf-playground-test--text buffer)))
      (etaf-dispatch-event runtime 'research-shelf-page-previous 'press)
      (should (string-match-p "Page 1 / 2"
                              (etaf-playground-test--text buffer))))))

(ert-deftest etaf-playground-mutations-persist-and-refresh ()
  "Add and mutate actions persist through the SQLite source and refresh UI."
  (etaf-playground-test--with-app (buffer database)
    (etaf-playground-open buffer)
    (let ((runtime (etaf-runtime-for-buffer buffer)))
      (etaf-dispatch-event runtime 'research-shelf-row-1 'press)
      (etaf-dispatch-event runtime 'research-shelf-progress 'press)
      (should (string-match-p "Progress saved"
                              (etaf-playground-test--text buffer)))
      (etaf-dispatch-event runtime 'research-shelf-star 'press)
      (should (string-match-p "Removed star"
                              (etaf-playground-test--text buffer)))
      (etaf-dispatch-event runtime 'research-shelf-add 'press)
      (should (string-match-p "Added to your shelf"
                              (etaf-playground-test--text buffer)))
      (should (file-exists-p database)))))

(ert-deftest etaf-playground-theme-and-lifecycle-are-repeatable ()
  "Theme changes and reset/close do not leave a stale mounted runtime."
  (etaf-playground-test--with-app (buffer database)
    (etaf-playground-open buffer)
    (let ((runtime (etaf-runtime-for-buffer buffer)))
      (etaf-dispatch-event runtime 'research-shelf-row-1 'press)
      (dotimes (_ 4)
        (etaf-dispatch-event runtime 'research-shelf-theme-toggle 'press))
      (should (string-match-p "The Shape of Tools"
                              (etaf-playground-test--text buffer)))
      (should (or (string-match-p "☑ Dark"
                                  (etaf-playground-test--text buffer))
                  (string-match-p "☐ Dark"
                                  (etaf-playground-test--text buffer)))))
    (etaf-playground-reset buffer)
    (should (etaf-runtime-p (etaf-runtime-for-buffer buffer))))
  (should-not (get-buffer " *etaf-research-shelf-test*")))

(provide 'etaf-playground-tests)
;;; etaf-playground-tests.el ends here
