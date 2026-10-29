#include "compat/vpnuiplugin.h"

#include <QLabel>
#include <QLineEdit>
#include <QProcess>
#include <QPushButton>
#include <QVBoxLayout>

class WProxySettingWidget final : public SettingWidget {
    Q_OBJECT
public:
    WProxySettingWidget(const NetworkManager::VpnSetting::Ptr &vpn, QWidget *parent)
        : SettingWidget(vpn, parent), m_values(vpn->toMap()) {
        auto *layout = new QVBoxLayout(this);
        auto *description = new QLabel(tr("This connection is managed by WProxy. Open WProxy to change servers or routing."), this);
        description->setWordWrap(true);
        layout->addWidget(description);
        auto *uri = new QLineEdit(this);
        uri->setAccessibleName(tr("Saved proxy configuration, hidden"));
        uri->setEchoMode(QLineEdit::Password);
        uri->setReadOnly(true);
        uri->setText(vpn->data().value(QStringLiteral("uri")));
        layout->addWidget(uri);
        auto *open = new QPushButton(tr("Open WProxy"), this);
        connect(open, &QPushButton::clicked, this, [] {
            QProcess::startDetached(QStringLiteral("/usr/bin/wproxy-manager"), {});
        });
        layout->addWidget(open);
    }

    QVariantMap setting() const override { return m_values; }

private:
    const QVariantMap m_values;
};

class WProxyUiPlugin final : public VpnUiPlugin {
    Q_OBJECT
public:
    explicit WProxyUiPlugin(QObject *parent = nullptr, const QVariantList & = {})
        : VpnUiPlugin(parent) {}

    SettingWidget *widget(const NetworkManager::VpnSetting::Ptr &vpn, QWidget *parent) override {
        return new WProxySettingWidget(vpn, parent);
    }

    SettingWidget *askUser(const NetworkManager::VpnSetting::Ptr &vpn, const QStringList &, QWidget *parent) override {
        // Credentials are already in the private saved profile; no extra secret is needed.
        return new WProxySettingWidget(vpn, parent);
    }

    QString suggestedFileName(const NetworkManager::ConnectionSettings::Ptr &connection) const override {
        return connection->id() + QStringLiteral(".wproxy");
    }
};

K_PLUGIN_CLASS_WITH_JSON(WProxyUiPlugin, "metadata.json")

#include "wproxy.moc"
