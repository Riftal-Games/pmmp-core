# What identity is used for, and what it forces on M1's schema

Finding for Riftal-Games/pmmp-core#34. Evidence gathered 2026-09-07. It starts from the
result in
[How is a player's identity derived, proxied versus direct?](player-identity-proxied-vs-direct.md)
(Riftal-Games/pmmp-core#29) and carries it to the point where it becomes a decision:
what keys per-player state today, what a proxy in front changes, and which of the three
values M1's schema could key on survive contact with the evidence.

It changes no code and picks no key. The primary-key choice is Nasir's and lives on
Riftal-Games/riftal-pm#7.

Nobody in this workspace has watched a real login through a WaterdogPE proxy. No proxy
image exists, and nothing here claims a client can join.

**Re-confirmed for Riftal-Games/pmmp-core#43, 2026-09-27.** The derivation document this
starts from was re-checked against `axolotl-pm/BedrockProtocol` `0e13c077d1060ae9e293908eff81fbef600ead5c`
(version `62.0.0+bedrock-1.26.50`, one minor past the `61.0.0+bedrock-1.26.45` issue #43
names, because PR #45 moved the pin further the same day) and this fork's `src/` after PR #45
rebased it onto upstream 5.49.1. Every claim in this document still holds; the fork's own
line numbers moved and are corrected below. See
[What is pinned to what](#what-is-pinned-to-what).

## What this starts from

Three results from the derivation document, restated as conclusions. How each was
established is there, not here.

- **The UUID is the same either way.** For a player signed into Xbox Live, the UUID this
  fork ends up with is `md5v3("pocket-auth-1-xuid:" + xuid)`, and the proxy computes that
  same value by the same algorithm and forwards it in the field the fork reads. The
  algorithm equality is measured; that the value travels in `leguuid` is read from source
  across three codebases and has not been observed
  ([Measured, not read](player-identity-proxied-vs-direct.md#measured-not-read-the-two-uuid-derivations-agree)).
- **The XUID does not survive the proxy.** A proxied login arrives as
  `AuthenticationType::SELF_SIGNED`, and the fork hardcodes `$xuid = ""` on that branch
  (`src/network/mcpe/handler/LoginPacketHandler.php:121`). WaterdogPE does send the real
  XUID, in the `xid` claim. The fork never reads it.
- **Every empty XUID derives one UUID.** `md5v3("pocket-auth-1-xuid:")` is
  `13cec93e-ba60-30df-9f67-b97138b8516d`, the single value
  `ChainValidationResult.java:96` produces for every caller whose XUID is empty. That is
  measured, and the hazard section below is where it matters.

## Evidence vocabulary

Tiers are defined in
[What "tier" means here](player-identity-proxied-vs-direct.md#what-tier-means-here),
borrowed from `riftal-infra/docs/waterdogpe-protocol-support.md`, section "Evidence, in
three tiers": tier 1 is declared
in source and read at a pinned commit, tier 2 is present in a downloadable checksummed
artifact, tier 3 is observed carrying a real client.

One further label is defined in that same section, the table row in
[What "tier" means here](player-identity-proxied-vs-direct.md#what-tier-means-here),
and is restated here because this is the document that uses it:

| Label | Means |
|---|---|
| **Inferred** | Stated by no source at any tier. A conclusion drawn from tier 1 evidence, which could be wrong while every line it rests on is right. |

`Inferred` always appears in bold at the head of the sentence it governs. If a claim
below is not marked `Inferred`, some cited line says it. Three claims below carry the
marker.

**Everything else here is tier 1, resting on the cited lines or on the one measurement
the derivation document owns. There is no tier 3 claim anywhere in this document.**

## What is pinned to what

Every source cited below, with the commit it was read at.

| Thing | Pinned at |
|---|---|
| This fork | `riftal` head `5868fd8dc5e4b3d2ecb1c95a7e1d2557eb029acd` (PR #45, upstream 5.49.1) |
| `axolotl-pm/BedrockProtocol` | `0e13c077d1060ae9e293908eff81fbef600ead5c`, from `composer.lock` at 62.0.0+bedrock-1.26.50 |
| `netresearch/jsonmapper` | v6.0.0, `31226dd465e3e38f5a8f66ef1393cd8daad248dd`, from `composer.lock:259` at 5.45.0 |
| WaterdogPE | `master` head `23c834e16a9a0a7cb2aa504b6ae28b358a6892c4`, 2026-09-03T21:38:08Z |
| CloudburstMC Protocol | `3.0` commit `db36d289968a1d07d6591f0d54426cc058b227c0`, 2026-08-24T11:39:57Z |

The fork and protocol-library rows were re-read for pmmp-core#43, 2026-09-27; they were
`1e4d7de99c990aacfc2414b20ac4461ac8755198` and
`7528264597919647eb11bb6a2bfe08b75430907f` (5.45.0, protocol lib 59.0.1) when this
document was first written, and the fork's line numbers below are corrected against the
new pin: PR #45 rebased `src/` onto upstream 5.49.1, so **the earlier claim that the
fork's line numbers held unchanged between `1e4d7de99` and `d2b9bbc13` no longer extends
past `5868fd8dc5`.** `netresearch/jsonmapper`, WaterdogPE and CloudburstMC were not
re-read for #43. The two upstream refs are moving branches, so both are cited as commits
rather than as branch names, and how the Cloudburst commit is tied to WaterdogPE's own
dependency pin is in
[What is pinned to what](player-identity-proxied-vs-direct.md#what-is-pinned-to-what).

## What actually keys per-player state today

Nothing in this fork keys on UUID or XUID.

`DatFilePlayerDataProvider` is the only implementation of `PlayerDataProvider` in the
tree, and its key is the lowercased username:

```php
private function getPlayerDataPath(string $username) : string{
	return Path::join($this->path, strtolower($username) . '.dat');
}
```

`src/player/DatFilePlayerDataProvider.php:50-52`. Load and save both go through it
(`:65`, `:95`), and `Server::getOfflinePlayerData` / `saveOfflinePlayerData` at
`src/Server.php:528` and `:540` take a name and nothing else. The lookup on login is
`$this->server->getOfflinePlayerData($this->info->getUsername())`,
`src/network/mcpe/NetworkSession.php:974`.

There is no database path in this fork at all. Whatever M1 builds will be the first.

The XUID is stored, but as a *value inside* the name-keyed file, not as a key:
`Player::TAG_LAST_KNOWN_XUID`, declared at `src/player/Player.php:207` and written at
`:2494` from `$this->xuid`, which is itself `""` for any non-`XboxLivePlayerInfo`
session (`src/player/Player.php:335`).

The username is not quite topology-invariant, and the exception is a config flag.
`Player::isValidUserName` at `src/player/Player.php:212-220` permits spaces
(`/[^A-Za-z0-9_ ]/`), and Xbox gamertags can contain them. WaterdogPE can rewrite them:
`HandshakeUtils.java:149-154` replaces spaces with underscores when
`replace_username_spaces` is set. That option defaults to `false`
(`ProxyConfig.java:126`), so by default the name passes through unchanged. Turning it
on renames the on-disk key for every affected player, which under today's name-keyed
storage is a rekey.

## What `player.verify-xuid` actually gates

One config read, `NetworkSession.php:937`, feeding two comparisons. Both compare the
current session's XUID against a previously known one, and both use `""` for any
session that is not an `XboxLivePlayerInfo` (`:938`).

1. **Duplicate-session kick.** `:952-960`. When a second session arrives with the same
   username or UUID, the existing session's XUID must match, or the *new* one is
   disconnected as an impersonation attempt.
2. **Stored-XUID check.** `:975-981`. `LastKnownXUID` is read out of the loaded player
   file and compared. If no XUID was ever recorded the fork logs "No previous XUID
   recorded, no choice but to trust this player" and continues. That line is
   `$this->logger->debug` at `:978`, so it is absent at the default `debug.level` of 1.

Both disconnect through `kickForXUIDMismatch` at `:939-950`, whose own comment says it
is a stopgap and that identifying player data by XUID or UUID would be the real fix.

**The duplicate-session kick does not survive an instance split, and that bears on the
key choice.** It iterates `$this->manager->getSessions()` at `:952`, which is one
process's session table. Hard rule 5 requires every world to be splittable onto its own
instance against one shared database, and at that point two instances each hold a
session table that knows nothing of the other. The guard is not weakened by the split so
much as scoped out of existence: it never sees the second login.

That much is tier 1: the iteration, its scope, and hard rule 5.

**Inferred:** so "is this player already online" and "who is this player" are the same
question, and neither the fork nor the on-disk store can answer it across instances. In
a closed economy where every item was mined by a person, one identity holding two live
sessions on two instances against one database is a duplication path, not just a
presence bug. Whatever M1 keys on has to be the thing an instance-crossing presence
check keys on too.

Marked because it reasons about a schema M1 has not built and a split that has never
been performed. It is not weaker for being marked, and it is the reason this constraint
belongs with the decision below rather than being left as a note about a guard. What is
certain is only the part above the mark: the guard does not see across instances. What
follows from that depends on what M1 builds.

This is why the platform fact in `riftal-infra/CLAUDE.md` requires
`player.verify-xuid: false` behind a proxy, and the code says exactly why: proxied
sessions always present `""`, so any player with a recorded non-empty `LastKnownXUID`
would be kicked on their next join. That requirement is now confirmed from the fork's
source rather than taken from documentation.

`xbox-auth=false` is required for a different reason. `NetworkSession.php:925-928`
disconnects an unauthenticated session with "Not authenticated" when auth is required,
and a proxied session is unauthenticated by construction
(`ProcessSelfSignedLoginTask.php:93`). Two settings, two independent mechanisms, both
genuinely necessary.

## The full matrix

Tier 1 throughout, from the code paths above and from the derivation document's.
`xbox-auth=false` in every row, which is the configuration M0 specifies
(`docs/roadmap.md` in riftal-pm, section "M0: Joinable").

| Topology | Player signed into XBL | `AuthenticationType` | `authenticated` | XUID the fork keeps | UUID the fork keeps | Disk key |
|---|---|---|---|---|---|---|
| Direct | yes | FULL | true | real | `md5v3("pocket-auth-1-xuid:"+xuid)` | lowercased username |
| Direct | no | SELF_SIGNED | false | `""` | client's own `leguuid`, arbitrary | lowercased username |
| Proxied, proxy `online_mode: true` | yes | SELF_SIGNED | false | `""` | `md5v3("pocket-auth-1-xuid:"+xuid)`, computed by the proxy | lowercased username |
| Proxied, proxy `online_mode: true` | no | n/a | n/a | n/a | n/a | rejected at the proxy, `LoginUpstreamHandler.java:195-198` |

Read the first and third rows together. That is the topology change, for one real
person: same username, same UUID, XUID goes from real to empty.

The second row is the one that has no counterpart. A direct, offline-mode server admits
players who are not signed into Xbox Live at all, with a client-chosen UUID and any
name that passes `isValidUserName`. Once a proxy with `online_mode: true` is in front,
those players cannot connect at all, and their UUID was never anchored to anything in
the first place.

## A hazard that is not ours yet: proxy `online_mode: false`

Not our configuration, and stated so it is not adopted by accident.

If the proxy runs `online_mode: false`, `LoginUpstreamHandler.java:187,195` stops
rejecting unauthenticated clients, and `HandshakeUtils.processHandshake` takes the
XUID and UUID from the *client's own* self-signed token. That XUID is empty, so
`ChainValidationResult.java:96` derives `md5v3("pocket-auth-1-xuid:")`, which the
measurement recorded in the derivation document shows is
`13cec93e-ba60-30df-9f67-b97138b8516d`.

**Inferred:** every unauthenticated player behind such a proxy would arrive at the
downstream carrying that same UUID.

It does not apply to our configuration: `online_mode` defaults to `true`
(`ProxyConfig.java:105`) and hard rule 6 requires the proxy to do the Xbox
authentication. It is recorded because the failure mode is silent and total, and
because a single `false` in a proxy config is all that separates us from it.

## The login-extras channel does not work on this fork

WaterdogPE can inject `Waterdog_XUID`, `Waterdog_IP`, `Waterdog_Auth` and
`Waterdog_MID` into the client data JSON (`HandshakeUtils.java:158-164`, `:176-180`).
This is the mechanism `riftal-infra/CLAUDE.md` describes as "forwards XUID and IP to
the downstream in custom login packet fields".

It is off by default, `use_login_extras` is `false` at `ProxyConfig.java:122`. And
turning it on would not help today, because those fields are unreachable from the
fork:

- The fork maps client data onto `ClientData`
  (`LoginPacketHandler.php:293`), a class with a fixed set of declared properties.
  None of them is a `Waterdog_*` field.
- Unknown keys go to `warnUndefinedJsonPropertyHandler`
  (`LoginPacketHandler.php:338-348`), a `: void` closure. JsonMapper only stores an
  unknown key if that handler *returns a string* to remap it to
  (`JsonMapper.php:185-193` at the pinned SHA); returning nothing means the value is
  dropped.
- `PlayerInfo::getExtraData()` is populated from `(array) $clientData`
  (`LoginPacketHandler.php:170`, `:178`), so a dropped key is not there either.

So a plugin cannot read `Waterdog_XUID` from `PlayerInfo`. The extras would also emit a
warning per unknown key, and `LoginPacketHandler.php:341-346` throws
`PacketHandlingException` after ten of them. Four extras is under that limit, so the
result is log noise rather than a failed login. That last sentence is a code read, not
an observation.

**Inferred:** this makes the `xid` claim the only channel by which a proxied XUID could
reach this fork without a plugin, and it is the one the fork discards.

## Consequence for M1's schema

The fork offers three candidate values. **Two survive contact with the evidence.**

**Username.** What the fork uses today. Survives the proxy being added. Does not
survive an Xbox gamertag change, and does not survive `replace_username_spaces` being
turned on. In a closed economy the rename case is not hypothetical: gamertag changes
are a normal Xbox Live operation, and a name-keyed row would silently become a new
account with an empty balance while the old row keeps the diamonds.

**UUID.** Stable across the topology change for any Xbox-authenticated player, which is
the derivation document's result. Stable across a gamertag change, because it derives
from the XUID and not from the name. Not stable for players who were never
Xbox-authenticated, whose UUID is whatever their client sent. Available on every path the
fork supports, including the proxied one.

**XUID. Ruled out.** The strongest identity when it is present, and absent on exactly
the path M0 targets. Keying on it means every proxied player has the empty string as a
key. This is the option Nasir's concern was pointing at, and it is the one the evidence
eliminates. It is listed because eliminating it is a result, not because it remains a
choice.

The practical shape of the risk: if closed alpha runs **direct** and the proxy arrives
later, players keep their username and their UUID, and lose their XUID. A
username-keyed or UUID-keyed schema carries through. An XUID-keyed schema orphans every
account at the moment the proxy is introduced.

There is a second-order trap in the UUID option that should be said out loud. Under
`xbox-auth=false` on a **direct** downstream, an unauthenticated player supplies their
own `leguuid`, unverified. Nothing stops that value colliding with an authenticated
player's derived UUID. A UUID-keyed schema on a directly-reachable offline-mode
downstream is therefore forgeable. It is not forgeable behind a proxy with
`online_mode: true`, because the proxy computes the UUID itself. This is the code
reason behind the existing platform rule that downstreams must never be reachable from
the internet, and it upgrades that rule from a networking preference to a data-integrity
requirement.

## The decision this forces

M1's schema needs a primary key and there is no default that is right on every axis.
This document deliberately picks none of them.

A and B are the two values the evidence above leaves standing, and every claim about
them traces to a cited line. **C is not a finding.** No evidence produced it, nothing
in the fork implements it, and it is offered because a document that eliminates one of
three values should say what the remaining two cannot do rather than leave the reader to
notice. Weigh it as a proposal, and weigh A and B as findings.

**A. Key on the derived UUID.** *From the evidence.* Survives the proxy arriving
(`LoginPacketHandler.php:119` against `ChainValidationResult.java:96`), survives a
gamertag change, available on every path the fork supports. Costs: it is forgeable on a
directly reachable offline-mode downstream because `leguuid` is unverified on the
self-signed branch (`LoginPacketHandler.php:116-119`), so it depends on the
proxy-only-entry-point rule being enforced rather than merely intended, and it is
meaningless for players who were never Xbox-authenticated.

**B. Key on the username, as the fork does.** *From the evidence.* Matches how the fork
already stores things (`DatFilePlayerDataProvider.php:50-52`), so plugin and core agree
with no translation layer. Costs: a gamertag change orphans the account, and
`replace_username_spaces` (`ProxyConfig.java:126`) is a one-flag rekey.

**C. Key on a server-issued internal ID, with UUID and username as attributes.**
*Proposed here, not derived from anything above.* Immune to every rekey named, because
the identity is ours rather than the client's or the proxy's. Costs: more schema, an
account-resolution step on every login, and a decision about what to do the first time
two identities need merging. It is the only option that can absorb a later change of
mind about A versus B, and it is also the only one with no line number behind it.

One constraint applies to all three and is not satisfied by any of them alone: the
duplicate-session guard is per-process, so an instance split leaves presence
unanswerable no matter which value is the key. See
[What `player.verify-xuid` actually gates](#what-playerverify-xuid-actually-gates).

All three are Nasir's call, and the choice belongs in an ADR under
`docs/decisions/` before M1's schema is written, not in this document.

## Method

The fork's paths, the upstream reads against `WaterdogPE/WaterdogPE`,
`CloudburstMC/Protocol` and `axolotl-pm/BedrockProtocol`, and the one measurement are
read as described in
[Method](player-identity-proxied-vs-direct.md#method); this document does not repeat
that account. Its own addition to the sources in that account is
`cweiske/jsonmapper`, read through `gh api` at the commit in the table above, not
re-read for #43.

One caution for anyone extending this. A config option existing is not the same as the
option working. `use_login_extras` exists on the proxy and is described in this
workspace's own platform facts as the mechanism that forwards XUID. Following it through
to `ClientData` and JsonMapper's undefined-property handling shows the value is dropped
before any plugin could see it. The option is real; its effect on this fork is not. The
derivation document's Method carries the matching caution about `SelfSignedJwtBody`: a
field being declared in a model is not the same as the field being read.

## What would settle what is still open

The proxy-image gap, the `debug.level` setup it needs and the first two log lines to
read are in
[What would settle what is still open](player-identity-proxied-vs-direct.md#what-would-settle-what-is-still-open);
this document does not repeat them. Two more settle what this document adds on top of
that:

- The name of the `.dat` file that appears, confirming the disk key.
- The player's UUID as the server reports it, compared against
  `md5v3("pocket-auth-1-xuid:" + xuid)` computed from that player's real XUID. That is
  the one comparison that turns the claim this document starts from into tier 3.
