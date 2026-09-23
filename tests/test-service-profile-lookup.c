#define main wproxy_service_main
#include "../service/nm-wproxy-service.c"
#undef main

static void test_profile_uri_lookup(void) {
    GError *error = NULL;
    gchar *directory = g_dir_make_tmp("wproxy-profile-test-XXXXXX", &error);
    g_assert_no_error(error);
    g_assert_nonnull(directory);

    const gchar *uuid = "11111111-2222-3333-4444-555555555555";
    const gchar *expected = "vless://test-user@example.com:443?security=tls#test";
    gchar *profile = g_strdup_printf(
        "[connection]\n"
        "id=WProxy test\n"
        "uuid=%s\n"
        "type=vpn\n\n"
        "[vpn]\n"
        "service-type=org.freedesktop.NetworkManager.wproxy\n"
        "user-name=%s\n",
        uuid, expected);
    gchar *path = g_build_filename(directory, "test.nmconnection", NULL);

    g_assert_true(g_file_set_contents(path, profile, -1, &error));
    g_assert_no_error(error);

    gchar *uri = lookup_uri_in_profile_dir(directory, uuid);
    g_assert_cmpstr(uri, ==, expected);
    g_clear_pointer(&uri, g_free);

    uri = lookup_uri_in_profile_dir(directory, "different-uuid");
    g_assert_null(uri);

    g_assert_cmpint(g_remove(path), ==, 0);
    g_assert_cmpint(g_rmdir(directory), ==, 0);
    g_free(path);
    g_free(profile);
    g_free(directory);
}

static void test_network_config(void) {
    GInetAddress *gateway = g_inet_address_new_from_string("198.51.100.42");
    GVariant *config = g_variant_ref_sink(build_general_config(gateway, TRUE, FALSE));
    guint32 raw_gateway = 0;
    gboolean has_ip4 = FALSE, has_ip6 = TRUE;
    g_assert_true(g_variant_lookup(config, "gateway", "u", &raw_gateway));
    g_assert_cmpmem(&raw_gateway, sizeof(raw_gateway), g_inet_address_to_bytes(gateway), 4);
    g_assert_true(g_variant_lookup(config, "has-ip4", "b", &has_ip4));
    g_assert_true(g_variant_lookup(config, "has-ip6", "b", &has_ip6));
    g_assert_true(has_ip4);
    g_assert_false(has_ip6);
    g_variant_unref(config);
    g_object_unref(gateway);

    GInetAddress *local = g_inet_address_new_from_string("172.19.0.1");
    config = g_variant_ref_sink(build_ip_config(local, 30));
    guint32 prefix = 0;
    gboolean never_default = FALSE;
    g_assert_true(g_variant_lookup(config, "prefix", "u", &prefix));
    g_assert_cmpuint(prefix, ==, 30);
    g_assert_true(g_variant_lookup(config, "never-default", "b", &never_default));
    g_assert_false(never_default);
    GVariant *dns = g_variant_lookup_value(config, "dns", G_VARIANT_TYPE("au"));
    g_assert_nonnull(dns);
    g_assert_cmpuint(g_variant_n_children(dns), ==, 2);
    g_variant_unref(dns);
    g_variant_unref(config);
    g_object_unref(local);

    gateway = g_inet_address_new_from_string("2001:db8::42");
    config = g_variant_ref_sink(build_general_config(gateway, TRUE, TRUE));
    GVariant *ip6_gateway = g_variant_lookup_value(config, "gateway", G_VARIANT_TYPE("ay"));
    g_assert_nonnull(ip6_gateway);
    gsize length = 0;
    const guint8 *bytes = g_variant_get_fixed_array(ip6_gateway, &length, 1);
    g_assert_cmpmem(bytes, length, g_inet_address_to_bytes(gateway), 16);
    g_variant_unref(ip6_gateway);
    g_variant_unref(config);
    g_object_unref(gateway);
}

int main(int argc, char **argv) {
    g_test_init(&argc, &argv, NULL);
    g_test_add_func("/wproxy/service/profile-uri-lookup", test_profile_uri_lookup);
    g_test_add_func("/wproxy/service/network-config", test_network_config);
    return g_test_run();
}
