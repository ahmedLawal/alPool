# alPool — living context & decision log

> **This is the project memory.** Read it before non-trivial work; append to it as
> soon as a decision is made or a change ships. It travels with the repo, so any
> fresh Claude Code session (or teammate) picks up where the last one left off.
>
> **How to keep it useful (anti-rot):**
> - Keep **Current focus** short — what's active *now*. Overwrite it; don't append.
> - **Decisions** is append-only. Newest at the top. Each entry is dated, numbered,
>   and states *context → decision → consequences*. Never delete a decision; if one
>   is reversed, add a new entry that says "supersedes #N".
> - When this file passes ~400 lines, move the oldest resolved decisions to
>   `docs/CONTEXT-ARCHIVE.md` and leave a one-line pointer here.
> - The mechanics (what to read, what to write, wrap-up) live in the
>   `/maxpool-builder` skill.

---

## Current focus

Ahmed's personal fork is branded alPool. The executable is `alpool`, the personal
repository is `ahmedLawal/alPool`, and the globally linked checkout pulls its own
`origin/main`. Compatibility-sensitive identifiers remain unchanged: alPool uses
the existing `~/.config/maxpool.json`, `MAXPOOL_*` environment variables,
`x-maxpool-*` headers, and `/maxpool/status` endpoint, so no account or integration
migration is required. Upstream remains `2solarmax/maxpool`; synchronization runs
locally through a six-hour macOS LaunchAgent and a transactional Bash script.

A native SwiftUI macOS client is the primary IO layer. The Node
backend remains the sole owner of proxying, credentials, configuration, routing,
updates, and lifecycle; the app attaches to a headless backend and can close
without interrupting traffic. The signed app is installed at
`/Applications/alPool.app`; the backend runs through the per-user
`com.ahmedlawal.alpool.backend` LaunchAgent. The existing TUI remains a fallback
client.

Multi-provider + routing modes + restart UX shipped v1.5.64–v1.5.83. The proxy now
load-balances across Anthropic OAuth + GLM (z.ai) + Kimi (Moonshot) with five named
routing modes. Current version: **v1.10.2** (installed as a global symlink to
`~/Sources/repo/Me/alPool`, so validated fast-forwards update the running install).

**Recently shipped (2026-08-10/11):**
- v1.5.80: routing modes (`balance`, `prefer-claude`, `prefer-zai`, `prefer-kimi`,
  `sticky`) replacing the opaque 3-policy knob. Utilisation-weighted scoring in
  `balance` mode. Session binding only under `sticky`.
- v1.5.81: restart UX fix — seamless path skips the 10s pre-drain (it was pure cost:
  30-60s requests never finish in 10s, so it was always 10s of guaranteed 503s for
  zero drained requests). Progress ticks during cold-path drain. Honest confirm text.
- v1.5.82: cache-first secret resolution (reads `~/.claude/.credentials-cache` before
  `gcloud`, fixing `secret-unresolved` rows that spawned duplicate `-fallback`
  entries). Routing modes exposed in TUI (`f`/`m` key cycle).
- v1.5.83: hide inert "Cross-provider: always" text under non-sticky modes (it
  looked like two conflicting controls when only the mode governed routing).

**Open items:**
- `glm max@gomokka.com` (legacy TOKENS_LIMIT plan) has no weekly limit — confirmed
  real (not a parse gap), but z.ai is sunsetting legacy plans (migration notice
  April 2026). Don't rely on this long-term.
- Ahmed's RESTRICTED_AL_MAXPOOL_ZAI key is absent from Max's credentials cache
  (~17s gcloud resolution at boot on Max's machine; instant on Ahmed's).
- `crossProviderFallbackPolicy: when-exhausted` still in config.json — inert
  (routingMode takes precedence), cleaned up on next `f` key cycle.

---

## Decisions

### 2026-08-24 · #24 — MaxPool v1.10.2 capacity and repair updates are integrated

