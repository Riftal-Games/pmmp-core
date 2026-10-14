# The self-hosted CI runner

Where this repository's CI runs, what that machine is, and why it must never run code
from an outside fork. Riftal-Games/pmmp-core#48.

## Which jobs run on it

Any job whose `runs-on` resolves to `[self-hosted, linux, riftal]` runs on this
runner, under any trigger that starts it. The `on:` blocks decide which triggers
those are, and this document does not repeat them. A `runs-on` resolves to those
labels by any of three routes:

- directly, as the literal array;
- through an input default: an expression such as `${{ fromJson(inputs.image) }}`
  over a `workflow_call` input whose default is that array, when the caller passes no
  other value in its `with:` block;
- through a `workflow_call`: a job whose `uses:` names a workflow in
  `./.github/workflows/` runs that workflow's jobs under the caller's trigger, so a
  called job on these labels runs here on every event that reaches the caller.

The workflow files are the only list of what runs here. From the repository root,
this prints each workflow's `on:` block, every `runs-on` line with the lines under it
when its labels are written as a block, and every call to a reusable workflow in this
repository together with the `with:` block passed to it:

```
awk '{sub(/\r$/, "")} FNR==1 {p=0; u=0; r=0; print "== " FILENAME} r {i=match($0, /[^ ]/); if (i < r || (i == r && substr($0, i, 2) != "- ")) r=0} /^on:/ {p=1} /^[^ #]/ && !/^on:/ {p=0} /^  [^ ]/ {u=0} /uses: \.\/\.github\/workflows\// {u=1} p || u || r || /runs-on:/ {print FNR ": " $0} /runs-on: *$/ {r=match($0, /[^ ]/)}' .github/workflows/*.y*ml
```

Read a job as running here when its `runs-on` reaches the labels by any of the three
routes, and read its triggers from the `on:` block of the workflow that starts it,
which for a called workflow is the caller's. A `runs-on` printed from inside a `run:`
script is text in that script, not a key.

GitHub hands such a job to any online runner registered to this repository that
carries all three labels. Which runners are registered is decided by registration,
not by this document:

```
gh api repos/Riftal-Games/pmmp-core/actions/runners --jq '.runners[] | {name, status, labels: [.labels[].name]}'
```

Riftal-Games/riftal-pm#1258 tracks the runner registrations of this repository.

## Where it lives

The runner is the GitHub `actions/runner` service, installed as a systemd unit
(`actions.runner.Riftal-Games-pmmp-core.<runner name>.service`) running as the Linux
user `runner` from `/home/runner/pmmp-core`, inside the WSL distro `Ubuntu-26.04` on
Nasir's development PC. Jobs check out under that directory's `_work`.

The same distro hosts the runners of the other Riftal-Games repositories and one
Docker daemon that all of them share, along with one `/tmp`. The
[runner-temp action](../.github/actions/runner-temp/action.yml) exists because of
that shared `/tmp`.

What the `runner` user holds there, read from the distro:

- membership of the `docker` group, so every job can drive the shared Docker daemon;
- `sudo` with `NOPASSWD: ALL`;
- the Windows drive at `/mnt/c`, including the working trees under
  `/mnt/c/Users/nasir/riftal-games`.

A job's workspace and anything it leaves on the distro persist between runs. CI is
down whenever that PC or that distro is.

## What it is, against hard rule 7

The runner is not a container, and its OS is not `ubuntu:24.04`: `/etc/os-release` in
the distro reads `Ubuntu 26.04 LTS`. The runner process runs directly on that distro,
and so does every step that does not call `docker` itself, with the tools, PHP
included, that the job's own setup steps install there. A job runs inside a container
only if it sets `container:`, which `grep -n 'container:' .github/workflows/*.y*ml`
shows, or if a step calls `docker` itself, as the image build and its smoke steps do.

