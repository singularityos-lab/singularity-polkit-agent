using GLib;

namespace Singularity.Auth {

    public class FingerprintWatch : Object {
        private const string SERVICE = "net.reactivated.Fprint";
        private const string DEVICE_IFACE = "net.reactivated.Fprint.Device";

        private DBusConnection bus;
        private string device;
        private uint[] subscriptions = {};
        private bool claimed = false;

        public bool active { get; set; default = true; }
        public bool seen_verify { get; private set; default = false; }

        public signal void verify_started();
        public signal void finger_present(bool present);
        public signal void verify_status(string result, bool done);

        private FingerprintWatch(DBusConnection bus, string device) {
            this.bus = bus;
            this.device = device;
            subscriptions += bus.signal_subscribe(SERVICE, DEVICE_IFACE, "VerifyFingerSelected", device, null,
                DBusSignalFlags.NONE, on_finger_selected);
            subscriptions += bus.signal_subscribe(SERVICE, DEVICE_IFACE, "VerifyStatus", device, null,
                DBusSignalFlags.NONE, on_verify_status);
            subscriptions += bus.signal_subscribe(SERVICE, "org.freedesktop.DBus.Properties", "PropertiesChanged",
                device, DEVICE_IFACE, DBusSignalFlags.NONE, on_properties_changed);
        }

        public static async FingerprintWatch? probe(string user_name) {
            try {
                var bus = yield Bus.get(BusType.SYSTEM);
                var reply = yield bus.call(SERVICE, "/net/reactivated/Fprint/Manager", "net.reactivated.Fprint.Manager",
                    "GetDefaultDevice", null, new VariantType("(o)"), DBusCallFlags.NONE, 2000, null);
                string device;
                reply.get("(o)", out device);
                var fingers = yield bus.call(SERVICE, device, DEVICE_IFACE, "ListEnrolledFingers",
                    new Variant("(s)", user_name), new VariantType("(as)"), DBusCallFlags.NONE, 2000, null);
                if (fingers.get_child_value(0).n_children() == 0) return null;
                return new FingerprintWatch(bus, device);
            } catch (Error e) {
                debug("Fingerprint unavailable: %s", e.message);
                return null;
            }
        }

        public async void block() {
            if (claimed) return;
            for (int attempt = 0; attempt < 20 && !claimed; attempt++) {
                try {
                    yield bus.call(SERVICE, device, DEVICE_IFACE, "Claim", new Variant("(s)", ""),
                        null, DBusCallFlags.NONE, 2000, null);
                    claimed = true;
                } catch (Error e) {
                    debug("Fingerprint claim attempt %d: %s", attempt, e.message);
                    Timeout.add(150, block.callback);
                    yield;
                }
            }
        }

        public void release() {
            if (claimed) {
                claimed = false;
                bus.call.begin(SERVICE, device, DEVICE_IFACE, "Release", null, null, DBusCallFlags.NONE, 2000, null);
            }
            foreach (uint id in subscriptions) bus.signal_unsubscribe(id);
            subscriptions = {};
        }

        private void on_finger_selected(DBusConnection conn, string? sender, string path, string iface,
                                        string name, Variant parameters) {
            if (!active) return;
            seen_verify = true;
            verify_started();
        }

        private void on_verify_status(DBusConnection conn, string? sender, string path, string iface,
                                      string name, Variant parameters) {
            if (!active || !parameters.is_of_type(new VariantType("(sb)"))) return;
            string result;
            bool done;
            parameters.get("(sb)", out result, out done);
            seen_verify = true;
            verify_status(result, done);
        }

        private void on_properties_changed(DBusConnection conn, string? sender, string path, string iface,
                                           string name, Variant parameters) {
            if (!active || !parameters.is_of_type(new VariantType("(sa{sv}as)"))) return;
            var changed = parameters.get_child_value(1);
            var present = changed.lookup_value("finger-present", VariantType.BOOLEAN);
            if (present != null) finger_present(present.get_boolean());
        }
    }
}