**Context:** The automatic upstream merge stopped at six overlapping hunks in
`package.json`, `account-manager.js`, and `index.js`. MaxPool added its capacity
ledger, executing-version reporting, drain-time state merge, and transcript
repair fixes where alPool already carried branding, live activity capture, and
native lifecycle integration. The new running-version test also imported Max's
checkout through an absolute `/Users/maxkrasnykh/...` path; another capacity test
failed the repository lint on an unused variable, and the live invariant utility
still defaulted to the retired `teamclaude.state.json` filename.
**Decision:** Merge the latest v1.10.2 release manually. Preserve alPool identity,
activity subscriptions, and log branding while accepting the upstream capacity,
boot-version, and safe drain-flush behavior. Make the running-version test import
the repository-relative account manager, remove the unused test variable, and
derive the invariant utility's default from the real configured state path.
**Consequences:** alPool receives v1.8.0 through v1.10.2 without dropping its
native IO features. Future source overlaps continue to fail closed, and the
portable test correction should be proposed upstream to prevent recurrence.

### 2026-08-24 · #23 — Backend LaunchAgent receives explicit GCP credentials

**Context:** Three enabled z.ai accounts remained `secret-unresolved` in the
native app even though their Secret Manager entries existed and were readable
from Ahmed's terminal. The backend LaunchAgent did not inherit the shell's
`CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE`; uncached secret lookups therefore used
interactive gcloud credentials and could not reauthenticate from a headless job.
**Decision:** At installation, detect the shell's explicit ADC override or the
standard per-user Application Default Credentials file and add that readable
path to the LaunchAgent environment. Keep the cache-first resolver unchanged and
never copy credentials into the plist or repository.
**Consequences:** GCP-backed provider secrets resolve after app-managed startup
and login without an interactive prompt. Machines without a readable ADC file
retain the existing cache/gcloud behavior, and the plist exposes only a local
file path under mode 0600.

### 2026-08-24 · #22 — Activity timestamps render in the Mac's timezone

**Context:** The native Activity page extracted the clock portion directly from
the backend's ISO timestamp, so UTC values appeared unchanged even when the Mac
used another timezone.
**Decision:** Keep backend event timestamps canonical and convert them only in the
SwiftUI presentation layer. Parse ISO timestamps with and without fractional
seconds, apply `TimeZone.current`, and preserve the existing 24-hour `HH:mm:ss`
row format.
**Consequences:** Activity history follows timezone changes on the local Mac
without changing backend events, API contracts, routing, or other clients.

### 2026-08-21 · #21 — Native quota notifications follow confirmed state transitions

**Context:** Quota safety and reset timing were visible in the native Overview,
but Ahmed had to keep watching the app to know when an account crossed a risky
usage level or became available after a reset.
**Decision:** Evaluate the existing two-second control snapshots in a deterministic
Swift core engine and deliver native macOS alerts from the SwiftUI IO client.
Notify enabled accounts once when either quota window crosses 60%, 85%, or 100%,
and notify a reset only when usage drops with an advanced/elapsed reset cycle.
Persist the last observations, suppress the initial snapshot, and expose separate
threshold/reset toggles plus permission status and a test action in a grouped
Notifications page.
**Consequences:** Alerts reuse the backend's normalized provider quota without
moving quota logic or credentials into the app. Missing windows and unlimited
weekly plans do not alert, relaunches do not replay warnings, and notifications
continue after the window closes but stop if the alPool app process is quit.

### 2026-08-20 · #20 — Known package branding conflicts are reconciled semantically

**Context:** MaxPool v1.7.1 changed the upstream package version in the same JSON
region where the personal fork carries its alPool name, command, scripts, and
repository metadata. Git therefore stopped every local upstream sync even though
the changes were compatible.
**Decision:** When `package.json` is the sole unresolved path, perform a guarded
three-way JSON merge after verifying the Git stages are MaxPool base, alPool fork,
and MaxPool upstream. Preserve changes made on only one side, combine compatible
object changes, and reject values changed differently on both sides. All other
conflicts continue to fail closed. Integrate the validated MaxPool v1.7.1 merge
while retaining alPool's identity.
**Consequences:** Routine upstream version bumps no longer require manual conflict
resolution, but genuine package or source conflicts cannot be silently accepted.
The merged result still must pass dependency installation, tests, and lint before
the personal `main` branch is pushed.

