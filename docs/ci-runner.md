# The self-hosted CI runner

Where this repository's CI runs, what that machine is, and why it must never run a
pull request from an outside fork. Riftal-Games/pmmp-core#48.

## Which jobs run on it

Every workflow job in this repository that does work for a pull request or a push to
`riftal` targets the labels `[self-hosted, linux, riftal]`. `main-php-matrix.yml` takes
its labels from an `image` input whose default is the same array. GitHub picks any
online runner registered to this repository that carries all three labels.

The jobs still on GitHub-hosted labels (`ubuntu-22.04`, `ubuntu-latest`) are the
release, publish, Crowdin, Discord and branch-sync workflows, which only run on a
release, a manual dispatch or a push touching `resources/translations/eng.ini`.

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
integration and codegen checks, code style, ShellCheck and the docs and translation
checks all run there, with PHP from `axolotl-pm/setup-php-action` rather than from the
image. Only the image build, its smoke steps and actionlint run in containers. No job
in this repository sets `container:`.

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

`pr-remove-waiting-label.yml` also runs here, on `pull_request_target`. That trigger
runs the base branch's copy of the workflow with a write token. It is safe only while
the job checks out nothing from the pull request, which it does not.

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
