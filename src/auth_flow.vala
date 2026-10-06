using GLib;

namespace Singularity.Auth {

    public class AuthFlow : Object {
        private const uint FINGERPRINT_WAIT_MS = 600;
        private const uint SUCCESS_LINGER_MS = 450;

        private string action_id;
        private string message;
        private string icon_name;
        private string user_name;
        private string cookie;
        private Polkit.Identity identity;
        private Cancellable? cancellable;

        private FingerprintWatch? fingerprint;
        private PolkitAgent.Session? session;
        private uint session_serial = 0;
        private Subprocess? helper;
        private DataInputStream? helper_out;
        private OutputStream? helper_in;
        private string mode = "";
        private bool awaiting_response = false;
        private string? queued_response = null;
        private string last_error = "";
        private uint decide_source = 0;
        private bool finished = false;
        private bool result = false;
        private SourceFunc? resume = null;

        public AuthFlow(string action_id, string message, string icon_name, string user_name,
                        string cookie, Polkit.Identity identity, Cancellable? cancellable) {
            this.action_id = action_id;
            this.message = message;
            this.icon_name = icon_name;
            this.user_name = user_name;
            this.cookie = cookie;
            this.identity = identity;
            this.cancellable = cancellable;
        }

        public async bool run() throws Error {
            fingerprint = yield FingerprintWatch.probe(user_name);
            if (fingerprint != null) {
                fingerprint.verify_started.connect(() => {
                    decide("fingerprint");
                    send("fp ready");
                });
                fingerprint.finger_present.connect((present) => {
                    if (mode == "fingerprint" && present) send("fp scanning");
                });
                fingerprint.verify_status.connect(on_verify_status);
            }

            ulong cancel_id = 0;
            if (cancellable != null) {
                cancel_id = cancellable.connect(() => {
                    Idle.add(() => {
                        finish(false, "request cancelled by polkit");
                        return false;
                    });
                });
            }

            start_session();
            if (fingerprint == null) {
                decide("password");
            } else if (mode == "") {
                decide_source = Timeout.add(FINGERPRINT_WAIT_MS, () => {
                    decide_source = 0;
                    decide("fingerprint");
                    return false;
                });
            }

            if (!finished) {
                resume = run.callback;
                yield;
            }

            if (cancellable != null) cancellable.disconnect(cancel_id);
            if (cancellable != null && cancellable.is_cancelled())
                throw new IOError.CANCELLED("Authentication cancelled");
            if (!result)
                throw new Polkit.Error.CANCELLED("Authentication dialog was dismissed by the user");
            return true;
        }

        private void start_session() {
            if (finished) return;
            var current = new PolkitAgent.Session(identity, cookie);
            uint serial = ++session_serial;
            session = current;
            awaiting_response = false;
            last_error = "";
            current.request.connect((prompt, echo_on) => {
                if (serial == session_serial) on_request(prompt, echo_on);
            });
            current.show_info.connect((text) => {
                if (serial == session_serial) on_info(text);
            });
            current.show_error.connect((text) => {
                if (serial == session_serial) on_error(text);
            });
            current.completed.connect((gained) => {
                if (serial == session_serial) on_completed(gained);
            });
            current.initiate();
        }

        private void discard_session() {
            session_serial++;
            var current = session;
            session = null;
            awaiting_response = false;
            if (current != null) current.cancel();
        }

        private void on_request(string prompt, bool echo_on) {
            awaiting_response = true;
            if (mode == "") {
                decide("password");
            } else if (mode == "fingerprint") {
                mode = "password";
                if (fingerprint != null) fingerprint.active = false;
                send("fallback");
            }
            if (queued_response != null) {
                string text = queued_response;
                queued_response = null;
                respond(text);
                return;
            }
            send("request %s %s".printf(echo_on ? "1" : "0", prompt));
        }

        private void on_info(string text) {
            if (mode == "" && fingerprint != null) {
                decide("fingerprint");
                return;
            }
            if (mode == "password") send("info " + text);
        }