### 2026-08-20 · #19 — Density picker label is accessible but visually hidden

**Context:** The Compact/Detailed segmented picker rendered its “Account detail”
label in the Accounts header. Constrained by the toggle and safety legend, the
label wrapped into a malformed vertical column.
**Decision:** Apply SwiftUI's native `labelsHidden()` modifier to the segmented
picker, preserving its semantic label for accessibility while removing it from
the visual layout.
**Consequences:** The Accounts header contains only the intended title, density
control, and safety legend without sacrificing the picker's accessible name.

### 2026-08-19 · #18 — Overview distinguishes quota safety from live serving

**Context:** Uniform blue quota bars hid the difference between safe, caution,
and critical usage. Every healthy account also displayed “Active,” which looked
like every account was currently serving traffic, while detailed request/token
totals made the overview unnecessarily tall for routine monitoring.
**Decision:** Use solid traffic-light quota fills: green below 60%, amber from
60–84%, and red at 85% or higher. Suppress routine healthy “Active” on Overview,
but keep exceptional health states and use `inFlight` for a green card outline and
Serving badge. Add a persistent Compact/Detailed toggle; Compact hides only
request/token totals and both modes retain separate five-hour and weekly rows.
**Consequences:** Quota risk and live traffic are visually distinct. Overview can
be dense without losing reset windows, while Accounts management retains complete
status and controls.

### 2026-08-19 · #17 — Native Activity uses a shared redacted backend feed

**Context:** The TUI kept an in-memory list of in-flight and completed requests,
but the headless backend used by the native app had no equivalent state in its
control snapshot, so moving to the app removed real-time traffic visibility.
**Decision:** Maintain one bounded, redacted activity feed in the Node worker from
the existing request hooks and event-log observer. Expose active requests and the
latest 200 completed/backend events through the control snapshot for both IO
clients, without request bodies, credentials, or full session identifiers.
**Consequences:** The native Activity page reaches operational parity with the TUI
on its existing two-second polling cycle. Activity is intentionally process-local
and starts fresh whenever the backend worker restarts.

### 2026-08-19 · #16 — Upstream sync health is part of the control snapshot

**Context:** The native Updates page could compare the running checkout with the
personal fork, but an upstream MaxPool merge failure left `origin/main` unchanged
and therefore looked "up to date" unless Ahmed inspected the LaunchAgent log.
**Decision:** Persist a small, atomic upstream-sync status record containing the
installed and latest upstream versions, sync phase, timestamps, and a safe failure
summary. Expose it through the Node control snapshot and render it in the existing
SwiftUI Updates form.
**Consequences:** Merge and validation failures are visible without parsing or
exposing logs. The live backend remains on the last validated version, while the
app identifies both that installed version and the blocked upstream version.

### 2026-08-19 · #15 — Overview summarizes enabled accounts only

**Context:** The native Overview account list repeated disabled rows that cannot
serve traffic, making the operational summary noisier than the active pool.
**Decision:** Filter Overview cards to enabled accounts while keeping the Accounts
management page as the complete inventory.
**Consequences:** Overview reflects the currently usable pool; disabled accounts
remain visible and re-enableable under Accounts.

### 2026-08-19 · #14 — Native app and login-managed backend are active

**Context:** The native client and control API were tested in isolation, while the
live proxy still belonged to a terminal process. That process could not expose the
new control endpoint or survive login independently of its terminal.
**Decision:** Install the signed app in `/Applications` and complete the one-time
cutover to the guarded `com.ahmedlawal.alpool.backend` LaunchAgent after the tested
integration reached personal `main`. Use the authenticated control API—not an
operating-system signal—for future app-initiated restart and stop operations.
**Consequences:** alPool starts when Ahmed logs in, closing the app does not stop
traffic, and backend logs live at `~/Library/Logs/alPool/backend.log`. The primary
checkout stays clean on `main`, so git-source automatic updates can fast-forward
and reload it again.

