const wproxyWidgetId = "org.wproxy.WProxy";
const systemTrayId = "org.kde.plasma.systemtray";

function widgetsOfType(containment, type) {
    const widgets = [];
    containment.widgetIds.forEach((id) => {
        const widget = containment.widgetById(id);
        if (widget && widget.type === type) {
            widgets.push(widget);
        }
    });
    return widgets;
}

function configItems(value) {
    if (value === undefined || value === null || value === "") {
        return [];
    }
    return String(value).split(",").filter((item) => item.length > 0);
}

function uniqueItems(items) {
    return items.filter((item, index) => items.indexOf(item) === index);
}

let removed = 0;

panels().forEach((panel) => {
    let trayOwnsWProxy = false;

    widgetsOfType(panel, systemTrayId).forEach((trayApplet) => {
        const containmentId = trayApplet.readConfig("SystrayContainmentId");
        const tray = containmentId ? desktopById(containmentId) : null;
        if (!tray) {
            return;
        }

        tray.currentConfigGroup = ["General"];
        const configuredItems = configItems(tray.readConfig("extraItems"));
        const deduplicatedItems = uniqueItems(configuredItems);
        if (configuredItems.length !== deduplicatedItems.length) {
            tray.writeConfig("extraItems", deduplicatedItems);
            tray.reloadConfig();
        }

        const trayWidgets = widgetsOfType(tray, wproxyWidgetId);
        trayOwnsWProxy = trayOwnsWProxy
            || deduplicatedItems.indexOf(wproxyWidgetId) !== -1
            || trayWidgets.length > 0;
        trayWidgets.slice(1).forEach((widget) => {
            widget.remove();
            removed += 1;
        });
    });

    const panelWidgets = widgetsOfType(panel, wproxyWidgetId);
    const keep = trayOwnsWProxy ? 0 : 1;
    panelWidgets.slice(keep).forEach((widget) => {
        widget.remove();
        removed += 1;
    });
});

print(`WProxy panel cleanup: removed ${removed} duplicate widget(s).`);
