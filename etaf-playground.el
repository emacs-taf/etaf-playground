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

;;;###autoload
(etaf-define-component etaf-playground-counter (&key title)
  "Render a retained counter titled TITLE."
  :setup
  (let ((count (etaf-ref 0 :name 'playground-count)))
    (lambda ()
      (etaf-view
       (column
        :class "etaf-playground-counter"
        (text :face 'bold (expr :value title))
        (text (expr :value (format "Count: %d" (etaf-value count))))
        (row
         (text :ref 'decrement :role 'button :tab-index 0
               :on-press (lambda () (cl-decf (etaf-value count)))
               " - ")
         (text :ref 'increment :role 'button :tab-index 0
               :on-press (lambda () (cl-incf (etaf-value count)))
               " + ")))))))

;;;###autoload
(defun etaf-playground-view ()
  "Return the core ETAF playground View without side effects."
  (etaf-view
   (column
    :class "etaf-playground-root"
    (text :face 'bold "ETAF Playground")
    (text :color "#687386"
          "One grammar: Hosts, Components, props, children, and expr.")
    (etaf-playground-counter :title "Reactive counter")
    (text :color "#687386"
          "Press + or - through the public event dispatch path."))))

;;;###autoload
(defun etaf-playground-ui-view ()
  "Return a View demonstrating the optional official `etaf-ui' catalog."
  (require 'etaf-ui)
  (etaf-view
   (column
    (etaf-panel :title "Official Components"
     (etaf-button :label "A public Component"
                  :on-press (lambda () (message "ETAF UI button pressed")))
     (etaf-checkbox :label "Controlled checkbox"
                    :on-change (lambda (value)
                                 (message "Checkbox value: %s" value))))
    (etaf-playground-counter :title "Core counter"))))

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
