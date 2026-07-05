(in-package #:nshell.domain.configuration)

(defun %copy-theme-colors (colors)
  "Return a detached theme color table."
  (check-type colors hash-table)
  (let ((copy (make-hash-table :test (hash-table-test colors))))
    (maphash (lambda (key value)
               (check-type value string)
               (setf (gethash key copy) value))
             colors)
    copy))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defstruct (theme
              (:constructor %allocate-theme (name colors))
              (:conc-name %theme-)
              (:copier nil))
    (name "default" :type string :read-only t)
    (colors (make-hash-table :test #'eq) :type hash-table :read-only t))

  (defun make-theme (&key (name "default") (colors (make-hash-table :test #'eq)))
    (check-type name string)
    (%allocate-theme name (%copy-theme-colors colors))))

(defun theme-name (theme)
  "Return THEME's display name."
  (%theme-name theme))

(defun theme-color (theme key)
  "Return THEME's color value for KEY, or NIL when KEY is not configured."
  (gethash key (%theme-colors theme)))

(defun theme-set-color (theme key value)
  "Set THEME's color value for KEY and return THEME."
  (check-type value string)
  (setf (gethash key (%theme-colors theme)) value)
  theme)

(defun default-theme ()
  (let ((th (make-theme :name "nshell-default")))
    (theme-set-color th :normal "00FF00")
    (theme-set-color th :command "00AFFF")
    (theme-set-color th :param "00AFFF")
    (theme-set-color th :comment "737373")
    (theme-set-color th :error "FF0000")
    (theme-set-color th :operator "FFFF00")
    (theme-set-color th :quote "FFA500")
    (theme-set-color th :redirection "00AFFF")
    (theme-set-color th :autosuggestion "555555")
    (theme-set-color th :search-match "FFFF00")
    (theme-set-color th :selection "FFFFFF")
    (theme-set-color th :prompt-host "00AFFF")
    (theme-set-color th :prompt-path "00FF00")
    (theme-set-color th :prompt-error "FF0000")
    (theme-set-color th :prompt-ok "00FF00")
    th))
