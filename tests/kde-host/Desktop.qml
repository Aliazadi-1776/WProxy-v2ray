import QtQuick

Rectangle {
    id: root
    width: 620
    height: 700
    color: "#20242a"
    property Item containment
    property var serverList: null
    property var footer: null
    property var popup: null
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
        if (item.objectName === "wproxyPopup") popup = item;
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
            if (root.serverList && root.serverList.count === 100 && root.footer && root.popup) {
                stop();
                const appletContainer = root.popup.parent.parent;
                appletContainer.height = root.popup.implicitHeight + root.popup.parent.y * 2;
                appletContainer.x = Math.round((root.width - appletContainer.width) / 2);
                appletContainer.y = Math.round((root.height - appletContainer.height) / 2);
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
            const footerBottom = root.footer.mapToItem(root, root.footer.width, root.footer.height);
            const footerInsideViewport = footerBottom.x <= root.width && footerBottom.y <= root.height;
            const ok = list.visible && list.atYEnd
                && Math.abs(list.height - rowHeight * 3) < 1
                && root.footer.visible && root.footer.y >= list.y + list.height
                && footerInsideViewport;
            root.grabToImage(function(result) {
                const saved = result.saveToFile(root.evidenceDirectory + "/widget-100-last.png");
                root.popup.backend.active = true;
                root.popup.backend.activeId = root.popup.backend.nodes[99].id;
                root.connectedResult = {
                    ok: ok && saved,
                    servers: list.count,
                    visibleRows: Math.round(list.height / rowHeight),
                    lastRowAccessible: list.atYEnd,
                    footerOutsideScroll: root.footer.y >= list.y + list.height,
                    footerInsideViewport: footerInsideViewport,
                    screenshot: saved
                };
                captureConnected.start();
            });
        }
    }

    property var connectedResult
    Timer {
        id: captureConnected
        interval: 500
        onTriggered: root.grabToImage(function(result) {
            root.connectedResult.connectedScreenshot = result.saveToFile(root.evidenceDirectory + "/widget-connected.png");
            root.connectedResult.ok = root.connectedResult.ok && root.connectedResult.connectedScreenshot;
            root.popup.backend.active = false;
            root.popup.backend.activeId = "";
            root.popup.backend.errorMessage = "The connection could not be started. Try another server.";
            captureError.start();
        })
    }

    Timer {
        id: captureError
        interval: 500
        onTriggered: root.grabToImage(function(result) {
            const bottom = root.footer.mapToItem(root, root.footer.width, root.footer.height);
            const popupBottom = root.footer.mapToItem(root.popup, root.footer.width, root.footer.height);
            root.connectedResult.errorScreenshot = result.saveToFile(root.evidenceDirectory + "/widget-error.png");
            root.connectedResult.errorFooterInsideViewport = bottom.x <= root.width && bottom.y <= root.height;
            root.connectedResult.errorFooterInsidePopup = popupBottom.x <= root.popup.width && popupBottom.y <= root.popup.height;
            root.connectedResult.ok = root.connectedResult.ok && root.connectedResult.errorScreenshot
                && root.connectedResult.errorFooterInsideViewport && root.connectedResult.errorFooterInsidePopup;
            print("WPROXY_HOST_SMOKE", JSON.stringify(root.connectedResult));
            desktop.close();
        })
    }
}
