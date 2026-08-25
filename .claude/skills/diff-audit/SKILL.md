---
name: diff-audit
description: Diff this fork against its upstream base and flag anything that is not protocol or build related. Use before any release tag, and any time the fork feels like it has drifted.
when_to_use: Before tagging a release, before a rebase onto upstream, or when a rebase produces more conflicts than expected.
---

# Diff audit

The value of this fork is that it is small. A small diff rebases onto upstream in minutes and can be abandoned for a different fork base if `axolotl-pm` stalls. A large diff traps us. This audit is how the diff stays small.

## Run

```
git fetch upstream
git fetch pmmp
```

Then produce three views:

1. **Against our base**, the diff we actually maintain:
   `git diff --stat upstream/stable...riftal`

   `upstream/stable` is theirs, `riftal` is ours. The mainline is deliberately not named `stable` so this pair cannot be misread. See `CLAUDE.md` under Branches.
2. **Against true vanilla**, total drift since PMMP's final release:
   `git diff --stat pmmp/stable...riftal`
3. **File list only**, for classification:
   `git diff --name-only upstream/stable...riftal`

## Classify

Put every changed file in exactly one bucket. Read the actual hunks, not just the filename, because a config file can hide game logic.

| Bucket | Verdict | Examples |
|---|---|---|
| Protocol | Keep | `src/network/**`, packet handling, `src/data/bedrock/**`, `WorldDataVersions.php` |
| Build and tooling | Keep | `composer.json`, `build/**`, CI workflows, `.gitignore`, version constants |
| Deployment config | Keep if justified | Defaults required by the WaterdogPE setup, for example xbox-auth and xuid verification defaults |
| Documentation | Keep | `CLAUDE.md`, `.claude/**`, README changes describing the fork |
| **Game logic** | **Remove** | Anything implementing ranks, mines, riots, economy, gangs, plots, or any custom mechanic |
| **Unjustified churn** | **Remove** | Refactors, renames, style changes, vanilla content parity work with no mechanic depending on it |

For each file in a Keep bucket, state in one line why it is there. If you cannot state why in one line, it belongs in a Remove bucket.

## Report

```
Base: upstream/stable  Drift: <n> files, +<a>/-<b>
Vanilla: pmmp/stable   Drift: <n> files, +<a>/-<b>

Keep (<n>):
  <file>  <one-line reason>

Flagged (<n>):
  <file>  <bucket>  <what to do about it>
```

## On a flag

Game logic found in core is a defect, not a preference. It moves to `riftal-game` as a plugin. Say so plainly, name the plugin it belongs in, and tell Nasir which workspace to open to do the move. Do not do the move from here.

If the flagged change genuinely cannot live in a plugin, that is a real finding worth writing up: it means a plugin API is missing in core. The fix is to add the smallest possible hook or event in core, not the feature itself, and to record it in the root `docs/decision-log.md`.

## Thresholds

There is no hard file-count limit, but treat these as alarms:

- More than 40 files diverged from `upstream/stable`
- Any file under `src/` that is not network, data, or version related
- A rebase onto upstream producing conflicts in more than a handful of files

Any of those means the audit stopped being a formality. Report it as a blocker before the release tag.