        private void on_error(string text) {
            last_error = text;
            if (mode == "" && fingerprint != null) decide("fingerprint");
            if (mode == "fingerprint") {
                if (fingerprint == null || !fingerprint.seen_verify) send("fp retry " + text);
                return;
            }
            if (mode == "password") send("error " + text);
        }

        private void on_verify_status(string status, bool done) {
            if (mode != "fingerprint") return;
            switch (status) {
                case "verify-match":
                    send("fp match");
                    break;
                case "verify-no-match":
                    send("fp nomatch");
                    break;
                case "verify-retry-scan":
                case "verify-swipe-too-short":
                case "verify-finger-not-centered":
                case "verify-remove-and-retry":
                    send("fp retry " + status);
                    break;
                default:
                    break;
            }
        }

        private void on_completed(bool gained) {
            session_serial++;
            session = null;
            awaiting_response = false;
            if (gained) {
                send("success");
                uint linger = mode == "fingerprint" ? SUCCESS_LINGER_MS : 0;
                Timeout.add(linger, () => {
                    finish(true, "authenticated");
                    return false;
                });
                return;
            }
            send("failed " + last_error);
            restart.begin();
        }

        private async void restart() {
            if (mode == "password" && fingerprint != null) yield fingerprint.block();
            start_session();
        }

        private async void use_password() {
            if (mode != "fingerprint" || finished) return;
            mode = "password";
            if (fingerprint != null) fingerprint.active = false;
            discard_session();
            if (fingerprint != null) yield fingerprint.block();
            start_session();
        }

        private void respond(string text) {
            awaiting_response = false;
            if (session != null) session.response(text);
        }

        private void decide(string chosen) {
            if (mode != "" || finished) return;
            mode = chosen;
            if (decide_source != 0) {
                Source.remove(decide_source);
                decide_source = 0;
            }
            try {
                string exe = FileUtils.read_link("/proc/self/exe");
                string path = Path.build_filename(Path.get_dirname(exe), "singularity-polkit-auth-helper");
                helper = new Subprocess(SubprocessFlags.STDIN_PIPE | SubprocessFlags.STDOUT_PIPE,
                    path, action_id, message, icon_name, user_name, chosen);
                helper_in = helper.get_stdin_pipe();
                helper_out = new DataInputStream(helper.get_stdout_pipe());
                read_helper.begin();
            } catch (Error e) {
                warning("Cannot start the authentication dialog: %s", e.message);
                finish(false, "dialog did not start");
            }
        }

        private async void read_helper() {
            var input = helper_out;
            while (true) {
                string? line = null;
                try {
                    line = yield input.read_line_async(Priority.DEFAULT, null);
                } catch (Error e) {
                    line = null;
                }
                if (line == null) {
                    finish(false, "dialog closed");
                    return;
                }
                if (line.has_prefix("response ")) {
                    string text = line.substring(9);
                    if (awaiting_response) respond(text);
                    else queued_response = text;
                } else if (line == "password") {
                    use_password.begin();
                } else if (line == "cancel") {
                    finish(false, "dialog cancelled");
                    return;
                }
            }
        }

        private void send(string line) {
            if (helper_in == null) return;
            try {
                helper_in.write_all((line.replace("\n", " ") + "\n").data, null);
                helper_in.flush();
            } catch (Error e) {
                debug("Authentication dialog is gone: %s", e.message);
            }
        }

        private void finish(bool gained, string reason) {
            if (finished) return;
            debug("Authentication flow finished: %s", reason);
            finished = true;
            result = gained;
            if (decide_source != 0) {
                Source.remove(decide_source);
                decide_source = 0;
            }
            discard_session();
            if (fingerprint != null) {
                fingerprint.active = false;
                fingerprint.release();
            }
            if (helper_in != null) {
                try {
                    helper_in.close();
                } catch (Error e) {
                }
                helper_in = null;
            }
            if (resume != null) {
                var callback = (owned) resume;
                resume = null;
                Idle.add((owned) callback);
            }
        }
    }
}
