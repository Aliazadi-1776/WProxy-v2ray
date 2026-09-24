#include <gio/gio.h>
#include <glib.h>
#include <glib/gstdio.h>
#include <glib-unix.h>
#include <NetworkManager.h>
#include <ifaddrs.h>
#include <netinet/in.h>
#include <string.h>
#include <signal.h>

#define WPROXY_PATH "/org/freedesktop/NetworkManager/VPN/Plugin"
#define WPROXY_IFACE "org.freedesktop.NetworkManager.VPN.Plugin"
#define WPROXY_SERVICE_NAME "org.freedesktop.NetworkManager.wproxy"
#define WPROXY_READY_PATH "/run/wproxy/ready"
#define WPROXY_GATEWAY_PATH "/run/wproxy/gateway"
#ifndef WPROXY_SYSTEM_CONNECTIONS_DIR
#define WPROXY_SYSTEM_CONNECTIONS_DIR "/etc/NetworkManager/system-connections"
#endif
#ifndef WPROXY_RUNTIME_CONNECTIONS_DIR
#define WPROXY_RUNTIME_CONNECTIONS_DIR "/run/NetworkManager/system-connections"
#endif
#ifndef WPROXY_RUNNER_PATH
#define WPROXY_RUNNER_PATH "/usr/libexec/wproxy-xray-runner"
#endif

typedef struct {
    GMainLoop *loop;
    GDBusConnection *bus;
    gchar *uri;
    GPid child;
    guint state;
    guint ready_source;
    guint ready_checks;
    gboolean connecting;
    gboolean nm_seen;
    guint nm_watch;
} App;

static void stop_runner(App *app);

static void emit_state(App *app, guint state) {
    app->state = state;
    if (app->bus)
        g_dbus_connection_emit_signal(
            app->bus, NULL, WPROXY_PATH, WPROXY_IFACE,
            "StateChanged", g_variant_new("(u)", state), NULL);
}

static void emit_failure(App *app, guint reason) {
    if (app->bus)
        g_dbus_connection_emit_signal(
            app->bus, NULL, WPROXY_PATH, WPROXY_IFACE,
            "Failure", g_variant_new("(u)", reason), NULL);
}

static GVariant *address_variant(GInetAddress *address) {
    const guint8 *bytes = g_inet_address_to_bytes(address);
    if (g_inet_address_get_family(address) == G_SOCKET_FAMILY_IPV4) {
        guint32 network_order;
        memcpy(&network_order, bytes, sizeof(network_order));
        return g_variant_new_uint32(network_order);
    }
    return g_variant_new_fixed_array(G_VARIANT_TYPE_BYTE, bytes, 16, 1);
}

static GVariant *build_general_config(GInetAddress *gateway,
                                       gboolean has_ip4, gboolean has_ip6) {
    GVariantBuilder config;
    g_variant_builder_init(&config, G_VARIANT_TYPE_VARDICT);
    g_variant_builder_add(&config, "{sv}", "tundev", g_variant_new_string("wproxy0"));
    g_variant_builder_add(&config, "{sv}", "mtu", g_variant_new_uint32(1500));
    g_variant_builder_add(&config, "{sv}", "gateway", address_variant(gateway));
    g_variant_builder_add(&config, "{sv}", "has-ip4", g_variant_new_boolean(has_ip4));
    g_variant_builder_add(&config, "{sv}", "has-ip6", g_variant_new_boolean(has_ip6));
    g_variant_builder_add(&config, "{sv}", "can-persist", g_variant_new_boolean(FALSE));
    return g_variant_builder_end(&config);
}

static GVariant *build_ip_config(GInetAddress *address, guint prefix) {
    GVariantBuilder config;
    g_variant_builder_init(&config, G_VARIANT_TYPE_VARDICT);
    g_variant_builder_add(&config, "{sv}", "address", address_variant(address));
    g_variant_builder_add(&config, "{sv}", "prefix", g_variant_new_uint32(prefix));
    // Xray 26.3.27 creates only the TUN device. NetworkManager owns its
    // default routes, DNS, and the physical route to the external gateway.
    g_variant_builder_add(&config, "{sv}", "never-default", g_variant_new_boolean(FALSE));
    if (g_inet_address_get_family(address) == G_SOCKET_FAMILY_IPV4) {
        GVariantBuilder dns;
        g_variant_builder_init(&dns, G_VARIANT_TYPE("au"));
        const gchar *servers[] = {"1.1.1.1", "8.8.8.8"};
        for (guint i = 0; i < G_N_ELEMENTS(servers); i++) {
            GInetAddress *server = g_inet_address_new_from_string(servers[i]);
            g_variant_builder_add_value(&dns, address_variant(server));
            g_object_unref(server);
        }
        g_variant_builder_add(&config, "{sv}", "dns", g_variant_builder_end(&dns));
        const gchar *domains[] = {"~.", NULL};
        g_variant_builder_add(&config, "{sv}", "domains", g_variant_new_strv(domains, -1));
    }
    return g_variant_builder_end(&config);
}

