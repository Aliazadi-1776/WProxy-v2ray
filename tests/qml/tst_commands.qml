import QtQuick
import QtTest
import "../../kde-plasmoid/org.wproxy.WProxy/contents/ui" as WProxy

TestCase {
    id: testCase
    name: "CommandRunner"
    when: windowShown
    WProxy.CommandRunner { id: runner }
    SignalSpy { id: completed; target: runner; signalName: "completed" }

    function init() { completed.clear(); }

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
