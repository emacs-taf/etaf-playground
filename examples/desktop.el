;;; desktop.el --- ETAF Desktop Playground consumer -*- lexical-binding: t; -*-

(require 'etaf)
(require 'etaf-desktop)
(require 'etaf-playground)

(defvar etaf-playground-desktop--controller nil
  "Controller owned by the desktop Playground example.")

(defun etaf-playground-desktop--register-apps ()
  "Register the two Playground applications consumed by the desktop host."
  (etaf-desktop-register-app
   'etaf-playground-notes :title "Notes"
   :capabilities '(multiple-instances resizable)
   :open (lambda (_context)
           (list :windows
                 (list (list :id "main" :title "Notes"
                             :view (etaf-view
                                    (text "A controlled ETAF Desktop window."))
                             :x 24 :y 2 :width 360 :height 10
                             :min-width 160 :min-height 4))))
   :replace t)
  (etaf-desktop-register-app
   'etaf-playground-signal :title "Signal"
   :capabilities '(resizable)
   :open (lambda (_context)
           (list :windows
                 (list (list :id "main" :title "Signal"
                             :view (etaf-view
                                    (text "Move, resize, minimize and restore me."))
                             :x 420 :y 8 :width 360 :height 8
                             :min-width 160 :min-height 4))))
   :replace t))

(defun etaf-playground-desktop--ensure ()
  "Create the example desktop and its initial application windows."
  (unless etaf-playground-desktop--controller
    (etaf-playground-desktop--register-apps)
    (setq etaf-playground-desktop--controller
          (etaf-desktop-create :name "*ETAF Playground Desktop*"
                               :workspaces '(main dev)))
    (etaf-desktop-launch etaf-playground-desktop--controller
                         'etaf-playground-notes :instance-id "playground-notes-1"
                         :workspace 'main)
    (etaf-desktop-launch etaf-playground-desktop--controller
                         'etaf-playground-signal :instance-id "playground-signal-1"
                         :workspace 'main)
    (etaf-desktop-set-layout-mode etaf-playground-desktop--controller
                                  'tiling 'main)
    (etaf-desktop-switch-workspace etaf-playground-desktop--controller 'main))
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

(etaf-playground-register-example "desktop" :root #'etaf-playground-desktop-root)

(provide 'etaf-playground-desktop)
;;; desktop.el ends here
