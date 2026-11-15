/*
 * Per-key libc call counter for scripts/perf/b3-measure.sh (macOS only).
 *
 * Loaded with DYLD_INSERT_LIBRARIES, it interposes the libc entry points that
 * touch file metadata, open or mutate files, or start processes, and counts
 * calls while counting is enabled. SBCL resolves foreign symbols through dyld,
 * so this also sees calls that SB-POSIX inlines into compiled Lisp code, which
 * no Lisp-level hook can intercept.
 *
 * t/perf/key-cost.lisp reads the counters through kc_enable, kc_count,
 * kc_category and kc_name.
 */
#include <dirent.h>
#include <fcntl.h>
#include <spawn.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <unistd.h>

enum { KC_STAT = 0, KC_FILE_IO = 1, KC_SPAWN = 2 };

enum {
  F_STAT, F_LSTAT, F_FSTAT, F_FSTATAT, F_ACCESS, F_FACCESSAT, F_REALPATH,
  F_READLINK, F_OPEN, F_OPENAT, F_CREAT, F_OPENDIR, F_RENAME, F_RENAMEAT,
  F_UNLINK, F_UNLINKAT, F_MKDIR, F_MKDIRAT, F_RMDIR, F_LINK, F_SYMLINK,
  F_FSYNC, F_FORK, F_POSIX_SPAWN, F_POSIX_SPAWNP, F_COUNT
};

static const char *const kc_names[F_COUNT] = {
  "stat", "lstat", "fstat", "fstatat", "access", "faccessat", "realpath",
  "readlink", "open", "openat", "creat", "opendir", "rename", "renameat",
  "unlink", "unlinkat", "mkdir", "mkdirat", "rmdir", "link", "symlink",
  "fsync", "fork", "posix_spawn", "posix_spawnp"
};

static const int kc_categories[F_COUNT] = {
  KC_STAT, KC_STAT, KC_STAT, KC_STAT, KC_STAT, KC_STAT, KC_STAT,
  KC_STAT, KC_FILE_IO, KC_FILE_IO, KC_FILE_IO, KC_FILE_IO, KC_FILE_IO,
  KC_FILE_IO, KC_FILE_IO, KC_FILE_IO, KC_FILE_IO, KC_FILE_IO, KC_FILE_IO,
  KC_FILE_IO, KC_FILE_IO, KC_FILE_IO, KC_SPAWN, KC_SPAWN, KC_SPAWN
};

/* Child processes must not inherit the injection: Apple's arm64e system
 * binaries refuse to start with an arm64 library inserted, so a spawned
 * /bin/sh or git would abort instead of running. */
__attribute__((constructor)) static void kc_drop_injection(void) {
  unsetenv("DYLD_INSERT_LIBRARIES");
}

static int kc_enabled;
static long kc_counts[F_COUNT];

#define KC_HIT(index)                                                      \
  do {                                                                     \
    if (__atomic_load_n(&kc_enabled, __ATOMIC_RELAXED))                    \
      __atomic_add_fetch(&kc_counts[index], 1, __ATOMIC_RELAXED);          \
  } while (0)

/* Enabling also clears the counters, so one call starts a measurement. */
void kc_enable(int enabled) {
  if (enabled)
    for (int i = 0; i < F_COUNT; i++)
      __atomic_store_n(&kc_counts[i], 0, __ATOMIC_RELAXED);
  __atomic_store_n(&kc_enabled, enabled, __ATOMIC_SEQ_CST);
}

int kc_function_count(void) { return F_COUNT; }
long kc_count(int index) { return (index >= 0 && index < F_COUNT) ? kc_counts[index] : -1; }
int kc_category(int index) { return (index >= 0 && index < F_COUNT) ? kc_categories[index] : -1; }
const char *kc_name(int index) { return (index >= 0 && index < F_COUNT) ? kc_names[index] : ""; }

