;;; etaf-playground.el --- Generic ETAF source and preview workspace -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;; Author: ETAF contributors
;; Version: 0.2.2
;; Package-Requires: ((emacs "29.1") (ecss "0.1.0") (etaf "0.2.1") (etaf-db "0.1.0") (etaf-ui "0.1.0"))
;; Keywords: tools, convenience, ui

;;; Commentary:

;; Public API
;;
;; Load this package with (require 'etaf-playground) after adding the repository
;; root to load-path.
;; Only the interfaces listed below are supported for use by other packages.
;; All unlisted symbols and implementation features are internal, including
;; names without a double hyphen. Do not require files below lisp/ from consumers.
;; This Commentary is the authoritative export list; implementations and precise
;; docstrings remain beside their definitions. The manual contains workflows.
;;
;; Error: etaf-playground-dependency-error
;; ETAF Playground requires TP 2.0.0 or newer with tp-transaction
;; Catch this condition with condition-case; failed calls do not return a value.
;;
;; Variable: etaf-playground-display-action
;; Standard `display-buffer' action used for the preview buffer.
;; The default shows the preview in a right side window using half the frame.
;; Set `window-width' to a float for a ratio or an integer for a fixed column
;; count.  Use `display-buffer-pop-up-frame' to place the preview in its own
;; frame.
;;
;; Function: etaf-playground-mount-example (buffer-name name &optional session mount-options)
;;;###autoload (autoload 'etaf-playground-mount-example "etaf-playground" nil nil)
;; Mount example NAME into BUFFER-NAME and return its buffer.
;;
;; This is the low-level consumer API.  `etaf-playground-open-example' adds the
;; source editors and side-by-side workspace around it.  MOUNT-OPTIONS is
;; forwarded to `etaf-mount', including an optional initial viewport.  Source
;; loading, root construction, ETAF publication, and Ebox rendering share one
;; public framework render burst so GC cannot split an interactive mount.
;;
;; Function: etaf-playground-open (&optional target)
;;;###autoload (autoload 'etaf-playground-open "etaf-playground" nil t)
;; Open the default or selected generic ETAF Playground.
;;
;; With a known example name, TARGET selects that workspace.  A target beginning
;; with `*' is treated as a legacy direct preview buffer name and mounts the
;; default example there.
;;
;; Function: etaf-playground-register-example (name &rest options)
;;;###autoload (autoload 'etaf-playground-register-example "etaf-playground" nil nil)
;; Register companion overrides for example NAME.
;;
;; OPTIONS accepts `:root' or `:root-component' and `:feature' or
;; `:companion-feature'.  `:reload-on-refresh' is useful for a companion that
;; must reload evaluated application behavior.  Registration
;; belongs in an example companion, not in the framework, and is optional when
;; the default `etaf-NAME-root' and `etaf-NAME' conventions are used.
;;

;;; Code:

;;;###autoload
(eval-and-compile
  (add-to-list 'load-path
               (expand-file-name "lisp"
                                 (file-name-directory
                                  (or load-file-name
                                      (bound-and-true-p byte-compile-current-file)
                                      buffer-file-name)))))

(require 'etaf-playground-runtime)

(provide 'etaf-playground)
;;; etaf-playground.el ends here