### 2026-08-19 · #13 — Finder launches Node explicitly and the linked checkout stays on main

**Context:** Finder does not inherit the interactive shell's NVM path, so invoking
the linked `alpool` shebang through `/usr/bin/env node` failed even though the app
found the executable. Separately, the globally linked checkout remained on a
feature branch, causing the intentionally conservative git updater to reject every
automatic pull.
**Decision:** Resolve and invoke Node explicitly, preferring the binary beside the
discovered `alpool` executable and supporting `ALPOOL_NODE_EXECUTABLE` as an
override. Integrate feature work into personal `main` and keep the globally linked
primary checkout on that branch.
**Consequences:** The native app works when launched from Finder without shell
initialization. Automatic updates can fast-forward the clean linked checkout again;
development branches remain isolated in separate worktrees.

### 2026-08-18 · #12 — Native macOS app is an IO client, not a backend port

**Context:** The terminal dashboard makes alPool operationally opaque and ties its
controls to the terminal that launched the proxy. Ahmed wants a native macOS app
but does not want the routing, quota, credential, or update logic rewritten in
Swift.
**Decision:** Keep Node as the single backend and extract TUI-owned operations into
a shared control service. Expose authenticated loopback status and command
interfaces, then build a native SwiftUI client that renders state and sends typed
commands. Run the backend independently of the app; closing the app never stops
traffic. Keep the TUI as a fallback adapter over the same service.
**Consequences:** Backend behavior stays testable once and consistent across both
frontends. A one-time, separately controlled cutover will eventually replace the
terminal-owned process with a login agent. Development and validation happen in an
isolated worktree and do not touch the live listener on port 3456.

### 2026-08-17 · #11 — Upstream synchronization runs locally, not in GitHub Actions

**Context:** Decision #9 used a scheduled GitHub workflow to merge and validate
upstream. Ahmed prefers the synchronization authority to remain on his Mac and
explicitly requested a local Bash-like job instead.
**Decision:** Supersede the hosted-sync portion of #9. Install a per-user macOS
LaunchAgent that runs `scripts/sync-upstream.sh` at login and every six hours. The
script fetches both remotes, merges in a disposable detached worktree, runs the
full test suite and lint, and pushes `origin/main` only after validation succeeds.
The existing alPool updater remains responsible for fast-forwarding the clean live
checkout and seamlessly reloading it.
**Consequences:** GitHub CI no longer decides when upstream is imported. A failed
merge, test, lint, authentication, or non-fast-forward push leaves personal `main`
unchanged. The LaunchAgent requires this Mac to be awake and logged in; a missed
interval is recovered by `RunAtLoad` or the next six-hour run.

### 2026-08-17 · #10 — Personal fork is branded alPool without migrating credentials

**Context:** Installing the personal fork under the upstream `maxpool` command made
it unclear whether a terminal was running Ahmed's fork or the former global tool.
Renaming config, environment variables, or routing headers at the same time would
strand accounts and break existing Claude aliases.
**Decision:** Rename the product and logs to `alPool`, expose only the `alpool` CLI,
and rename the personal repository/checkout. Preserve `~/.config/maxpool.json`,
`MAXPOOL_*`, `x-maxpool-*`, and `/maxpool/status` as compatibility interfaces.
**Consequences:** `npm uninstall -g maxpool` can remove the former executable and
`npm link` installs the unambiguous `alpool` command. Existing credentials and
client integrations continue to work unchanged.

### 2026-08-17 · #9 — Personal-fork updates use a tested upstream sync plus checkout pulls

