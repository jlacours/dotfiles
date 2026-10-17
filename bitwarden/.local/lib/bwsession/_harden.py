"""Process hardening for secret-handling entry points.

RLIMIT_CORE=0 is inherited across fork/exec, so it also covers the Node.js
`bw` children.  systemd-coredump honours the limit (%c in core_pattern), which
matters here because fs.suid_dumpable=2 would otherwise still dump processes
that cleared PR_SET_DUMPABLE.  PR_SET_DUMPABLE=0 additionally makes this
process's /proc entries root-owned, so same-user tools cannot read its environ
or attach ptrace while it runs; execve resets it for children.
"""

import ctypes
import resource
import sys

_PR_SET_DUMPABLE = 4
_done = False


def harden_process():
    global _done
    if _done:
        return
    try:
        resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    except (ValueError, OSError):
        pass
    try:
        libc = ctypes.CDLL(None, use_errno=True)
        libc.prctl(_PR_SET_DUMPABLE, 0, 0, 0, 0)
    except (OSError, AttributeError):
        pass
    # Never print frames or locals from secret-handling code.
    sys.tracebacklimit = 0
    _done = True
