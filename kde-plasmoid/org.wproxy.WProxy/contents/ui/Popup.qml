import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../code/Commands.js" as Commands

Item {
    id: popup
    objectName: "wproxyPopup"
    required property var backend
    readonly property int rowHeight: Math.max(54, Math.ceil(Kirigami.Units.gridUnit * 3))
    readonly property color accentColor: Kirigami.Theme.highlightColor
    readonly property color statusColor: backend.errorMessage.length ? Kirigami.Theme.negativeTextColor
        : backend.active ? Kirigami.Theme.positiveTextColor : accentColor
    readonly property string connectionName: {
        const id = backend.connectingId || backend.activeId;
        const node = backend.nodes.find(function(item) { return item.id === id; });
        return node ? node.name : qsTr("Choose a server below");
    }
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
        spacing: Kirigami.Units.largeSpacing

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing * 2
            Rectangle {
                implicitWidth: 36
                implicitHeight: 36
                radius: 10
                color: Qt.rgba(popup.accentColor.r, popup.accentColor.g, popup.accentColor.b, 0.12)
                Kirigami.Icon {
                    anchors.centerIn: parent
                    source: "network-vpn"
                    width: 22
                    height: 22
                    color: popup.accentColor
                }
            }
            ColumnLayout {
                spacing: 0
                Layout.fillWidth: true
                Controls.Label { text: "WProxy"; font.weight: Font.DemiBold; font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.2 }
                Controls.Label { text: qsTr("Private routing"); color: Kirigami.Theme.disabledTextColor; font: Kirigami.Theme.smallFont }
            }
            Controls.Label { text: "2.7.4"; color: Kirigami.Theme.disabledTextColor; font: Kirigami.Theme.smallFont }
        }

        Controls.Frame {
            Layout.fillWidth: true
            padding: Kirigami.Units.largeSpacing
            background: Rectangle {
                radius: 10
                color: Qt.rgba(popup.statusColor.r, popup.statusColor.g, popup.statusColor.b, 0.06)
                border.color: Qt.rgba(popup.statusColor.r, popup.statusColor.g, popup.statusColor.b, 0.12)
            }
            contentItem: RowLayout {
                spacing: Kirigami.Units.largeSpacing
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    RowLayout {
                        spacing: Kirigami.Units.smallSpacing
                        Rectangle {
                            implicitWidth: 7
                            implicitHeight: 7
                            radius: width / 2
                            color: popup.statusColor
                        }
                        Controls.Label {
                            text: popup.backend.busy ? qsTr("Working…") : popup.backend.errorMessage.length ? qsTr("Needs attention")
                                : popup.backend.active ? qsTr("Connected") : qsTr("Disconnected")
                            font.weight: Font.DemiBold
                        }
                    }
                    Controls.Label {
                        Layout.fillWidth: true
                        Layout.minimumHeight: Math.ceil(Kirigami.Units.gridUnit * 1.5)
                        Layout.maximumHeight: Layout.minimumHeight
                        text: popup.backend.errorMessage || (popup.backend.active || popup.backend.connectingId ? popup.connectionName : qsTr("Choose a server below"))
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        color: popup.backend.errorMessage.length ? Kirigami.Theme.textColor : Kirigami.Theme.disabledTextColor
                        font: Kirigami.Theme.smallFont
                        Accessible.name: text
                    }
                }
                Controls.Switch {
                    objectName: "connectionSwitch"
                    checked: popup.backend.active
                    enabled: !popup.backend.busy && (popup.backend.active || popup.backend.nodes.length > 0)
                    Accessible.name: qsTr("VPN connection")
                    onClicked: popup.backend.toggleConnection()
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
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
                icon.name: "list-add"
                enabled: !popup.backend.busy
                onClicked: popup.backend.addSubscription(subscriptionInput.text)
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Controls.Label { text: qsTr("Servers"); font.weight: Font.DemiBold }
            Item { Layout.fillWidth: true }
            Controls.Label {
                text: popup.backend.traffic || qsTr("%1 saved").arg(popup.backend.nodes.length)
                textFormat: Text.PlainText
                color: Kirigami.Theme.disabledTextColor
                font: Kirigami.Theme.smallFont
            }
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
                text: qsTr("Add a subscription or open Manager to get started.")
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
                leftPadding: Kirigami.Units.smallSpacing * 2
                rightPadding: Kirigami.Units.smallSpacing
                background: Rectangle {
                    radius: 8
                    color: serverRow.highlighted || serverRow.hovered || serverRow.activeFocus
                        ? Qt.rgba(popup.accentColor.r, popup.accentColor.g, popup.accentColor.b, serverRow.highlighted ? 0.12 : 0.06)
                        : "transparent"
                    border.width: serverRow.activeFocus ? 1 : 0
                    border.color: popup.accentColor
                }
                contentItem: RowLayout {
                    spacing: Kirigami.Units.smallSpacing * 2
                    Kirigami.Icon {
                        source: serverRow.highlighted ? "emblem-ok-symbolic" : "network-server-symbolic"
                        implicitWidth: 20
                        implicitHeight: 20
                        color: serverRow.highlighted ? popup.accentColor : Kirigami.Theme.disabledTextColor
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        Controls.Label {
                            Layout.fillWidth: true
                            text: serverRow.modelData.name
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            font.weight: serverRow.highlighted ? Font.DemiBold : Font.Normal
                        }
                        Controls.Label {
                            Layout.fillWidth: true
                            text: serverRow.highlighted ? qsTr("Active connection")
                                : serverRow.modelData.source_name || (serverRow.modelData.source ? qsTr("Subscription") : qsTr("Manual"))
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            font: Kirigami.Theme.smallFont
                            color: Kirigami.Theme.disabledTextColor
                        }
                    }
                    Controls.Label {
                        text: popup.backend.connectingId === serverRow.modelData.id ? qsTr("Connecting…")
                            : !Object.prototype.hasOwnProperty.call(popup.backend.latencies, serverRow.modelData.id) && !popup.backend.pinging[serverRow.modelData.id]
                                ? qsTr("Not tested") : Commands.latencyText(serverRow.modelData.id, popup.backend.latencies, popup.backend.pinging)
                        font: Kirigami.Theme.smallFont
                        color: Kirigami.Theme.disabledTextColor
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

        Kirigami.Separator { Layout.fillWidth: true }

        RowLayout {
            objectName: "fixedActions"
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            Controls.ToolButton {
                Layout.fillWidth: true
                text: qsTr("Ping all")
                icon.name: "network-connect"
                enabled: !popup.backend.busy && Object.keys(popup.backend.pinging).length === 0
                onClicked: popup.backend.pingAll()
            }
            Controls.ToolButton {
                Layout.fillWidth: true
                text: qsTr("Refresh")
                icon.name: "view-refresh"
                enabled: !popup.backend.busy
                Accessible.name: qsTr("Update subscriptions")
                onClicked: popup.backend.updateSubscriptions()
            }
            Controls.Button {
                Layout.fillWidth: true
                text: qsTr("Manager")
                icon.name: "configure"
                onClicked: popup.backend.openManager()
            }
        }
    }

    Connections {
        target: popup.backend
        function onSubscriptionAdded() { subscriptionInput.clear(); }
    }
}