static gboolean emit_config(App *app) {
    gchar *gateway_text = NULL;
    if (!g_file_get_contents(WPROXY_GATEWAY_PATH, &gateway_text, NULL, NULL)) {
        g_warning("WProxy: missing gateway metadata; update the runner and wproxyctl together.");
        return FALSE;
    }
    GInetAddress *gateway = g_inet_address_new_from_string(g_strstrip(gateway_text));
    g_free(gateway_text);
    if (!gateway) {
        g_warning("WProxy: invalid gateway address in runtime metadata.");
        return FALSE;
    }

    GInetAddress *addresses[2] = {NULL, NULL};
    guint prefixes[2] = {0, 0};
    struct ifaddrs *interfaces = NULL;
    if (getifaddrs(&interfaces) == 0) {
        for (struct ifaddrs *item = interfaces; item; item = item->ifa_next) {
            if (!item->ifa_addr || !item->ifa_netmask ||
                g_strcmp0(item->ifa_name, "wproxy0") != 0)
                continue;
            gint family = item->ifa_addr->sa_family;
            if (family != AF_INET && family != AF_INET6)
                continue;
            guint index = family == AF_INET ? 0 : 1;
            if (addresses[index])
                continue;
            const guint8 *bytes = family == AF_INET
                ? (const guint8 *)&((struct sockaddr_in *)item->ifa_addr)->sin_addr
                : (const guint8 *)&((struct sockaddr_in6 *)item->ifa_addr)->sin6_addr;
            GInetAddress *address = g_inet_address_new_from_bytes(bytes,
                family == AF_INET ? G_SOCKET_FAMILY_IPV4 : G_SOCKET_FAMILY_IPV6);
            if (g_inet_address_get_is_link_local(address)) {
                g_object_unref(address);
                continue;
            }
            addresses[index] = address;
            const guint8 *mask = family == AF_INET
                ? (const guint8 *)&((struct sockaddr_in *)item->ifa_netmask)->sin_addr
                : (const guint8 *)&((struct sockaddr_in6 *)item->ifa_netmask)->sin6_addr;
            for (guint n = 0; n < (family == AF_INET ? 4u : 16u); n++)
                for (guint bit = 0; bit < 8; bit++)
                    prefixes[index] += (mask[n] >> bit) & 1;
        }
        freeifaddrs(interfaces);
    }
    if (!app->bus || (!addresses[0] && !addresses[1])) {
        g_warning("WProxy: ready tunnel has no usable IP address.");
        g_clear_object(&addresses[0]);
        g_clear_object(&addresses[1]);
        g_object_unref(gateway);
        return FALSE;
    }
    g_dbus_connection_emit_signal(
        app->bus, NULL, WPROXY_PATH, WPROXY_IFACE,
        "Config", g_variant_new("(@a{sv})", build_general_config(
            gateway, addresses[0] != NULL, addresses[1] != NULL)), NULL);
    for (guint i = 0; i < 2; i++) {
        if (!addresses[i])
            continue;
        g_dbus_connection_emit_signal(app->bus, NULL, WPROXY_PATH, WPROXY_IFACE,
            i == 0 ? "Ip4Config" : "Ip6Config",
            g_variant_new("(@a{sv})", build_ip_config(addresses[i], prefixes[i])), NULL);
        g_object_unref(addresses[i]);
    }
    g_object_unref(gateway);
    return TRUE;
}

