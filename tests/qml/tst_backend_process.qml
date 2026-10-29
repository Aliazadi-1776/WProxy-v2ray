import QtQuick
import QtTest
import "../../kde-plasmoid/org.wproxy.WProxy/contents/ui" as WProxy

TestCase {
    id: testCase
    name: "BackendRealProcesses"
    when: windowShown
    readonly property string fixture: decodeURIComponent(Qt.resolvedUrl("fixtures/desktop-command.sh").toString().replace(/^file:\/\//, ""))
    WProxy.Backend { id: backend; cliPath: testCase.fixture; pkexecPath: testCase.fixture }
    SignalSpy { id: completed; target: backend.executor; signalName: "completed" }

    function init() {
        backend.errorMessage = "";
        completed.clear();
    }

    function finish() {
        tryCompare(backend, "busy", false, 3000);
        tryCompare(backend.executor, "activeJobs", 0, 3000);
    }

    function completions(token) {
        return completed.signalArguments.filter(function(args) { return args[0] === token; });
    }

    function test_repeated_connect_uses_fresh_scoped_helper_process() {
        const pids = [];
        for (let index = 0; index < 4; index++) {
            completed.clear();
            backend.connectNode("0123456789abcdef");
            finish();
            compare(backend.errorMessage, "");
            const results = completions("connect");
            compare(results.length, 1);
            compare(results[0][1], 0);
            verify(results[0][2].indexOf("Helper up-remember 0123456789abcdef") >= 0);
            pids.push(results[0][2]);
        }
        compare(new Set(pids).size, 4);
    }

    function test_successful_deactivation_output_is_not_an_error() {
        backend.errorMessage = "Previous failure";
        backend.disconnect();
        finish();
        compare(backend.errorMessage, "");
        compare(completions("disconnect")[0][1], 0);
        verify(completions("disconnect")[0][2].indexOf("successfully deactivated") >= 0);
    }

    function test_cancelled_approval_finishes_without_retry() {
        backend.connectNode("0000000000000001");
        finish();
        compare(backend.errorMessage, "Authentication cancelled");
        compare(completions("connect").length, 1);
    }

    function test_subscription_sync_uses_same_scoped_helper() {
        backend.addSubscription("https://example.invalid/sub?a='&b=$(fixture)");
        finish();
        compare(backend.errorMessage, "");
        compare(completions("sub-sync")[0][1], 0);
        compare(completions("sub-sync")[0][2].trim(), "Helper profiles synced");
    }
}
