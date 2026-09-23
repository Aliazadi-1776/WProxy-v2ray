#include <gio/gio.h>
#include <gtk/gtk.h>
#include <NetworkManager.h>
#include <gmodule.h>

#define WPROXY_SERVICE "org.freedesktop.NetworkManager.wproxy"
#define WPROXY_NAME "WProxy"
#define WPROXY_VERSION "2.2"

typedef struct {
    GObject parent;
    GtkWidget *box;
    GtkWidget *name_entry;
    GtkWidget *uri_entry;
    GtkWidget *hint_label;
} WProxyEditor;

typedef struct {
    GObjectClass parent_class;
} WProxyEditorClass;

static GObject *editor_get_widget(NMVpnEditor *editor);
static gboolean editor_update_connection(NMVpnEditor *editor,
                                         NMConnection *connection,
                                         GError **error);
static void wproxy_editor_iface_init(NMVpnEditorInterface *iface);

G_DEFINE_TYPE_WITH_CODE(
    WProxyEditor,
    wproxy_editor,
    G_TYPE_OBJECT,
    G_IMPLEMENT_INTERFACE(NM_TYPE_VPN_EDITOR, wproxy_editor_iface_init))

#if GTK_MAJOR_VERSION >= 4
static void add_css_class(GtkWidget *widget, const char *klass)
{
    gtk_widget_add_css_class(widget, klass);
}
static void box_append(GtkWidget *box, GtkWidget *child)
{
    gtk_box_append(GTK_BOX(box), child);
}
static const char *entry_text(GtkWidget *entry)
{
    return gtk_editable_get_text(GTK_EDITABLE(entry));
}
static void entry_set_text(GtkWidget *entry, const char *text)
{
    gtk_editable_set_text(GTK_EDITABLE(entry), text ? text : "");
}
static void label_set_wrap(GtkWidget *label)
{
    gtk_label_set_wrap(GTK_LABEL(label), TRUE);
}
#else
static void add_css_class(GtkWidget *widget, const char *klass)
{
    GtkStyleContext *ctx = gtk_widget_get_style_context(widget);
    gtk_style_context_add_class(ctx, klass);
}
static void box_append(GtkWidget *box, GtkWidget *child)
{
    gtk_box_pack_start(GTK_BOX(box), child, FALSE, FALSE, 0);
}
static const char *entry_text(GtkWidget *entry)
{
    return gtk_entry_get_text(GTK_ENTRY(entry));
}
static void entry_set_text(GtkWidget *entry, const char *text)
{
    gtk_entry_set_text(GTK_ENTRY(entry), text ? text : "");
}
static void label_set_wrap(GtkWidget *label)
{
    gtk_label_set_line_wrap(GTK_LABEL(label), TRUE);
}
#endif

static GtkWidget *make_label(const char *text, gboolean dim)
{
    GtkWidget *label = gtk_label_new(text);
    gtk_widget_set_halign(label, GTK_ALIGN_START);
    gtk_widget_set_hexpand(label, TRUE);
    gtk_label_set_xalign(GTK_LABEL(label), 0.0f);
    label_set_wrap(label);
    if (dim)
        add_css_class(label, "dim-label");
    return label;
}

static void editor_changed(GtkEditable *editable, gpointer user_data)
{
    (void)editable;
    g_signal_emit_by_name(user_data, "changed");
}

static void open_manager_clicked(GtkButton *button, gpointer user_data)
{
    (void)button;
    (void)user_data;

    GError *error = NULL;
    if (!g_spawn_command_line_async("wproxy-manager", &error)) {
        g_warning("Could not launch WProxy Manager: %s", error->message);
        g_clear_error(&error);
    }
}

static GObject *editor_get_widget(NMVpnEditor *editor)
{
    WProxyEditor *self = (WProxyEditor *)editor;
    return G_OBJECT(self->box);
}

static gboolean valid_uri(const char *uri)
{
    if (!uri)
        return FALSE;

    while (g_ascii_isspace(*uri))
        uri++;

    return g_str_has_prefix(uri, "vless://") ||
           g_str_has_prefix(uri, "vmess://") ||
           g_str_has_prefix(uri, "trojan://") ||
           g_str_has_prefix(uri, "ss://");
}

