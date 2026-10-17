pragma Singleton

import QtQuick 6.0
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications as Notifications

Singleton {
    id: root

    property bool dnd: false
    property int timeRevision: 0
    property int criticalCount: 0
    readonly property int unreadCount: historyModel.count

    readonly property alias history: historyModel
    readonly property alias popupQueue: popupQueueModel

    property var notificationMap: ({})
    property var popupExpiryMap: ({})
    property int hoveredPopupId: -1
    property var popupPausedRemaining: ({})

    signal centerToggled()

    function nowMs() {
        return Date.now()
    }

    function nowSeconds() {
        return Math.floor(Date.now() / 1000)
    }

    function urgencyValue(notification) {
        if (!notification)
            return 1
        switch (notification.urgency) {
        case Notifications.NotificationUrgency.Low:
            return 0
        case Notifications.NotificationUrgency.Critical:
            return 2
        default:
            return 1
        }
    }

    function isCritical(notification) {
        return urgencyValue(notification) === 2
    }

    function notificationById(notificationId) {
        return notificationMap[notificationId] || null
    }

    function popupExpiry(notification) {
        if (!notification || isCritical(notification))
            return 0

        const timeout = Number(notification.expireTimeout || 0)
        if (timeout > 0)
            return nowMs() + timeout

        if (urgencyValue(notification) === 0)
            return nowMs() + 3000

        return nowMs() + 5000
    }

    function setPopupHovered(notificationId, hovered) {
        if (hovered) {
            if (root.hoveredPopupId === notificationId)
                return
            root.hoveredPopupId = notificationId

            const expiryAt = root.popupExpiryMap[notificationId] || 0
            const remaining = expiryAt > 0 ? Math.max(1500, expiryAt - root.nowMs()) : 4000

            const next = Object.assign({}, root.popupPausedRemaining)
            next[notificationId] = remaining
            root.popupPausedRemaining = next
        } else {
            if (root.hoveredPopupId === notificationId)
                root.hoveredPopupId = -1

            const remaining = root.popupPausedRemaining[notificationId]
            if (remaining !== undefined) {
                const nextExpiry = Object.assign({}, root.popupExpiryMap)
                nextExpiry[notificationId] = root.nowMs() + remaining
                root.popupExpiryMap = nextExpiry

                const next = Object.assign({}, root.popupPausedRemaining)
                delete next[notificationId]
                root.popupPausedRemaining = next
            }
        }
    }

    function indexForId(model, notificationId) {
        for (let i = 0; i < model.count; i++) {
            if (model.get(i).notificationId === notificationId)
                return i
        }
        return -1
    }

    function recalcCriticalCount() {
        let count = 0
        for (let i = 0; i < historyModel.count; i++) {
            const notif = notificationById(historyModel.get(i).notificationId)
            if (isCritical(notif))
                count += 1
        }
        criticalCount = count
    }

    function appKeyFor(notification) {
        if (!notification)
            return ""
        return notification.appName || notification.desktopEntry || notification.appIcon || ("id-" + notification.id)
    }

    function enqueuePopup(notification, timestamp) {
        if (!notification)
            return
        if (dnd && !isCritical(notification))
            return

        const appKey = appKeyFor(notification)
        let existingIndex = -1
        for (let i = 0; i < popupQueueModel.count; i++) {
            if (popupQueueModel.get(i).appKey === appKey) {
                existingIndex = i
                break
            }
        }

        if (existingIndex !== -1) {
            const existing = popupQueueModel.get(existingIndex)
            const nextCount = (existing.stackTotal || 1) + 1
            popupQueueModel.remove(existingIndex)
            popupQueueModel.insert(0, {
                notificationId: notification.id,
                timestamp: timestamp,
                appKey: appKey,
                stackTotal: nextCount
            })
        } else {
            popupQueueModel.insert(0, {
                notificationId: notification.id,
                timestamp: timestamp,
                appKey: appKey,
                stackTotal: 1
            })

            while (popupQueueModel.count > 5) {
                const stale = popupQueueModel.get(popupQueueModel.count - 1)
                const nextExpiry = Object.assign({}, popupExpiryMap)
                delete nextExpiry[stale.notificationId]
                popupExpiryMap = nextExpiry
                popupQueueModel.remove(popupQueueModel.count - 1)
            }
        }

        const expiryAt = popupExpiry(notification)
        const nextExpiry = Object.assign({}, popupExpiryMap)
        nextExpiry[notification.id] = expiryAt
        popupExpiryMap = nextExpiry
    }

    function registerNotification(notification) {
        if (!notification)
            return

        notification.tracked = true

        // Check for synchronous replacement hint (e.g. volume or brightness)
        const syncTag = notification.hints
            ? (notification.hints["x-canonical-private-synchronous"] || notification.hints["synchronous"])
            : null

        let existingId = -1
        if (notificationMap[notification.id]) {
            existingId = notification.id
        } else if (syncTag) {
            for (const key in notificationMap) {
                const item = notificationMap[key]
                if (item && item.hints) {
                    const tag = item.hints["x-canonical-private-synchronous"] || item.hints["synchronous"]
                    if (tag && tag === syncTag) {
                        existingId = Number(key)
                        break
                    }
                }
            }
        }

        if (existingId !== -1 && existingId !== notification.id) {
            const oldNotif = notificationMap[existingId]
            removeById(existingId)
            if (oldNotif)
                oldNotif.dismiss()
        } else if (existingId === notification.id) {
            removeById(notification.id)
        }

        const nextMap = Object.assign({}, notificationMap)
        nextMap[notification.id] = notification
        notificationMap = nextMap

        const timestamp = nowSeconds()
        historyModel.insert(0, {
            notificationId: notification.id,
            timestamp: timestamp
        })

        while (historyModel.count > 50) {
            const oldest = historyModel.get(historyModel.count - 1)
            const oldestNotif = notificationMap[oldest.notificationId]
            if (oldestNotif && indexForId(popupQueueModel, oldest.notificationId) === -1) {
                oldestNotif.tracked = false
                delete nextMap[oldest.notificationId]
            }
            historyModel.remove(historyModel.count - 1)
        }

        enqueuePopup(notification, timestamp)
        recalcCriticalCount()

        notification.closed.connect(function() {
            root.removePopupById(notification.id)
        })
    }

    function removePopupById(notificationId) {
        const popupIndex = indexForId(popupQueueModel, notificationId)
        if (popupIndex !== -1)
            popupQueueModel.remove(popupIndex)

        const nextExpiry = Object.assign({}, popupExpiryMap)
        delete nextExpiry[notificationId]
        popupExpiryMap = nextExpiry

        if (root.hoveredPopupId === notificationId)
            root.hoveredPopupId = -1
    }

    function removeById(notificationId) {
        const historyIndex = indexForId(historyModel, notificationId)
        if (historyIndex !== -1)
            historyModel.remove(historyIndex)

        removePopupById(notificationId)

        const nextMap = Object.assign({}, notificationMap)
        delete nextMap[notificationId]
        notificationMap = nextMap

        recalcCriticalCount()
    }

    function dismissPopup(notificationId) {
        removePopupById(notificationId)
    }

    function dismissOne(notificationId) {
        const notification = notificationById(notificationId)
        removeById(notificationId)
        if (notification)
            notification.dismiss()
    }

    function dismissAllPopups() {
        popupQueueModel.clear()
        popupExpiryMap = ({})
        hoveredPopupId = -1
        popupPausedRemaining = ({})
    }

    function dismissAll() {
        dismissAllPopups()
    }

    function clearHistory() {
        const items = []
        for (let i = 0; i < historyModel.count; i++) {
            const item = notificationById(historyModel.get(i).notificationId)
            if (item)
                items.push(item)
        }
        historyModel.clear()
        dismissAllPopups()
        notificationMap = ({})
        criticalCount = 0
        for (let i = 0; i < items.length; i++)
            items[i].dismiss()
    }

    function toggleDnd() {
        dnd = !dnd
        if (dnd)
            dismissAllPopups()
    }

    function toggleCenter() {
        root.centerToggled()
    }

    function defaultAction(notification) {
        if (!notification || !notification.actions)
            return null
        for (let i = 0; i < notification.actions.length; i++) {
            const action = notification.actions[i]
            if (action.identifier === "default")
                return action
        }
        return null
    }

    function invokeDefault(notification) {
        const action = defaultAction(notification)
        if (action)
            action.invoke()
        if (notification)
            dismissPopup(notification.id)
    }

    function invokeAction(notification, action) {
        if (action)
            action.invoke()
        if (notification)
            dismissPopup(notification.id)
    }

    Notifications.NotificationServer {
        id: server

        keepOnReload: true
        bodySupported: true
        bodyMarkupSupported: true
        bodyImagesSupported: true
        bodyHyperlinksSupported: true
        actionsSupported: true
        actionIconsSupported: true
        imageSupported: true
        persistenceSupported: true
        inlineReplySupported: true

        onNotification: notification => root.registerNotification(notification)
    }

    ListModel {
        id: historyModel
        dynamicRoles: true
    }

    ListModel {
        id: popupQueueModel
        dynamicRoles: true
    }

    Timer {
        interval: 250
        running: popupQueueModel.count > 0
        repeat: true

        onTriggered: {
            const current = root.nowMs()
            const expired = []

            for (let i = 0; i < popupQueueModel.count; i++) {
                const entry = popupQueueModel.get(i)
                const expiryAt = root.popupExpiryMap[entry.notificationId] || 0
                if (expiryAt > 0 && expiryAt <= current && entry.notificationId !== root.hoveredPopupId) {
                    expired.push(entry.notificationId)
                }
            }

            for (let i = 0; i < expired.length; i++) {
                root.removePopupById(expired[i])
            }
        }
    }

    Timer {
        interval: 15000
        running: true
        repeat: true
        onTriggered: root.timeRevision += 1
    }

    IpcHandler {
        target: "notifs"

        function dismissAll() {
            root.dismissAll()
        }

        function dismissPopups() {
            root.dismissAllPopups()
        }

        function clearAll() {
            root.clearHistory()
        }

        function toggleDnd() {
            root.toggleDnd()
        }

        function toggleCenter() {
            root.toggleCenter()
        }

        function state() {
            return "popups: " + root.popupQueue.count + " · history: " + root.history.count
                + " · unread: " + root.unreadCount + " · dnd: " + (root.dnd ? "on" : "off")
        }
    }
}
