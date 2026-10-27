// Claude Usage: shows the plan limits from ~/.cache/claude-usage/state.json (written by statusline.py and
// poll.py). Panel: one small percentage + bar per limit, plus the context fill of the Claude Code session
// used last. Popup: bars, reset countdowns, the context of every recently active session, data age, refresh.
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PC3
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    readonly property string stateCmd: "cat \"${XDG_CACHE_HOME:-$HOME/.cache}/claude-usage/state.json\""
    readonly property string pollCmd: "python3 -I \"${XDG_DATA_HOME:-$HOME/.local/share}/claude-usage/poll.py\" --force"
    readonly property int staleSecs: 30 * 60
    property var st: null
    property real now: Date.now() / 1000
    property bool refreshing: false
    readonly property var keys: st ? (st.order || Object.keys(st.limits)) .filter(k => st.limits[k]) : []
    // Claude Code sessions with a status line update in the last 30 min, newest first
    readonly property var contexts: st && st.contexts && cfg.showContext
        ? Object.keys(st.contexts).map(k => st.contexts[k]).filter(c => now - c.at < staleSecs)
            .sort((a, b) => b.at - a.at) : []

    Plasmoid.icon: "speedometer"
    toolTipMainText: "Claude usage"
    toolTipSubText: keys.map(k => st.limits[k].label + ": " + Math.round(pct(st.limits[k])) + " %, resets "
                                 + resetText(st.limits[k])).join("\n") + contexts.map(c => "\nContext " + c.project
                                 + ": " + Math.round(c.percent) + " %").join("")
                    || "No data yet. Use Claude Code once."

    // ---------- data ----------
    P5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            disconnectSource(source)
            if (source === root.stateCmd) {
                try { root.st = JSON.parse(data["stdout"]) } catch (e) { }
            } else if (source === root.pollCmd) {
                root.refreshing = false
                exec.connectSource(root.stateCmd)
            }
        }
    }
    Timer {
        interval: root.expanded ? 1000 : 5000
        running: true; repeat: true; triggeredOnStart: true
        onTriggered: {
            root.now = Date.now() / 1000
            exec.connectSource(root.stateCmd)
        }
    }

    function pct(l) { return l.resets_at && l.resets_at <= now ? 0 : l.percent }
    readonly property var cfg: Plasmoid.configuration
    function color(p) {
        if (cfg.useThemeColors)
            return p >= cfg.critAt ? Kirigami.Theme.negativeTextColor
                 : p >= cfg.warnAt ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.highlightColor
        return p >= cfg.critAt ? cfg.critColor : p >= cfg.warnAt ? cfg.warnColor : cfg.normalColor
    }
    function textColor(p) { return cfg.colorNumbers || p >= cfg.warnAt ? color(p) : Kirigami.Theme.textColor }
    function stale(l) { return now - l.at > staleSecs && !(l.resets_at && l.resets_at <= now) }
    function short(k, l) {
        if (k === "session") return "5h"
        if (k === "weekly_all") return "wk"
        const m = /\((.*)\)/.exec(l.label)
        return m ? m[1] : l.label
    }
    function span(s) {
        s = Math.max(0, Math.round(s))
        const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60)
        if (d > 0) return d + " d " + h + " h"
        if (h > 0) return h + " h " + m + " min"
        return m + " min" + (expanded && m < 5 ? " " + (s % 60) + " s" : "")
    }
    function clock(t) {
        const d = new Date(t * 1000), today = new Date(now * 1000)
        return d.toDateString() === today.toDateString()
            ? Qt.formatTime(d, "hh:mm") : Qt.formatDateTime(d, "ddd dd.MM. hh:mm")
    }
    function resetText(l) {
        if (!l.resets_at) return "unknown"
        if (l.resets_at <= now) return "done, back at 0 %"
        return "in " + span(l.resets_at - now) + " (" + clock(l.resets_at) + ")"
    }
    function ago(t) { return t ? span(now - t) + " ago" : "never" }

    // ---------- panel ----------
    compactRepresentation: MouseArea {
        readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
        Layout.minimumWidth: vertical ? -1 : row.implicitWidth + Kirigami.Units.smallSpacing * 2
        Layout.preferredWidth: Layout.minimumWidth
        Layout.minimumHeight: vertical ? row.implicitHeight + Kirigami.Units.smallSpacing * 2 : -1
        Layout.preferredHeight: Layout.minimumHeight
        onClicked: root.expanded = !root.expanded

        GridLayout {                                 // a row in horizontal panels, a column in vertical ones
            id: row
            anchors.centerIn: parent
            flow: parent.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
            rows: parent.vertical ? -1 : 1
            columns: parent.vertical ? 1 : -1
            rowSpacing: Kirigami.Units.smallSpacing
            columnSpacing: Kirigami.Units.largeSpacing

            ColumnLayout {                           // context of the session used last
                visible: root.contexts.length > 0
                readonly property real p: visible ? root.contexts[0].percent : 0
                spacing: 1
                Layout.alignment: Qt.AlignHCenter
                PC3.Label {
                    Layout.alignment: Qt.AlignHCenter
                    horizontalAlignment: Text.AlignHCenter
                    text: "ctx" + (row.flow === GridLayout.TopToBottom ? "\n" : " ") + Math.round(parent.p) + "%"
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    color: root.textColor(parent.p)
                }
                Rectangle {
                    Layout.fillWidth: true
                    height: 3; radius: 1.5
                    color: Qt.alpha(Kirigami.Theme.textColor, 0.2)
                    Rectangle {
                        width: parent.width * Math.min(1, parent.parent.p / 100)
                        height: parent.height; radius: parent.radius
                        color: root.color(parent.parent.p)
                    }
                }
            }
            Kirigami.Icon {
                visible: root.keys.length === 0 && root.contexts.length === 0
                source: "speedometer"
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Layout.preferredWidth
            }
            Repeater {
                model: root.keys
                ColumnLayout {
                    required property string modelData
                    readonly property var lim: root.st.limits[modelData]
                    readonly property real p: root.pct(lim)
                    spacing: 1
                    opacity: root.stale(lim) ? 0.5 : 1
                    Layout.alignment: Qt.AlignHCenter
                    PC3.Label {
                        Layout.alignment: Qt.AlignHCenter
                        horizontalAlignment: Text.AlignHCenter
                        // vertical panel: name above the number, the panel is too narrow for both in one line
                        text: root.short(modelData, lim) + (row.flow === GridLayout.TopToBottom ? "\n" : " ")
                              + Math.round(p) + "%"
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        color: root.textColor(p)
                    }
                    Rectangle {                      // thin bar under the number
                        Layout.fillWidth: true
                        height: 3; radius: 1.5
                        color: Qt.alpha(Kirigami.Theme.textColor, 0.2)
                        Rectangle {
                            width: parent.width * Math.min(1, p / 100)
                            height: parent.height; radius: parent.radius
                            color: root.color(p)
                        }
                    }
                }
            }
        }
    }

    // ---------- popup ----------
    fullRepresentation: ColumnLayout {
        Layout.preferredWidth: Kirigami.Units.gridUnit * 22
        Layout.minimumHeight: implicitHeight
        spacing: Kirigami.Units.largeSpacing

        Kirigami.Heading { text: "Claude usage"; level: 3 }

        PC3.Label {
            visible: root.keys.length === 0
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: "No data yet. The limits arrive with the next Claude Code reply."
        }

        Repeater {
            model: root.keys
            ColumnLayout {
                required property string modelData
                readonly property var lim: root.st.limits[modelData]
                readonly property real p: root.pct(lim)
                Layout.fillWidth: true
                spacing: 2
                RowLayout {
                    Layout.fillWidth: true
                    PC3.Label { text: lim.label; font.bold: true; Layout.fillWidth: true }
                    PC3.Label { text: Math.round(p) + " %"; color: root.textColor(p) }
                }
                Rectangle {
                    Layout.fillWidth: true
                    height: 6; radius: 3
                    color: Qt.alpha(Kirigami.Theme.textColor, 0.15)
                    Rectangle {
                        width: parent.width * Math.min(1, p / 100)
                        height: parent.height; radius: parent.radius
                        color: root.color(p)
                    }
                }
                PC3.Label {
                    text: "Resets " + root.resetText(lim)
                          + (root.stale(lim) ? "  ·  as of " + root.clock(lim.at) : "")
                    opacity: 0.7
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                }
            }
        }

        Kirigami.Separator { Layout.fillWidth: true; visible: root.contexts.length > 0 }

        Repeater {                                   // context fill per active Claude Code session
            model: root.contexts
            ColumnLayout {
                required property var modelData
                readonly property real p: modelData.percent
                Layout.fillWidth: true
                spacing: 2
                RowLayout {
                    Layout.fillWidth: true
                    PC3.Label {
                        text: "Context · " + modelData.project + (modelData.model ? "  (" + modelData.model + ")" : "")
                        font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true
                    }
                    PC3.Label { text: Math.round(p) + " %"; color: root.textColor(p) }
                }
                Rectangle {
                    Layout.fillWidth: true
                    height: 6; radius: 3
                    color: Qt.alpha(Kirigami.Theme.textColor, 0.15)
                    Rectangle {
                        width: parent.width * Math.min(1, p / 100)
                        height: parent.height; radius: parent.radius
                        color: root.color(p)
                    }
                }
                PC3.Label {
                    text: "Last reply " + root.ago(modelData.at)
                    opacity: 0.7
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                }
            }
        }

        Kirigami.Separator { Layout.fillWidth: true }

        RowLayout {
            Layout.fillWidth: true
            PC3.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                opacity: 0.7
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                text: !root.st ? "" :
                      "Claude Code: " + root.ago(root.st.statusline_at)
                      + "\nUsage API: " + root.ago(root.st.api.last_ok)
                      + (root.st.api.error ? " (" + root.st.api.error.replace("_", " ") + ")" : "")
            }
            PC3.ToolButton {
                icon.name: "view-refresh"
                text: root.refreshing ? "…" : "Refresh"
                enabled: !root.refreshing
                onClicked: { root.refreshing = true; exec.connectSource(root.pollCmd) }
                PC3.ToolTip.text: "Ask the usage API now (at most once a minute)"
                PC3.ToolTip.visible: hovered
            }
        }
    }
}