static gchar *find_uri_recursive(GVariant *value) {
    if (!value)
        return NULL;

    if (g_variant_is_of_type(value, G_VARIANT_TYPE_VARIANT)) {
        GVariant *inner = g_variant_get_variant(value);
        gchar *uri = find_uri_recursive(inner);
        g_variant_unref(inner);
        return uri;
    }

    if (g_variant_is_container(value)) {
        gsize count = g_variant_n_children(value);
        for (gsize i = 0; i < count; i++) {
            GVariant *child = g_variant_get_child_value(value, i);

            if (g_variant_is_of_type(child, G_VARIANT_TYPE_DICT_ENTRY)) {
                GVariant *key = g_variant_get_child_value(child, 0);
                GVariant *item = g_variant_get_child_value(child, 1);
                const gchar *key_text = g_variant_is_of_type(key, G_VARIANT_TYPE_STRING)
                    ? g_variant_get_string(key, NULL) : NULL;
                GVariant *unboxed = item;
                if (g_variant_is_of_type(item, G_VARIANT_TYPE_VARIANT))
                    unboxed = g_variant_get_variant(item);

                gchar *uri = NULL;
                if (g_strcmp0(key_text, "uri") == 0 &&
                    g_variant_is_of_type(unboxed, G_VARIANT_TYPE_STRING))
                    uri = g_strdup(g_variant_get_string(unboxed, NULL));
                else
                    uri = find_uri_recursive(unboxed);

                if (unboxed != item)
                    g_variant_unref(unboxed);
                g_variant_unref(item);
                g_variant_unref(key);
                g_variant_unref(child);
                if (uri)
                    return uri;
                continue;
            }

            gchar *uri = find_uri_recursive(child);
            g_variant_unref(child);
            if (uri)
                return uri;
        }
    }

    return NULL;
}

static gboolean is_supported_uri(const gchar *value) {
    return value && (
        g_str_has_prefix(value, "vless://") ||
        g_str_has_prefix(value, "vmess://") ||
        g_str_has_prefix(value, "trojan://") ||
        g_str_has_prefix(value, "ss://"));
}

static gchar *lookup_uri_in_profile_dir(const gchar *directory,
                                        const gchar *wanted_uuid) {
    if (!directory || !wanted_uuid || !*wanted_uuid)
        return NULL;

    GError *error = NULL;
    GDir *profiles = g_dir_open(directory, 0, &error);
    if (!profiles) {
        g_clear_error(&error);
        return NULL;
    }

    gchar *result = NULL;
    const gchar *name = NULL;
    while (!result && (name = g_dir_read_name(profiles))) {
        if (!g_str_has_suffix(name, ".nmconnection"))
            continue;

        gchar *path = g_build_filename(directory, name, NULL);
        GKeyFile *keyfile = g_key_file_new();
        if (!g_key_file_load_from_file(keyfile, path, G_KEY_FILE_NONE, NULL)) {
            g_key_file_unref(keyfile);
            g_free(path);
            continue;
        }

        gchar *profile_uuid = g_key_file_get_string(
            keyfile, "connection", "uuid", NULL);
        if (g_strcmp0(profile_uuid, wanted_uuid) == 0) {
            gchar *candidate = g_key_file_get_string(
                keyfile, "vpn", "uri", NULL);
            if (!is_supported_uri(candidate)) {
                g_clear_pointer(&candidate, g_free);
                candidate = g_key_file_get_string(
                    keyfile, "vpn", "user-name", NULL);
            }
            if (is_supported_uri(candidate))
                result = g_steal_pointer(&candidate);
            g_free(candidate);
        }

        g_free(profile_uuid);
        g_key_file_unref(keyfile);
        g_free(path);
    }

    g_dir_close(profiles);
    return result;
}

static gchar *lookup_uri_from_profiles(const gchar *uuid) {
    gchar *uri = lookup_uri_in_profile_dir(
        WPROXY_SYSTEM_CONNECTIONS_DIR, uuid);
    if (!uri)
        uri = lookup_uri_in_profile_dir(
            WPROXY_RUNTIME_CONNECTIONS_DIR, uuid);
    return uri;
}

