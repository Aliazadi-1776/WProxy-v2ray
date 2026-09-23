import QtQuick
import QtTest

TestCase {
    name: "PlasmaEntrypoint"
    when: windowShown
    function test_main_component_compiles() {
        const component = Qt.createComponent("../../kde-plasmoid/org.wproxy.WProxy/contents/ui/main.qml");
        compare(component.status, Component.Ready, component.errorString());
    }
}
