pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications as Notify

Singleton {
  id: root

  signal notified()

  property bool dnd: false
  property bool centerVisible: false
  property string centerScreenName: ""
  property var notificationMap: ({})
  readonly property alias history: historyModel
  readonly property alias popupQueue: popupQueueModel
  readonly property int unreadCount: historyModel.count
  property int criticalCount: 0
  readonly property int timeoutMs: 10000
  property int timeRevision: 0
  property int hoveredPopupId: -1
  property var popupPausedRemaining: ({})

  function nowMs() {
    return Date.now()
  }

  function notificationById(notificationId) {
    return notificationMap[notificationId] || null
  }

  function isCritical(notification) {
    return notification && notification.urgency === Notify.NotificationUrgency.Critical
  }

  function urgencyValue(notification) {
    if (!notification) return 1
    if (notification.urgency === Notify.NotificationUrgency.Low) return 0
    if (notification.urgency === Notify.NotificationUrgency.Critical) return 2
    return 1
  }

  function appKeyFor(notification) {
    if (!notification) return ""
    return notification.appName || notification.desktopEntry || notification.appIcon || ("id-" + notification.id)
  }

  // Absolute expiry timestamp, or 0 to never expire (critical / persistent).
  function popupExpiresAt(notification) {
    if (!notification || isCritical(notification)) return 0

    const timeout = Number(notification.expireTimeout || 0)
    if (timeout > 0) return nowMs() + timeout
    if (urgencyValue(notification) === 0) return nowMs() + 4000

    return nowMs() + timeoutMs
  }

  function setPopupHovered(notificationId, hovered) {
    if (hovered) {
      if (root.hoveredPopupId === notificationId) return
      root.hoveredPopupId = notificationId

      const idx = indexForId(popupQueueModel, notificationId)
      const expiresAt = idx !== -1 ? popupQueueModel.get(idx).expiresAt : 0
      const remaining = expiresAt > 0 ? Math.max(1500, expiresAt - root.nowMs()) : 4000

      const next = Object.assign({}, root.popupPausedRemaining)
      next[notificationId] = remaining
      root.popupPausedRemaining = next
    } else {
      if (root.hoveredPopupId === notificationId) root.hoveredPopupId = -1

      const remaining = root.popupPausedRemaining[notificationId]
      if (remaining !== undefined) {
        const idx = indexForId(popupQueueModel, notificationId)
        if (idx !== -1) popupQueueModel.setProperty(idx, "expiresAt", root.nowMs() + remaining)

        const next = Object.assign({}, root.popupPausedRemaining)
        delete next[notificationId]
        root.popupPausedRemaining = next
      }
    }
  }

  function indexForId(model, notificationId) {
    for (let i = 0; i < model.count; i++) {
      if (model.get(i).notificationId === notificationId) return i
    }
    return -1
  }

  function recalcCriticalCount() {
    let next = 0
    for (let i = 0; i < historyModel.count; i++) {
      if (isCritical(notificationById(historyModel.get(i).notificationId))) next += 1
    }
    criticalCount = next
  }

  function removePopupById(notificationId) {
    const index = indexForId(popupQueueModel, notificationId)
    if (index !== -1) popupQueueModel.remove(index)
  }

  function removeById(notificationId) {
    const historyIndex = indexForId(historyModel, notificationId)
    if (historyIndex !== -1) historyModel.remove(historyIndex)
    removePopupById(notificationId)

    const next = Object.assign({}, notificationMap)
    delete next[notificationId]
    notificationMap = next

    recalcCriticalCount()
  }

  function enqueuePopup(notification, timestamp) {
    if (dnd || !notification) return

    const appKey = root.appKeyFor(notification)
    const expiresAt = root.popupExpiresAt(notification)

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
        stackTotal: nextCount,
        expiresAt: expiresAt
      })
    } else {
      popupQueueModel.insert(0, {
        notificationId: notification.id,
        timestamp: timestamp,
        appKey: appKey,
        stackTotal: 1,
        expiresAt: expiresAt
      })

      while (popupQueueModel.count > 4) {
        popupQueueModel.remove(popupQueueModel.count - 1)
      }
    }

    root.notified()
  }

  function registerNotification(notification) {
    if (!notification) return

    notification.tracked = true
    removeById(notification.id)

    const next = Object.assign({}, notificationMap)
    next[notification.id] = notification
    notificationMap = next

    const timestamp = Math.floor(nowMs() / 1000)
    historyModel.insert(0, {
      notificationId: notification.id,
      timestamp: timestamp
    })

    enqueuePopup(notification, timestamp)
    recalcCriticalCount()

    notification.closed.connect(function() {
      root.removeById(notification.id)
    })
  }

  function dismissOne(notification) {
    if (!notification) return
    notification.dismiss()
    removeById(notification.id)
  }

  function clearAll() {
    const ids = []
    for (let i = 0; i < historyModel.count; i++) {
      ids.push(historyModel.get(i).notificationId)
    }

    for (let i = 0; i < ids.length; i++) {
      const notification = notificationById(ids[i])
      if (notification) notification.dismiss()
    }

    historyModel.clear()
    popupQueueModel.clear()
    notificationMap = ({})
    criticalCount = 0
  }

  function toggleDnd() {
    dnd = !dnd
    if (dnd) popupQueueModel.clear()
  }

  function toggleCenter(screenName) {
    const target = screenName || ""
    if (centerVisible && centerScreenName === target) {
      centerVisible = false
      centerScreenName = ""
      return
    }

    centerScreenName = target
    centerVisible = true
  }

  function invokeDefault(notification) {
    if (!notification || !notification.actions) return

    for (let i = 0; i < notification.actions.length; i++) {
      const action = notification.actions[i]
      if (action.identifier === "default") {
        action.invoke()
        return
      }
    }
  }

  IpcHandler {
    target: "notifications"

    function open(screen: string): void {
      root.centerScreenName = screen || ""
      root.centerVisible = true
    }

    function toggle(screen: string): void {
      root.toggleCenter(screen)
    }

    function hide(): void {
      root.centerVisible = false
      root.centerScreenName = ""
    }

    function setDnd(value: bool): void {
      root.dnd = value
      if (value) popupQueueModel.clear()
    }
  }

  Notify.NotificationServer {
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

    onNotification: function(notification) {
      root.registerNotification(notification)
    }
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
    interval: 500
    running: popupQueueModel.count > 0
    repeat: true
    onTriggered: {
      const current = root.nowMs()
      for (let i = popupQueueModel.count - 1; i >= 0; i--) {
        const entry = popupQueueModel.get(i)
        if (entry.expiresAt > 0 && entry.expiresAt <= current && entry.notificationId !== root.hoveredPopupId) {
          root.removePopupById(entry.notificationId)
        }
      }
    }
  }

  Timer {
    interval: 30000
    running: true
    repeat: true
    onTriggered: root.timeRevision += 1
  }
}
