;;; desktop.el --- ETAF Desktop Playground consumer -*- lexical-binding: t; -*-

(require 'etaf)
(require 'etaf-desktop)
(require 'etaf-playground)

(defvar etaf-playground-desktop--controller nil
  "Controller owned by the desktop Playground example.")

(defun etaf-playground-desktop--ensure ()
  "Create the example desktop and its initial application windows."
  (unless etaf-playground-desktop--controller
    (setq etaf-playground-desktop--controller
          (etaf-desktop-create :name "*ETAF Playground Desktop*"
                               :canvas-width 120 :canvas-height 32))
    (etaf-desktop-open-window
     etaf-playground-desktop--controller 'notes :title "Notes"
     :x 3 :y 2 :width 42 :height 10
     :view (etaf-view (text "A controlled ETAF Desktop window.")))
    (etaf-desktop-open-window
     etaf-playground-desktop--controller 'signal :title "Signal"
     :x 52 :y 8 :width 38 :height 8
     :view (etaf-view (text "Move, resize, minimize and restore me."))))
  etaf-playground-desktop--controller)

(etaf-define-component etaf-playground-desktop--root (&key desktop)
  "Own the Playground desktop Runtime lifecycle without owning its policy."
  :setup
  (progn
    (etaf-on-unmounted (lambda () (etaf-desktop-close desktop)))
    nil)
  :view
  (expr (etaf-desktop-view desktop)))

(defun etaf-playground-desktop-root (&optional _static-form _ecss-form)
  "Return the public ETAF Desktop View for the Playground consumer example."
  (let ((desktop (etaf-playground-desktop--ensure)))
    (etaf-view (etaf-playground-desktop--root :desktop desktop))))

(etaf-playground-register-example
 "desktop" :root #'etaf-playground-desktop-root
 :feature 'etaf-playground-desktop)

(provide 'etaf-playground-desktop)
;;; desktop.el ends here
