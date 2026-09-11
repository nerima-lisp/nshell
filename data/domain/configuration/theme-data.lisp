;;; Theme data tables: the style-spec vocabulary, the role -> palette-slot
;;; mapping shared by every preset, and the preset palettes themselves.
(in-package #:nshell.domain.configuration)

(defparameter +style-named-colors+
  '(("black" . 0) ("red" . 1) ("green" . 2) ("yellow" . 3)
    ("blue" . 4) ("magenta" . 5) ("purple" . 5) ("cyan" . 6) ("white" . 7)
    ("brblack" . 8) ("grey" . 8) ("gray" . 8) ("brred" . 9) ("brgreen" . 10)
    ("bryellow" . 11) ("brblue" . 12) ("brmagenta" . 13) ("brpurple" . 13)
    ("brcyan" . 14) ("brwhite" . 15))
  "fish set_color names mapped to the 16-color terminal palette index.")

(defparameter +style-flag-tokens+
  '(("--bold" . :bold) ("-o" . :bold)
    ("--dim" . :dim) ("-d" . :dim)
    ("--italics" . :italic) ("--italic" . :italic) ("-i" . :italic)
    ("--underline" . :underline) ("-u" . :underline)
    ("--reverse" . :reverse) ("-r" . :reverse))
  "Style-spec flag tokens and the text-style attribute each one enables.")

(defparameter +theme-role-palette-slots+
  '((:normal nil)
    (:command :blue "--bold")
    (:builtin :blue "--bold")
    (:function :blue "--bold")
    (:keyword :magenta "--bold")
    (:option :cyan)
    (:argument nil)
    (:param nil)
    (:quote :yellow)
    (:variable :green)
    (:path nil "--underline")
    (:operator :orange)
    (:redirection :orange)
    (:comment :gray "--italics")
    (:error :red "--bold")
    (:autosuggestion :dim)
    (:search-match :yellow "--bold")
    (:selection nil "--reverse")
    (:prompt-host :green)
    (:prompt-path :blue "--bold")
    (:prompt-git :magenta)
    (:prompt-git-dirty :yellow)
    (:prompt-ok :green "--bold")
    (:prompt-error :red "--bold")
    (:prompt-time :gray)
    (:prompt-duration :yellow)
    (:prompt-assistant :gray)
    (:prompt-continuation :gray)
    (:completion-command :blue)
    (:completion-directory :blue "--bold")
    (:completion-file nil)
    (:completion-option :cyan)
    (:completion-variable :green)
    (:completion-description :gray)
    (:completion-selected nil "--reverse")
    (:completion-more :gray))
  "Each entry is (ROLE PALETTE-SLOT [FLAGS]); a NIL slot renders in the
terminal's default foreground so the flags alone carry the emphasis.")

(defparameter +theme-presets+
  '(("nshell"
     :blue "5fafff" :cyan "5fd7d7" :green "87d787" :yellow "d7af5f"
     :orange "ff875f" :red "ff5f5f" :magenta "d787ff" :gray "808080"
     :dim "6c6c6c")
    ("ansi"
     :blue "blue" :cyan "cyan" :green "green" :yellow "yellow"
     :orange "bryellow" :red "red" :magenta "magenta" :gray "brblack"
     :dim "brblack")
    ("mono"
     :blue "normal" :cyan "normal" :green "normal" :yellow "normal"
     :orange "normal" :red "normal" :magenta "normal" :gray "normal"
     :dim "normal --dim")
    ("dracula"
     :blue "bd93f9" :cyan "8be9fd" :green "50fa7b" :yellow "f1fa8c"
     :orange "ffb86c" :red "ff5555" :magenta "ff79c6" :gray "6272a4"
     :dim "6272a4")
    ("nord"
     :blue "81a1c1" :cyan "88c0d0" :green "a3be8c" :yellow "ebcb8b"
     :orange "d08770" :red "bf616a" :magenta "b48ead" :gray "616e88"
     :dim "4c566a")
    ("gruvbox"
     :blue "83a598" :cyan "8ec07c" :green "b8bb26" :yellow "fabd2f"
     :orange "fe8019" :red "fb4934" :magenta "d3869b" :gray "928374"
     :dim "7c6f64")
    ("solarized-dark"
     :blue "268bd2" :cyan "2aa198" :green "859900" :yellow "b58900"
     :orange "cb4b16" :red "dc322f" :magenta "d33682" :gray "586e75"
     :dim "586e75")
    ("solarized-light"
     :blue "268bd2" :cyan "2aa198" :green "859900" :yellow "b58900"
     :orange "cb4b16" :red "dc322f" :magenta "d33682" :gray "93a1a1"
     :dim "93a1a1")
    ("catppuccin-mocha"
     :blue "89b4fa" :cyan "94e2d5" :green "a6e3a1" :yellow "f9e2af"
     :orange "fab387" :red "f38ba8" :magenta "cba6f7" :gray "6c7086"
     :dim "585b70")
    ("tokyo-night"
     :blue "7aa2f7" :cyan "7dcfff" :green "9ece6a" :yellow "e0af68"
     :orange "ff9e64" :red "f7768e" :magenta "bb9af7" :gray "565f89"
     :dim "565f89"))
  "Preset name followed by a palette plist; the first entry is the default.")