**Context:** npm auto-update always installs `maxpool@latest`, which would replace
Ahmed's personal quota-display changes with the upstream package. A separate npm
package would require new publishing credentials and release infrastructure. The
runtime symptom behind GLM rows stuck on "probing" was also concrete: Ahmed's
config still carries `quotaProbeSeconds: 0`, the original generated default, so
the otherwise-working z.ai monitor endpoint never runs.
**Decision:** Add a scheduled/manual GitHub workflow that merges upstream `main`,
runs tests and lint, and pushes only on success. Add a `git` update source that
checks a configured remote/ref and pulls it with `--ff-only` for linked checkout
installs; this personal fork defaults to that Git source, while upstream retains
its npm behavior. Treat a legacy zero probe
interval without `quotaProbeEnabled` as the old generated default and migrate it
to 60 seconds; `quotaProbeEnabled: false` is the unambiguous opt-out. Render
`quota off` when monitoring is intentionally disabled.
**Consequences:** The personal fork receives upstream work without borrowing the
upstream npm publishing identity, local modifications block rather than being
overwritten, and GLM 5-hour/weekly bars populate automatically for legacy users.
The personal checkout must be globally linked (`npm link`) for git-source updates.

### 2026-08-10 · #8 — Five named routing modes replace crossProviderFallbackPolicy

**Context:** `crossProviderFallbackPolicy: 'always'` read as "load balance across
everything" but only governed a session's FIRST request — after that, the session
was pinned to one account (per-ACCOUNT, not per-provider). ~30 sessions that started
on the same account hammered it forever while every other account idled. The pin
existed for signed-thinking-block safety, which was empirically disproven (2026-07-02,
cross-account replay returned 200) and provider-authored thinking blocks are now
auto-stripped (v1.5.64+).
**Decision:** Replace the single knob with five explicit modes. `balance` scores
every request across the whole pool. `prefer-*` modes bias toward a provider
family. `sticky` preserves the old behavior. Migration: `always`→`balance`,
`when-exhausted`→`prefer-claude`, `never`→`sticky`. TUI `f`/`m` cycles modes.
**Consequences:** The per-provider `claudeFallback` knob (`g`/`k` keys) is now
inert under every mode except `sticky`. The header only renders it under `sticky`.

### 2026-08-10 · #7 — Cache-first secret resolution

**Context:** Resolving 5 GCP secrets via `gcloud secrets versions access` in
parallel at boot caused 3 of 5 to hit the 45s timeout (gcloud invocations contend
on credential cache + network). Unresolved secrets left config providers in
`error: secret-unresolved` state, and the header-based runtime path created
duplicate `-fallback` rows beside them.
**Decision:** Read `~/.claude/.credentials-cache` (plaintext JSON, written by
`scripts/load-secrets.sh`, mode 0600, sanctioned) FIRST. Fall back to gcloud
sequentially only for names the cache lacks. Measured: 5/5 resolve in 17.5s
(4 from cache instantly, 1 gcloud miss) vs 2/5 before.
**Consequences:** No new attack surface (an attacker who can read the cache
already has everything). Cache staleness bounded: a rotated key 401s → provider
shows error → degrades gracefully. alPool restart picks up refreshed cache.

### 2026-08-10 · #6 — Seamless restart skips the pre-drain

**Context:** `r` → `y` paused admission immediately, then waited up to 10s for
in-flight requests to drain. With ~30 sessions running 30-60s requests, the drain
NEVER completed naturally — it always timed out, producing 10s of guaranteed 503s
across the fleet. The seamless baton path already drains in-flight requests
post-handoff (releaseBatonAndDrain, 60s+ cap), so the pre-drain was redundant.
**Decision:** `RestartController` now takes an `isSeamless()` predicate. When true,
the restart fires immediately — in-flight requests finish on the old worker after
the baton passes. Cold path still drains (socket closes, so in-flight would be
severed without it).
**Consequences:** `admissionPaused` is constructor-initialised false and never
persisted — a cold start always begins with admission open. The 503 message now
reads "finishing in-flight requests first" instead of "Retry immediately".

### 2026-08-07 · #5 — Multi-provider support (GLM/Kimi)

