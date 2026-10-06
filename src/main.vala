using Singularity.Auth;

public class PolkitAgentApp : GLib.Application {
    private Singularity.Auth.Agent agent;
    private AuthenticationState state = new AuthenticationState();
    private static string[] launch_args;
    private string exe_path = "";
    private FileMonitor? exe_monitor = null;
    private bool restart_pending = false;

    public PolkitAgentApp() {
        Object(application_id: "dev.sinty.PolkitAgent", flags: ApplicationFlags.FLAGS_NONE);
    }

    protected override void activate() {
        hold();
    }

    public override bool dbus_register(DBusConnection connection, string object_path) throws Error {
        base.dbus_register(connection, object_path);
        connection.register_object(object_path + "/Authentication", state);
        return true;
    }

    protected override void startup() {
        base.startup();
        agent = new Agent(state);
        agent.register_agent();
        watch_executable();
        hold();
    }

    private void watch_executable() {
        try {
            exe_path = FileUtils.read_link("/proc/self/exe");
            exe_monitor = File.new_for_path(exe_path).monitor_file(FileMonitorFlags.WATCH_MOVES, null);
            exe_monitor.changed.connect(() => {
                if (restart_pending) return;
                restart_pending = true;
                Timeout.add_seconds(2, () => {
                    restart_when_idle();
                    return false;
                });
            });
        } catch (Error e) {
            warning("Cannot watch the agent executable: %s", e.message);
        }
    }

    private void restart_when_idle() {
        if (state.authenticating) {
            ulong handler = 0;
            handler = state.authenticating_changed.connect((authenticating) => {
                if (authenticating) return;
                state.disconnect(handler);
                restart_when_idle();
            });
            return;
        }
        if (!FileUtils.test(exe_path, FileTest.IS_EXECUTABLE)) {
            restart_pending = false;
            return;
        }
        message("Agent executable was replaced, restarting");
        Posix.execv(exe_path, launch_args);
        warning("Cannot restart the agent: %s", Posix.strerror(Posix.errno));
        restart_pending = false;
    }

    public static int main(string[] args) {
        launch_args = args;
        var app = new PolkitAgentApp();
        return app.run(args);
    }
}
