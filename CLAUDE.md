# pmmp-core

This is the RiftalGames server fork. It exists for one reason: to speak the current Minecraft Bedrock protocol. Nothing else belongs here.

Base: `axolotl-pm/PocketMine-MP` 5.45.0, a community continuation of PMMP 5.44.3 after pmmp/PocketMine-MP was archived on 2026-07-09. LGPL-3.0. Our work lives on the `riftal` branch.

## The only rule that matters

**No game logic, ever.** Ranks, mines, riots, economy, gangs, plots: none of it touches this repo. All game logic lives in plugins, in `riftal-game`. If you are about to write a feature here, you are in the wrong workspace. Close this one and open `riftal-game`.

The reason is swappability. The moment core carries gameplay, we can no longer rebase onto a different fork base or take an upstream update cleanly, and a protocol drop that should cost days starts costing weeks.

## Keep the diff minimal

Every change here must answer one question:

> Does this help ship the next protocol version faster?

If the answer is no, it does not go in. That includes tidy-ups, refactors, style fixes, and vanilla content parity work. Content parity with vanilla is explicitly skipped unless a mechanic the design plan depends on is broken without it.

Acceptable changes:

- Protocol implementation and packet handling
- Build tooling, CI, and the release/tag process
- Configuration defaults required by our deployment, for example proxy-related settings
- Bug fixes that block a boot or a join

Run `/diff-audit` before any release tag to confirm nothing else crept in.

## Remotes

| Remote | Points at | Use |
|---|---|---|
| `origin` | `git@github.com:Riftal-Games/pmmp-core.git` | Our fork. Private. |
| `upstream` | `axolotl-pm/PocketMine-MP` | Where protocol updates come from. Fetch before doing protocol work by hand. |
| `pmmp` | `pmmp/PocketMine-MP` (archived) | True vanilla 5.44.3 baseline, for measuring total drift. |

## Branches

Working-branch names follow PMMP's own conventions, per `CONTRIBUTING.md`. Our mainline does not, and that is deliberate.

| Branch | Role |
|---|---|
| `riftal` | Our mainline. Default on `origin`. Currently at tag `5.45.0`. |
| `stable` | Read-only mirror of `upstream/stable`. It is how we see how far upstream has moved. Never commit to it. |
| `bedrock-<version>` | Protocol work. Cut from `riftal`, merged back into it. |
| `feat/<name>` | Feature work, which here means build tooling and deployment config. Game logic is forbidden, so there is little else it can be. |
| `experimental/<name>` | Spikes that may be thrown away. |

We do **not** run PMMP's `minor-next` and `major-next` release lines. Those exist to version a public plugin API across compatibility levels for thousands of consumers. This fork has one consumer and keeps game logic out of core, so both branches would sit empty while still needing to be kept in sync.

The mainline is not called `stable` because that name is taken by the upstream mirror above, and because `/diff-audit` rests on `upstream/stable...riftal` being unambiguous at a glance. That check gets run under release pressure.

Decided 2026-08-26. See `../docs/decision-log.md`.

## Versioning

Protocol changes ship as a new **minor** version, never a patch. PMMP's rule, and the reason is ours too: a protocol change forces every player to update their client, which is a disruption a patch release is not allowed to cause.

## Protocol position

- This build: Bedrock 1.26.40, `axolotl-pm/bedrock-protocol` 59.0.1+bedrock-1.26.40.
- PMMP's final release 5.44.3 was Bedrock 1.26.30, protocol 1001.
- Live Bedrock at bootstrap time was 26.42 (protocol 2168, released 2026-08-07).

Confirm the live number before acting on it. Read `CURRENT_PROTOCOL` and `MINECRAFT_VERSION_NETWORK` from `vendor/axolotl-pm/bedrock-protocol/src/ProtocolInfo.php` for what this build actually speaks. `vendor/` is produced inside the build container, so on a fresh checkout it does not exist on the host and the pinned `axolotl-pm/bedrock-protocol` version in `composer.json` is the fallback source of truth.

We support a single protocol version at a time. There is no multi-version compatibility layer and we are not adding one. The accepted cost is 1 to 3 days of downtime per Bedrock minor release.

## Workflow

- New Bedrock version: run `/protocol-update`. Always check `git fetch upstream && git log upstream/stable --oneline` first, because if upstream already did the work, this is a rebase and not an implementation.
- Before tagging: run `/diff-audit`.
- Protocol updates are priority one on this project. They preempt everything else.

## Build and test

**Everything builds and runs in a container.** Decided 2026-08-23, see `../docs/decision-log.md`. Nothing is installed on the host, and nothing should be. Requesting a host PHP install is the wrong answer, always.

`docker/Dockerfile` does the work. Its first stage runs `build/php/compile.sh` to produce the PMMP PHP binary with the extensions this server needs: pmmpthread, leveldb, chunkutils2, crypto, encoding, igbinary, morton, yaml. System PHP has none of them and will never work. The second stage runs composer and builds the phar. The third is a slim runtime.

That PHP stage is deliberately separate so a source change does not recompile PHP. Do not merge the stages. The first build takes roughly 20 to 40 minutes; later ones reuse the layer.

The build image is the artifact. Every instance in production runs this same image by immutable tag, so a build that works here works there by construction.

Locally the container CLI is `wslc`, which is what Nasir's Windows machine has. Nothing in the Dockerfile may depend on it, because production does not have it.

Run `composer install`, `vendor/bin/phpstan analyze`, and `vendor/bin/phpunit tests/phpunit` inside a container built from the PHP stage, not on a host.

Boot test before every tag: start the container, join with a real Bedrock client on the target version through the proxy, confirm chunk load and block break, stop cleanly.

### Known gaps

- `build/php` is a submodule and is **not initialized**. The first build stage copies `build/php/compile.sh`, so the image build fails immediately until `git submodule update --init --recursive` is run.
- The Dockerfile inherits `ubuntu:22.04` from upstream. Our base image is `ubuntu:24.04`. This needs changing here, and it counts as build tooling under the minimal-diff rule, so it is an acceptable change.
- `build/php` is pinned to a commit of the archived `pmmp/php-build-scripts`. Whether it builds the extension versions `axolotl-pm` 5.45.0 expects is unverified. Find out on the first build.
- Four shell scripts show as modified, mode 100755 to 100644, from a Windows checkout dropping the exec bit. `git config core.filemode false` clears it.

## Communication style

Direct and concise. Short points, minimal words.
Never use em dashes.
Answer what was asked. No unrequested analysis.
When you need a decision, ask one clear question with options.
