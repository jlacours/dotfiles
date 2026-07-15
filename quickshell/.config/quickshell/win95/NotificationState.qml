pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Notifications as Notify

Singleton {
  id: root

  property var notificationMap: ({})
  readonly property alias popupQueue: popupQueueModel

  function indexForId(notificationId): int {
    for (let i = 0; i < popupQueueModel.count; i++) {
      if (popupQueueModel.get(i).notificationId === notificationId)
        return i;
    }
    return -1;
  }

  function expiresAt(notification): double {
    if (!notification)
      return 0;

    const requested = Number(notification.expireTimeout);
    if (notification.urgency === Notify.NotificationUrgency.Critical || requested === 0)
      return 0;
    if (requested > 0)
      return Date.now() + requested;
    if (notification.urgency === Notify.NotificationUrgency.Low)
      return Date.now() + 4000;
    return Date.now() + 6000;
  }

  function notificationById(notificationId) {
    return notificationMap[notificationId] || null;
  }

  function forget(notificationId, dismissNotification): void {
    const popupIndex = indexForId(notificationId);
    if (popupIndex !== -1)
      popupQueueModel.remove(popupIndex);

    const notification = notificationMap[notificationId] || null;
    const next = Object.assign({}, notificationMap);
    delete next[notificationId];
    notificationMap = next;

    if (dismissNotification && notification)
      notification.dismiss();
  }

  function dismiss(notificationId): void {
    forget(notificationId, true);
  }

  function expire(notificationId): void {
    const notification = notificationMap[notificationId] || null;
    forget(notificationId, false);
    if (notification)
      notification.expire();
  }

  function registerNotification(notification): void {
    if (!notification)
      return;

    if (notificationMap[notification.id])
      forget(notification.id, true);

    notification.tracked = true;

    const next = Object.assign({}, notificationMap);
    next[notification.id] = notification;
    notificationMap = next;

    popupQueueModel.insert(0, {
      notificationId: notification.id,
      expiresAt: expiresAt(notification)
    });

    while (popupQueueModel.count > 4) {
      const oldest = popupQueueModel.get(popupQueueModel.count - 1).notificationId;
      forget(oldest, true);
    }

    const notificationId = notification.id;
    notification.closed.connect(function() {
      root.forget(notificationId, false);
    });
  }

  Notify.NotificationServer {
    keepOnReload: true
    bodySupported: true
    bodyMarkupSupported: false
    bodyImagesSupported: false
    bodyHyperlinksSupported: false
    actionsSupported: false
    actionIconsSupported: false
    imageSupported: true
    persistenceSupported: false
    inlineReplySupported: false

    onNotification: notification => root.registerNotification(notification)
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
      const now = Date.now();
      for (let i = popupQueueModel.count - 1; i >= 0; i--) {
        const popup = popupQueueModel.get(i);
        if (popup.expiresAt > 0 && popup.expiresAt <= now)
          root.expire(popup.notificationId);
      }
    }
  }
}