static gchar *extract_uri(GVariant *connection) {
    /* Let libnm deserialize its own wire format first.  This is deliberately
     * preferred over hand-parsing a{sa{sv}} because NetworkManager and the
     * Netplan-backed settings plugin may normalize VPN dictionaries
     * differently across releases. */
    GError *error = NULL;
    NMConnection *nm_connection = nm_simple_connection_new_from_dbus(connection, &error);
    if (nm_connection) {
        const gchar *connection_uuid = nm_connection_get_uuid(nm_connection);
        NMSettingVpn *vpn = nm_connection_get_setting_vpn(nm_connection);
        if (vpn) {
            const gchar *value = nm_setting_vpn_get_data_item(vpn, "uri");
            if (!value || !*value)
                value = nm_setting_vpn_get_user_name(vpn);
            if (is_supported_uri(value)) {
                gchar *uri = g_strdup(value);
                g_object_unref(nm_connection);
                g_clear_error(&error);
                return uri;
            }
        }

        /* NetworkManager deliberately filters unknown VPN keys from the
         * Connect() payload on some settings backends.  The UUID is stable,
         * however, and this service runs as root, so resolve the matching
         * keyfile and recover the WProxy URI from its [vpn] section. */
        gchar *uri = lookup_uri_from_profiles(connection_uuid);
        g_object_unref(nm_connection);
        if (uri) {
            g_clear_error(&error);
            return uri;
        }
    }
    g_clear_error(&error);

    /* Compatibility fallback for older or hand-built callers. */
    gchar *uri = find_uri_recursive(connection);
    if (!is_supported_uri(uri))
        g_clear_pointer(&uri, g_free);
    return uri;
}

static void child_watch(GPid pid, gint status, gpointer user_data) {
    App *app = user_data;
    gboolean was_connecting = app->connecting;

    if (app->child == pid)
        app->child = 0;

    g_spawn_close_pid(pid);

    if (app->ready_source) {
        g_source_remove(app->ready_source);
        app->ready_source = 0;
    }
    app->connecting = FALSE;

    if (app->state == 3 || app->state == 4) {
        if (was_connecting || status != 0)
            emit_failure(app, 1);
        emit_state(app, 6);
    }
}


static gboolean ready_poll(gpointer user_data) {
    App *app = user_data;

    if (!app->connecting) {
        app->ready_source = 0;
        return G_SOURCE_REMOVE;
    }

    if (g_file_test(WPROXY_READY_PATH, G_FILE_TEST_EXISTS)) {
        app->connecting = FALSE;
        app->ready_source = 0;
        if (emit_config(app)) {
            emit_state(app, 4);
        } else {
            stop_runner(app);
            emit_failure(app, 1);
            emit_state(app, 6);
        }
        return G_SOURCE_REMOVE;
    }

    app->ready_checks++;
    if (app->ready_checks >= 150) {
        app->connecting = FALSE;
        app->ready_source = 0;
        if (app->child)
            kill(app->child, SIGTERM);
        emit_failure(app, 1);
        emit_state(app, 6);
        return G_SOURCE_REMOVE;
    }

    return G_SOURCE_CONTINUE;
}

static gboolean start_runner_async(App *app, gchar **message) {
    if (!app->uri || !*app->uri) {
        if (message) *message = g_strdup("Missing WProxy URI.");
        return FALSE;
    }

    if (app->child) {
        if (message) *message = g_strdup("A WProxy runtime is already active.");
        return FALSE;
    }

    g_unlink(WPROXY_READY_PATH);

    gchar *argv[] = { WPROXY_RUNNER_PATH, "start", NULL };
    gchar **envp = g_get_environ();
    envp = g_environ_setenv(envp, "WPROXY_URI", app->uri, TRUE);
    GError *error = NULL;

    gboolean spawned = g_spawn_async(
        NULL, argv, envp, G_SPAWN_DO_NOT_REAP_CHILD,
        NULL, NULL, &app->child, &error);
    g_strfreev(envp);

    if (!spawned) {
        if (message)
            *message = g_strdup(error ? error->message : "Could not start WProxy runtime.");
        g_clear_error(&error);
        return FALSE;
    }

    app->connecting = TRUE;
    app->ready_checks = 0;
    g_child_watch_add(app->child, child_watch, app);
    app->ready_source = g_timeout_add(100, ready_poll, app);
    return TRUE;
}

static void stop_runner(App *app) {
    gchar *argv[] = { WPROXY_RUNNER_PATH, "stop", NULL };

    if (app->ready_source) {
        g_source_remove(app->ready_source);
        app->ready_source = 0;
    }
    app->connecting = FALSE;

    g_spawn_async(NULL, argv, NULL, G_SPAWN_SEARCH_PATH,
                  NULL, NULL, NULL, NULL);

    if (app->child)
        kill(app->child, SIGTERM);
}

