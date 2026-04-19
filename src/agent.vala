using GLib;
using Gtk;

namespace Singularity.Auth {

    public class Agent : PolkitAgent.Listener {

        private GLib.List<void*> registration_handles = new GLib.List<void*>();

        public void register_agent() {
            // Collect session IDs to register for
            var session_ids = new GLib.GenericArray<string>();

            string? env_session = GLib.Environment.get_variable("XDG_SESSION_ID");
            if (env_session != null && env_session != "")
                session_ids.add(env_session);

            // Enumerate all logind sessions for this user (needed in container where
            // host-spawn processes may be in a different session than the graphical one)
            var discovered = find_all_user_sessions();
            foreach (string s in discovered) {
                bool already = false;
                foreach (string existing in session_ids)
                    if (existing == s) { already = true; break; }
                if (!already) session_ids.add(s);
            }

            if (session_ids.length == 0) {
                // Last resort: register by process
                try {
                    var subject = new Polkit.UnixProcess.for_owner(
                        (int) Posix.getpid(), 0, (int) Posix.getuid());
                    void* h = register(PolkitAgent.RegisterFlags.NONE, subject,
                        "/dev/sinty/PolicyKit1/AuthenticationAgent");
                    registration_handles.append(h);
                    message("Polkit Agent: registered via UnixProcess (fallback)");
                } catch (GLib.Error e) {
                    warning("Failed to register Polkit Agent: %s", e.message);
                }
                return;
            }

            foreach (string sid in session_ids) {
                try {
                    var subject = new Polkit.UnixSession(sid);
                    void* h = register(PolkitAgent.RegisterFlags.NONE, subject,
                        "/dev/sinty/PolicyKit1/AuthenticationAgent");
                    registration_handles.append(h);
                    message("Polkit Agent: registered for session %s", sid);
                } catch (GLib.Error e) {
                    warning("Failed to register for session %s: %s", sid, e.message);
                }
            }
        }

        private GLib.GenericArray<string> find_all_user_sessions() {
            var result_list = new GLib.GenericArray<string>();
            try {
                string host_socket = "/run/host/run/dbus/system_bus_socket";
                DBusConnection conn;
                if (GLib.FileUtils.test(host_socket, GLib.FileTest.EXISTS)) {
                    conn = new DBusConnection.for_address_sync(
                        "unix:path=" + host_socket,
                        DBusConnectionFlags.AUTHENTICATION_CLIENT |
                        DBusConnectionFlags.MESSAGE_BUS_CONNECTION, null, null);
                } else {
                    conn = Bus.get_sync(BusType.SYSTEM);
                }
                uint32 my_uid = (uint32) Posix.getuid();
                var result = conn.call_sync(
                    "org.freedesktop.login1",
                    "/org/freedesktop/login1",
                    "org.freedesktop.login1.Manager",
                    "ListSessionsEx",
                    null, null, DBusCallFlags.NONE, -1, null);
                var sessions = result.get_child_value(0);
                for (size_t i = 0; i < sessions.n_children(); i++) {
                    var s = sessions.get_child_value(i);
                    string sid = s.get_child_value(0).get_string();
                    uint32 uid = s.get_child_value(1).get_uint32();
                    if (uid == my_uid) {
                        result_list.add(sid);
                        message("Polkit Agent: found user session %s", sid);
                    }
                }
            } catch (GLib.Error e) {
                debug("find_all_user_sessions: %s", e.message);
            }
            return result_list;
        }

        public override async bool initiate_authentication(
            string action_id,
            string message,
            string icon_name,
            Polkit.Details details,
            string cookie,
            GLib.List<Polkit.Identity> identities,
            GLib.Cancellable? cancellable = null) throws GLib.Error {

            debug("BeginAuthentication: %s", action_id);

            // Pick best identity: prefer current user, fallback to first
            Polkit.Identity? chosen = null;
            int current_uid = (int) Posix.getuid();
            foreach (var id in identities) {
                if (id is Polkit.UnixUser) {
                    if (((Polkit.UnixUser)id).get_uid() == current_uid) {
                        chosen = id; break;
                    }
                    if (chosen == null) chosen = id;
                }
            }
            if (chosen == null && identities.length() > 0)
                chosen = identities.nth_data(0);

            // Resolve display username
            string user_name = "root";
            if (chosen != null && chosen is Polkit.UnixUser) {
                unowned Posix.Passwd? pw = Posix.getpwuid(
                    (Posix.uid_t)((Polkit.UnixUser)chosen).get_uid());
                if (pw != null) user_name = pw.pw_name;
            }

            var app = (Gtk.Application) GLib.Application.get_default();
            var dialog = new AuthDialog(app, action_id, message, icon_name, user_name);

            bool success = false;
            var loop = new GLib.MainLoop(null, false);

            if (cancellable != null) {
                cancellable.cancelled.connect(() => {
                    dialog.close_dialog();
                    loop.quit();
                });
            }

            dialog.authenticated.connect((password) => {
                attempt_auth.begin(cookie, chosen, password, dialog, (obj, res) => {
                    try {
                        success = attempt_auth.end(res);
                    } catch (GLib.Error e) {
                        warning("Auth error: %s", e.message);
                    }
                    if (success) {
                        dialog.close_dialog();
                        loop.quit();
                    }
                });
            });

            dialog.cancelled.connect(() => {
                loop.quit();
            });

            dialog.open_dialog();
            loop.run();

            if (cancellable != null && cancellable.is_cancelled())
                throw new GLib.IOError.CANCELLED("Authentication cancelled");

            return success;
        }

        private async bool attempt_auth(string cookie, Polkit.Identity? identity,
                                        string password, AuthDialog dialog) throws GLib.Error {
            if (identity == null) {
                dialog.show_error(_("No identity to authenticate."));
                return false;
            }

            bool gained = false;
            var session = new PolkitAgent.Session(identity, cookie);

            session.request.connect((request_text, echo_on) => {
                session.response(password);
            });

            session.show_error.connect((text) => {
                dialog.show_error(text);
            });

            session.completed.connect((ok) => {
                gained = ok;
                if (!ok) dialog.show_error(_("Authentication failed. Wrong password?"));
                attempt_auth.callback();
            });

            session.initiate();
            yield;

            return gained;
        }
    }
}
