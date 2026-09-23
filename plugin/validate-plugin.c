#include <NetworkManager.h>
#include <gmodule.h>
#include <stdio.h>

typedef NMVpnEditorPlugin *(*Factory)(GError **error);

int main(int argc, char **argv)
{
    if (argc != 2) {
        fprintf(stderr, "usage: %s /path/to/libnm-vpn-plugin-wproxy.so\n", argv[0]);
        return 2;
    }

    GModule *m = g_module_open(argv[1], G_MODULE_BIND_LOCAL);
    if (!m) {
        fprintf(stderr, "LOAD FAILED: %s\n", g_module_error());
        return 1;
    }

    Factory factory = NULL;
    if (!g_module_symbol(m, "nm_vpn_editor_plugin_factory",
                         (gpointer *)&factory) || !factory) {
        fprintf(stderr, "FACTORY MISSING: nm_vpn_editor_plugin_factory\n");
        g_module_close(m);
        return 1;
    }

    GError *error = NULL;
    NMVpnEditorPlugin *plugin = factory(&error);
    if (!plugin) {
        fprintf(stderr, "FACTORY FAILED: %s\n",
                error ? error->message : "unknown");
        g_clear_error(&error);
        g_module_close(m);
        return 1;
    }

    char *name = NULL;
    char *description = NULL;
    char *service = NULL;

    g_object_get(plugin,
                 NM_VPN_EDITOR_PLUGIN_NAME, &name,
                 NM_VPN_EDITOR_PLUGIN_DESCRIPTION, &description,
                 NM_VPN_EDITOR_PLUGIN_SERVICE, &service,
                 NULL);

    printf("OK\n");
    printf("name=%s\n", name ? name : "(null)");
    printf("description=%s\n", description ? description : "(null)");
    printf("service=%s\n", service ? service : "(null)");

    if (!service || !g_str_equal(service,
                                 "org.freedesktop.NetworkManager.wproxy")) {
        fprintf(stderr, "SERVICE MISMATCH\n");
        g_free(name);
        g_free(description);
        g_free(service);
        g_object_unref(plugin);
        g_module_close(m);
        return 1;
    }

    g_free(name);
    g_free(description);
    g_free(service);
    g_object_unref(plugin);
    g_module_close(m);
    return 0;
}
