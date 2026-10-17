pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick 6.0

// Bitwarden vault state for the bar chip (component Q). Polls the
// non-prompting `bw-session status --json` relay (bitwarden.sh) and owns
// the chip actions: open the vault menu, and open the unlock card first
// when the vault is locked, then open the menu once THAT card completes an
// unlock.
//
// R10 hardening: the unlock waiter observes the specific bw-unlock-card
// process it spawned (exit code via Process, not execDetached + polling).
// A cancelled or failing card, an explicit lock, a desktop lock, a status
// or probe error, or the 5 minute bound clears the waiter, and an
// unrelated unlock while our card is open never opens the menu. No vault
// data, item IDs, or secrets ever pass through this singleton.
//
// N5 hardening (final review): every menu spawn passes a desktop-lock
// probe with an EXPLICIT exit-code contract (BwGate.qml: 0 = hyprlock
// running, 1 = desktop active, anything else = probe error). Probe errors
// fail CLOSED: no menu, and an armed unlock flow is dropped. Explicit
// lock (right-click) always attempts `bw-session lock` regardless of the
// cached chip state — the authority revokes pending unlocks — and a
// failed lock attempt is reported in the tooltip.
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string bwMenu: home + "/.local/bin/bw-menu"
    readonly property string bwUnlockCard: home + "/.local/bin/bw-unlock-card"
    readonly property string bwLockScript: home + "/.config/quickshell/hyprbar/bitwarden.sh"

    // Desktop-lock probe: hyprlock process presence for this user,
    // mirroring W's hyprlock_running() (uid-scoped /proc/*/comm scan;
    // unreadable comm files belong to other users and are skipped).
    // EXPLICIT contract (classified by BwGate.probeOutcome): exit 0 =
    // hyprlock running, exit 1 = desktop active, any other exit or a
    // crash = probe error, which every consumer treats as "not
    // permitted" (fail closed).
    readonly property string lockCheck: "for f in /proc/[0-9]*/comm; do IFS= read -r c < \"$f\" 2>/dev/null || continue; [ \"$c\" = hyprlock ] && exit 0; done; exit 1"

    // Same states as the bw-session status contract.
    property string state: "error"
    property double deadline: 0
    property string tooltip: "Bitwarden — status unavailable"
    readonly property bool unlocked: root.state === "unlocked"
    readonly property bool locked: root.state === "locked"
    // True while an unlock card this singleton spawned is being observed.
    readonly property bool waitingForUnlock: waiter.active
    // Sticky since the last FAILED explicit lock attempt; cleared by the
    // next successful one. Surfaced in the tooltip (N5: report failure).
    property bool lockAttemptFailed: false

    BwGate {
        id: gate
    }

    BwUnlockWaiter {
        id: waiter
    }

    function lockNow() {
        // An explicit lock always abandons any pending unlock flow (R10)
        // and ALWAYS attempts the authority lock, regardless of the cached
        // chip state: during an unlock W deliberately reports `locked`, so
        // gating on `unlocked` would skip the revoke of a live unlock
        // (N5). bw-session lock also cancels pending unlocks in W.
        waiter.explicitLock()
        if (!lockProc.running)
            lockProc.start()
    }

    function openMenu() {
        if (root.unlocked) {
            root.requestMenu()
        } else if (root.locked && !waiter.active) {
            // Locked: spawn the unlock card ONCE and observe that process.
            waiter.arm()
            unlockCard.command = [root.bwUnlockCard]
            unlockCard.start()
        }
    }

    function classify(value) {
        const states = ["unlocked", "locked", "unauthenticated", "keyring-locked", "error"]
        return states.includes(value) ? value : "error"
    }

    function parseStatus(text) {
        try {
            const result = JSON.parse(text.trim())
            root.state = root.classify(String(result.state || "error"))
            const deadline = Number(result.deadline)
            root.deadline = deadline > 0 ? deadline : 0
            root.tooltip = String(result.tooltip || "Bitwarden")
        } catch (error) {
            root.state = "error"
            root.deadline = 0
            root.tooltip = "Bitwarden — status unavailable"
        }
        if (root.lockAttemptFailed)
            root.tooltip += " — last lock attempt failed"
        waiter.statusObserved(root.state)
    }

    function setStatusFailed() {
        root.state = "error"
        root.deadline = 0
        root.tooltip = "Bitwarden — status unavailable"
        waiter.statusObserved(root.state)
    }

    // Every menu spawn passes a desktop-lock gate first, so a pending
    // unlock cannot surface the menu after the screen locked (R10), and
    // a FAILED probe denies the menu entirely (N5: fail closed).
    function requestMenu() {
        if (!menuGateCheck.running)
            menuGateCheck.start()
    }

    function spawnMenu() {
        Quickshell.execDetached([root.bwMenu])
    }

    StatusScript {
        id: poller
        script: "bitwarden.sh"
        interval: 30000
        onStatusRead: text => root.parseStatus(text)
        onStatusFailed: root.setStatusFailed()
    }

    // The one unlock card this singleton spawned (replaced per attempt).
    // Output is discarded; only the exit code is observed.
    Process {
        id: unlockCard
        onExited: (exitCode, exitStatus) => {
            waiter.cardExited(exitCode)
            // Fresh read immediately: the confirmation decision pairs this
            // exit with the current vault state.
            poller.refresh()
        }
        // Quickshell's Process has no failed-to-start signal: a card that
        // stops running without ever emitting `started` failed to launch.
        property bool didStart: false
        onStarted: didStart = true
        onRunningChanged: {
            if (running)
                return
            if (!didStart)
                waiter.cardFailedToStart()
            didStart = false
        }
    }

    // Explicit-lock runner: always launched by lockNow(), never gated on
    // cached state. The relay (bitwarden.sh lock) bounds it at 30 s and
    // propagates W's exit code. Output is discarded; only the outcome.
    Process {
        id: lockProc
        command: [root.bwLockScript, "lock"]
        onExited: (exitCode, exitStatus) => {
            root.lockAttemptFailed = !(exitCode === 0 && exitStatus === Process.NormalExit)
            // Fresh status either way; parseStatus appends the failure
            // note to the tooltip while lockAttemptFailed is set.
            poller.refresh()
        }
        property bool didStart: false
        onStarted: didStart = true
        onRunningChanged: {
            if (running)
                return
            if (!didStart) {
                // Failed to launch at all: report it like a failed lock.
                root.lockAttemptFailed = true
                poller.refresh()
            }
            didStart = false
        }
    }

    // Desktop-lock probe on the 2 s cadence while a flow is pending.
    Process {
        id: lockTickCheck
        command: ["sh", "-c", root.lockCheck]
        onExited: (exitCode, exitStatus) => {
            const outcome = gate.probeOutcome(exitCode, exitStatus === Process.NormalExit)
            if (outcome === "locked")
                waiter.desktopLocked()
            else if (outcome === "error")
                // Probe failed while a flow is pending: fail closed (N5).
                waiter.probeError()
        }
    }

    // Desktop-lock probe immediately before the menu would spawn. Only an
    // explicit "active desktop" outcome (exit 1, normal exit) permits the
    // menu; a locked desktop, a probe error, a crash, or a probe that
    // never started denies it — fail closed, no menu (N5).
    Process {
        id: menuGateCheck
        command: ["sh", "-c", root.lockCheck]
        onExited: (exitCode, exitStatus) => {
            if (gate.probeOutcome(exitCode, exitStatus === Process.NormalExit) === "active")
                root.spawnMenu()
        }
    }

    // While an unlock flow is live, poll faster (2 s) so the menu opens
    // promptly after a successful unlock. BwUnlockWaiter keeps its own
    // 150-tick (~5 min) bound.
    Timer {
        running: waiter.active
        interval: 2000
        repeat: true
        onTriggered: {
            if (waiter.tick()) {
                poller.refresh()
                if (!lockTickCheck.running)
                    lockTickCheck.start()
            }
        }
    }

    Connections {
        target: waiter
        function onRequestMenu() {
            root.requestMenu()
        }
    }
}
