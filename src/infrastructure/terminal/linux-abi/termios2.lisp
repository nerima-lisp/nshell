("asm/termbits.h" "asm/ioctls.h")

((:integer-no-check +kernel-tcgets2+ "(unsigned long) TCGETS2")
 (:integer-no-check +kernel-tcsets2+ "(unsigned long) TCSETS2")
 (:type kernel-cc-t "cc_t")
 (:type kernel-speed-t "speed_t")
 (:type kernel-flag-t "tcflag_t")
 (:structure kernel-termios2
  ("struct termios2"
   (kernel-flag-t input-flags "tcflag_t" "c_iflag")
   (kernel-flag-t output-flags "tcflag_t" "c_oflag")
   (kernel-flag-t control-flags "tcflag_t" "c_cflag")
   (kernel-flag-t local-flags "tcflag_t" "c_lflag")
   (kernel-cc-t discipline "cc_t" "c_line")
   ((array kernel-cc-t) control-chars "cc_t" "c_cc")
   (kernel-speed-t input-speed "speed_t" "c_ispeed")
   (kernel-speed-t output-speed "speed_t" "c_ospeed"))))
