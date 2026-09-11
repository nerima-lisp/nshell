(in-package #:nshell.domain.configuration)

;;; A theme maps highlight roles to style specs. A style spec is the fish
;;; set_color vocabulary in one string: an optional color ("5fafff", "#fff",
;;; "brblue", "normal") followed by flags ("--bold", "--underline",
;;; "--background=303030"). Parsing happens once at theme construction so
;;; rendering only looks up a parsed TEXT-STYLE.

(define-condition invalid-style-spec (error)
  ((spec :initarg :spec :reader invalid-style-spec-spec)
   (reason :initarg :reason :reader invalid-style-spec-reason))
  (:report (lambda (condition stream)
             (format stream "invalid style ~s: ~a"
                     (invalid-style-spec-spec condition)
                     (invalid-style-spec-reason condition)))))

(define-value-struct text-style
    ((foreground nil :type list)
     (background nil :type list)
     (bold nil :type boolean)
     (dim nil :type boolean)
     (italic nil :type boolean)
     (underline nil :type boolean)
     (reverse nil :type boolean))
  :documentation
  "A parsed style spec. FOREGROUND and BACKGROUND are NIL (terminal default),
(:RGB R G B), or (:NAMED INDEX) with INDEX in the 16-color palette."
  :keyword-constructor t)

(defun %style-token-separator-p (ch)
  (member ch '(#\Space #\Tab) :test #'char=))

(defun %split-style-tokens (spec)
  (let ((tokens '())
        (start nil))
    (dotimes (index (length spec))
      (if (%style-token-separator-p (char spec index))
          (when start
            (push (subseq spec start index) tokens)
            (setf start nil))
          (unless start
            (setf start index))))
    (when start
      (push (subseq spec start) tokens))
    (nreverse tokens)))

(defun %hex-color-body (token)
  (let ((body (if (and (plusp (length token)) (char= #\# (char token 0)))
                  (subseq token 1)
                  token)))
    (and (member (length body) '(3 6))
         (every (lambda (ch) (digit-char-p ch 16)) body)
         body)))

(defun %hex-body-rgb (body)
  (flet ((byte-at (index)
           (parse-integer body :start index :end (+ index 2) :radix 16))
         (nibble-at (index)
           (* 17 (parse-integer body :start index :end (1+ index) :radix 16))))
    (if (= (length body) 6)
        (list :rgb (byte-at 0) (byte-at 2) (byte-at 4))
        (list :rgb (nibble-at 0) (nibble-at 1) (nibble-at 2)))))

(defun parse-style-color (token)
  "Parse one color TOKEN into NIL, (:RGB R G B), or (:NAMED INDEX); a second
value of T reports that TOKEN was a color at all."
  (let ((named (assoc token +style-named-colors+ :test #'string-equal))
        (hex (%hex-color-body token)))
    (cond
      ((member token '("normal" "default") :test #'string-equal)
       (values nil t))
      (named (values (list :named (cdr named)) t))
      (hex (values (%hex-body-rgb hex) t))
      (t (values nil nil)))))

(defun %style-background-token (token)
  (cond
    ((and (> (length token) 13) (string-equal "--background=" token :end2 13))
     (subseq token 13))
    ((and (> (length token) 3) (string-equal "-b=" token :end2 3))
     (subseq token 3))
    (t nil)))

(defun %style-spec-fail (spec reason)
  (error 'invalid-style-spec :spec spec :reason reason))

(defun parse-style-spec (spec)
  "Parse the style SPEC string into a TEXT-STYLE, signalling
INVALID-STYLE-SPEC for an unknown token or a repeated color."
  (unless (stringp spec)
    (%style-spec-fail spec "not a string"))
  (let ((foreground nil)
        (foreground-set-p nil)
        (background nil)
        (flags '()))
    (dolist (token (%split-style-tokens spec))
      (let ((flag (cdr (assoc token +style-flag-tokens+ :test #'string-equal)))
            (background-token (%style-background-token token)))
        (cond
          (flag (pushnew flag flags))
          (background-token
           (multiple-value-bind (color color-p) (parse-style-color background-token)
             (unless color-p
               (%style-spec-fail spec (format nil "unknown background color ~s"
                                              background-token)))
             (setf background color)))
          (t
           (multiple-value-bind (color color-p) (parse-style-color token)
             (unless color-p
               (%style-spec-fail spec (format nil "unknown token ~s" token)))
             (when foreground-set-p
               (%style-spec-fail spec "more than one foreground color"))
             (setf foreground color
                   foreground-set-p t))))))
    (%make-text-style :foreground foreground
                      :background background
                      :bold (and (member :bold flags) t)
                      :dim (and (member :dim flags) t)
                      :italic (and (member :italic flags) t)
                      :underline (and (member :underline flags) t)
                      :reverse (and (member :reverse flags) t))))

(defun valid-style-spec-p (spec)
  (handler-case (progn (parse-style-spec spec) t)
    (invalid-style-spec () nil)))

(defun %parse-theme-colors (colors)
  "Return detached copies of COLORS and of the parsed styles for each entry."
  (unless (hash-table-p colors)
    (error "theme colors must be a hash table: ~s" colors))
  (let ((specs (make-hash-table :test #'eq))
        (styles (make-hash-table :test #'eq)))
    (maphash (lambda (role spec)
               (setf (gethash role styles) (parse-style-spec spec)
                     (gethash role specs) spec))
             colors)
    (values specs styles)))

(nshell.util:define-value-struct
  theme
  ((name "default" :type string)
   (colors (make-hash-table :test #'eq) :type hash-table)
   (styles (make-hash-table :test #'eq) :type hash-table))
  :documentation
  "An immutable named mapping from highlight roles to style specs, with the
parsed TEXT-STYLE of every spec cached alongside."
  :constructor
  %allocate-theme
  :public-accessors
  nil)

(defun make-theme (&key (name "default") (colors (make-hash-table :test #'eq)))
  (unless (stringp name)
    (error "theme name must be a string: ~s" name))
  (multiple-value-bind (specs styles) (%parse-theme-colors colors)
    (%allocate-theme name specs styles)))

(defun make-theme-from-entries (name entries)
  "Build a theme named NAME from ENTRIES, an alist of (ROLE . SPEC)."
  (let ((colors (make-hash-table :test #'eq)))
    (dolist (entry entries)
      (setf (gethash (car entry) colors) (cdr entry)))
    (make-theme :name name :colors colors)))

(defun theme-name (theme)
  "Return THEME's display name."
  (%theme-name theme))

(defun theme-color (theme key)
  "Return THEME's style spec string for KEY, or NIL when KEY is not configured."
  (gethash key (%theme-colors theme)))

(defun theme-style (theme key)
  "Return the parsed TEXT-STYLE for KEY, or NIL when KEY is not configured."
  (gethash key (%theme-styles theme)))

(defun theme-roles (theme)
  "Return the configured roles of THEME sorted by name."
  (let ((roles '()))
    (maphash (lambda (role spec) (declare (ignore spec)) (push role roles))
             (%theme-colors theme))
    (sort roles #'string< :key #'symbol-name)))

(defun theme-entries (theme)
  "Return THEME as an alist of (ROLE . SPEC) sorted by role name."
  (mapcar (lambda (role) (cons role (theme-color theme role)))
          (theme-roles theme)))

(defun theme-set-color (theme key value)
  "Return a theme with VALUE configured for KEY, signalling INVALID-STYLE-SPEC
when VALUE does not parse."
  (let ((colors (make-hash-table :test #'eq)))
    (maphash (lambda (role spec) (setf (gethash role colors) spec))
             (%theme-colors theme))
    (setf (gethash key colors) value)
    (make-theme :name (%theme-name theme) :colors colors)))

(defun theme-rename (theme name)
  "Return THEME under a new NAME."
  (make-theme-from-entries name (theme-entries theme)))

(defun %palette-role-entries (palette)
  (mapcar (lambda (entry)
            (destructuring-bind (role slot &optional flags) entry
              (let ((color (if slot (getf palette slot) "normal")))
                (cons role
                      (if flags
                          (format nil "~a ~a" color flags)
                          color)))))
          +theme-role-palette-slots+))

(defun theme-preset-names ()
  "Return the preset theme names in definition order."
  (mapcar #'first +theme-presets+))

(defun find-theme-preset (name)
  "Return the preset theme called NAME (case-insensitively), or NIL."
  (let ((preset (assoc name +theme-presets+ :test #'string-equal)))
    (when preset
      (make-theme-from-entries (first preset)
                               (%palette-role-entries (rest preset))))))

(defun default-theme ()
  (find-theme-preset (first (theme-preset-names))))
