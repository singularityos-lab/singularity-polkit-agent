using Singularity.Auth;

public class PolkitAgentApp : GLib.Application {
    private Singularity.Auth.Agent agent;

    public PolkitAgentApp() {
        Object(application_id: "dev.sinty.PolkitAgent", flags: ApplicationFlags.FLAGS_NONE);
    }

    protected override void activate() {
        hold();
    }

    protected override void startup() {
        base.startup();
        agent = new Agent();
        agent.register_agent();
        hold();
    }

    public static int main(string[] args) {
        var app = new PolkitAgentApp();
        return app.run(args);
    }
}
