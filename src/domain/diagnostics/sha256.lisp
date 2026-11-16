;;; SHA-256 (FIPS 180-4) for `nshell bug-report` (task P0-6). No dependency of
;;; nshell provides it, and the report only hashes small configuration files.
(in-package #:nshell.domain.bug-report)

(defparameter +sha256-round-constants+
  (coerce
   '(#x428a2f98 #x71374491 #xb5c0fbcf #xe9b5dba5 #x3956c25b #x59f111f1
     #x923f82a4 #xab1c5ed5 #xd807aa98 #x12835b01 #x243185be #x550c7dc3
     #x72be5d74 #x80deb1fe #x9bdc06a7 #xc19bf174 #xe49b69c1 #xefbe4786
     #x0fc19dc6 #x240ca1cc #x2de92c6f #x4a7484aa #x5cb0a9dc #x76f988da
     #x983e5152 #xa831c66d #xb00327c8 #xbf597fc7 #xc6e00bf3 #xd5a79147
     #x06ca6351 #x14292967 #x27b70a85 #x2e1b2138 #x4d2c6dfc #x53380d13
     #x650a7354 #x766a0abb #x81c2c92e #x92722c85 #xa2bfe8a1 #xa81a664b
     #xc24b8b70 #xc76c51a3 #xd192e819 #xd6990624 #xf40e3585 #x106aa070
     #x19a4c116 #x1e376c08 #x2748774c #x34b0bcb5 #x391c0cb3 #x4ed8aa4a
     #x5b9cca4f #x682e6ff3 #x748f82ee #x78a5636f #x84c87814 #x8cc70208
     #x90befffa #xa4506ceb #xbef9a3f7 #xc67178f2)
   '(simple-array (unsigned-byte 32) (64))))

(defparameter +sha256-initial-state+
  '(#x6a09e667 #xbb67ae85 #x3c6ef372 #xa54ff53a
    #x510e527f #x9b05688c #x1f83d9ab #x5be0cd19))

(declaim (inline %u32+ %rotr))
(defun %u32+ (&rest values)
  (logand #xffffffff (reduce #'+ values)))

(defun %rotr (value count)
  (logand #xffffffff
          (logior (ash value (- count)) (ash value (- 32 count)))))

(defun %sha256-padded (octets)
  "Return OCTETS followed by the SHA-256 padding: #x80, zeros up to 56 modulo
64, and the message length in bits as a 64-bit big-endian integer."
  (let* ((length (length octets))
         (padded-length (* 64 (ceiling (+ length 9) 64)))
         (padded (make-array padded-length
                             :element-type '(unsigned-byte 8)
                             :initial-element 0))
         (bit-length (* 8 length)))
    (replace padded octets)
    (setf (aref padded length) #x80)
    (loop for index from 0 below 8
          do (setf (aref padded (- padded-length 1 index))
                   (ldb (byte 8 (* 8 index)) bit-length)))
    padded))

(defun %sha256-compress (state block start)
  "Process the 64-octet block of BLOCK at START and update STATE, a vector of
eight 32-bit words."
  (let ((schedule (make-array 64 :element-type '(unsigned-byte 32))))
    (loop for index from 0 below 16
          for offset = (+ start (* 4 index))
          do (setf (aref schedule index)
                   (logior (ash (aref block offset) 24)
                           (ash (aref block (+ offset 1)) 16)
                           (ash (aref block (+ offset 2)) 8)
                           (aref block (+ offset 3)))))
    (loop for index from 16 below 64
          for w15 = (aref schedule (- index 15))
          for w2 = (aref schedule (- index 2))
          do (setf (aref schedule index)
                   (%u32+ (aref schedule (- index 16))
                          (logxor (%rotr w15 7) (%rotr w15 18) (ash w15 -3))
                          (aref schedule (- index 7))
                          (logxor (%rotr w2 17) (%rotr w2 19) (ash w2 -10)))))
    (let ((a (aref state 0)) (b (aref state 1)) (c (aref state 2))
          (d (aref state 3)) (e (aref state 4)) (f (aref state 5))
          (g (aref state 6)) (h (aref state 7)))
      (loop for index from 0 below 64
            do (let* ((t1 (%u32+ h
                                 (logxor (%rotr e 6) (%rotr e 11) (%rotr e 25))
                                 (logxor (logand e f)
                                         (logand (logxor e #xffffffff) g))
                                 (aref +sha256-round-constants+ index)
                                 (aref schedule index)))
                      (t2 (%u32+ (logxor (%rotr a 2) (%rotr a 13) (%rotr a 22))
                                 (logxor (logand a b) (logand a c)
                                         (logand b c)))))
                 (setf h g g f f e e (%u32+ d t1)
                       d c c b b a a (%u32+ t1 t2))))
      (loop for value in (list a b c d e f g h)
            for index from 0
            do (setf (aref state index) (%u32+ (aref state index) value))))))

(defun sha256-hex (octets)
  "Return the SHA-256 digest of OCTETS, a vector of (unsigned-byte 8), as 64
lowercase hexadecimal digits."
  (let ((state (make-array 8 :element-type '(unsigned-byte 32)
                             :initial-contents +sha256-initial-state+))
        (padded (%sha256-padded octets)))
    (loop for start from 0 below (length padded) by 64
          do (%sha256-compress state padded start))
    (format nil "~(~{~8,'0x~}~)" (coerce state 'list))))
