import QtQuick
import QtTest
import "../../kde-plasmoid/org.wproxy.WProxy/contents/ui" as WProxy

Item {
    width: 600
    height: 760

    Item {
        id: fixture
        property bool active: false
        property bool busy: false
        property string activeId: ""
        property string connectingId: ""
        property string errorMessage: ""
        property string traffic: "4.84 GB left"
        property var nodes: []
        property var latencies: ({})
        property var pinging: ({})
        property string selected: ""
        signal subscriptionAdded()
        function connectNode(id) { selected = id; }
        function toggleConnection() {}
        function pingNode(id) {}
        function pingAll() {}
        function updateSubscriptions() {}
        function addSubscription(url) {}
        function openManager() {}
    }

    WProxy.Popup {
        id: popup
        backend: fixture
        width: 420
        height: implicitHeight
    }

    TestCase {
        name: "ThreeRowPopup"
        when: windowShown

        function init() {
            fixture.nodes = [];
            fixture.selected = "";
            fixture.latencies = {};
        }

        function test_viewport_data() {
            return [0, 1, 3, 4, 100].map(function(count) { return {tag: String(count), count: count}; });
        }

        function test_viewport(data) {
            fixture.nodes = Array.from({length: data.count}, function(_, index) {
                return {id: "server-" + index, name: "🇩🇪 Example server " + index};
            });
            const list = findChild(popup, "serverList");
            tryCompare(list, "count", data.count);
            waitForRendering(popup);
            compare(list.height, Math.max(1, Math.min(3, data.count)) * popup.rowHeight);
            const footer = findChild(popup, "fixedActions");
            verify(footer.y >= list.y + list.height, "Footer must remain outside the scrolling list");
            verify(popup.height < 700, "Controls must fit in a short popup");
            if (data.count > 3) {
                list.positionViewAtEnd();
                waitForRendering(popup);
                verify(list.atYEnd, "Last server must be reachable");
                const position = list.contentY;
                fixture.latencies = {"server-0": 42};
                waitForRendering(popup);
                compare(list.contentY, position, "Ping update must not reset scrolling");
            }
        }

        function test_select_server() {
            fixture.nodes = [{id: "one", name: "One"}, {id: "two", name: "Two"}];
            const list = findChild(popup, "serverList");
            tryCompare(list, "count", 2);
            waitForRendering(popup);
            const row = list.itemAtIndex(1);
            verify(row !== null);
            mouseClick(row, 35, row.height / 2);
            compare(fixture.selected, "two");
        }
    }
}
