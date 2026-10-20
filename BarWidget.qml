import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "devnull.log"

  property bool opened: false
  property bool loading: false
  property bool pendingRefresh: false
  property bool cursorActive: false
  property int selectedIndex: 0
  property int fetchIndex: 0
  property var fetchUsers: []
  property var fetched: []
  property var commits: []
  property string errorText: ""
  property date refreshedAt: new Date(0)
  property bool authenticated: false
  property string accountUsername: ""
  property int unreadCount: 0
  property var notificationItems: []
  property bool loadingNotifications: false
  property bool notificationsLoaded: false
  property date notificationsUpdatedAt: new Date(0)
  property bool notificationsVisible: false
  property bool connecting: false
  property string authError: ""

  readonly property string helperPath: Quickshell.env("HOME") + "/.config/omarchy/plugins/devnull.log/devnull.py"

  readonly property var selectedUsers: Model.usernames(setting("usernames", "nunomaduro,brendt,paulinevos"))
  readonly property color foreground: Commons.Color.popups.text
  readonly property color muted: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.62)
  readonly property color accent: Commons.Color.accent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function open() {
    opened = true
    cursorActive = false
    pollMe()
    if (commits.length === 0 || Date.now() - refreshedAt.getTime() > 300000) refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() { opened = false }
  function toggle() { if (opened) close(); else open() }

  function refresh() {
    if (loading) { pendingRefresh = true; return }
    errorText = ""
    fetched = []
    fetchIndex = 0
    fetchUsers = selectedUsers
    if (fetchUsers.length === 0) {
      commits = []
      errorText = "Set at least one dev/null username in widget settings."
      return
    }
    loading = true
    fetchNext()
  }

  function fetchNext() {
    if (fetchIndex >= fetchUsers.length) {
      if (fetched.length > 0) commits = fetched
      else if (errorText === "") commits = []
      loading = false
      refreshedAt = new Date()
      selectedIndex = Math.min(selectedIndex, Math.max(0, commits.length - 1))
      if (pendingRefresh) { pendingRefresh = false; Qt.callLater(refresh) }
      return
    }
    var username = fetchUsers[fetchIndex]
    fetchProcess.command = ["curl", "--disable", "--proto", "=https", "--fail", "--silent", "--show-error", "--max-time", "8",
      "https://dev-null.sh/api/v1/users/" + encodeURIComponent(username) + "/commits"]
    fetchProcess.running = true
  }

  function openUrl(url) {
    if (!/^https:\/\/dev-null\.sh\//.test(url)) return
    Qt.openUrlExternally(url)
    close()
  }

  function selectedCommit() {
    return commits.length > 0 ? commits[Math.max(0, Math.min(selectedIndex, commits.length - 1))] : null
  }

  function scrollToSelection() {
    var item = commitRepeater.itemAt(selectedIndex)
    if (!item) return
    var point = item.mapToItem(feedFlick.contentItem, 0, 0)
    if (point.y < feedFlick.contentY) feedFlick.contentY = point.y
    else if (point.y + item.height > feedFlick.contentY + feedFlick.height)
      feedFlick.contentY = point.y + item.height - feedFlick.height
  }

  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function") return bar.switchPanelFrom(root, direction)
    return false
  }

  function closeForPopoutSwitch() { close() }

  function pollMe() {
    if (meProcess.running) return
    meProcess.command = ["python3", helperPath, "me"]
    meProcess.running = true
  }

  function refreshNotifications() {
    if (!authenticated || loadingNotifications) return
    loadingNotifications = true
    notificationsProcess.command = ["python3", helperPath, "notifications"]
    notificationsProcess.running = true
  }

  function connectAccount() {
    if (authProcess.running || connecting) return
    authError = ""
    authProcess.command = ["python3", helperPath, "auth-start"]
    authProcess.running = true
  }

  function toggleNotifications() {
    notificationsVisible = !notificationsVisible
    feedFlick.contentY = 0
    if (notificationsVisible && authenticated &&
        (!notificationsLoaded || unreadCount > 0 || Date.now() - notificationsUpdatedAt.getTime() > 300000))
      refreshNotifications()
  }

  onSelectedUsersChanged: if (opened) refresh()

  Timer {
    interval: 300000
    repeat: true
    running: root.opened
    onTriggered: root.refresh()
  }

  Timer {
    interval: 60000
    repeat: true
    running: true
    onTriggered: root.pollMe()
  }

  Timer {
    interval: 2000
    repeat: true
    running: root.connecting
    onTriggered: {
      if (!authStatusProcess.running) {
        authStatusProcess.command = ["python3", root.helperPath, "auth-status"]
        authStatusProcess.running = true
      }
    }
  }

  Component.onCompleted: pollMe()

  Process {
    id: meProcess
    command: []
    stdout: StdioCollector { id: meOutput; waitForEnd: true }
    onExited: function(exitCode) {
      try {
        var state = JSON.parse(String(meOutput.text || "{}"))
        var wasAuthenticated = root.authenticated
        root.authenticated = state.authenticated === true
        root.accountUsername = String(state.username || "")
        root.unreadCount = Math.max(0, Number(state.unread) || 0)
        if (!wasAuthenticated && root.authenticated) root.connecting = false
      } catch (e) { root.authError = "Could not check account status." }
    }
  }

  Process {
    id: notificationsProcess
    command: []
    stdout: StdioCollector { id: notificationsOutput; waitForEnd: true }
    onExited: function(exitCode) {
      root.loadingNotifications = false
      if (exitCode !== 0) {
        root.authError = "Could not load notifications."
        return
      }
      try {
        var response = JSON.parse(String(notificationsOutput.text || "{}"))
        if (!Array.isArray(response.notifications)) throw new Error("Invalid response")
        root.notificationItems = response.notifications
        root.notificationsLoaded = true
        root.notificationsUpdatedAt = new Date()
        root.authError = ""
        root.pollMe()
      } catch (e) { root.authError = "Could not read notifications." }
    }
  }

  Process {
    id: authProcess
    command: []
    stdout: StdioCollector { id: authOutput; waitForEnd: true }
    onExited: function(exitCode) {
      try {
        var result = JSON.parse(String(authOutput.text || "{}"))
        if (exitCode !== 0 || !/^https:\/\/dev-null\.sh\/mobile\/authorize\?/.test(result.url))
          throw new Error(String(result.error || "Could not start connection."))
        root.connecting = true
        Qt.openUrlExternally(result.url)
      } catch (e) { root.authError = String(e) }
    }
  }

  Process {
    id: authStatusProcess
    command: []
    stdout: StdioCollector { id: authStatusOutput; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) return
      try {
        var result = JSON.parse(String(authStatusOutput.text || "{}"))
        if (result.state === "connected") {
          root.connecting = false
          root.authError = ""
          root.pollMe()
        } else if (result.state === "error" || result.state === "idle") {
          root.connecting = false
          root.authError = String(result.message || "Connection stopped. Try again.")
        }
      } catch (e) { root.authError = "Could not check connection progress." }
    }
  }

  Process {
    id: fetchProcess
    command: []
    stdout: StdioCollector { id: fetchOutput; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        try { root.fetched = Model.merged(root.fetched, Model.parseCommits(String(fetchOutput.text || ""))) }
        catch (e) { root.errorText = "Some commits could not be read." }
      } else {
        root.errorText = "Some users could not be loaded. Check their names or your connection."
      }
      root.fetchIndex++
      Qt.callLater(root.fetchNext)
    }
  }

  IpcHandler {
    target: root.moduleName
    function open(): void { root.broadcast("open") }
    function close(): void { root.broadcast("close") }
    function toggle(): void { root.broadcast("toggle") }
    function refresh(): void { root.broadcast("refresh") }
    function status(): string {
      return JSON.stringify({ opened: root.opened, loading: root.loading,
        count: root.commits.length, error: root.errorText,
        authenticated: root.authenticated, username: root.accountUsername,
        unread: root.unreadCount, notifications: root.notificationItems.length,
        authError: root.authError, connecting: root.connecting,
        notificationsVisible: root.notificationsVisible })
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: (root.vertical ? "/d/n" : "/dev/null") + (root.unreadCount > 0 ? " " + root.unreadCount : "")
    fontSize: Style.font.bodySmall
    tooltipText: "dev/null log"
    active: root.opened
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.MiddleButton) root.refresh()
      else if (mouseButton === Qt.RightButton) root.openUrl("https://dev-null.sh/log/trending")
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: fittedContentWidth(Style.space(460))
    contentHeight: fittedContentHeight(content.implicitHeight, Style.space(600))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (dy === 0 || root.notificationsVisible || root.commits.length === 0) return
        root.cursorActive = true
        root.selectedIndex = Math.max(0, Math.min(root.commits.length - 1, root.selectedIndex + dy))
        Qt.callLater(root.scrollToSelection)
      }
      onActivateRequested: {
        if (root.notificationsVisible) return
        var commit = root.selectedCommit()
        if (commit) root.openUrl(commit.url)
      }
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(key) {
        if (key === "r" || key === "R") {
          root.refresh()
          if (root.notificationsVisible) root.refreshNotifications()
        }
        if (key === "o" || key === "O") root.openUrl("https://dev-null.sh/log/trending")
        if ((key === "i" || key === "I") && root.authenticated) root.toggleNotifications()
      }

      Flickable {
        id: feedFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick

        Column {
          id: content
          width: parent.width
          spacing: Style.space(10)

          Row {
            width: parent.width
            spacing: Style.space(7)

            Text {
              text: "//"
              color: root.accent
              font.family: "monospace"
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              text: "/dev/null"
              textFormat: Text.PlainText
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }
            Text {
              text: "@" + root.accountUsername
              visible: root.authenticated
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(4)

            Rectangle {
              width: (parent.width - parent.spacing) / 2
              height: Style.space(38)
              radius: Style.cornerRadius
              color: !root.notificationsVisible ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16) : "transparent"
              Text {
                anchors.centerIn: parent
                text: "⌁  Log"
                color: root.notificationsVisible ? root.muted : root.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.body + 1
                font.bold: !root.notificationsVisible
              }
              Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 2
                color: root.notificationsVisible ? "transparent" : root.accent
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root.notificationsVisible) root.toggleNotifications()
              }
            }

            Rectangle {
              width: (parent.width - parent.spacing) / 2
              height: Style.space(38)
              radius: Style.cornerRadius
              color: root.notificationsVisible ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16) : "transparent"
              Text {
                anchors.centerIn: parent
                text: "◉  Notifications" + (root.unreadCount > 0 ? "  " + root.unreadCount : "")
                color: root.notificationsVisible ? root.accent : root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.body + 1
                font.bold: root.notificationsVisible
              }
              Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 2
                color: root.notificationsVisible ? root.accent : "transparent"
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: if (!root.notificationsVisible) root.toggleNotifications()
              }
            }
          }

          Rectangle {
            visible: root.notificationsVisible && !root.authenticated
            width: parent.width
            height: connectText.implicitHeight + Style.space(22)
            radius: Style.cornerRadius
            color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.15)

            Text {
              id: connectText
              anchors.centerIn: parent
              width: parent.width - Style.space(20)
              text: root.connecting
                ? "Waiting for approval…\nApprove in your browser, then open with Omarchy dev/null authorization if asked."
                : "Connect your dev/null account →\nSee notifications and an unread badge in the bar."
              color: root.foreground
              wrapMode: Text.WordWrap
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
            MouseArea {
              anchors.fill: parent
              enabled: !root.connecting
              cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
              onClicked: root.connectAccount()
            }
          }

          Text {
            visible: root.notificationsVisible && root.authError !== ""
            width: parent.width
            text: root.authError
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            color: Commons.Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            visible: root.notificationsVisible && root.authenticated
            width: parent.width
            text: "RECENT ACTIVITY"
            color: root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }

          Text {
            visible: root.notificationsVisible && root.loadingNotifications
            width: parent.width
            text: "Loading notifications…"
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Repeater {
            model: root.authenticated && root.notificationsVisible ? root.notificationItems : []
            delegate: Rectangle {
              required property var modelData
              width: content.width
              height: noticeContent.implicitHeight + Style.space(20)
              color: "transparent"

              Rectangle {
                x: Style.space(11)
                width: 1
                height: parent.height
                color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
              }
              Rectangle {
                x: Style.space(3)
                y: Style.space(8)
                width: Style.space(17)
                height: width
                radius: width / 2
                color: Commons.Color.popups.background
                border.width: 1
                border.color: root.accent
                Text {
                  anchors.centerIn: parent
                  text: modelData.kind === "starred" ? "★" : modelData.kind === "replied" ? "↳" : modelData.kind === "followed" ? "+" : "·"
                  color: root.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }
              }

              Column {
                id: noticeContent
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: Style.space(32)
                anchors.rightMargin: Style.space(6)
                anchors.topMargin: Style.space(7)
                spacing: Style.space(4)

                Row {
                  width: parent.width
                  spacing: Style.space(6)
                  Text {
                    width: parent.width - noticeTime.implicitWidth - parent.spacing
                    text: modelData.title
                    textFormat: Text.PlainText
                    wrapMode: Text.WordWrap
                    color: root.foreground
                    font.family: root.fontFamily
                    font.bold: true
                    font.pixelSize: Style.font.body + 1
                  }
                  Text {
                    id: noticeTime
                    text: Model.age(modelData.createdAt, Date.now())
                    color: root.muted
                    font.family: "monospace"
                    font.pixelSize: Style.font.bodySmall
                  }
                }
                Text {
                  visible: modelData.body !== ""
                  width: parent.width
                  text: modelData.body
                  textFormat: Text.PlainText
                  wrapMode: Text.WordWrap
                  maximumLineCount: 2
                  elide: Text.ElideRight
                  color: root.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
              }
              Rectangle {
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                width: parent.width - Style.space(32)
                height: 1
                color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openUrl(modelData.url)
              }
            }
          }

          Text {
            visible: root.authenticated && root.notificationsVisible && !root.loadingNotifications && root.notificationItems.length === 0
            width: parent.width
            text: "No notifications yet."
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          Text {
            visible: !root.notificationsVisible
            width: parent.width
            text: "CURATED LOG"
            color: root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }

          Text {
            visible: !root.notificationsVisible
            width: parent.width
            text: root.loading ? "Loading recent commits…" :
                  (root.refreshedAt.getTime() > 0 ? "Updated " + Qt.formatTime(root.refreshedAt, "HH:mm") + "  ·  R refresh  ·  O open" : "R refresh  ·  O open")
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            visible: !root.notificationsVisible
            width: parent.width
            text: root.selectedUsers.map(function(name) { return "@" + name }).join("  ")
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            visible: !root.notificationsVisible && root.errorText !== ""
            width: parent.width
            text: root.errorText
            wrapMode: Text.WordWrap
            color: Commons.Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            visible: !root.notificationsVisible && !root.loading && root.commits.length === 0 && root.errorText === ""
            width: parent.width
            text: "No commits yet from the selected developers."
            wrapMode: Text.WordWrap
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          Repeater {
            id: commitRepeater
            model: root.notificationsVisible ? [] : root.commits
            delegate: Rectangle {
              required property var modelData
              required property int index
              width: content.width
              height: rowContent.implicitHeight + Style.space(24)
              color: root.cursorActive && root.selectedIndex === index
                ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.10)
                : "transparent"

              Rectangle {
                x: Style.space(11)
                width: 1
                height: parent.height
                color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
              }
              Rectangle {
                x: Style.space(4)
                y: Style.space(8)
                width: Style.space(15)
                height: width
                radius: width / 2
                color: Commons.Color.popups.background
                border.width: 2
                border.color: root.accent
              }

              Column {
                id: rowContent
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: Style.space(32)
                anchors.rightMargin: Style.space(6)
                anchors.topMargin: Style.space(7)
                spacing: Style.space(5)

                Row {
                  width: parent.width
                  spacing: Style.space(6)
                  Text {
                    width: parent.width - commitHash.implicitWidth - parent.spacing
                    text: "@" + modelData.username + "  ·  " + Model.age(modelData.createdAt, Date.now())
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    color: root.foreground
                    font.family: root.fontFamily
                    font.bold: true
                    font.pixelSize: Style.font.bodySmall
                  }
                  Text {
                    id: commitHash
                    text: modelData.hash
                    color: root.muted
                    font.family: "monospace"
                    font.pixelSize: Style.font.bodySmall
                  }
                }
                Text {
                  width: parent.width
                  text: modelData.body
                  textFormat: Text.PlainText
                  wrapMode: Text.WordWrap
                  maximumLineCount: 3
                  elide: Text.ElideRight
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
                Text {
                  text: "★ " + modelData.stars + "    ↳ " + modelData.replies
                  color: root.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }
              }

              Rectangle {
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                width: parent.width - Style.space(32)
                height: 1
                color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: { root.selectedIndex = index; root.cursorActive = true }
                onClicked: root.openUrl(modelData.url)
              }
            }
          }
        }
      }
    }
  }
}
