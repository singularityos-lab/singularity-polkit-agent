using Gtk;
using Singularity.Widgets;

namespace Singularity.Auth {

    public class AuthDialog : Singularity.Shell.ShellDialog {
        private Box fingerprint_page;
        private Box password_page;
        private Singularity.Animation.MotionBin fingerprint_bin;
        private Label fingerprint_status;
        private PasswordRow password_entry;
        private Button auth_btn;
        private Label info_label;
        private Label error_label;
        private string user_name;
        private bool fingerprint_mode;
        private string fingerprint_state = "";
        private Singularity.Animation.TimedAnimation? anim;

        public signal void response(string text);
        public signal void password_requested();
        public signal void cancelled();
        public signal void dismissed();

        public AuthDialog(Gtk.Application app, string action_id, string message, string icon_name,
                          string user_name, bool fingerprint) {
            Object(
                application: app,
                anchor_top: true,
                anchor_bottom: true,
                anchor_left: true,
                anchor_right: true
            );
            this.user_name = user_name;
            fingerprint_mode = fingerprint;
            add_css_class("auth-dialog");

            var box = new Box(Orientation.VERTICAL, 0);
            box.halign = Align.CENTER;
            box.valign = Align.CENTER;
            box.add_css_class("power-card");
            box.margin_top    = 28;
            box.margin_bottom = 24;
            box.margin_start  = 40;
            box.margin_end    = 40;
            content_box.append(box);

            fingerprint_page = build_fingerprint_page(message);
            password_page = build_password_page(message, icon_name);
            box.append(fingerprint_page);
            box.append(password_page);
            fingerprint_page.visible = fingerprint_mode;
            password_page.visible = !fingerprint_mode;

            hide();
        }

        private void append_header(Box page, string message) {
            var title = new Label(_("Authentication Required"));
            title.add_css_class("title-2");
            page.append(title);

            var msg = new Label(message);
            msg.wrap = true;
            msg.max_width_chars = 42;
            msg.justify = Justification.CENTER;
            msg.add_css_class("dim-label");
            page.append(msg);
        }

        private Box build_fingerprint_page(string message) {
            var page = new Box(Orientation.VERTICAL, 16);

            var icon = new Image.from_gicon(new ThemedIcon.from_names({
                "auth-fingerprint", "fingerprint-symbolic", "auth-fingerprint-symbolic"
            }));
            icon.pixel_size = 96;
            fingerprint_bin = new Singularity.Animation.MotionBin(icon);
            fingerprint_bin.halign = Align.CENTER;
            fingerprint_bin.margin_bottom = 4;
            page.append(fingerprint_bin);

            append_header(page, message);

            fingerprint_status = new Label(_("Touch the fingerprint reader"));
            fingerprint_status.add_css_class("title-4");
            fingerprint_status.add_css_class("auth-fingerprint-status");
            fingerprint_status.wrap = true;
            fingerprint_status.max_width_chars = 36;
            fingerprint_status.justify = Justification.CENTER;
            fingerprint_status.margin_top = 4;
            page.append(fingerprint_status);

            var btn_box = new Box(Orientation.HORIZONTAL, 12);
            btn_box.halign = Align.CENTER;
            btn_box.margin_top = 8;
            page.append(btn_box);

            var cancel_btn = new Button.with_label(_("Cancel"));
            cancel_btn.add_css_class("pill");
            cancel_btn.width_request = 120;
            cancel_btn.clicked.connect(() => close_dialog());
            btn_box.append(cancel_btn);

            var password_btn = new Button.with_label(_("Use Password Instead"));
            password_btn.add_css_class("pill");
            password_btn.clicked.connect(() => {
                show_password_page("");
                password_requested();
            });
            btn_box.append(password_btn);

            return page;
        }

        private Box build_password_page(string message, string icon_name) {
            var page = new Box(Orientation.VERTICAL, 16);

            string safe_icon = "dialog-password";
            if (icon_name != "") {
                var theme = Gtk.IconTheme.get_for_display(Gdk.Display.get_default());
                if (theme.has_icon(icon_name)) safe_icon = icon_name;
            }
            var icon = new Image.from_icon_name(safe_icon);
            icon.pixel_size = 64;
            page.append(icon);

            append_header(page, message);

            info_label = new Label("");
            info_label.wrap = true;
            info_label.max_width_chars = 42;
            info_label.justify = Justification.CENTER;
            info_label.visible = false;
            page.append(info_label);

            var group = new Singularity.Widgets.PreferencesGroup();
            password_entry = new PasswordRow(password_title());
            password_entry.entry_activated.connect(on_auth_clicked);
            group.add_row(password_entry);
            page.append(group);

            error_label = new Label("");
            error_label.add_css_class("error");
            error_label.wrap = true;
            error_label.max_width_chars = 42;
            error_label.justify = Justification.CENTER;
            error_label.visible = false;
            page.append(error_label);

            var btn_box = new Box(Orientation.HORIZONTAL, 12);
            btn_box.halign = Align.CENTER;
            page.append(btn_box);

            var cancel_btn = new Button.with_label(_("Cancel"));
            cancel_btn.add_css_class("pill");
            cancel_btn.width_request = 120;
            cancel_btn.clicked.connect(() => close_dialog());
            btn_box.append(cancel_btn);

            auth_btn = new Button.with_label(_("Authenticate"));
            auth_btn.add_css_class("pill");
            auth_btn.add_css_class("suggested-action");
            auth_btn.width_request = 140;
            auth_btn.clicked.connect(on_auth_clicked);
            btn_box.append(auth_btn);

            return page;
        }