static void method_call(
    GDBusConnection *connection G_GNUC_UNUSED,
    const gchar *sender G_GNUC_UNUSED,
    const gchar *object_path G_GNUC_UNUSED,
    const gchar *interface_name G_GNUC_UNUSED,
    const gchar *method_name,
    GVariant *parameters,
    GDBusMethodInvocation *invocation,
    gpointer user_data) {

    App *app = user_data;

    if (g_str_equal(method_name, "Connect") ||
        g_str_equal(method_name, "ConnectInteractive")) {

        GVariant *conn = NULL;

        if (g_str_equal(method_name, "Connect")) {
            g_variant_get(parameters, "(@a{sa{sv}})", &conn);
        } else {
            GVariant *details = NULL;
            g_variant_get(parameters,
                          "(@a{sa{sv}}@a{sv})",
                          &conn, &details);
            g_variant_unref(details);
        }

        g_free(app->uri);
        app->uri = extract_uri(conn);
        g_variant_unref(conn);

        emit_state(app, 3);

        /* NetworkManager expects Connect() to return promptly.  The previous
         * implementation waited for Xray/TUN readiness inside the D-Bus
         * method and could emit Config before NetworkManager had advanced its
         * activation state, leaving the UI stuck on “Working”.
         * Start the runtime asynchronously and emit Config only after the
         * runner signals readiness. */
        gchar *start_message = NULL;
        if (!start_runner_async(app, &start_message)) {
            emit_failure(app, 1);
            emit_state(app, 6);
            g_dbus_method_invocation_return_dbus_error(
                invocation,
                "org.freedesktop.NetworkManager.VPN.Error.ConnectFailed",
                start_message ? start_message : "Could not start the WProxy runtime.");
            g_free(start_message);
            return;
        }
        g_free(start_message);

        g_dbus_method_invocation_return_value(invocation, NULL);
        return;
    }

    if (g_str_equal(method_name, "Disconnect")) {
        emit_state(app, 5);
        stop_runner(app);
        emit_state(app, 6);
        g_dbus_method_invocation_return_value(invocation, NULL);
        return;
    }

    if (g_str_equal(method_name, "NeedSecrets")) {
        g_dbus_method_invocation_return_value(
            invocation, g_variant_new("(s)", ""));
        return;
    }

    if (g_str_equal(method_name, "SetConfig") ||
        g_str_equal(method_name, "SetIp4Config") ||
        g_str_equal(method_name, "SetIp6Config") ||
        g_str_equal(method_name, "SetFailure") ||
        g_str_equal(method_name, "NewSecrets")) {

        g_dbus_method_invocation_return_value(invocation, NULL);
        return;
    }

    g_dbus_method_invocation_return_dbus_error(
        invocation,
        "org.freedesktop.DBus.Error.UnknownMethod",
        "Unknown method.");
}

static GVariant *get_property(
    GDBusConnection *connection G_GNUC_UNUSED,
    const gchar *sender G_GNUC_UNUSED,
    const gchar *object_path G_GNUC_UNUSED,
    const gchar *interface_name G_GNUC_UNUSED,
    const gchar *property_name,
    GError **error,
    gpointer user_data) {

    App *app = user_data;

    if (g_str_equal(property_name, "State"))
        return g_variant_new_uint32(app->state);

    g_set_error(error, G_IO_ERROR, G_IO_ERROR_FAILED,
                "Unknown property.");
    return NULL;
}

static const GDBusInterfaceVTable vtable = {
    .method_call = method_call,
    .get_property = get_property,
    .set_property = NULL
};

static const gchar *introspection_xml =
    "<node>"
    " <interface name='org.freedesktop.NetworkManager.VPN.Plugin'>"
    "  <method name='Connect'>"
    "   <arg name='connection' type='a{sa{sv}}' direction='in'/>"
    "  </method>"
    "  <method name='ConnectInteractive'>"
    "   <arg name='connection' type='a{sa{sv}}' direction='in'/>"
    "   <arg name='details' type='a{sv}' direction='in'/>"
    "  </method>"
    "  <method name='NeedSecrets'>"
    "   <arg name='settings' type='a{sa{sv}}' direction='in'/>"
    "   <arg name='setting_name' type='s' direction='out'/>"
    "  </method>"
    "  <method name='Disconnect'/>"
    "  <method name='SetConfig'>"
    "   <arg name='config' type='a{sv}' direction='in'/>"
    "  </method>"
    "  <method name='SetIp4Config'>"
    "   <arg name='config' type='a{sv}' direction='in'/>"
    "  </method>"
    "  <method name='SetIp6Config'>"
    "   <arg name='config' type='a{sv}' direction='in'/>"
    "  </method>"
    "  <method name='SetFailure'>"
    "   <arg name='reason' type='s' direction='in'/>"
    "  </method>"
    "  <method name='NewSecrets'>"
    "   <arg name='connection' type='a{sa{sv}}' direction='in'/>"
    "  </method>"
    "  <signal name='StateChanged'>"
    "   <arg name='state' type='u'/>"
    "  </signal>"
    "  <signal name='Config'>"
    "   <arg name='config' type='a{sv}'/>"
    "  </signal>"
    "  <signal name='Failure'>"
    "   <arg name='reason' type='u'/>"
    "  </signal>"
    "  <signal name='Ip4Config'>"
    "   <arg name='config' type='a{sv}'/>"
    "  </signal>"
    "  <signal name='Ip6Config'>"
    "   <arg name='config' type='a{sv}'/>"
    "  </signal>"
    "  <property name='State' type='u' access='read'/>"
    " </interface>"
    "</node>";

