#include <gio/gio.h>
#include <signal.h>

static guint stop_helpers;
static GPid signalled_pid;
static int signalled_signal;

static gboolean fake_spawn_async(const gchar *directory G_GNUC_UNUSED,
                                gchar **argv G_GNUC_UNUSED,
                                gchar **envp G_GNUC_UNUSED,
                                GSpawnFlags flags G_GNUC_UNUSED,
                                GSpawnChildSetupFunc setup G_GNUC_UNUSED,
                                gpointer setup_data G_GNUC_UNUSED,
                                GPid *child G_GNUC_UNUSED,
                                GError **error G_GNUC_UNUSED) {
    stop_helpers++;
    return TRUE;
}

static int fake_kill(pid_t pid, int signal) {
    signalled_pid = pid;
    signalled_signal = signal;
    return 0;
}

#define g_spawn_async fake_spawn_async
#define kill fake_kill
#define main wproxy_service_main
#include "../service/nm-wproxy-service.c"
#undef main
#undef kill
#undef g_spawn_async

static void test_stop_targets_owned_generation(void) {
    App app = {.child = 4242, .connecting = TRUE};
    stop_helpers = 0;
    signalled_pid = 0;
    stop_runner(&app);
    g_assert_cmpuint(stop_helpers, ==, 0);
    g_assert_cmpint(signalled_pid, ==, 4242);
    g_assert_cmpint(signalled_signal, ==, SIGTERM);
    g_assert_false(app.connecting);
}

static void test_stale_watch_keeps_new_generation(void) {
    App app = {.child = 4242, .connecting = TRUE, .state = 4};
    child_watch(1234, 0, &app);
    g_assert_cmpint(app.child, ==, 4242);
    g_assert_true(app.connecting);
    g_assert_cmpuint(app.state, ==, 4);
}

static void test_disconnect_stops_after_owned_child_exits(void) {
    App app = {.child = 4242, .state = 5};
    child_watch(4242, 0, &app);
    g_assert_cmpint(app.child, ==, 0);
    g_assert_cmpuint(app.state, ==, 6);
}

int main(int argc, char **argv) {
    g_test_init(&argc, &argv, NULL);
    g_test_add_func("/wproxy/lifecycle/owned-stop", test_stop_targets_owned_generation);
    g_test_add_func("/wproxy/lifecycle/stale-watch", test_stale_watch_keeps_new_generation);
    g_test_add_func("/wproxy/lifecycle/disconnect-completion", test_disconnect_stops_after_owned_child_exits);
    return g_test_run();
}
