# Security Policy

## Supported versions

nshell is in early development (0.x). Security fixes are prioritized for the
latest released version and `main`. If a vulnerability only affects an older
release, include that version in the report so the maintainers can decide
whether a backport is appropriate.

## Reporting a vulnerability

Please **do not** open a public issue for security vulnerabilities.

Instead, report privately using GitHub's
[private vulnerability reporting](https://github.com/nerima-lisp/nshell/security/advisories/new)
("Report a vulnerability" under the repository's *Security* tab).

Please include:

- A description of the vulnerability and practical impact.
- Steps to reproduce, ideally with a minimal proof of concept.
- The nshell version (`nshell --version`) or commit SHA.
- OS, architecture, terminal emulator, and relevant shell environment details.
- Whether the issue involves parsing, expansion, completion, history, job
  control, process execution, terminal handling, or filesystem access.
- Any mitigations you have already identified.

Do not include private keys, access tokens, credentials, or command history that
contains secrets. Redact environment values unless they are required to
reproduce the issue.

## Security scope

Examples of in-scope issues include:

- Command injection or unintended command execution caused by parsing,
  expansion, completion, or source-file handling.
- Secret disclosure through history, diagnostics, completion candidates, or
  crash output.
- Unsafe filesystem access caused by redirection, path handling, or builtin
  behavior.
- Terminal escape handling that can mislead the user or corrupt visible output.
- Process, signal, or job-control behavior that breaks expected user isolation.

Examples that are usually out of scope:

- Vulnerabilities in the host operating system, terminal emulator, SBCL, or
  third-party tools unless nshell makes them directly exploitable.
- Denial-of-service cases that require intentionally unbounded local resource
  consumption without crossing a security boundary.
- Social engineering, phishing, or reports without a plausible nshell impact.

## Response process

We aim to acknowledge reports within a few days, assess severity, develop a fix,
and coordinate disclosure with the reporter. Public disclosure should wait until
a fix or mitigation is available, unless there is active exploitation or another
compelling reason to warn users sooner.
