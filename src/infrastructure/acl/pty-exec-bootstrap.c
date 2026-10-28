#define _DARWIN_C_SOURCE 1

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdlib.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <unistd.h>

#ifndef __APPLE__
#error "The PTY exec bootstrap is Darwin-specific"
#endif

#ifndef TIOCSCTTY
#error "TIOCSCTTY is required to establish the PTY controlling terminal"
#endif

_Static_assert(sizeof(int) == 4, "PTY bootstrap error protocol requires 32-bit int");

extern char **environ;

static void report_failure(int error_fd, int error_number)
{
    const unsigned char *bytes = (const unsigned char *)&error_number;
    size_t offset = 0;

    while (offset < sizeof(error_number)) {
        ssize_t count = write(error_fd, bytes + offset, sizeof(error_number) - offset);
        if (count < 0) {
            if (errno == EINTR) {
                continue;
            }
            break;
        }
        if (count == 0) {
            break;
        }
        offset += (size_t)count;
    }
    _exit(127);
}

static int parse_error_fd(const char *value)
{
    char *end = NULL;
    long parsed;

    errno = 0;
    parsed = strtol(value, &end, 10);
    if (errno != 0 || end == value || *end != '\0' || parsed < 3 || parsed > INT_MAX) {
        return -1;
    }
    return (int)parsed;
}

int main(int argc, char **argv)
{
    int error_fd = argc > 2 ? parse_error_fd(argv[2]) : -1;
    int descriptor_flags;
    int slave_fd;
    int target_fd;

    if (error_fd < 0) {
        return 127;
    }
    descriptor_flags = fcntl(error_fd, F_GETFD);
    if (descriptor_flags < 0 ||
        fcntl(error_fd, F_SETFD, descriptor_flags | FD_CLOEXEC) < 0) {
        report_failure(error_fd, errno);
    }
    if (argc < 4 || argv[1][0] == '\0' || argv[3][0] == '\0') {
        report_failure(error_fd, EINVAL);
    }
    if (setsid() < 0) {
        report_failure(error_fd, errno);
    }
    /* Open after setsid so the slave can become this session's controlling terminal. */
    slave_fd = open(argv[1], O_RDWR);
    if (slave_fd < 0) {
        report_failure(error_fd, errno);
    }
    (void)ioctl(slave_fd, TIOCSCTTY, 0);
    if (tcsetpgrp(slave_fd, getpid()) < 0) {
        report_failure(error_fd, errno);
    }
    for (target_fd = STDIN_FILENO; target_fd <= STDERR_FILENO; target_fd++) {
        if (slave_fd != target_fd && dup2(slave_fd, target_fd) < 0) {
            report_failure(error_fd, errno);
        }
    }
    if (slave_fd > STDERR_FILENO && close(slave_fd) < 0) {
        report_failure(error_fd, errno);
    }
    execve(argv[3], &argv[3], environ);
    report_failure(error_fd, errno);
}
