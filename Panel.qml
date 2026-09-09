import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "SleepMath.js" as SleepMath

// Sleep calculator for the bar: the two questions sleepcalculator.com answers,
// in the place you already look for the time.
//
// One panel rather than the site's calculate-then-go-back flow. A bar popup is
// opened for a few seconds and dismissed, so the answer is on screen the
// moment it opens and every change to the wake time re-reads the list under
// the cursor. The two modes are a toggle at the top:
//
//   Bedtime   what time to fall asleep to be up at a set time
//   Wake-up   what time to get up if you go to bed right now
//
// The arithmetic is in SleepMath.js, kept separate from the drawing so it can
// be diffed against the site's own scripts/common.js.
//
// Glyphs are \u surrogate pairs rather than literal characters so the source
// survives editors and patches that mangle private-use codepoints.
Panel {
  id: root

  moduleName: "dielerorn.sleep-calculator"
  ipcTarget: "dielerorn.sleep-calculator"

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color panelForeground: Color.popups.text
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // ------------------------------------------------------------- settings

  readonly property int panelWidth: setting("panelWidth", 300)

  // Wake time and mode live in shell.json rather than in memory: the whole
  // point of the widget is that it is the same question every night, so it
  // should open already holding last night's answer.
  property int wakeMinutes: 7 * 60
  property string mode: "bedtime"

  // Which of the three time cells the arrow keys drive. Pointer users never
  // see it; it only paints once the panel has been given a key.
  property int fieldIndex: 0
  property bool keyboardActive: false

  property bool loading: false

  function loadSettings() {
    loading = true
    wakeMinutes = SleepMath.parseIso(setting("wakeTime", "07:00"), 7 * 60)
    mode = String(setting("mode", "bedtime")) === "wakeup" ? "wakeup" : "bedtime"
    loading = false
  }

  // Debounced: stepping from 7:00 to 7:30 is six clicks, and each one would
  // otherwise be its own rewrite of shell.json.
  function persist() {
    if (loading) return
    persistTimer.restart()
  }

  function persistNow() {
    if (!root.bar || !root.bar.shell || typeof root.bar.shell.updateEntryInline !== "function") return
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    entry.wakeTime = SleepMath.formatIso(root.wakeMinutes)
    entry.mode = root.mode
    if (JSON.stringify(entry) === JSON.stringify(root.settings)) return
    root.settings = entry
    root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  Timer {
    id: persistTimer
    interval: 500
    onTriggered: root.persistNow()
  }

  Component.onCompleted: loadSettings()
  onSettingsChanged: if (!loading) loadSettings()

  // ------------------------------------------------------------- the clock
  //
  // Minute precision keeps the wake-up list honest while the panel sits open:
  // "if you go to sleep right now" is a moving question.
  SystemClock {
    id: clock
    precision: SystemClock.Minutes
  }

  readonly property int nowMinutes: clock.date.getHours() * 60 + clock.date.getMinutes()

  // ------------------------------------------------------------- the answer

  readonly property bool bedtimeMode: mode === "bedtime"
  readonly property var rows: bedtimeMode ? SleepMath.bedtimes(wakeMinutes)
                                          : SleepMath.wakeTimes(nowMinutes)
  readonly property var bestRow: rows.length > 0 ? rows[0] : null

  readonly property string wakeClock: SleepMath.formatClock(wakeMinutes)
  readonly property string nowClock: SleepMath.formatClock(nowMinutes)

  function setMode(next) {
    if (root.mode === next) return
    root.mode = next
    root.persist()
  }

  function toggleMode() {
    setMode(root.bedtimeMode ? "wakeup" : "bedtime")
  }

  // Every cell steps the same underlying minutes-of-day value, so a minute
  // rolling past 59 carries into the hour and an hour past 11 carries into
  // AM/PM, the way a clock does — rather than three fields that each wrap on
  // their own and quietly disagree.
  function step(delta) {
    root.wakeMinutes = SleepMath.normalize(root.wakeMinutes + delta)
    root.persist()
  }

  function stepField(index, direction) {
    if (index === 0) step(direction * 60)
    else if (index === 1) step(direction * 5)
    else step(720)
  }

  function moveField(delta) {
    root.keyboardActive = true
    root.fieldIndex = (root.fieldIndex + delta + 3) % 3
  }

  // ------------------------------------------------------------- lifecycle

  function open() {
    root.keyboardActive = false
    root.fieldIndex = 0
    root.controller.show()
  }

  function close() {
    // A pending write must not be lost just because the panel was dismissed
    // in the half second after the last click.
    if (persistTimer.running) {
      persistTimer.stop()
      root.persistNow()
    }
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  // ------------------------------------------------------------- time cell
  //
  // One digit pair with a chevron over and under it. Clicking a chevron steps
  // the whole wake time, so carrying works; the wheel does the same, which is
  // how a time gets set quickly. Declared last: an inline component is a
  // member of the file, not part of the layout.

  component TimeCell: Item {
    id: cell

    property int index: 0
    property string valueText: ""

    readonly property bool selected: root.keyboardActive && root.fieldIndex === cell.index

    implicitWidth: Math.max(Style.space(38), valueLabel.implicitWidth + Style.space(14))
    implicitHeight: upArrow.height + valueBox.height + downArrow.height

    Text {
      id: upArrow
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: parent.top
      // nf-md-chevron-up / nf-md-chevron-down (U+F0143 / U+F0140)
      text: "󰅃"
      color: root.panelForeground
      opacity: upMouse.containsMouse ? 1.0 : 0.45
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall

      MouseArea {
        id: upMouse
        anchors.fill: parent
        anchors.margins: -Style.space(4)
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.stepField(cell.index, 1)
      }
    }

    BorderSurface {
      id: valueBox
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: upArrow.bottom
      width: cell.width
      height: valueLabel.implicitHeight + Style.space(8)
      radius: Style.cornerRadius
      color: Style.controlFill(false, cell.selected || cellMouse.containsMouse, root.panelForeground, Color.accent)
      borderSpec: Border.controlSpec(cell.selected ? "focus" : "normal", root.panelForeground, Color.accent)

      Text {
        id: valueLabel
        anchors.centerIn: parent
        text: cell.valueText
        color: root.panelForeground
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
      }

      MouseArea {
        id: cellMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: function(mouse) {
          root.keyboardActive = true
          root.fieldIndex = cell.index
          root.stepField(cell.index, mouse.button === Qt.RightButton ? -1 : 1)
        }
        onWheel: function(wheel) {
          root.keyboardActive = true
          root.fieldIndex = cell.index
          root.stepField(cell.index, wheel.angleDelta.y > 0 ? 1 : -1)
        }
      }
    }

    Text {
      id: downArrow
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: valueBox.bottom
      text: "󰅀"
      color: root.panelForeground
      opacity: downMouse.containsMouse ? 1.0 : 0.45
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall

      MouseArea {
        id: downMouse
        anchors.fill: parent
        anchors.margins: -Style.space(4)
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.stepField(cell.index, -1)
      }
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // ------------------------------------------------------------- bar button

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar

    // nf-md-sleep (U+F0904): a moon with the Zs, which is the one picture
    // that reads as "sleep" rather than as "night" or "alarm".
    text: "󰤄"
    active: root.opened

    tooltipText: {
      if (!root.bestRow) return "Sleep calculator"
      if (root.bedtimeMode)
        return "Asleep by " + root.bestRow.time + " to wake at " + root.wakeClock
      return "Asleep now, wake at " + root.bestRow.time
    }

    onPressed: function(b) {
      // Right-click flips the question without opening anything: the two modes
      // are one keystroke apart and the tooltip already carries the answer.
      if (b === Qt.RightButton) {
        root.toggleMode()
        return
      }
      root.toggle()
    }
  }

  // ------------------------------------------------------------- the panel

  KeyboardPanel {
    id: popup
    anchorItem: button
    bar: root.bar
    owner: root
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: popup.fittedContentWidth(Style.space(root.panelWidth))
    contentHeight: Math.round(Math.min(
      Math.max(popup.verticalContentInset, content.implicitHeight + popup.verticalContentInset),
      popup.usableCardHeight))

    // fittedContentHeight() measures the space left over after the bar window,
    // and collapses to its 120px floor under a bar whose window is the whole
    // screen. Measure the strip itself in that case; both bar hosts expose
    // barSize.
    readonly property real usableCardHeight: {
      if (barH >= screenH && root.bar && Number(root.bar.barSize) > 0)
        return Math.max(120, screenH - (Number(root.bar.barSize) + gap + margin))
      return availableCardHeight
    }

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (dx !== 0) root.moveField(dx)
        if (dy !== 0 && root.bedtimeMode) {
          root.keyboardActive = true
          root.stepField(root.fieldIndex, -dy)   // Up is later, as on a clock
        }
      }
      onActivateRequested: root.toggleMode()
      onTextKey: function(t) {
        var c = t.toLowerCase()
        if (c === "b") root.setMode("bedtime")
        else if (c === "w") root.setMode("wakeup")
      }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(10)

        // ---- Title

        Text {
          text: "Sleep calculator"
          color: root.panelForeground
          font.family: root.fontFamily
          font.pixelSize: Style.font.subtitle
          font.bold: true
        }

        // ---- Mode. Two buttons rather than a switch: they are two different
        //      questions, not one question with a direction.

        Row {
          width: parent.width
          spacing: Style.space(6)

          Button {
            width: (content.width - Style.space(6)) / 2
            text: "Bedtime"
            selected: root.bedtimeMode
            bordered: true
            foreground: root.panelForeground
            fontFamily: root.fontFamily
            tooltipText: "What time to fall asleep to be up at a set time"
            onClicked: root.setMode("bedtime")
          }

          Button {
            width: (content.width - Style.space(6)) / 2
            text: "Wake-up"
            selected: !root.bedtimeMode
            bordered: true
            foreground: root.panelForeground
            fontFamily: root.fontFamily
            tooltipText: "What time to get up if you go to bed right now"
            onClicked: root.setMode("wakeup")
          }
        }

        PanelSeparator { foreground: root.panelForeground }

        // ---- The input half. In bedtime mode it is the wake time; in wake-up
        //      mode there is nothing to set, so it states the time it is
        //      working from instead of leaving the space empty.

        PanelSectionHeader {
          text: root.bedtimeMode ? "I WANT TO WAKE UP AT" : "IF I FALL ASLEEP NOW"
          foreground: root.panelForeground
          fontFamily: root.fontFamily
        }

        Item {
          width: parent.width
          height: root.bedtimeMode ? picker.height : nowLabel.height

          Row {
            id: picker
            visible: root.bedtimeMode
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.space(4)

            TimeCell {
              index: 0
              valueText: SleepMath.pad2(SleepMath.hour12Of(root.wakeMinutes))
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: ":"
              color: root.panelForeground
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
            }

            TimeCell {
              index: 1
              valueText: SleepMath.pad2(SleepMath.minuteOf(root.wakeMinutes))
            }

            TimeCell {
              index: 2
              valueText: SleepMath.meridiemOf(root.wakeMinutes)
            }
          }

          Text {
            id: nowLabel
            visible: !root.bedtimeMode
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.nowClock
            color: root.panelForeground
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
          }
        }

        PanelSeparator { foreground: root.panelForeground }

        // ---- The answer.

        PanelSectionHeader {
          text: root.bedtimeMode ? "GO TO SLEEP AT" : "WAKE UP AT"
          foreground: root.panelForeground
          fontFamily: root.fontFamily
        }

        Column {
          width: parent.width
          spacing: Style.space(1)

          Repeater {
            model: root.rows

            // A row is the time, and then what that time buys: how many whole
            // cycles it is, and how long you are actually asleep for. The top
            // two are the ones the site marks — five or six complete cycles —
            // and they are the reason anyone opens this, so they are the only
            // rows drawn at full strength.
            Item {
              id: row
              required property var modelData
              width: parent.width
              height: Style.space(24)

              readonly property bool best: modelData.recommended

              Rectangle {
                anchors.fill: parent
                visible: row.best
                color: Util.alpha(Color.accent, 0.10)
                radius: Style.cornerRadius
              }

              Text {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                text: row.modelData.time
                color: row.best ? Color.accent : root.panelForeground
                opacity: row.best ? 1.0 : 0.75
                font.family: root.fontFamily
                font.pixelSize: Style.font.subtitle
                font.bold: row.best
              }

              Text {
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                text: row.modelData.cycles + (row.modelData.cycles === 1 ? " cycle · " : " cycles · ") + row.modelData.sleep
                color: root.panelForeground
                opacity: row.best ? 0.8 : 0.5
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }

        PanelSeparator { foreground: root.panelForeground }

        // ---- The two assumptions behind every row above, stated rather than
        //      buried, because they are what makes the numbers land where they
        //      do. Same figures the site quotes.

        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          text: "Cycles run 90 minutes, plus the 15 minutes the average person "
              + "takes to fall asleep. Five or six complete cycles is a good night."
          color: root.panelForeground
          opacity: 0.55
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
