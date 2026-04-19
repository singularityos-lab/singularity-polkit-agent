using Gtk;
using Singularity.Widgets;

namespace Singularity.Auth {

    public class AuthDialog : Singularity.Shell.ShellDialog {
        private PasswordRow password_entry;
        private Button auth_btn;
        private Label error_label;
        private Singularity.Animation.TimedAnimation? anim;

        public signal void authenticated(string password);
        public signal void cancelled();

        public AuthDialog(Gtk.Application app, string action_id, string message, string icon_name, string user_name) {
            Object(
                application: app,
                anchor_top: true,
                anchor_bottom: true,
                anchor_left: true,
                anchor_right: true
            );
            add_css_class("auth-dialog");

            var box = new Box(Orientation.VERTICAL, 16);
            box.halign = Align.CENTER;
            box.valign = Align.CENTER;
            box.add_css_class("power-card");
            box.margin_top    = 28;
            box.margin_bottom = 24;
            box.margin_start  = 40;
            box.margin_end    = 40;
            content_box.append(box);

            // Pick a safe icon: use polkit-provided name only if it exists in current theme
            string safe_icon = "dialog-password-symbolic";
            if (icon_name != "") {
                var theme = Gtk.IconTheme.get_for_display(Gdk.Display.get_default());
                if (theme.has_icon(icon_name)) safe_icon = icon_name;
            }
            var icon = new Image.from_icon_name(safe_icon);
            icon.pixel_size = 48;
            icon.add_css_class("dim-label");
            box.append(icon);

            var title = new Label("Authentication Required");
            title.add_css_class("title-2");
            box.append(title);

            var msg = new Label(message);
            msg.wrap = true;
            msg.max_width_chars = 42;
            msg.justify = Justification.CENTER;
            msg.add_css_class("dim-label");
            box.append(msg);

            var user_lbl = new Label("Password for <b>%s</b>".printf(user_name));
            user_lbl.use_markup = true;
            user_lbl.add_css_class("caption");
            user_lbl.add_css_class("dim-label");
            box.append(user_lbl);

            var group = new Singularity.Widgets.PreferencesGroup();
            password_entry = new PasswordRow("Password");
            password_entry.entry_activated.connect(on_auth_clicked);
            group.add_row(password_entry);
            box.append(group);

            error_label = new Label("");
            error_label.add_css_class("error");
            error_label.wrap = true;
            error_label.visible = false;
            box.append(error_label);

            var btn_box = new Box(Orientation.HORIZONTAL, 12);
            btn_box.halign = Align.CENTER;
            box.append(btn_box);

            var cancel_btn = new Button.with_label("Cancel");
            cancel_btn.add_css_class("pill");
            cancel_btn.width_request = 120;
            cancel_btn.clicked.connect(() => {
                cancelled();
                close_dialog();
            });
            btn_box.append(cancel_btn);

            auth_btn = new Button.with_label("Authenticate");
            auth_btn.add_css_class("pill");
            auth_btn.add_css_class("suggested-action");
            auth_btn.width_request = 140;
            auth_btn.clicked.connect(on_auth_clicked);
            btn_box.append(auth_btn);

            hide();
        }

        private void on_auth_clicked() {
            auth_btn.sensitive = false;
            password_entry.sensitive = false;
            error_label.visible = false;
            authenticated(password_entry.text);
        }

        public void show_error(string msg) {
            error_label.label = msg;
            error_label.visible = true;
            auth_btn.sensitive = true;
            password_entry.sensitive = true;
            password_entry.text = "";
            password_entry.grab_focus();
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
                password_entry.grab_focus();
            });
            anim.play();
            present();
        }

        public override void close_dialog() {
            if (anim != null) anim.skip();
            anim = new Singularity.Animation.TimedAnimation(
                this, 1, 0, 120,
                Singularity.Animation.TimedAnimation.Easing.EASE_IN_CUBIC);
            anim.tick.connect(() => { opacity = anim.value; });
            anim.done.connect(() => { anim = null; hide(); });
            anim.play();
        }
    }
}
