#include "compat/vpnuiplugin.h"

#include <QApplication>
#include <QLineEdit>
#include <KPluginMetaData>
#include <memory>

int main(int argc, char **argv) {
    QApplication app(argc, argv);
    if (argc != 2)
        qFatal("Expected plugin search root");
    QCoreApplication::addLibraryPath(QString::fromLocal8Bit(argv[1]));
    const auto plugins = KPluginMetaData::findPlugins(QStringLiteral("plasma/network/vpn"), [](const KPluginMetaData &metadata) {
        return metadata.value(QStringLiteral("X-NetworkManager-Services")) == QStringLiteral("org.freedesktop.NetworkManager.wproxy");
    });
    if (plugins.size() != 1)
        qFatal("Expected exactly one native WProxy VPN plugin");
    const auto result = KPluginFactory::instantiatePlugin<VpnUiPlugin>(plugins.first(), &app);
    if (!result)
        qFatal("WProxy VPN factory failed: %s", qPrintable(result.errorString));
    auto vpn = NetworkManager::VpnSetting::Ptr::create();
    vpn->setServiceType(QStringLiteral("org.freedesktop.NetworkManager.wproxy"));
    vpn->setData({{QStringLiteral("uri"), QStringLiteral("trojan://fixture-secret@example.invalid:443")},
                  {QStringLiteral("routing64"), QStringLiteral("fixture-routing-policy")},
                  {QStringLiteral("node-id"), QStringLiteral("0123456789abcdef")},
                  {QStringLiteral("custom-preserved"), QStringLiteral("fixture-value")}});
    const auto expected = vpn->toMap();
    std::unique_ptr<SettingWidget> editor(result.plugin->widget(vpn, nullptr));
    std::unique_ptr<SettingWidget> auth(result.plugin->askUser(vpn, {}, nullptr));
    if (!editor || !auth || editor->setting() != expected || auth->setting() != expected)
        qFatal("Native widget lost VPN settings");
    const auto entries = editor->findChildren<QLineEdit *>();
    if (entries.size() != 1 || entries.first()->echoMode() != QLineEdit::Password || !entries.first()->isReadOnly())
        qFatal("Proxy credentials must stay hidden and managed by WProxy");
    qInfo("Native Plasma WProxy metadata, factory, editor/auth widgets and settings preservation: PASS");
    return 0;
}