static gboolean shutdown_service(gpointer user_data) {
    App *app = user_data;
    stop_runner(app);
    g_main_loop_quit(app->loop);
    return G_SOURCE_REMOVE;
}

static void nm_appeared(GDBusConnection *connection G_GNUC_UNUSED,
                        const gchar *name G_GNUC_UNUSED,
                        const gchar *owner G_GNUC_UNUSED, gpointer user_data) {
    ((App *)user_data)->nm_seen = TRUE;
}

static void nm_vanished(GDBusConnection *connection G_GNUC_UNUSED,
                        const gchar *name G_GNUC_UNUSED,
                        gpointer user_data) {
    App *app = user_data;
    if (app->nm_seen)
        shutdown_service(app);
}

static void bus_acquired(GDBusConnection *connection,
                         const gchar *name G_GNUC_UNUSED,
                         gpointer user_data) {
    App *app = user_data;
    app->bus = g_object_ref(connection);
    app->nm_watch = g_bus_watch_name_on_connection(connection,
        "org.freedesktop.NetworkManager", G_BUS_NAME_WATCHER_FLAGS_NONE,
        nm_appeared, nm_vanished, app, NULL);

    GError *error = NULL;
    GDBusNodeInfo *info =
        g_dbus_node_info_new_for_xml(introspection_xml, &error);

    if (!info)
        g_error("WProxy introspection: %s", error->message);

    g_dbus_connection_register_object(
        connection, WPROXY_PATH,
        info->interfaces[0], &vtable,
        app, NULL, &error);

    if (error)
        g_error("WProxy D-Bus registration: %s", error->message);

    g_dbus_node_info_unref(info);
    emit_state(app, 1);
}

int main(int argc, char **argv) {
    /* NetworkManager starts the executable from nm-wproxy-service.name as-is.
     * Official NM VPN services therefore have a built-in default D-Bus name
     * and only use --bus-name as an optional override.  The old WProxy build
     * exited with status 2 when NetworkManager started it without arguments,
     * which surfaced as "The VPN service did not start in time". */
    gchar *service_name = g_strdup(WPROXY_SERVICE_NAME);

    for (int i = 1; i < argc; ++i) {
        if (g_str_equal(argv[i], "--version")) {
            g_print("WProxy service 2.3.1\n");
            g_free(service_name);
            return 0;
        }
        if (g_str_equal(argv[i], "--bus-name") && i + 1 < argc) {
            g_free(service_name);
            service_name = g_strdup(argv[++i]);
        }
    }

    if (!service_name || !*service_name) {
        g_printerr("WProxy: invalid D-Bus service name.\n");
        g_free(service_name);
        return 2;
    }

    App app = {0};
    app.state = 1;
    app.loop = g_main_loop_new(NULL, FALSE);
    g_unix_signal_add(SIGTERM, shutdown_service, &app);
    g_unix_signal_add(SIGINT, shutdown_service, &app);

    guint owner =
        g_bus_own_name(G_BUS_TYPE_SYSTEM,
                       service_name,
                       G_BUS_NAME_OWNER_FLAGS_NONE,
                       bus_acquired,
                       NULL, NULL, &app, NULL);

    g_main_loop_run(app.loop);

    g_bus_unown_name(owner);
    if (app.nm_watch)
        g_bus_unwatch_name(app.nm_watch);
    if (app.ready_source)
        g_source_remove(app.ready_source);
    g_clear_object(&app.bus);
    g_free(app.uri);
    g_free(service_name);
    g_main_loop_unref(app.loop);
    return 0;
}
