#include <gio/gio.h>
#include <NetworkManager.h>
#include <gmodule.h>
#include <glib.h>

#define WPROXY_SERVICE "org.freedesktop.NetworkManager.wproxy"
#define WPROXY_NAME "WProxy"
#define WPROXY_DESC "Xray / V2Ray VPN"

#ifndef WPROXY_PLUGIN_DIR
#define WPROXY_PLUGIN_DIR "/usr/lib/NetworkManager"
#endif

typedef struct {
    GObject parent;
} WProxyPlugin;

typedef struct {
    GObjectClass parent_class;
} WProxyPluginClass;

enum {
    PROP_0,
    PROP_NAME,
    PROP_DESCRIPTION,
    PROP_SERVICE,
};

static void wproxy_plugin_iface_init(NMVpnEditorPluginInterface *iface);

G_DEFINE_TYPE_WITH_CODE(
    WProxyPlugin,
    wproxy_plugin,
    G_TYPE_OBJECT,
    G_IMPLEMENT_INTERFACE(NM_TYPE_VPN_EDITOR_PLUGIN,
                          wproxy_plugin_iface_init))

typedef NMVpnEditor *(*WProxyEditorFactory)(NMVpnEditorPlugin *plugin,
                                             NMConnection *connection,
                                             GError **error);

/* Keep editor modules resident for the lifetime of the hosting process. */
static GPtrArray *loaded_modules;

static gboolean host_is_gtk3(void)
{
    gpointer gtk3_symbol = NULL;
    GModule *self = g_module_open(NULL, 0);
    if (!self)
        return FALSE;

    gboolean gtk3 = g_module_symbol(self, "gtk_container_add", &gtk3_symbol) && gtk3_symbol;
    g_module_close(self);
    return gtk3;
}

static NMVpnEditor *plugin_get_editor(NMVpnEditorPlugin *plugin,
                                      NMConnection *connection,
                                      GError **error)
{
    const char *module_name = host_is_gtk3()
        ? "libnm-vpn-plugin-wproxy-editor.so"
        : "libnm-gtk4-vpn-plugin-wproxy-editor.so";

    gchar *module_path = g_build_filename(WPROXY_PLUGIN_DIR, module_name, NULL);
    GModule *module = g_module_open(module_path, G_MODULE_BIND_LAZY | G_MODULE_BIND_LOCAL);
    if (!module) {
        g_set_error(error, G_IO_ERROR, G_IO_ERROR_FAILED,
                    "Could not load WProxy editor module %s: %s",
                    module_path, g_module_error());
        g_free(module_path);
        return NULL;
    }

    gpointer symbol = NULL;
    if (!g_module_symbol(module, "nm_vpn_editor_factory_wproxy", &symbol) || !symbol) {
        g_set_error(error, G_IO_ERROR, G_IO_ERROR_FAILED,
                    "WProxy editor module is missing its factory: %s",
                    g_module_error());
        g_module_close(module);
        g_free(module_path);
        return NULL;
    }

    if (!loaded_modules)
        loaded_modules = g_ptr_array_new();
    g_ptr_array_add(loaded_modules, module);

    WProxyEditorFactory factory = (WProxyEditorFactory)symbol;
    NMVpnEditor *editor = factory(plugin, connection, error);
    g_free(module_path);
    return editor;
}

static NMVpnEditorPluginCapability plugin_get_capabilities(NMVpnEditorPlugin *plugin)
{
    (void)plugin;
#ifdef NM_VPN_EDITOR_PLUGIN_CAPABILITY_IPV6
    return NM_VPN_EDITOR_PLUGIN_CAPABILITY_IPV6;
#else
    return NM_VPN_EDITOR_PLUGIN_CAPABILITY_NONE;
#endif
}

static void wproxy_plugin_get_property(GObject *object,
                                       guint prop_id,
                                       GValue *value,
                                       GParamSpec *pspec)
{
    (void)object;
    switch (prop_id) {
    case PROP_NAME:
        g_value_set_string(value, WPROXY_NAME);
        break;
    case PROP_DESCRIPTION:
        g_value_set_string(value, WPROXY_DESC);
        break;
    case PROP_SERVICE:
        g_value_set_string(value, WPROXY_SERVICE);
        break;
    default:
        G_OBJECT_WARN_INVALID_PROPERTY_ID(object, prop_id, pspec);
    }
}

static void wproxy_plugin_class_init(WProxyPluginClass *klass)
{
    GObjectClass *object_class = G_OBJECT_CLASS(klass);
    object_class->get_property = wproxy_plugin_get_property;

    g_object_class_override_property(object_class, PROP_NAME,
                                     NM_VPN_EDITOR_PLUGIN_NAME);
    g_object_class_override_property(object_class, PROP_DESCRIPTION,
                                     NM_VPN_EDITOR_PLUGIN_DESCRIPTION);
    g_object_class_override_property(object_class, PROP_SERVICE,
                                     NM_VPN_EDITOR_PLUGIN_SERVICE);
}

static void wproxy_plugin_init(WProxyPlugin *self)
{
    (void)self;
}

static void wproxy_plugin_iface_init(NMVpnEditorPluginInterface *iface)
{
    iface->get_editor = plugin_get_editor;
    iface->get_capabilities = plugin_get_capabilities;
}

G_MODULE_EXPORT NMVpnEditorPlugin *
nm_vpn_editor_plugin_factory(GError **error)
{
    if (error)
        *error = NULL;
    return NM_VPN_EDITOR_PLUGIN(g_object_new(wproxy_plugin_get_type(), NULL));
}