**Context:** alPool was Anthropic-only. Max wanted to add GLM (z.ai) and Kimi
(Moonshot) accounts to the pool so Claude Code sessions could spread across three
providers.
**Decision:** Provider accounts carry an API key (not OAuth). Keys stored in
`~/.config/teamclaude.json` as GCP secret names, resolved at boot. Provider quota
probed from each provider's own usage API. Providers participate in routing
according to the mode (see #8). Provider-authored thinking blocks are auto-stripped
before forwarding to Anthropic (rejected-block self-heal via revert-to-issuer).
**Consequences:** Provider keys are owner-scoped via GCP IAM. Adding a teammate's
key: `gcloud secrets create RESTRICTED_<USER>_MAXPOOL_ZAI` + IAM binding. Team
registry: `mokka-workspace/knowledge/technical/maxpool-api-key-registry.md`.

### 2026-07-23 · #4 — Project-context harness is committed in-repo

**Context:** alPool lives outside the mokka-workspace, so it inherits none of
that workspace's skills/rules/memory. Goal: a fresh Claude Code session should
pick up full project context + keep an evolving memory.
**Decision:** Ship the harness as committed files in *this* repo — `CLAUDE.md`
(always-loaded facts/invariants), `docs/CONTEXT.md` (this living log), a
`.claude/` SessionStart hook that injects the memory head at session open, and a
project-agnostic `/maxpool-builder` skill. Reading is guaranteed by a CLAUDE.md
imperative + the hook (not a skill that only loads when invoked); writing is
event-driven (append on each decision/change, not an end-of-session ritual).
**Consequences:** Everything travels with the clone. The skill body is generic,
so reusing this pattern on another repo is copy-the-folder + drop a seed
`CLAUDE.md`/`CONTEXT.md`, not a rewrite. A plugin/marketplace is deferred until a
second project actually needs it.

### 2026-07-23 · #3 — In-repo CHANGELOG via git-cliff; leave publish.yml's release notes as-is

**Context:** Releases shipped silently — no CHANGELOG, and GitHub Release bodies
were empty because `publish.yml` built notes from merged PRs while maxpool
commits directly to main. A parallel session had already fixed the *Release body*
(now generated from the commit log since the previous tag — works; see v1.5.37).
**Decision:** Add the missing **in-repo** `CHANGELOG.md` with **git-cliff** (a
changelog *generator*, pinned as a devDep, run from the package.json `version`
hook) — NOT a release orchestrator (semantic-release / release-please /
changesets), which would replace `release.sh`'s version/tag logic and break the
tag-triggered OIDC publish. **Leave the working `publish.yml` release-notes step
untouched** — both derive from the same Conventional Commits, so they stay
consistent, and there's no reason to churn release-critical CI another session
just shipped.
**Consequences:** `cliff.toml` + `scripts/update-changelog.sh` + a pinned
`git-cliff` devDep + a backfilled `CHANGELOG.md` (49 sections; pre-1.1 history is
a best-effort import). No change to `release.sh` or `publish.yml`. If the repo
ever adopts a PR flow, GitHub's native `--generate-notes` becomes viable and this
can be revisited.

### 2026-07-23 · #2 — Harden the npm account (2FA + disallow tokens)

**Context:** OIDC Trusted Publishing means no long-lived npm token is needed.
**Decision:** Enable "Require two-factor authentication and disallow tokens" on
the npm account. OIDC publishing keeps working with this on.
**Consequences:** Removes long-lived publish tokens as an attack surface.
**Status:** Done 2026-07-23 — 2FA enabled + `maxpool` package publishing access
set to "require 2FA and disallow tokens"; OIDC publish unaffected.

### 2026-07-23 · #1 — Release-record posture: forward-only + in-repo, log-not-announce

**Context:** alPool is a ToS gray-area tool; the public GitHub Release page is
the first npm-linked, search-indexed "what this does" surface, and commit
subjects can describe quota/rate mechanics.
**Decision:** Keep the rich record **in-repo** (`CHANGELOG.md`); go **forward-only**
on public GitHub Release bodies (do not bulk-populate the ~50 old ones); use
neutral, factual phrasing in anything release-surfaced. **Log everything, announce
almost nothing** — reserve any announcement for a major or security release.
**Consequences:** The low-profile posture is the default for all release work here.
