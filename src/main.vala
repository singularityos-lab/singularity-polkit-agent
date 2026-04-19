using Gtk;
using Singularity.Auth;

public class PolkitAgentApp : Singularity.Application {
    private Singularity.Auth.Agent agent;

    public PolkitAgentApp() {
        base("dev.sinty.PolkitAgent");
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
