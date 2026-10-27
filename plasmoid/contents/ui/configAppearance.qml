// Settings page: bar colours (Claude orange by default, or the Plasma theme's), the two thresholds and
// whether the numbers are coloured too.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kquickcontrols as KQC
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    property alias cfg_useThemeColors: theme.checked
    property alias cfg_normalColor: normal.color
    property alias cfg_warnColor: warn.color
    property alias cfg_critColor: crit.color
    property alias cfg_warnAt: warnAt.value
    property alias cfg_critAt: critAt.value
    property alias cfg_colorNumbers: numbers.checked
    property alias cfg_showContext: showContext.checked
    property alias cfg_showHistory: showHistory.checked

    Kirigami.FormLayout {
        QQC2.CheckBox {
            id: theme
            Kirigami.FormData.label: "Colours:"
            text: "Use the Plasma theme's colours"
        }
        KQC.ColorButton {
            id: normal
            enabled: !theme.checked
            Kirigami.FormData.label: "Normal:"
            dialogTitle: "Bar colour below the warning level"
        }
        RowLayout {
            Kirigami.FormData.label: "Warning:"
            KQC.ColorButton { id: warn; enabled: !theme.checked; dialogTitle: "Bar colour from the warning level" }
            QQC2.Label { text: "from" }
            QQC2.SpinBox { id: warnAt; from: 1; to: critAt.value - 1 }
            QQC2.Label { text: "%" }
        }
        RowLayout {
            Kirigami.FormData.label: "Critical:"
            KQC.ColorButton { id: crit; enabled: !theme.checked; dialogTitle: "Bar colour from the critical level" }
            QQC2.Label { text: "from" }
            QQC2.SpinBox { id: critAt; from: warnAt.value + 1; to: 100 }
            QQC2.Label { text: "%" }
        }
        QQC2.CheckBox {
            id: numbers
            text: "Colour the numbers too, not only from the warning level"
        }
        QQC2.CheckBox {
            id: showContext
            Kirigami.FormData.label: "Context:"
            text: "Show how full the context of the current Claude Code session is"
        }
        QQC2.CheckBox {
            id: showHistory
            Kirigami.FormData.label: "History:"
            text: "Graph of each limit in the popup, with where the current pace ends up"
        }
        QQC2.Button {
            text: "Back to Claude orange"
            icon.name: "edit-undo"
            onClicked: {
                theme.checked = false
                normal.color = "#D97757"
                warn.color = "#E8B04B"
                crit.color = "#E5484D"
                warnAt.value = 70
                critAt.value = 90
                numbers.checked = false
            }
        }
    }
}
