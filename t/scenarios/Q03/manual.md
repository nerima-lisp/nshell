# Q03: Continue after heap exhaustion

## Procedure

1. Use a disposable Linux VM with a 2 GiB memory limit and a fresh home directory. Do not run this probe on a host session that contains valuable work.
2. From the candidate source tree, start nshell with `nix develop -c sbcl --dynamic-space-size 512 --eval '(asdf:load-system "nshell")' --eval '(nshell:main)'`. The option must be on the SBCL command line before the system is loaded, not passed as an nshell argument.
3. At the interactive S-expression prompt, enter `(echo ,(make-array 1073741824 :element-type '(unsigned-byte 8)))`. The `,(...)` form evaluates a native Lisp expression; this allocation is 1 GiB, above the 512 MiB dynamic-space limit and below the VM limit.
4. After the allocation error, enter `echo Q03_CONTINUED` at the prompt.
5. Capture the terminal output and process exit status. Record the image revision and the VM and SBCL memory limits.

## Pass condition

The allocation failure is reported as one concise error without a debugger or structure dump. The shell remains alive and prints `Q03_CONTINUED`.
