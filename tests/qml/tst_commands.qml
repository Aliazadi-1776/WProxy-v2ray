import QtQuick
import QtTest
import "../../kde-plasmoid/org.wproxy.WProxy/contents/ui" as WProxy

TestCase {
    id: testCase
    name: "CommandRunner"
    when: windowShown
    WProxy.CommandRunner { id: runner }
    SignalSpy { id: completed; target: runner; signalName: "completed" }
    property var pids: []
    Connections {
        target: runner
        function onCompleted(token, code, output, error) {
            if (token !== "repeat") return;
            testCase.pids = testCase.pids.concat([output]);
            if (testCase.pids.length < 4)
                runner.run("repeat", ["/bin/sh", "-c", "printf '%s' $$"]);
        }
    }

    function init() { completed.clear(); pids = []; }
    function cleanup() {
        for (const source of Object.keys(runner.jobs)) runner.take(source);
    }

    function test_missing_executable_reports_failure_without_timeout() {
        verify(runner.run("missing", ["/wproxy-test/nonexistent-command"]));
        tryCompare(completed, "count", 1, 2000);
        compare(completed.signalArguments[0][1], 127);
        verify(completed.signalArguments[0][3].indexOf("nonexistent-command") >= 0);
        compare(runner.activeJobs, 0);
    }

    function test_immediate_repeat_executes_fresh_process() {
        verify(runner.run("repeat", ["/bin/sh", "-c", "printf '%s' $$"]));
        tryVerify(function() { return pids.length === 4; }, 3000);
        compare(new Set(pids).size, 4);
        compare(runner.activeJobs, 0);
    }

    function test_duplicate_inflight_command_is_not_started() {
        verify(runner.run("slow", ["/bin/sleep", "0.1"]));
        verify(!runner.run("duplicate", ["/bin/sleep", "0.1"]));
        tryCompare(completed, "count", 1, 1000);
        compare(completed.signalArguments[0][0], "slow");
        compare(runner.activeJobs, 0);
    }

    function test_detached_application_does_not_wait_for_window_to_close() {
        verify(runner.run("manager", ["/bin/sleep", "2"], true));
        tryCompare(completed, "count", 1, 1000);
        compare(completed.signalArguments[0][1], 0);
        compare(runner.activeJobs, 0);
    }

    function test_missing_detached_application_reports_failure() {
        verify(runner.run("manager", ["/wproxy-test/nonexistent-manager"], true));
        tryCompare(completed, "count", 1, 1000);
        compare(completed.signalArguments[0][1], 127);
        verify(completed.signalArguments[0][3].indexOf("nonexistent-manager") >= 0);
    }

    function test_timeout_completes_once_and_drops_late_output() {
        verify(runner.run("timeout", ["/bin/sleep", "0.2"]));
        runner.jobs[Object.keys(runner.jobs)[0]].started = 0;
        runner.watchdog.triggered();
        compare(completed.count, 1);
        compare(completed.signalArguments[0][1], 124);
        wait(300);
        compare(completed.count, 1);
        compare(runner.activeJobs, 0);
    }

    function test_literal_arguments() {
        const payload = "https://example.invalid/sub?a=';$(printf INJECTED)\n&b=\"quoted\"";
        verify(runner.run("literal", ["/usr/bin/printf", "%s", payload]));
        completed.wait(5000);
        compare(completed.signalArguments[0][0], "literal");
        compare(completed.signalArguments[0][1], 0);
        compare(completed.signalArguments[0][2], payload);
    }

    function test_failed_command() {
        verify(runner.run("failure", ["/bin/sh", "-c", "printf denied >&2; exit 7"]));
        completed.wait(5000);
        compare(completed.signalArguments[0][1], 7);
        compare(completed.signalArguments[0][3], "denied");
    }
}
