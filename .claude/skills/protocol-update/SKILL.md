---
name: protocol-update
description: Ordered checklist for implementing a new Minecraft Bedrock protocol version in this fork, from data dumps through boot test and version tag. Use when a new Bedrock version needs to be supported.
when_to_use: A new Bedrock release shipped and this fork must be updated to speak it. Invoked by the root workspace's bedrock-update sequence.
---

# Protocol update

This is the PMMP update workflow, adapted to this fork. It is the single most important procedure in the project. Work it top to bottom and do not skip stages, because later stages consume artifacts the earlier ones produce.

Source: PMMP's published update documentation at https://doc.pmmp.io/en/rtfd/developers/internals-docs/updating-minecraft-protocol.html

## Stage 0: Check whether upstream already did it

1. `git fetch upstream && git log upstream/stable --oneline -20`
2. `git fetch upstream 'refs/heads/bedrock-*:refs/remotes/upstream/bedrock-*'` and look for a branch named for the target version.
3. If upstream has shipped it, this whole skill collapses to: `git rebase upstream/stable` on `riftal`, resolve conflicts (there should be almost none, that is the point of the minimal diff rule), then jump to Stage 5.

Do the hand implementation only when upstream is behind and we cannot wait. That call belongs to Nasir, not to this session.

## Stage 1: Prerequisites

This work happens in a Linux container on an `ubuntu:24.04` base, not on the host. Nothing here gets installed on Nasir's Windows machine. Build a toolchain image once, with the tooling below baked in, and reuse it for every future protocol update. That image is worth keeping, because this procedure runs under time pressure and installing tools at 2 AM is how a 3-day window becomes a 5-day one.

- [ ] A toolchain container image on `ubuntu:24.04` carrying Python 3, `binutils`, and the PMMP PHP binary from the core image's PHP stage.
- [ ] The five repo clones bind mounted into it: this fork, BedrockProtocol, BedrockData, BedrockBlockUpgradeSchema, BedrockItemUpgradeSchema. Use the `axolotl-pm` forks of each, matching what `composer.json` pins. Bind mounts mean the work is committed from Windows as normal and nothing is trapped in a container.
- [ ] Bedrock Dedicated Server build matching the exact target Minecraft version, with debugging symbols (`bedrock_server_symbols.debug`). BDS is a Linux binary, which is the other reason this runs in a container.
- [ ] Local clone of the `bds-modding-devkit` tooling and the `bds-mod-mapping` data extraction mod.
- [ ] A test Minecraft world containing the features you intend to exercise.
- [ ] A real Bedrock client on the target version to test with.

The packet tracer runs BDS under `sudo` inside the container and needs to bind Bedrock's UDP port. Publish `19132/udp`, not TCP. UDP publishing was verified working on this setup on 2026-08-23.

Create a working branch: `git switch -c bedrock-<version>` off `riftal`. This name is PMMP's convention and upstream uses it too, so a branch of the same name may already exist on `upstream`. Check before you cut, since if it does, Stage 0 above already applies.

## Stage 2: Generate initial supporting data

- [ ] Dump basic protocol info from the BDS binary:
      `python3 protocol_info_dumper.py ./bedrock_server_symbols.debug ./protocol_info.json`
      Copy the result into BedrockData.
- [ ] Run the data extraction mod against BDS. Copy all files (files only, not folders) from `mapping_files/` into BedrockData. Confirm the `input_files/old_block_palettes` submodule holds the previous version's palette, since the upgrade schema is a diff against it.
- [ ] Capture packet traces. Run BDS directly, not through `start.sh`, and with no mods loaded:
      `sudo python3 tracer.py rw bedrock_server_symbols.debug`
      Join with a vanilla client, exercise gameplay broadly, stop the server. Note the output filename, for example `packets_123456789.txt`.

## Stage 3: BedrockProtocol and core code