static gboolean editor_update_connection(NMVpnEditor *editor,
                                         NMConnection *connection,
                                         GError **error)
{
    WProxyEditor *self = (WProxyEditor *)editor;
    const char *id = entry_text(self->name_entry);
    const char *uri = entry_text(self->uri_entry);

    if (!valid_uri(uri)) {
        g_set_error(error, G_IO_ERROR, G_IO_ERROR_INVALID_ARGUMENT,
                    "Paste one VLESS, VMess, Trojan or Shadowsocks share link.");
        return FALSE;
    }

    NMSettingConnection *s_con = nm_connection_get_setting_connection(connection);
    if (!s_con) {
        s_con = (NMSettingConnection *)nm_setting_connection_new();
        nm_connection_add_setting(connection, NM_SETTING(s_con));
    }

    g_object_set(G_OBJECT(s_con),
                 NM_SETTING_CONNECTION_ID,
                 (id && *id) ? id : WPROXY_NAME,
                 NM_SETTING_CONNECTION_TYPE,
                 NM_SETTING_VPN_SETTING_NAME,
                 NULL);

    NMSettingVpn *vpn = nm_connection_get_setting_vpn(connection);
    if (!vpn) {
        vpn = (NMSettingVpn *)nm_setting_vpn_new();
        nm_connection_add_setting(connection, NM_SETTING(vpn));
    }

    g_object_set(G_OBJECT(vpn),
                 NM_SETTING_VPN_SERVICE_TYPE,
                 WPROXY_SERVICE,
                 NM_SETTING_VPN_USER_NAME,
                 uri,
                 NULL);

    nm_setting_vpn_add_data_item(vpn, "uri", uri);
    nm_setting_vpn_add_data_item(vpn, "wproxy-version", WPROXY_VERSION);
    return TRUE;
}

static void wproxy_editor_iface_init(NMVpnEditorInterface *iface)
{
    iface->get_widget = editor_get_widget;
    iface->update_connection = editor_update_connection;
}

static void wproxy_editor_class_init(WProxyEditorClass *klass)
{
    (void)klass;
}

static void wproxy_editor_init(WProxyEditor *self)
{
    self->box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 10);
    gtk_widget_set_margin_top(self->box, 18);
    gtk_widget_set_margin_bottom(self->box, 18);
    gtk_widget_set_margin_start(self->box, 18);
    gtk_widget_set_margin_end(self->box, 18);
    gtk_widget_set_hexpand(self->box, TRUE);

    GtkWidget *title = make_label("WProxy", FALSE);
    add_css_class(title, "title-2");
    box_append(self->box, title);

    GtkWidget *subtitle = make_label(
        "Xray / V2Ray connection managed by NetworkManager", TRUE);
    box_append(self->box, subtitle);

    GtkWidget *separator_top = gtk_separator_new(GTK_ORIENTATION_HORIZONTAL);
    box_append(self->box, separator_top);

    GtkWidget *name_label = make_label("Connection name", FALSE);
    box_append(self->box, name_label);

    self->name_entry = gtk_entry_new();
    gtk_entry_set_placeholder_text(GTK_ENTRY(self->name_entry), "WProxy");
    gtk_widget_set_hexpand(self->name_entry, TRUE);
    box_append(self->box, self->name_entry);

    GtkWidget *uri_label = make_label("Share link", FALSE);
    box_append(self->box, uri_label);

    self->uri_entry = gtk_entry_new();
    gtk_entry_set_placeholder_text(GTK_ENTRY(self->uri_entry),
                                   "vless://...   vmess://...   trojan://...   ss://...");
    gtk_widget_set_hexpand(self->uri_entry, TRUE);
    box_append(self->box, self->uri_entry);

    self->hint_label = make_label(
        "This profile appears in Settings > Network > VPN and can be connected like a normal VPN. "
        "For subscription URLs and the full server list, use WProxy Manager; imported servers are synced back as individual NetworkManager VPN profiles.",
        TRUE);
    box_append(self->box, self->hint_label);

    GtkWidget *manager_button = gtk_button_new_with_label("Manage subscriptions and servers");
    gtk_widget_set_halign(manager_button, GTK_ALIGN_START);
    g_signal_connect(manager_button, "clicked", G_CALLBACK(open_manager_clicked), self);
    box_append(self->box, manager_button);

    g_signal_connect(self->name_entry, "changed", G_CALLBACK(editor_changed), self);
    g_signal_connect(self->uri_entry, "changed", G_CALLBACK(editor_changed), self);
}

G_MODULE_EXPORT NMVpnEditor *
nm_vpn_editor_factory_wproxy(NMVpnEditorPlugin *plugin,
                             NMConnection *connection,
                             GError **error)
{
    (void)plugin;
    if (error)
        *error = NULL;

    WProxyEditor *editor = g_object_new(wproxy_editor_get_type(), NULL);
    if (!editor) {
        g_set_error(error, G_IO_ERROR, G_IO_ERROR_FAILED,
                    "Could not create WProxy editor.");
        return NULL;
    }

    if (connection) {
        NMSettingConnection *s_con = nm_connection_get_setting_connection(connection);
        if (s_con) {
            const char *id = nm_setting_connection_get_id(s_con);
            if (id)
                entry_set_text(editor->name_entry, id);
        }

        NMSettingVpn *vpn = nm_connection_get_setting_vpn(connection);
        if (vpn) {
            const char *uri = nm_setting_vpn_get_data_item(vpn, "uri");
            if (uri)
                entry_set_text(editor->uri_entry, uri);
        }
    }

    return NM_VPN_EDITOR(editor);
}
