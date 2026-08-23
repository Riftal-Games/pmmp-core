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
| `origin` | `git@github.com:Riftal-Studios/pmmp-core.git` | Our fork. Private. |
| `upstream` | `axolotl-pm/PocketMine-MP` | Where protocol updates come from. Fetch before doing protocol work by hand. |
| `pmmp` | `pmmp/PocketMine-MP` (archived) | True vanilla 5.44.3 baseline, for measuring total drift. |

Branch: `riftal`, currently at tag `5.45.0`.

## Protocol position

- This build: Bedrock 1.26.40, `axolotl-pm/bedrock-protocol` 59.0.1+bedrock-1.26.40.
- PMMP's final release 5.44.3 was Bedrock 1.26.30, protocol 1001.
- Live Bedrock at bootstrap time was 26.42 (protocol 2168, released 2026-08-07).

Confirm the live number before acting on it. Read `CURRENT_PROTOCOL` and `MINECRAFT_VERSION_NETWORK` from `vendor/axolotl-pm/bedrock-protocol/src/ProtocolInfo.php` for what this build actually speaks.

We support a single protocol version at a time. There is no multi-version compatibility layer and we are not adding one. The accepted cost is 1 to 3 days of downtime per Bedrock minor release.

## Workflow

- New Bedrock version: run `/protocol-update`. Always check `git fetch upstream && git log upstream/stable --oneline` first, because if upstream already did the work, this is a rebase and not an implementation.
- Before tagging: run `/diff-audit`.
- Protocol updates are priority one on this project. They preempt everything else.

## Build and test

Requires the PMMP PHP binary, not system PHP. Build it with `build/php/compile.sh` from the pmmp/PHP-Binaries workflow, or install a prebuilt binary matching this version. Ubuntu 24.04 is the supported host.

```
composer install
vendor/bin/phpstan analyze
vendor/bin/phpunit tests/phpunit
```

Boot test before every tag: start the server, join with a real Bedrock client on the target version, confirm chunk load and block break, stop cleanly.

## Communication style

Direct and concise. Short points, minimal words.
Never use em dashes.
Answer what was asked. No unrequested analysis.
When you need a decision, ask one clear question with options.
