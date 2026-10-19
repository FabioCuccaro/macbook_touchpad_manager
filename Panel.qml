import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Panel {
  id: root
  moduleName: "fabiocuccaro.touchpad"
  ipcTarget: "fabiocuccaro.touchpad"

  readonly property string ctl: Qt.resolvedUrl("bin/touchpad-ctl").toString().replace("file://", "")

  // Last state reported by touchpad-ctl.
  property var tp: ({
    settings: {},
    apps: [],
    builtinProfiles: [],
    profiles: [],
    activeProfile: ""
  })
  readonly property var s: tp.settings
  readonly property bool ready: s.scroll_factor !== undefined
  property string errorText: ""
  property var openWindows: []

  // Omarchy's own per-app rules, minus the ones the user already overrides.
  readonly property var defaultApps: (tp.omarchyApps || []).filter(function(a) {
    return !tp.apps.some(function(u) { return u["class"] === a["class"] })
  })
  // Open windows that don't have a rule yet.
  readonly property var pickableWindows: openWindows.filter(function(c) {
    return !tp.apps.some(function(u) { return u["class"] === c })
  })

  // Commands run strictly one at a time; a queued "set" for the same key is
  // replaced so dragging a slider doesn't pile up processes.
  property var queue: []

  function run(args, coalesceKey) {
    var q = queue.slice()
    if (coalesceKey) {
      for (var i = q.length - 1; i >= 0; i--)
        if (q[i].key === coalesceKey) q.splice(i, 1)
    }
    q.push({ args: args, key: coalesceKey || "" })
    queue = q
    next()
  }

  function next() {
    if (proc.running || queue.length === 0) return
    var q = queue.slice()
    var item = q.shift()
    queue = q
    proc.command = ["python3", ctl].concat(item.args)
    proc.running = true
  }

  function handleOutput(text) {
    var data
    try { data = JSON.parse(text) } catch (e) { errorText = "Invalid response from touchpad-ctl"; return }
    if (data.error) { errorText = data.error; return }
    if (data.windows !== undefined) { openWindows = data.windows; return }
    errorText = data.warning || ""
    // While changes are still queued the UI keeps its optimistic values.
    var pendingChange = queue.some(function(q) { return q.key.indexOf("set:") === 0 || q.key.indexOf("app:") === 0 })
    if (!pendingChange) tp = data
  }

  function setting(key, value) {
    var copy = JSON.parse(JSON.stringify(tp))
    copy.settings[key] = value
    tp = copy
    run(["set", key, JSON.stringify(value)], "set:" + key)
  }

  function refresh() {
    run(["get"], "get")
    run(["windows"], "windows")
  }

  // Optimistic update so the slider doesn't jump back while the command runs.
  function setApp(cls, value) {
    var v = Math.round(value * 100) / 100
    var copy = JSON.parse(JSON.stringify(tp))
    var found = false
    for (var i = 0; i < copy.apps.length; i++) {
      if (copy.apps[i]["class"] === cls) { copy.apps[i].factor = v; found = true }
    }
    if (!found) copy.apps.push({ "class": cls, factor: v })
    tp = copy
    run(["app-set", cls, String(v)], "app:" + cls)
  }

  function scrollList(wheel) {
    var dy = wheel.pixelDelta.y !== 0 ? wheel.pixelDelta.y : wheel.angleDelta.y / 2
    var maxY = Math.max(0, flick.contentHeight - flick.height)
    flick.contentY = Math.max(0, Math.min(maxY, flick.contentY - dy))
  }

  function pct(v) { return (v >= 0 ? "+" : "") + Math.round(v * 100) + "%" }

  Process {
    id: proc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.handleOutput(text)
    }
    onExited: root.next()
  }

  Component.onCompleted: refresh()
  onOpenedChanged: if (opened) refresh()

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰍽"
    tooltipText: "Touchpad"
    onPressed: function(b) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: profileName.activeFocus || appClass.activeFocus
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: column
          width: flick.width
          spacing: Style.space(14)

          // ---------- Hero ----------
          Column {
            width: parent.width
            spacing: Style.space(2)

            Text {
              text: "Touchpad"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }
            Text {
              text: (root.tp.activeProfile ? "Profile: " + root.tp.activeProfile : "Custom").toUpperCase()
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
            }
          }

          Text {
            visible: root.errorText !== ""
            width: parent.width
            text: root.errorText
            wrapMode: Text.WordWrap
            color: Commons.Color.accent
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          // ---------- Not yet connected to Hyprland ----------
          Column {
            visible: root.ready && root.tp.wired === false
            width: parent.width
            spacing: Style.space(8)

            Text {
              width: parent.width
              text: "Changes apply now but are lost on reload until the plugin is connected to your Hyprland config (adds one line to ~/.config/hypr/input.lua, with a backup)."
              wrapMode: Text.WordWrap
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
            Button {
              text: "Connect to Hyprland"
              fontSize: Style.font.bodySmall
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              bordered: true
              onClicked: root.run(["setup"])
            }
          }

          // ---------- Profiles ----------
          PanelSeparator { foreground: root.bar.foreground }

          Column {
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader { text: "PROFILES"; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily }

            Flow {
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: root.tp.builtinProfiles.concat(root.tp.profiles)
                Button {
                  required property var modelData
                  readonly property bool saved: root.tp.profiles.indexOf(modelData) >= 0
                  text: String(modelData)
                  tooltipText: saved ? "Right-click to delete" : ""
                  fontSize: Style.font.bodySmall
                  foreground: root.bar.foreground
                  fontFamily: root.bar.fontFamily
                  bordered: true
                  active: root.tp.activeProfile === modelData
                  onClicked: root.run(["preset", String(modelData)])
                  onRightClicked: if (saved) root.run(["profile-delete", String(modelData)])
                }
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(6)

              TextField {
                id: profileName
                width: parent.width - saveButton.width - parent.spacing
                placeholderText: "Save current settings as…"
                foreground: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                onAccepted: saveButton.save()
              }
              Button {
                id: saveButton
                text: "Save"
                fontSize: Style.font.bodySmall
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                bordered: true
                function save() {
                  if (profileName.text.trim() === "") return
                  root.run(["profile-save", profileName.text.trim()])
                  profileName.text = ""
                  profileName.focus = false
                }
                onClicked: save()
              }
            }
          }

          // ---------- Scrolling ----------
          PanelSeparator { foreground: root.bar.foreground }

          Column {
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader { text: "SCROLLING"; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily }

            SettingToggle {
              label: "Natural scrolling"
              description: "Content follows your fingers, like on macOS."
              checked: root.s.natural_scroll === true
              onClicked: root.setting("natural_scroll", !checked)
            }

            SettingSlider {
              label: "Scroll speed"
              valueText: (root.s.scroll_factor || 0).toFixed(2) + "×"
              minimum: 0.1
              maximum: 2
              step: 0.05
              value: root.s.scroll_factor || 0.4
              onCommit: function(v) { root.setting("scroll_factor", Math.round(v * 100) / 100) }
            }
          }

          // ---------- Pointer ----------
          PanelSeparator { foreground: root.bar.foreground }

          Column {
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader { text: "POINTER"; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily }

            SettingSlider {
              label: "Pointer speed"
              valueText: root.pct(root.s.sensitivity || 0)
              minimum: -1
              maximum: 1
              step: 0.05
              value: root.s.sensitivity || 0
              onCommit: function(v) { root.setting("sensitivity", Math.round(v * 100) / 100) }
            }

            Text {
              text: "Acceleration"
              color: root.bar.foreground
              opacity: 0.6
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
            ButtonGroup {
              options: [
                { value: "adaptive", label: "Adaptive" },
                { value: "flat", label: "Flat" }
              ]
              value: root.s.accel_profile || "adaptive"
              foreground: root.bar.foreground
              background: root.bar.background
              fontFamily: root.bar.fontFamily
              fontSize: Style.font.bodySmall
              onChanged: function(v) { root.setting("accel_profile", v) }
            }
          }

          // ---------- Click ----------
          PanelSeparator { foreground: root.bar.foreground }

          Column {
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader { text: "CLICKING"; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily }

            SettingToggle {
              label: "Tap to click"
              description: "A light tap counts as a click."
              checked: root.s.tap_to_click === true
              onClicked: root.setting("tap_to_click", !checked)
            }
            SettingToggle {
              label: "Two-finger right click"
              description: "Two fingers = right button. Off: click by area."
              checked: root.s.clickfinger_behavior === true
              onClicked: root.setting("clickfinger_behavior", !checked)
            }
            SettingToggle {
              label: "Disable while typing"
              description: "Ignore the touchpad while you type."
              checked: root.s.disable_while_typing === true
              onClicked: root.setting("disable_while_typing", !checked)
            }
          }

          // ---------- Gestures ----------
          PanelSeparator { foreground: root.bar.foreground }

          Column {
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader { text: "GESTURES"; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily }

            SettingToggle {
              label: "Swipe to change workspace"
              description: "Swipe horizontally to switch workspaces."
              checked: root.s.gestures_workspace === true
              onClicked: root.setting("gestures_workspace", !checked)
            }

            ButtonGroup {
              visible: root.s.gestures_workspace === true
              options: [
                { value: "3", label: "3 fingers" },
                { value: "4", label: "4 fingers" }
              ]
              value: String(root.s.gestures_fingers || 3)
              foreground: root.bar.foreground
              background: root.bar.background
              fontFamily: root.bar.fontFamily
              fontSize: Style.font.bodySmall
              onChanged: function(v) { root.setting("gestures_fingers", parseInt(v)) }
            }

            SettingToggle {
              visible: root.s.gestures_workspace === true
              label: "Natural direction"
              description: "The workspace follows your fingers. Off: reversed."
              checked: root.s.gestures_natural === true
              onClicked: root.setting("gestures_natural", !checked)
            }
          }

          // ---------- Per-app scroll ----------
          PanelSeparator { foreground: root.bar.foreground }

          Column {
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader { text: "PER-APP SCROLL SPEED"; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily }

            Text {
              width: parent.width
              text: "Replaces the global scroll speed for every window of an app. Your rules win over Omarchy's defaults."
              wrapMode: Text.WordWrap
              color: root.bar.foreground
              opacity: 0.6
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }

            Repeater {
              model: root.tp.apps
              AppSpeed {
                required property var modelData
                appClass: modelData["class"]
                speed: Number(modelData.factor)
              }
            }

            Repeater {
              model: root.defaultApps
              AppSpeed {
                required property var modelData
                appClass: modelData["class"]
                speed: Number(modelData.factor)
                builtin: true
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(6)

              TextField {
                id: appClass
                width: parent.width - addApp.width - parent.spacing
                placeholderText: "Window class (or pick an open app)"
                foreground: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                onAccepted: addApp.add()
              }
              Button {
                id: addApp
                text: "Add"
                fontSize: Style.font.bodySmall
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                bordered: true
                function add() {
                  var cls = appClass.text.trim()
                  if (cls === "") return
                  root.setApp(cls, root.s.scroll_factor || 1)
                  appClass.text = ""
                  appClass.focus = false
                }
                onClicked: add()
              }
            }

            Flow {
              visible: root.pickableWindows.length > 0
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: root.pickableWindows
                Button {
                  required property var modelData
                  text: String(modelData)
                  fontSize: Style.font.caption
                  foreground: root.bar.foreground
                  fontFamily: root.bar.fontFamily
                  bordered: true
                  onClicked: appClass.text = String(modelData)
                }
              }
            }
          }
        }
      }
    }
  }

  // PanelSlider changes its value on wheel/two-finger scroll, which hijacks
  // scrolling the settings list. Put this inside a slider to take the wheel and
  // scroll the list instead; clicks and drags still reach the slider.
  component WheelGuard: MouseArea {
    anchors.fill: parent
    z: 10
    acceptedButtons: Qt.NoButton
    onWheel: function(wheel) { root.scrollList(wheel) }
  }

  component AppSpeed: Column {
    id: app
    property string appClass: ""
    property real speed: 1
    property bool builtin: false

    width: parent.width
    spacing: Style.space(4)

    Row {
      width: parent.width
      spacing: Style.space(8)

      Text {
        width: parent.width - appValue.implicitWidth - appAction.width - parent.spacing * 2
        text: app.appClass + (app.builtin ? "  · Omarchy default" : "")
        elide: Text.ElideRight
        color: root.bar.foreground
        opacity: app.builtin ? 0.6 : 1
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.bodySmall
        anchors.verticalCenter: parent.verticalCenter
      }
      Text {
        id: appValue
        text: app.speed.toFixed(2) + "×"
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
        anchors.verticalCenter: parent.verticalCenter
      }
      PanelActionButton {
        id: appAction
        iconText: app.builtin ? "\uF040" : "\uF00D"
        tooltipText: app.builtin ? "Override" : "Remove"
        foreground: root.bar.foreground
        fontFamily: root.bar.fontFamily
        onClicked: {
          if (app.builtin) root.setApp(app.appClass, app.speed)
          else root.run(["app-remove", app.appClass])
        }
      }
    }

    PanelSlider {
      visible: !app.builtin
      bar: root.bar
      width: parent.width
      minimum: 0.1
      maximum: 3
      step: 0.05
      value: app.speed
      onMoved: function(v) { root.setApp(app.appClass, v) }

      WheelGuard {}
    }
  }

  component SettingToggle: Toggle {
    width: parent.width
    foreground: root.bar.foreground
    fontFamily: root.bar.fontFamily
  }

  component SettingSlider: Column {
    id: row
    property string label: ""
    property string valueText: ""
    property alias minimum: slider.minimum
    property alias maximum: slider.maximum
    property alias step: slider.step
    property alias value: slider.value
    signal commit(real value)

    width: parent.width
    spacing: Style.space(4)

    Row {
      width: parent.width
      Text {
        width: parent.width - valueLabel.implicitWidth
        text: row.label
        color: root.bar.foreground
        opacity: 0.6
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
      Text {
        id: valueLabel
        text: row.valueText
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }
    }

    PanelSlider {
      id: slider
      bar: root.bar
      width: parent.width
      onMoved: function(v) { row.commit(v) }

      WheelGuard {}
    }
  }
}
