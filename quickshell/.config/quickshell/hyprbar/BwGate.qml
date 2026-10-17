import QtQuick 6.0

// Pure desktop-probe classifier (component Q, final-review N5).
//
// Explicit exit-code contract for the hyprlock probe command
// (BitwardenState.qml lockCheck):
//   exit 0, normal exit  -> "locked"  hyprlock is running (screen locked)
//   exit 1, normal exit  -> "active"  no hyprlock; desktop is in use
//   anything else        -> "error"   the probe itself failed (exit 2/127,
//                                      CrashExit, killed, ...)
//
// "error" MUST be treated as "not permitted" by every caller (fail
// closed): the menu gate spawns only on "active", the lock tick clears
// the waiter on "locked" and on "error". A failed probe never grants
// permission. Deliberately Quickshell-free so it unit-tests under
// qmltestrunner (tst_BwGate.qml).
Item {
    id: root

    // exitStatus is passed as a boolean by the caller, which owns the
    // Process enum comparison (exitStatus === Process.NormalExit).
    function probeOutcome(exitCode, normalExit) {
        if (!normalExit)
            return "error"
        if (exitCode === 0)
            return "locked"
        if (exitCode === 1)
            return "active"
        return "error"
    }
}
