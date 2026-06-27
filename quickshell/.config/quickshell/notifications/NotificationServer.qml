pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Notifications as Notifications

Singleton {
  id: root

  property bool dnd: false
  property bool centerVisible: false
  property string centerScreenName: ""
  property int unreadCount: historyModel.count
  property int criticalCount: 0
  property int timeRevision: 0

  readonly property alias history: historyModel
  readonly property alias popupQueue: popupQueueModel

  property var notificationMap: ({})
  property var popupExpiryMap: ({})
  property int hoveredPopupId: -1
  property var popupPausedRemaining: ({})

  function setPopupHovered(notificationId, hovered) {
    if (hovered) {
      if (root.hoveredPopupId === notificationId) return
      root.hoveredPopupId = notificationId

      const expiryAt = root.popupExpiryMap[notificationId] || 0
      const remaining = expiryAt > 0 ? Math.max(1500, expiryAt - root.nowMs()) : 4000

      const next = Object.assign({}, root.popupPausedRemaining)
      next[notificationId] = remaining
      root.popupPausedRemaining = next
    } else {
      if (root.hoveredPopupId === notificationId) root.hoveredPopupId = -1

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

  function nowMs() {
    return Date.now()
  }

  function nowSeconds() {
    return Math.floor(Date.now() / 1000)
  }

  function urgencyValue(notification) {
    if (!notification) return 1

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
    if (!notification || isCritical(notification)) return 0

    const timeout = Number(notification.expireTimeout || 0)
    if (timeout > 0) return nowMs() + timeout

    if (urgencyValue(notification) === 0) return nowMs() + 3000

    return nowMs() + 5000
  }

  function indexForId(model, notificationId) {
    for (let i = 0; i < model.count; i++) {
      const entry = model.get(i)
      if (entry.notificationId === notificationId) return i
    }

    return -1
  }

  function recalcCriticalCount() {
    let nextCount = 0

    for (let i = 0; i < historyModel.count; i++) {
      const notification = notificationById(historyModel.get(i).notificationId)
      if (isCritical(notification)) nextCount += 1
    }

    criticalCount = nextCount
  }

  function removeById(notificationId) {
    const historyIndex = indexForId(historyModel, notificationId)
    if (historyIndex !== -1) historyModel.remove(historyIndex)

    removePopupById(notificationId)

    const nextMap = Object.assign({}, notificationMap)
    delete nextMap[notificationId]
    notificationMap = nextMap

    recalcCriticalCount()
  }

  function removePopupById(notificationId) {
    const popupIndex = indexForId(popupQueueModel, notificationId)
    if (popupIndex !== -1) popupQueueModel.remove(popupIndex)

    const nextExpiry = Object.assign({}, popupExpiryMap)
    delete nextExpiry[notificationId]
    popupExpiryMap = nextExpiry
  }

  function appKeyFor(notification) {
    if (!notification) return ""
    return notification.appName || notification.desktopEntry || notification.appIcon || ("id-" + notification.id)
  }

  function enqueuePopup(notification, timestamp) {
    if (dnd || !notification) return

    const appKey = root.appKeyFor(notification)

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
    if (!notification) return

    removeById(notification.id)

    notification.tracked = true

    const nextMap = Object.assign({}, notificationMap)
    nextMap[notification.id] = notification
    notificationMap = nextMap

    const timestamp = nowSeconds()
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

  function dismissById(notificationId) {
    const notification = notificationById(notificationId)
    if (notification) dismissOne(notification)
  }

  function clearPopupQueue() {
    popupQueueModel.clear()
    popupExpiryMap = ({})
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
    clearPopupQueue()
    notificationMap = ({})
    criticalCount = 0
  }

  function toggleDnd() {
    dnd = !dnd
    if (dnd) clearPopupQueue()
  }

  function toggleCenter(screenName) {
    const targetScreen = screenName || ""

    if (centerVisible && centerScreenName === targetScreen) {
      centerVisible = false
      centerScreenName = ""
      return
    }

    centerScreenName = targetScreen
    centerVisible = true
  }

  function defaultAction(notification) {
    if (!notification || !notification.actions) return null

    for (let i = 0; i < notification.actions.length; i++) {
      const action = notification.actions[i]
      if (action.identifier === "default") return action
    }

    return null
  }

  function invokeDefault(notification) {
    const action = defaultAction(notification)
    if (action) action.invoke()
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
    interval: 250
    running: popupQueueModel.count > 0
    repeat: true

    onTriggered: {
      const currentTime = root.nowMs()
      const expiredIds = []

      for (let i = 0; i < popupQueueModel.count; i++) {
        const entry = popupQueueModel.get(i)
        const expiryAt = root.popupExpiryMap[entry.notificationId] || 0

        if (expiryAt > 0 && expiryAt <= currentTime && entry.notificationId !== root.hoveredPopupId) {
          expiredIds.push(entry.notificationId)
        }
      }

      for (let i = 0; i < expiredIds.length; i++) {
        root.removePopupById(expiredIds[i])
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
