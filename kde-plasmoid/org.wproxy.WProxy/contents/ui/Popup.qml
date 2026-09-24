import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../code/Commands.js" as Commands

Item {
    id: popup
    required property var backend
    readonly property int rowHeight: Math.max(46, Math.ceil(Kirigami.Units.gridUnit * 2.75))
    implicitWidth: Kirigami.Units.gridUnit * 24
    implicitHeight: column.implicitHeight + Kirigami.Units.largeSpacing * 2
    Layout.minimumWidth: Kirigami.Units.gridUnit * 20
    Layout.preferredWidth: implicitWidth
    Layout.minimumHeight: implicitHeight
    Layout.preferredHeight: implicitHeight

    ColumnLayout {
        id: column
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            Kirigami.Icon { source: "network-vpn"; implicitWidth: 32; implicitHeight: 32 }
            ColumnLayout {
                spacing: 0
                Layout.fillWidth: true
                Controls.Label { text: "WProxy"; font.bold: true; font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.25 }
                Controls.Label { text: "2.3.1 · Xray / V2Ray"; opacity: 0.65 }
            }
            Controls.Switch {
                objectName: "connectionSwitch"
                checked: popup.backend.active
                enabled: !popup.backend.busy && (popup.backend.active || popup.backend.nodes.length > 0)
                Accessible.name: qsTr("VPN connection")
                onClicked: popup.backend.toggleConnection()
            }
        }

        RowLayout {
            Controls.Label {
                Layout.fillWidth: true
                text: popup.backend.busy ? qsTr("Working…") : popup.backend.active ? qsTr("Connected") : qsTr("Disconnected")
                color: popup.backend.active ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.textColor
            }
            Controls.Label { text: popup.backend.traffic; textFormat: Text.PlainText; opacity: 0.8 }
        }

        RowLayout {
            Controls.TextField {
                id: subscriptionInput
                objectName: "subscriptionInput"
                Layout.fillWidth: true
                placeholderText: qsTr("Paste subscription URL")
                enabled: !popup.backend.busy
                Accessible.name: qsTr("Subscription URL")
                onAccepted: popup.backend.addSubscription(text)
            }
            Controls.Button {
                text: qsTr("Add")
                enabled: !popup.backend.busy
                onClicked: popup.backend.addSubscription(subscriptionInput.text)
            }
        }

        Controls.Label {
            Layout.fillWidth: true
            visible: popup.backend.errorMessage.length > 0
            text: popup.backend.errorMessage
            textFormat: Text.PlainText
            color: Kirigami.Theme.negativeTextColor
            wrapMode: Text.Wrap
            maximumLineCount: 3
            elide: Text.ElideRight
            Accessible.name: text
        }

        ListView {
            id: serverList
            objectName: "serverList"
            Layout.fillWidth: true
            Layout.minimumHeight: popup.rowHeight * Math.max(1, Math.min(3, count))
            Layout.maximumHeight: Layout.minimumHeight
            Layout.preferredHeight: Layout.minimumHeight
            clip: true
            spacing: 0
            boundsBehavior: Flickable.StopAtBounds
            model: popup.backend.nodes
            keyNavigationEnabled: true
            Controls.ScrollBar.vertical: Controls.ScrollBar { id: scrollBar }

            Controls.Label {
                anchors.centerIn: parent
                visible: serverList.count === 0
                text: qsTr("No servers. Add a subscription or open Manager.")
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
            }

            delegate: Controls.ItemDelegate {
                id: serverRow
                required property var modelData
                required property int index
                width: serverList.width - (scrollBar.visible ? scrollBar.width : 0)
                height: popup.rowHeight
                highlighted: popup.backend.activeId === modelData.id
                enabled: !popup.backend.busy
                Accessible.name: modelData.name
                onClicked: popup.backend.connectNode(modelData.id)
                contentItem: RowLayout {
                    spacing: Kirigami.Units.smallSpacing
                    Controls.Label { text: popup.backend.activeId === serverRow.modelData.id ? "✓" : ""; Layout.preferredWidth: 16 }
                    Controls.Label {
                        Layout.fillWidth: true
                        text: serverRow.modelData.name
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                    }
                    Controls.Label {
                        text: popup.backend.connectingId === serverRow.modelData.id ? qsTr("Connecting…")
                            : Commands.latencyText(serverRow.modelData.id, popup.backend.latencies, popup.backend.pinging)
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.9
                    }
                    Controls.ToolButton {
                        icon.name: "view-refresh"
                        Accessible.name: qsTr("Ping %1").arg(serverRow.modelData.name)
                        enabled: !popup.backend.pinging[serverRow.modelData.id]
                        onClicked: popup.backend.pingNode(serverRow.modelData.id)
                        Controls.ToolTip.text: qsTr("TCP latency; this is not a full tunnel test")
                        Controls.ToolTip.visible: hovered
                    }
                }
            }
        }

        RowLayout {
            objectName: "fixedActions"
            Layout.fillWidth: true
            Controls.Button {
                Layout.fillWidth: true
                text: qsTr("Ping all")
                enabled: !popup.backend.busy && Object.keys(popup.backend.pinging).length === 0
                onClicked: popup.backend.pingAll()
            }
            Controls.Button {
                Layout.fillWidth: true
                text: qsTr("Update")
                enabled: !popup.backend.busy
                Accessible.name: qsTr("Update subscriptions")
                onClicked: popup.backend.updateSubscriptions()
            }
            Controls.Button {
                Layout.fillWidth: true
                text: qsTr("Manager")
                onClicked: popup.backend.openManager()
            }
        }
    }

    Connections {
        target: popup.backend
        function onSubscriptionAdded() { subscriptionInput.clear(); }
    }
}
