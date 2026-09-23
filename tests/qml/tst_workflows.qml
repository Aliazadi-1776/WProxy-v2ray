import QtQuick
import QtTest
import "../../kde-plasmoid/org.wproxy.WProxy/contents/ui" as WProxy

TestCase {
    name: "DesktopWorkflows"
    when: windowShown

    QtObject {
        id: fake
        property var calls: []
        signal completed(string token, int exitCode, string output, string error)
        function run(token, args) {
            calls = calls.concat([{token: token, args: args}]);
            return true;
        }
    }
    WProxy.Backend { id: backend; pollingEnabled: false; executor: fake }

    function init() {
        fake.calls = [];
        backend.busy = false;
        backend.errorMessage = "";
        backend.connectingId = "";
        backend.pinging = {};
        backend.nodes = [{id: "one", name: "One"}];
    }

    function test_connect_missing_profile_sync_and_retry_once() {
        backend.connectNode("one");
        compare(fake.calls[0].args.join("|"), "/usr/bin/wproxyctl|nm|up|one");
        verify(backend.busy);
        fake.completed("connect", 1, "", "Unknown connection");
        compare(fake.calls[1].args.join("|"), "/usr/bin/pkexec|/usr/bin/wproxyctl|nm|sync");
        fake.completed("connect-sync", 0, "", "");
        compare(fake.calls[2].token, "connect");
        fake.completed("connect", 1, "", "Unknown connection");
        verify(!backend.busy);
        compare(fake.calls.filter(function(c) { return c.token === "connect-sync"; }).length, 1);
    }

    function test_polkit_cancel_does_not_retry_connection() {
        backend.connectNode("one");
        fake.completed("connect", 1, "", "Unknown connection");
        fake.completed("connect-sync", 126, "", "Authentication cancelled");
        verify(!backend.busy);
        compare(backend.errorMessage, "Authentication cancelled");
        compare(fake.calls.filter(function(c) { return c.token === "connect"; }).length, 1);
    }

    function test_generic_activation_error_does_not_sync() {
        backend.connectNode("one");
        fake.completed("connect", 1, "", "Connection activation failed: Unknown reason");
        verify(!backend.busy);
        compare(fake.calls.filter(function(c) { return c.token === "connect-sync"; }).length, 0);
    }

    function test_subscription_chain() {
        const url = "https://example.invalid/sub?a='&b=$(x)";
        backend.addSubscription(url);
        compare(fake.calls[0].args[3], url);
        fake.completed("sub-add", 0, "new-sub-id\n", "");
        compare(fake.calls[1].args.join("|"), "/usr/bin/wproxyctl|sub|update|new-sub-id");
        fake.completed("sub-update", 0, "", "");
        compare(fake.calls[2].token, "sub-sync");
        fake.completed("sub-sync", 0, "", "");
        verify(!backend.busy);
        compare(backend.errorMessage, "");
    }

    function test_no_duplicate_ping_all() {
        backend.pingAll();
        backend.pingAll();
        compare(fake.calls.length, 1);
        fake.completed("ping-all", 0, '[{"id":"one","latency_ms":null}]', "");
        compare(Object.keys(backend.pinging).length, 0);
        compare(backend.latencies.one, null);
    }
}
