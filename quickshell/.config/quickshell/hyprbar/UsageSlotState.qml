pragma Singleton

import QtQuick 6.0
import Quickshell

// Shared toggle state keeps both monitor bars on the same view.
Singleton {
    id: root

    property bool showingAiUsage: true

    function toggle() {
        root.showingAiUsage = !root.showingAiUsage
    }
}
