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

(nshell.util:define-value-struct
  theme
  ((name "default" :type string)
   (colors (make-hash-table :test #'eq) :type hash-table))
  :documentation
  "An immutable named mapping from highlight roles to color strings."
  :constructor
  %allocate-theme
  :public-accessors
  nil)

(defun make-theme (&key (name "default") (colors (make-hash-table :test #'eq)))
  (check-type name string)
  (check-type colors hash-table)
  (%allocate-theme name (%copy-theme-colors colors)))

(defun theme-name (theme)
  "Return THEME's display name."
  (%theme-name theme))

(defun theme-color (theme key)
  "Return THEME's color value for KEY, or NIL when KEY is not configured."
  (gethash key (%theme-colors theme)))

(defun theme-set-color (theme key value)
  "Return a theme with VALUE configured for KEY."
  (check-type value string)
  (let ((colors (%copy-theme-colors (%theme-colors theme))))
    (setf (gethash key colors) value)
    (%allocate-theme (%theme-name theme) colors)))

(defun default-theme ()
  (reduce (lambda (theme color)
            (apply #'theme-set-color theme color))
          '((:normal "00FF00") (:command "00AFFF") (:param "00AFFF")
            (:comment "737373") (:error "FF0000") (:operator "FFFF00")
            (:quote "FFA500") (:redirection "00AFFF")
            (:autosuggestion "555555") (:search-match "FFFF00")
            (:selection "FFFFFF") (:prompt-host "00AFFF")
            (:prompt-path "00FF00") (:prompt-error "FF0000")
            (:prompt-ok "00FF00"))
          :initial-value (make-theme :name "nshell-default")))
