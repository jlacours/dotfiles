import QtQuick 6.0

// Pure decision logic for the unlock-card waiter (component Q, R10).
//
// The waiter follows ONE specific bw-unlock-card process spawned by
// BitwardenState.qml. It never opens the vault menu on its own polling:
// the menu is emitted only when that process exited 0 AND a fresh status
// read then reports the vault unlocked — i.e. the card itself completed
// the unlock. T's card exit contract (final review): 0 success, 1 runtime
// failure, 2 setup/usage failure, 3 dismissal/cancel/desktop-gate denial,
// 4 duplicate instance. Only 0 may continue; every non-zero disarms. The
// exit is still paired with a post-exit status read so a stale or lying
// exit code can never open the menu on its own (defense in depth).
// status errors and probe errors clear the waiter (N5): an armed flow
// must not survive the very machinery that would confirm it failing.
//
// Deliberately free of Quickshell imports so the state machine can be unit
// tested with qmltestrunner (tst_BwUnlockWaiter.qml).
Item {
    id: root

    // 2 s ticks, 150 cap => ~5 minute bound on the whole wait (plan v2).
    readonly property int maxTicks: 150

    // The spawned unlock card is still running.
    property bool armed: false
    // The card exited 0; awaiting exactly one fresh status read.
    property bool confirming: false
    property int ticks: 0
    // An unrelated unlock was observed while our card was still open.
    // Such a waiter must never open the menu for someone else's unlock.
    property bool sawUnlockedWhileArmed: false

    readonly property bool active: root.armed || root.confirming

    signal requestMenu()

    function reset() {
        root.armed = false
        root.confirming = false
        root.ticks = 0
        root.sawUnlockedWhileArmed = false
    }

    function arm() {
        if (root.active)
            return
        root.reset()
        root.armed = true
    }

    // The spawned card process ended. Only code 0 (success) may continue;
    // codes 1/2 (failures), 3 (dismissed, cancelled or desktop-gate
    // denial) and 4 (another unlock card instance is already running) all
    // disarm without a menu — as does an unlock that already happened
    // through another path while our card was open.
    function cardExited(code) {
        if (!root.armed)
            return
        root.armed = false
        if (code !== 0 || root.sawUnlockedWhileArmed)
            return
        root.confirming = true
    }

    function cardFailedToStart() {
        root.reset()
    }

    // Desktop locked (hyprlock observed): drop the whole pending flow.
    function desktopLocked() {
        root.reset()
    }

    // The desktop-lock probe itself failed (N5): we can no longer verify
    // the desktop is in use, so the pending flow is dropped, fail closed.
    function probeError() {
        root.reset()
    }

    // Explicit lock requested from the chip: same.
    function explicitLock() {
        root.reset()
    }

    // Returns true while the caller should keep fast-polling. Enforces the
    // 5 minute bound regardless of sub-state.
    function tick() {
        if (!root.active)
            return false
        root.ticks++
        if (root.ticks >= root.maxTicks)
            root.reset()
        return root.active
    }

    // Feed every status observation here (the singleton calls this after
    // each poll).
    function statusObserved(state) {
        if (root.confirming) {
            if (state === "unlocked") {
                root.confirming = false
                root.ticks = 0
                root.requestMenu()
            } else {
                // Card closed 0 but the vault is not unlocked: it was
                // cancelled (or the unlock failed). Disarm, no menu.
                root.reset()
            }
        } else if (root.armed) {
            if (state === "unlocked") {
                // Unlocked while OUR card is still open: another path did it.
                // Poison the waiter so it can never claim this unlock.
                root.sawUnlockedWhileArmed = true
            } else if (state === "error") {
                // The status machinery itself is failing (N5): an armed
                // flow must not outlive the observer that would confirm
                // it. Drop the flow, fail closed.
                root.reset()
            }
        }
    }
}
