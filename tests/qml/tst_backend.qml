import QtQuick
import QtTest
import "../../kde-plasmoid/org.wproxy.WProxy/contents/ui" as WProxy

TestCase {
    name: "BackendState"
    when: windowShown
    WProxy.Backend { id: backend; pollingEnabled: false }

    function init() {
        backend.errorMessage = "";
        backend.pinging = {};
        backend.latencies = {};
    }

    function test_status() {
        backend.consume("status", 0, JSON.stringify({active: true, node_id: "abc", name: "WProxy · Example"}), "");
        compare(backend.active, true);
        compare(backend.activeId, "abc");
        compare(backend.activeName, "Example");
    }

    function test_unchanged_nodes_preserve_model() {
        const data = JSON.stringify([{id: "abc", name: "Example"}]);
        backend.consume("nodes", 0, data, "");
        const model = backend.nodes;
        backend.consume("nodes", 0, data, "");
        verify(backend.nodes === model);
    }

    function test_ping() {
        backend.pinging = {abc: true};
        backend.consume("ping:abc", 0, JSON.stringify([{id: "abc", latency_ms: 51}]), "");
        compare(backend.latencies.abc, 51);
        verify(!backend.pinging.abc);
    }

    function test_invalid_json() {
        backend.consume("nodes", 0, "not-json", "");
        verify(backend.errorMessage.indexOf("Invalid") >= 0);
    }

    function test_reject_subscription() {
        backend.addSubscription("file:///etc/passwd");
        verify(!backend.busy);
        verify(backend.errorMessage.length > 0);
    }
}