Hard rule 7 puts `ubuntu:24.04` in the image, not on the host. riftal-pm's
`docs/decision-log.md`, under the heading "2026-08-23: Containers are the deployment
model, dev and production", makes the host OS only a container runtime and keeps
`ubuntu:24.04` as the base image for everything built. Every stage of
[docker/Dockerfile](../docker/Dockerfile), the image this runner builds and
smoke-tests, is `FROM ubuntu:24.04`, and `docker/check-ubuntu-base.sh` holds it there.

The runner itself running outside a container, on Ubuntu 26.04, is allowed for CI
only by two entries in the same log, cited by heading:

- "2026-09-27: Self-hosted CI runner, Docker inside the WSL distro Ubuntu-26.04",
  Nasir's call;
- "2026-09-28: CI moves from GitHub-hosted to self-hosted runners, forced by a billing
  lockout, superseding "No self-hosted CI runner"", which records the runner as the
  `actions/runner` service running directly inside the distro against its native
  Docker daemon.

## The fork pull request hazard

A job on the `pull_request` trigger checks out and runs the pull request's own code.
When that job runs here, the code runs as `runner`, with passwordless root, the shared
Docker daemon and the Windows drive. Code that reaches the runner can read or change
anything on the PC, tamper with the other repositories' runners and the local
container stack, and persist between runs, since a self-hosted runner's machine is not
thrown away after a job. For example, `main.yml` runs PHPStan and PHPUnit over a pull
request's code on these labels; that is an illustration, and the command under
[Which jobs run on it](#which-jobs-run-on-it) is the list.

### pull_request_target and workflow_run

These triggers run the workflow file from this repository's own branch, not from the
pull request, with a token that can write to this repository and with its secrets,
including for an event raised by a fork. That makes them safe only under one
invariant:

**No job on `pull_request_target` or `workflow_run`, directly or through a workflow it
calls, checks out, installs, builds or runs code from the head of an unmerged pull
request, or downloads an artifact a pull request's run produced.**

`actions/checkout` with no `ref` takes the event's commit, which on
`pull_request_target` is the tip of the base branch, so it holds the invariant. Any
other source of code is for a person to judge, because the expressions that name pull
request code are too many to list safely.

The invariant is a rule upheld in review. Whoever reviews a change to a workflow on
either trigger, or to anything such a workflow reaches through `uses: ./`, reads the
whole change against it. No command in this document checks it.
Riftal-Games/pmmp-core#205 is where it gets a real check.

### Why the hazard is closed while these settings hold

Only someone who can push a branch to this repository can open a pull request whose
code runs here, because nothing from outside can arrive:

- the repository is private, and `allow_forking` is `false` on it
  (`gh api repos/Riftal-Games/pmmp-core --jq '{private, allow_forking}'`);
- the organization sets `members_can_fork_private_repositories` to `false`
  (`gh api orgs/Riftal-Games --jq .members_can_fork_private_repositories`);
- the repository's fork pull request settings have
  `run_workflows_from_fork_pull_requests: false`
  (`gh api repos/Riftal-Games/pmmp-core/actions/permissions/fork-pr-workflows-private-repos`);
- the only collaborator with write access is `nasiridrishi`, and any other
  collaborator holds `read`, which cannot push a branch
  (`gh api repos/Riftal-Games/pmmp-core/collaborators --jq '.[] | {login, role_name}'`).

Code that can be pushed here is code from someone who can already reach the PC.

### What must change before an outside fork pull request is accepted

Any one of these makes the hazard live: the repository going public, forking being
allowed, fork pull request workflows being enabled, or a collaborator gaining write
access who is not trusted with the PC. Before any of them:

1. Move every job a `pull_request` event reaches off `[self-hosted, linux, riftal]`
   to GitHub-hosted runners, or to an ephemeral runner on a machine with nothing else
   on it, whose user has no `sudo`, no host Docker socket and no host drive.
2. If any job must stay self-hosted, require approval for every outside contributor's
   run and limit the job to `push` on `riftal`.
3. Hold the `pull_request_target` and `workflow_run` invariant above: those triggers
   carry this repository's token and secrets.

Changing the triggers or labels is a workflow change through the normal loop. Making
the repository public or reaching outside contributors is Nasir's.
