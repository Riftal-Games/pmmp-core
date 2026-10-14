# The self-hosted CI runner

Where this repository's CI runs, what that machine is, and why it must never run a
pull request from an outside fork. Riftal-Games/pmmp-core#48.

## Which jobs run on it

Every workflow job in this repository that does work for a pull request or a push to
`riftal` targets the labels `[self-hosted, linux, riftal]`. `main-php-matrix.yml` takes
its labels from an `image` input whose default is the same array. GitHub picks any
online runner registered to this repository that carries all three labels.

Three more workflows target the same labels without a pull request or a push to
`riftal`: `pr-stale.yml` on a manual dispatch, `support.yml` when an issue is
labeled, unlabeled or reopened, and `pr-remove-waiting-label.yml` together with the
`check` job of `draft-release.yml`, both described under the hazard below.

The jobs on GitHub-hosted labels (`ubuntu-22.04`, `ubuntu-latest`) are:

- `docker-image-publish.yml`, `discord-release-notify.yml` and
  `update-updater-api.yml`, on a published release or a manual dispatch;
- `crowdin-upload-trigger.yml`, on a push to `stable`, `minor-next` or `major-next`
  touching `resources/translations/eng.ini`, or a manual dispatch;
- `branch-sync-cron-trigger.yml` and `crowdin-download-cron-trigger.yml`, on a
  manual dispatch only;
- the `skip`, `trigger-post-release-workflow` and `draft` jobs of
  `draft-release.yml`, but not its `check` job.

Which runners exist is decided by registration, not by this document:

```
gh api repos/Riftal-Games/pmmp-core/actions/runners
```

Riftal-Games/riftal-pm#1258 tracks whether a second runner for this repository is
registered again.

## Where it lives

The runner is the GitHub `actions/runner` service, installed as a systemd unit
(`actions.runner.Riftal-Games-pmmp-core.<runner name>.service`) running as the Linux
user `runner` from `/home/runner/pmmp-core`, inside the WSL distro `Ubuntu-26.04` on
Nasir's development PC. Jobs check out under that directory's `_work`.

The same distro hosts the runners of the other Riftal-Games repositories and one
Docker daemon that all of them share, along with one `/tmp`. The
`.github/actions/runner-temp` action exists because of that shared `/tmp`.

What the `runner` user holds there, read from the distro:

- membership of the `docker` group, so every job can drive the shared Docker daemon;
- `sudo` with `NOPASSWD: ALL`;
- the Windows drive at `/mnt/c`, including the working trees under
  `/mnt/c/Users/nasir/riftal-games`.

CI is therefore down whenever that PC or that distro is.

## What it is, against hard rule 7

The runner is not a container, and its OS is not `ubuntu:24.04`. `/etc/os-release` in
the distro reads `Ubuntu 26.04 LTS`. The runner process runs directly on that distro,
and so does every step that does not call `docker` itself: PHPStan, PHPUnit, the
integration and codegen checks, code style, ShellCheck, the docs and translation
checks and the release checks all run there. PHP comes from the runner's setup
actions, not from the image: `axolotl-pm/setup-php-action` in `main-php-matrix.yml`
and `copilot-setup-steps.yml`, `shivammathur/setup-php` in the code style and
translation jobs of `main.yml` and in `draft-release-pr-check.yml`. Only the image
build, its smoke steps and actionlint run in containers. No job in this repository
sets `container:`.

Hard rule 7 puts `ubuntu:24.04` in the image, not on the host: riftal-pm's
`docs/decision-log.md`, under "2026-08-23: Containers are the deployment model, dev
and production", makes the host OS only a container runtime. The image this runner
builds and smoke-tests is `FROM ubuntu:24.04` in all three stages of
`docker/Dockerfile`, and `docker/check-ubuntu-base.sh` holds it there.

The runner itself running outside a container, on Ubuntu 26.04, is allowed for CI
only by two entries in the same log:

