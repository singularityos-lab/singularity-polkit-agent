# singularity-polkit-agent

> [!IMPORTANT]
> Report bugs and request features in the
> [Singularity Desktop tracker](https://github.com/singularityos-lab/singularity-desktop/issues/new/choose).

A lightweight Polkit authentication agent for the [Singularity Desktop Environment](https://github.com/singularityos-lab).

## Requirements

- [Meson](https://mesonbuild.com/) ≥ 1.0
- [Vala](https://vala.dev/) compiler
- GTK4
- polkit-gobject-1
- [libsingularity](https://github.com/singularityos-lab/libsingularity)

## Build & Install

```sh
meson setup build
meson compile -C build
meson install -C build
```

## How authentication works

The agent never decides by itself whether a user is authenticated. For every
request it opens a `PolkitAgent.Session`, which runs polkit's own
`polkit-agent-helper-1` (spawned setuid, or reached through
`/run/polkit/agent-helper.socket`). The helper runs the `polkit-1` PAM stack and
reports the result straight to polkitd. The dialog only renders the PAM
conversation: prompts become the password field, info and error messages become
status text.

The session starts as soon as the request arrives, before any input, so a PAM
stack that begins with a fingerprint module can run right away.

### Fingerprint

When fprintd is present and the user has enrolled fingers
(`net.reactivated.Fprint`, `ListEnrolledFingers`), and the PAM conversation
starts with the fingerprint module instead of a password prompt, the dialog opens
on a fingerprint prompt:

- live feedback comes from the fprintd signals `VerifyFingerSelected`,
  `VerifyStatus` and the `finger-present` property. The PAM text is used only
  when those signals are not visible;
- "Use Password Instead" cancels the running session, claims the fingerprint
  reader for the user (`Claim`), and starts a new session. `pam_fprintd` cannot
  claim a busy reader, returns `PAM_AUTHINFO_UNAVAIL`, and the stack goes on to
  the password module. The reader is released when the request ends;
- when the fingerprint module gives up (no match after its retries, timeout), the
  password prompt that follows switches the dialog to the password field.

Without fprintd, without enrolled fingers, or when the first PAM message is a
password prompt, the dialog opens straight on the password field.

fprintd is used only to decide what to show. A match seen over D-Bus never
authorizes anything: only the PAM result delivered by the polkit helper does.
An agent cannot report a successful authentication to polkitd itself
(`AuthenticationAgentResponse2` is reserved to root), so verifying a finger in
the agent and then answering polkit would be a bypass, and is not done.

## For distributors

- Fingerprint for administrator prompts needs `pam_fprintd` in the `polkit-1`
  PAM stack, before the password module. On Debian and Ubuntu enable it with
  `pam-auth-update` (Fingerprint authentication), on Fedora with
  `authselect enable-feature with-fingerprint`. Without it the dialog asks for
  the password, even when fingers are enrolled.
- The fingerprint prompt uses the `auth-fingerprint` icon and falls back to
  `fingerprint-symbolic` when the icon theme lacks it.
- No init system is assumed: fprintd is reached on the system bus, activated or
  already running.

## License

LGPL-2.1-only - see [LICENSE](LICENSE).

## Use of Generative AI

Maintainers may use generative AI tools as assistants while working on singularity-polkit-agent. Non-trivial assisted commits disclose the tool, model, and scope of the work.

AI tools may assist with code comments, documentation, repetitive code, and issue triage. Maintainers make project decisions and review every assisted change before it is merged.

Use these trailers for non-trivial assisted commits:

```plain
Assisted-by: <tool>:<model-version>
AI-Scope: <what the tool generated and the prompt or a short prompt summary>
```

Single-line completions, renames, and formatting changes do not need trailers.

Coding agents must also follow [AGENTS.md](AGENTS.md) before changing files,
creating commits, or opening pull requests.
