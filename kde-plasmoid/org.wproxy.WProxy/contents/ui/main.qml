import QtQuick
import QtQuick.Controls as Controls
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore

PlasmoidItem {
    id: root
    Plasmoid.icon: "network-vpn"
    Plasmoid.status: controller.active ? PlasmaCore.Types.ActiveStatus : PlasmaCore.Types.PassiveStatus
    toolTipMainText: "WProxy"
    toolTipSubText: controller.active ? controller.activeName : qsTr("Disconnected")

    Backend { id: controller }

    compactRepresentation: Controls.ToolButton {
        icon.name: "network-vpn"
        highlighted: controller.active
        Accessible.name: qsTr("WProxy VPN controls")
        onClicked: root.expanded = !root.expanded
    }

    fullRepresentation: Popup { backend: controller }
    onExpandedChanged: if (expanded) controller.refresh()
}
