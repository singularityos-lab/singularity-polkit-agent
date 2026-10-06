using Gtk;
using Singularity.Auth;

public class PolkitAuthHelperApp : Singularity.Application {
    private string action_id;
    private string auth_message;
    private string icon_name;
    private string user_name;
    private bool fingerprint;
    private AuthDialog? dialog;
    private DataInputStream input;
    private bool done = false;

    public PolkitAuthHelperApp(string[] args) {
        // NON_UNIQUE: each pkexec prompt is a separate process; they must not
        // forward activate() to each other through the D-Bus singleton mechanism.
        base(_("dev.sinty.PolkitAuthHelper"), ApplicationFlags.NON_UNIQUE);
        action_id = args.length > 1 ? args[1] : "";
        auth_message = args.length > 2 ? args[2] : "Authentication required";
        icon_name = args.length > 3 ? args[3] : "";
        user_name = args.length > 4 ? args[4] : "root";
        fingerprint = args.length > 5 && args[5] == "fingerprint";
    }

    protected override void activate() {
        if (dialog != null) return;
        hold();
        dialog = new AuthDialog(this, action_id, auth_message, icon_name, user_name, fingerprint);
        dialog.response.connect((text) => reply("response " + text));
        dialog.password_requested.connect(() => reply("password"));
        dialog.cancelled.connect(() => {
            reply("cancel");
            finish();
        });
        dialog.dismissed.connect(finish);
        dialog.open_dialog();
        input = new DataInputStream(new UnixInputStream(0, false));
        read_commands.begin();
    }

    private void reply(string line) {
        stdout.printf("%s\n", line);
        stdout.flush();
    }

    private void finish() {
        if (done) return;
        done = true;
        if (dialog != null) dialog.destroy();
        release();
        quit();
    }

    private async void read_commands() {
        while (!done) {
            string? line = null;
            try {
                line = yield input.read_line_async(Priority.DEFAULT, null);
            } catch (Error e) {
                line = null;
            }
            if (line == null) {
                if (!done) dialog.dismiss();
                return;
            }
            handle(line);
        }
    }

    private void handle(string line) {
        string command = line;
        string rest = "";
        int space = line.index_of_char(' ');
        if (space >= 0) {
            command = line.substring(0, space);
            rest = line.substring(space + 1);
        }
        switch (command) {
            case "fp": {
                string state = rest;
                string detail = "";
                int split = rest.index_of_char(' ');
                if (split >= 0) {
                    state = rest.substring(0, split);
                    detail = rest.substring(split + 1);
                }
                dialog.set_fingerprint_state(state, detail);
                break;
            }
            case "request": {
                bool echo_on = rest.has_prefix("1");
                dialog.request(echo_on, rest.length > 2 ? rest.substring(2) : "");
                break;
            }
            case "fallback":
                dialog.fallback_to_password();
                break;
            case "info":
                dialog.show_info(rest);
                break;
            case "error":
                dialog.show_error(rest);
                break;
            case "failed":
                dialog.failed(rest);
                break;
            case "success":
                dialog.succeeded();
                break;
            default:
                break;
        }
    }

    public static int main(string[] args) {
        GLib.Log.writer_default_set_use_stderr(true);
        Intl.setlocale(GLib.LocaleCategory.ALL, "");
        string locale_dir = "/usr/share/locale";
        try {
            string exe = GLib.FileUtils.read_link("/proc/self/exe");
            locale_dir = GLib.Path.build_filename(GLib.Path.get_dirname(GLib.Path.get_dirname(exe)), "share", "locale");
        } catch (GLib.Error e) { }
        Intl.bindtextdomain("singularity-polkit-agent", locale_dir);
        Intl.bind_textdomain_codeset("singularity-polkit-agent", "UTF-8");
        Intl.textdomain("singularity-polkit-agent");

        var app = new PolkitAuthHelperApp(args);
        // Pass only argv[0] so GLib.Application doesn't see action/message args
        // as files and trigger the "can not open files" critical error.
        return app.run({args[0]});
    }
}
