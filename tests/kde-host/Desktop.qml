import QtQuick

Rectangle {
    id: root
    width: 620
    height: 700
    color: "#20242a"
    property Item containment
    property var serverList: null
    property var footer: null
    property int attempts: 0
    readonly property string evidenceDirectory: EVIDENCE_DIRECTORY

    onContainmentChanged: {
        containment.visible = true;
        containment.anchors.fill = root;
    }

    function inspect(item) {
        if (!item) return;
        if (typeof item.expanded === "boolean" && typeof item.compactRepresentation !== "undefined")
            item.expanded = true;
        if (item.objectName === "serverList") serverList = item;
        if (item.objectName === "fixedActions") footer = item;
        const children = item.children || [];
        for (let index = 0; index < children.length; index++) inspect(children[index]);
    }

    Timer {
        id: waitForApplet
        interval: 500
        repeat: true
        running: true
        onTriggered: {
            root.inspect(root.containment);
            if (root.serverList && root.serverList.count === 100 && root.footer) {
                stop();
                root.serverList.positionViewAtEnd();
                capture.start();
            } else if (++root.attempts === 20) {
                print("WPROXY_HOST_SMOKE", JSON.stringify({ok: false, reason: "Applet did not load 100 fixture servers"}));
                desktop.close();
            }
        }
    }

    Timer {
        id: capture
        interval: 500
        onTriggered: {
            const list = root.serverList;
            const rowHeight = list.contentHeight / list.count;
            const ok = list.visible && list.atYEnd
                && Math.abs(list.height - rowHeight * 3) < 1
                && root.footer.visible && root.footer.y >= list.y + list.height;
            root.grabToImage(function(result) {
                const saved = result.saveToFile(root.evidenceDirectory + "/widget-100-last.png");
                print("WPROXY_HOST_SMOKE", JSON.stringify({
                    ok: ok && saved,
                    servers: list.count,
                    visibleRows: Math.round(list.height / rowHeight),
                    lastRowAccessible: list.atYEnd,
                    footerOutsideScroll: root.footer.y >= list.y + list.height,
                    screenshot: saved
                }));
                desktop.close();
            });
        }
    }
}