- "2026-09-27: Self-hosted CI runner, Docker inside the WSL distro Ubuntu-26.04",
  Nasir's call;
- "2026-09-28: CI moves from GitHub-hosted to self-hosted runners, forced by a billing
  lockout, superseding "No self-hosted CI runner"", which records the runner as the
  `actions/runner` service running directly inside the distro against its native
  Docker daemon.

## The fork pull request hazard

A `pull_request` job checks out and runs the pull request's own code. On this runner
that code runs as `runner`, with passwordless root, the shared Docker daemon and the
Windows drive. Code that reaches it can read or change anything on the PC, tamper
with the other repositories' runners and the local container stack, and persist
between runs, since a self-hosted runner's machine is not thrown away after a job.

These workflows run pull request code here:

| Workflow | Trigger | Runs here |
|---|---|---|
| `main.yml`, calling `main-php-matrix.yml` | every `pull_request` | all jobs |
| `docker-image-ci.yml` | every `pull_request` | image build and the smoke steps |
| `draft-release-pr-check.yml` | `pull_request` to `stable`, `minor-next`, `major-next` or `legacy/*` touching `src/VersionInfo.php` | `check-intent`, `check-validity` |
| `copilot-setup-steps.yml` | `pull_request` touching that workflow file | `copilot-setup-steps` |

Two workflows reach this runner on `pull_request_target`. That trigger runs the base
branch's copy of the workflow with a write token, so it is safe only while no job
checks out or runs the head of an unmerged pull request.

- `pr-remove-waiting-label.yml`, on `synchronize`. Its one job checks out nothing and
  only removes two labels through `actions/github-script`.
- `draft-release.yml`, on a pull request to `stable`, `minor-next`, `major-next` or
  `legacy/*` touching `src/VersionInfo.php` being closed, merged or not, and on a
  push of any tag. Unless the tag already has a release, its `check` job calls
  `draft-release-pr-check.yml` through `workflow_call`, so `check-intent` runs here,
  and `check-validity` too when `IS_DEVELOPMENT_BUILD` is `false`. Both use
  `actions/checkout` with no `ref`, which takes the event's commit: the tip of the
  base branch on `pull_request_target`, holding the merged code after a merge and
  never the head of an unmerged pull request, or the tagged commit on a tag push.
  `check-validity` then runs `composer install` and `php build/dump-version-info.php`
  from that checkout. Code reaches the runner this way only once someone with push
  access has landed it on one of those branches or tagged it.

### Why this is acceptable today

Only someone who can push a branch to this repository can open a pull request whose
code runs here, because nothing from outside can arrive:

- the repository is private;
- `allow_forking` is `false` on the repository, and the organization sets
  `members_can_fork_private_repositories` to `false`;
- the repository's fork pull request settings
  (`actions/permissions/fork-pr-workflows-private-repos`) have
  `run_workflows_from_fork_pull_requests: false`;
- the only collaborator with write access is `nasiridrishi`. Any other collaborator
  holds `read`, which cannot push a branch.

Each of these can be re-read with `gh api`. Code that can be pushed here is code from
someone who can already reach the PC.

### What must change before an outside fork pull request is accepted

Any one of these makes the hazard live: the repository going public, forking being
allowed, fork pull request workflows being enabled, or a collaborator gaining write
access who is not trusted with the PC. Before any of them:

1. Move every `pull_request` job off `[self-hosted, linux, riftal]` to GitHub-hosted
   runners, or to an ephemeral runner on a machine with nothing else on it, whose
   user has no `sudo`, no host Docker socket and no host drive.
2. If any job must stay self-hosted, require approval for every outside contributor's
   run and limit the job to `push` on `riftal`.
3. Never add a `pull_request_target` or `workflow_run` job here that checks out or
   runs the pull request's code: those triggers carry this repository's token and
   secrets.

Changing the triggers or labels is a workflow change through the normal loop. Making
the repository public or reaching outside contributors is Nasir's.
