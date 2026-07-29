//@ pragma UseQApplication

import Quickshell
import QtQuick 6.0

ShellRoot {
    Variants {
        model: Quickshell.screens

        delegate: Component {
            Bar {
                required property var modelData
                screen: modelData
            }
        }
    }
}