        private string password_title() {
            return _("Password for %s").printf(user_name);
        }

        private void on_auth_clicked() {
            if (!auth_btn.sensitive) return;
            auth_btn.sensitive = false;
            password_entry.sensitive = false;
            error_label.visible = false;
            response(password_entry.text);
        }

        private void enable_entry(bool clear) {
            auth_btn.sensitive = true;
            password_entry.sensitive = true;
            if (clear) password_entry.text = "";
            password_entry.grab_focus();
        }

        private void show_password_page(string note) {
            if (note != "") show_info(note);
            if (!fingerprint_mode) return;
            fingerprint_mode = false;
            Singularity.Motion.crossfade(fingerprint_page, password_page);
            enable_entry(false);
        }

        public void fallback_to_password() {
            string note = fingerprint_state == "nomatch"
                ? _("Too many attempts. Enter your password instead.")
                : _("Enter your password to continue.");
            show_password_page(note);
        }

        public void request(bool echo_on, string prompt) {
            string label = prompt.strip();
            if (label.has_suffix(":")) label = label.substring(0, label.length - 1).strip();
            password_entry.title = label == "" || label.down().has_prefix("password") ? password_title() : label;
            if (!password_entry.sensitive || password_entry.text == "") enable_entry(true);
        }

        public void show_info(string text) {
            info_label.label = text;
            info_label.visible = text != "";
        }

        public void show_error(string text) {
            error_label.label = text;
            error_label.visible = text != "";
        }

        public void failed(string text) {
            if (fingerprint_mode) {
                set_fingerprint_state("nomatch", "");
                return;
            }
            show_error(text != "" ? text : _("Sorry, that didn't work. Please try again."));
            enable_entry(true);
        }

        public void succeeded() {
            if (fingerprint_mode) set_fingerprint_state("match", "");
        }

        public void set_fingerprint_state(string state, string detail) {
            if (!fingerprint_mode) return;
            if (state == "ready" && (fingerprint_state == "nomatch" || fingerprint_state == "retry")) return;
            fingerprint_state = state;
            fingerprint_status.remove_css_class("error");
            fingerprint_status.remove_css_class("success");
            string text;
            switch (state) {
                case "scanning":
                    text = _("Reading your fingerprint");
                    Singularity.Motion.spring_to(fingerprint_bin, "scale", 0.92, Singularity.Motion.Spring.SNAPPY);
                    break;
                case "retry":
                    text = retry_text(detail);
                    Singularity.Motion.spring_to(fingerprint_bin, "scale", 1.0, Singularity.Motion.Spring.BOUNCY);
                    Singularity.Motion.spring_to(fingerprint_bin, "translate-y", 0.0,
                        Singularity.Motion.Spring.BOUNCY, -260.0);
                    break;
                case "nomatch":
                    text = _("No match. Try again.");
                    fingerprint_status.add_css_class("error");
                    Singularity.Motion.spring_to(fingerprint_bin, "scale", 1.0, Singularity.Motion.Spring.SNAPPY);
                    Singularity.Motion.spring_to(fingerprint_bin, "translate-x", 0.0,
                        Singularity.Motion.Spring.BOUNCY, -900.0);
                    break;
                case "match":
                    text = _("Fingerprint recognized");
                    fingerprint_status.add_css_class("success");
                    Singularity.Motion.spring_to(fingerprint_bin, "scale", 1.0,
                        Singularity.Motion.Spring.BOUNCY, 3.0);
                    break;
                default:
                    text = _("Touch the fingerprint reader");
                    Singularity.Motion.spring_to(fingerprint_bin, "scale", 1.0, Singularity.Motion.Spring.SNAPPY);
                    break;
            }
            if (fingerprint_status.label != text) {
                fingerprint_status.label = text;
                fingerprint_status.opacity = 0.0;
                Singularity.Motion.tween(fingerprint_status, "opacity", 1.0,
                    Singularity.Motion.Duration.SMALL, Singularity.Motion.Curve.ENTER);
            }
        }

        private string retry_text(string detail) {
            switch (detail) {
                case "verify-swipe-too-short":
                    return _("That was too quick. Touch the reader again.");
                case "verify-finger-not-centered":
                    return _("Center your finger on the reader");
                case "verify-remove-and-retry":
                    return _("Lift your finger and touch the reader again");
                case "verify-retry-scan":
                case "":
                    return _("Touch the reader again");
                default:
                    return detail;
            }
        }

        public override void open_dialog() {
            opacity = 0;
            if (anim != null) anim.skip();
            anim = new Singularity.Animation.TimedAnimation(
                this, 0, 1, 160,
                Singularity.Animation.TimedAnimation.Easing.EASE_OUT_CUBIC);
            anim.tick.connect(() => { opacity = anim.value; });
            anim.done.connect(() => {
                anim = null;
                if (!fingerprint_mode) password_entry.grab_focus();
            });
            anim.play();
            present();
            if (!fingerprint_mode) password_entry.grab_focus();
        }

        private void animate_out(bool user_cancelled) {
            if (anim != null) anim.skip();
            anim = new Singularity.Animation.TimedAnimation(
                this, 1, 0, 120,
                Singularity.Animation.TimedAnimation.Easing.EASE_IN_CUBIC);
            anim.tick.connect(() => { opacity = anim.value; });
            anim.done.connect(() => {
                anim = null;
                hide();
                if (user_cancelled) cancelled();
                else dismissed();
            });
            anim.play();
        }

        public override void close_dialog() {
            animate_out(true);
        }

        public void dismiss() {
            animate_out(false);
        }
    }
}
