using Gtk;
using Singularity.Auth;

public class PolkitAuthHelperApp : Singularity.Application {
    private string action_id;
    private string auth_message;
    private string icon_name;
    private string user_name;
    private string error_message;

    public PolkitAuthHelperApp(string[] args) {
        base("dev.sinty.PolkitAuthHelper");
        action_id = args.length > 1 ? args[1] : "";
        auth_message = args.length > 2 ? args[2] : "Authentication required";
        icon_name = args.length > 3 ? args[3] : "";
        user_name = args.length > 4 ? args[4] : "root";
        error_message = args.length > 5 ? args[5] : "";
    }

    protected override void activate() {
        var dialog = new AuthDialog(this, action_id, auth_message, icon_name, user_name);
        dialog.authenticated.connect((password) => {
            stdout.printf("%s\n", password);
            stdout.flush();
            dialog.destroy();
            quit();
        });
        dialog.cancelled.connect(() => {
            dialog.destroy();
            quit();
        });
        dialog.open_dialog();
        if (error_message != "") {
            dialog.show_error(error_message);
        }
    }

    public static int main(string[] args) {
        var app = new PolkitAuthHelperApp(args);
        return app.run(args);
    }
}