- [ ] In BedrockProtocol: `php tools/update-from-bedrock-data.php` to generate the mechanical parts from Stage 2 output.
- [ ] Hand-patch changed packets. Diff the trace against the previous version's behavior. Cross-reference the official Bedrock protocol documentation, and disassemble `bedrock_server_symbols.debug` with IDA or GDB where the docs are silent. Update encode/decode, constants, enums, and packet direction (clientbound vs serverbound).
- [ ] `php tools/generate-create-static-methods.php`
- [ ] `php-cs-fixer` for formatting.
- [ ] Point this repo at the local BedrockProtocol clone (composer path repository) so the two can be developed together.
- [ ] `vendor/bin/phpstan analyze` here, and fix what it reports in core. PHPStan is the fastest way to find every call site the protocol change broke.

## Stage 4: Advanced supporting data and data-layer changes

Only after BedrockProtocol can parse the new version's packets.

- [ ] `php tools/generate-bedrock-data-from-packets.php ./packets_123456789.txt ../deps/BedrockData`
      This extracts creative inventory contents, crafting recipes, and related data.
- [ ] Blockstate upgrade schema: find the palette mapping file (pattern `*_to_current_block_map.bin`), run `tools/blockstate-upgrade-schema-utils.php`, and add the output to `nbt_upgrade_schema/` in BedrockBlockUpgradeSchema using the numbered naming convention, for example `0271_<from>_to_<to>.json`.
- [ ] Item upgrade schema: run `tools/generate-item-upgrade-schema.php` against `r16_to_current_item_map.json` plus the existing schemas, and add the output to `id_meta_upgrade_schema/` with the same numbering convention.
- [ ] Update `src/data/bedrock/block` and `src/data/bedrock/item` for any new or changed types.
- [ ] `composer update-codegen`
- [ ] Update `src/data/bedrock/WorldDataVersions.php`. `LAST_OPENED_IN` and `NETWORK` change every update. `BLOCK_STATES` changes often. `CHUNK`, `SUBCHUNK`, and `STORAGE` rarely do.
- [ ] `vendor/bin/phpstan analyze` until clean.
- [ ] `vendor/bin/phpunit tests/phpunit` until green.

Do not push schema or data changes to a main branch before the Minecraft version is publicly released. They describe an unreleased format.

## Stage 5: Boot test

Non-negotiable. A green test suite has never once proven a client can join.

Build the core image from the working branch and boot that image, not a loose source tree. The image is what production runs, so it is what gets tested. `/dev-stack` in `riftal-infra` covers bringing the stack up.

- [ ] Build the core image. Confirm it builds clean, since a protocol change that alters dependencies can break the build stage rather than the runtime.
- [ ] Create a fresh world in the target Minecraft client version and load it into the server.
- [ ] Start the server. It must reach "Done" with no exceptions in the log.
- [ ] Join with a real Bedrock client on the target version.
- [ ] Verify, in this order: chunks render, movement syncs, break a block, place a block, open and use a chest, take damage, respawn, rejoin.
- [ ] Restart the server and confirm the world reloads without upgrade errors. This is what catches a wrong `WorldDataVersions` constant.
- [ ] Stop the server cleanly, no errors on shutdown.

If the plugin layer is in play, hand off to `riftal-game` and run `/test-server` there before tagging.

## Stage 6: Tag

- [ ] Merge the working branch into `riftal`.
- [ ] Bump `BASE_VERSION` in `src/VersionInfo.php`. A protocol change is a **minor** bump, never a patch. Per `CONTRIBUTING.md`, protocol changes force a client update, which is a disruption a patch release may not cause.
- [ ] Commit with a subject naming the version, for example `Bedrock <version>`.
- [ ] Tag it: `git tag -a <version> -m "Bedrock <version>, protocol <number>"`.
- [ ] `git push origin riftal --tags`
- [ ] Build the core image from the tag and push it to the registry under an immutable tag matching. The image is the deployable artifact, and `/deploy-release` deploys tags, not commits. A git tag with no image behind it is not shippable.
- [ ] Report to Nasir: the version, the protocol number, the image tag, and confirmation the boot test passed. Rollout is `riftal-infra`'s job, via `/deploy-release`.

## Rules

Nothing in this procedure is an excuse to add game logic. If a protocol change tempts you to implement a vanilla mechanic, check whether the design plan actually needs that mechanic first. It usually does not.