static int kc_stat(const char *path, struct stat *buf) { KC_HIT(F_STAT); return stat(path, buf); }
static int kc_lstat(const char *path, struct stat *buf) { KC_HIT(F_LSTAT); return lstat(path, buf); }
static int kc_fstat(int fd, struct stat *buf) { KC_HIT(F_FSTAT); return fstat(fd, buf); }
static int kc_fstatat(int fd, const char *path, struct stat *buf, int flag) {
  KC_HIT(F_FSTATAT); return fstatat(fd, path, buf, flag);
}
static int kc_access(const char *path, int mode) { KC_HIT(F_ACCESS); return access(path, mode); }
static int kc_faccessat(int fd, const char *path, int mode, int flag) {
  KC_HIT(F_FACCESSAT); return faccessat(fd, path, mode, flag);
}
static char *kc_realpath(const char *path, char *resolved) {
  KC_HIT(F_REALPATH); return realpath(path, resolved);
}
static ssize_t kc_readlink(const char *path, char *buf, size_t size) {
  KC_HIT(F_READLINK); return readlink(path, buf, size);
}
static int kc_open(const char *path, int flags, ...) {
  int mode = 0;
  if (flags & O_CREAT) {
    va_list arguments;
    va_start(arguments, flags);
    mode = va_arg(arguments, int);
    va_end(arguments);
  }
  KC_HIT(F_OPEN);
  return open(path, flags, mode);
}
static int kc_openat(int fd, const char *path, int flags, ...) {
  int mode = 0;
  if (flags & O_CREAT) {
    va_list arguments;
    va_start(arguments, flags);
    mode = va_arg(arguments, int);
    va_end(arguments);
  }
  KC_HIT(F_OPENAT);
  return openat(fd, path, flags, mode);
}
static int kc_creat(const char *path, mode_t mode) { KC_HIT(F_CREAT); return creat(path, mode); }
static DIR *kc_opendir(const char *path) { KC_HIT(F_OPENDIR); return opendir(path); }
static int kc_rename(const char *from, const char *to) { KC_HIT(F_RENAME); return rename(from, to); }
static int kc_renameat(int from_fd, const char *from, int to_fd, const char *to) {
  KC_HIT(F_RENAMEAT); return renameat(from_fd, from, to_fd, to);
}
static int kc_unlink(const char *path) { KC_HIT(F_UNLINK); return unlink(path); }
static int kc_unlinkat(int fd, const char *path, int flag) {
  KC_HIT(F_UNLINKAT); return unlinkat(fd, path, flag);
}
static int kc_mkdir(const char *path, mode_t mode) { KC_HIT(F_MKDIR); return mkdir(path, mode); }
static int kc_mkdirat(int fd, const char *path, mode_t mode) {
  KC_HIT(F_MKDIRAT); return mkdirat(fd, path, mode);
}
static int kc_rmdir(const char *path) { KC_HIT(F_RMDIR); return rmdir(path); }
static int kc_link(const char *from, const char *to) { KC_HIT(F_LINK); return link(from, to); }
static int kc_symlink(const char *from, const char *to) { KC_HIT(F_SYMLINK); return symlink(from, to); }
static int kc_fsync(int fd) { KC_HIT(F_FSYNC); return fsync(fd); }
static pid_t kc_fork(void) { KC_HIT(F_FORK); return fork(); }
static int kc_posix_spawn(pid_t *pid, const char *path,
                          const posix_spawn_file_actions_t *actions,
                          const posix_spawnattr_t *attributes,
                          char *const argv[], char *const envp[]) {
  KC_HIT(F_POSIX_SPAWN); return posix_spawn(pid, path, actions, attributes, argv, envp);
}
static int kc_posix_spawnp(pid_t *pid, const char *file,
                           const posix_spawn_file_actions_t *actions,
                           const posix_spawnattr_t *attributes,
                           char *const argv[], char *const envp[]) {
  KC_HIT(F_POSIX_SPAWNP); return posix_spawnp(pid, file, actions, attributes, argv, envp);
}

#define KC_INTERPOSE(replacement, original) \
  { (const void *)(unsigned long)&replacement, (const void *)(unsigned long)&original }

__attribute__((used)) static const struct {
  const void *replacement;
  const void *original;
} kc_interposers[] __attribute__((section("__DATA,__interpose"))) = {
  KC_INTERPOSE(kc_stat, stat),
  KC_INTERPOSE(kc_lstat, lstat),
  KC_INTERPOSE(kc_fstat, fstat),
  KC_INTERPOSE(kc_fstatat, fstatat),
  KC_INTERPOSE(kc_access, access),
  KC_INTERPOSE(kc_faccessat, faccessat),
  KC_INTERPOSE(kc_realpath, realpath),
  KC_INTERPOSE(kc_readlink, readlink),
  KC_INTERPOSE(kc_open, open),
  KC_INTERPOSE(kc_openat, openat),
  KC_INTERPOSE(kc_creat, creat),
  KC_INTERPOSE(kc_opendir, opendir),
  KC_INTERPOSE(kc_rename, rename),
  KC_INTERPOSE(kc_renameat, renameat),
  KC_INTERPOSE(kc_unlink, unlink),
  KC_INTERPOSE(kc_unlinkat, unlinkat),
  KC_INTERPOSE(kc_mkdir, mkdir),
  KC_INTERPOSE(kc_mkdirat, mkdirat),
  KC_INTERPOSE(kc_rmdir, rmdir),
  KC_INTERPOSE(kc_link, link),
  KC_INTERPOSE(kc_symlink, symlink),
  KC_INTERPOSE(kc_fsync, fsync),
  KC_INTERPOSE(kc_fork, fork),
  KC_INTERPOSE(kc_posix_spawn, posix_spawn),
  KC_INTERPOSE(kc_posix_spawnp, posix_spawnp),
};
