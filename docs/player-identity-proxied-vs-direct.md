# How is a player's identity derived, proxied versus direct?

Finding for Riftal-Games/pmmp-core#29. Evidence gathered 2026-09-07. This answers the
question M1's schema cannot be written without: does the same person get a different
primary key depending on whether WaterdogPE is in front of the downstream?

This document covers the derivation: how the fork arrives at a UUID and an XUID for
each login type, what WaterdogPE builds and sends downstream, and whether the two UUID
derivations agree. What that identity is then used for, and what M1's schema should key
on, is
[What identity is used for, and what it forces on M1's schema](player-identity-consequences-for-m1.md),
Riftal-Games/pmmp-core#34.

It changes no code. It records what is true and what is still unproven.

## Short answer

**The UUID is the same either way. The XUID is not.**

For a player signed into Xbox Live, the UUID this fork ends up with is
`md5v3("pocket-auth-1-xuid:" + xuid)`, and the proxy computes that same value by the
same algorithm and forwards it in the field the fork reads.

That sentence is two claims of different strength, and they must not be quoted as one.

- **Measured.** The two derivations are byte-identical. PHP 8.2 running this fork's
  function against Java 21 running Cloudburst's expression, same inputs, with a negative
  control. This is the *algorithm* equality and nothing more.
- **Read from source, not observed.** That WaterdogPE puts that value in `leguuid` and
  that this fork reads `leguuid`. That is a code read across three codebases, at pinned
  commits, and no login has been watched doing it.

So "the UUID is the same either way" is a sound conclusion from an exact measurement
plus an unobserved source reading, not a measured fact end to end. See
[Measured, not read](#measured-not-read-the-two-uuid-derivations-agree) for the
boundary, stated again there.

The XUID does not survive the proxy. A proxied login arrives as
`AuthenticationType::SELF_SIGNED`, and this fork hardcodes `$xuid = ""` on that branch
(`src/network/mcpe/handler/LoginPacketHandler.php:120`). WaterdogPE does send the real
XUID, in the `xid` claim, deliberately
(`HandshakeUtils.java:107-108`). The fork never reads it. So the same person has a real
XUID direct and an empty XUID proxied.

**Per-player state on disk is keyed by neither.** It is keyed by the lowercased
username (`src/player/DatFilePlayerDataProvider.php:50-52`), which is the only
persistence key the fork has today. What that implies for M1 is
Riftal-Games/pmmp-core#34.

So Nasir's concern is half right, and the half that is right is not the half that was
suspected. The identity does not fork into two different UUIDs. What forks is the
XUID, which goes from a real value to an empty string the moment a proxy appears in
front. Anything that keys on XUID breaks on that transition. Anything that keys on the
UUID does not.

There is a real structural choice in this, and it is Nasir's. Which value M1's schema
should key on is worked through in Riftal-Games/pmmp-core#34.

Nobody in this workspace has watched a real login through a WaterdogPE proxy. No proxy
image exists.

## What "tier" means here

Borrowed from `riftal-infra/docs/waterdogpe-protocol-2168.md:26-167`, which defines
them, so that the two documents can be read against each other:

| Tier | Means |
|---|---|
| 1 | Declared in source, read at a pinned commit |
| 2 | Present in a downloadable, checksummed artifact |
| 3 | Observed carrying a real client |

One label is added here that the 2168 document does not have, because this one needs it
and having two vocabularies for evidence strength in a single document is how a third
gets invented:

| Label | Means |
|---|---|
| **Inferred** | Stated by no source at any tier. A conclusion drawn from tier 1 evidence, which could be wrong while every line it rests on is right. |

`Inferred` always appears in bold at the head of the sentence it governs. If a claim
below is not marked `Inferred`, some cited line says it. Nothing in this document
carries the marker: every claim here rests on a cited line or on the measurement.

**This document contains tier 1 claims and one measurement, and no tier 3 claim
anywhere.** There is nothing at tier 2 either: no artifact was downloaded and probed,
because the question is what the code does, not what a jar contains.

The measurement does not fit the ladder, which is why it is named rather than numbered.
It executes two implementations and compares their output, which is stronger than
reading either one, and weaker than tier 3 because nothing was running a server. It is
confined to [one section](#measured-not-read-the-two-uuid-derivations-agree) and
covers exactly one claim.

Every proxied-path claim below is tier 1 unless it says otherwise, and the sections that
carry them say so in their own words.

## What is pinned to what

| Thing | Pinned at |
|---|---|
| This fork | `riftal` head `1e4d7de99c990aacfc2414b20ac4461ac8755198` |
| `axolotl-pm/BedrockProtocol` | `7528264597919647eb11bb6a2bfe08b75430907f`, from `composer.lock:152` |
| WaterdogPE | `master` head `23c834e16a9a0a7cb2aa504b6ae28b358a6892c4`, 2026-09-03T21:38:08Z |
| CloudburstMC Protocol | `3.0` commit `db36d289968a1d07d6591f0d54426cc058b227c0`, 2026-08-24T11:39:57Z |

The two upstream refs are moving branches, so both are cited as commits rather than as
branch names. The Cloudburst commit is not a guess: WaterdogPE's `gradle/libs.versions.toml:3` at its
master head pins `protocol = "3.0.0.Beta13-20260824.114016-17"`, and that snapshot
timestamp, 2026-08-24T11:40:16Z, falls 19 seconds after `db36d289`, which is the
newest commit on `3.0` at or before it. WaterdogPE's master head is the same SHA that
`riftal-infra/docs/waterdogpe-protocol-2168.md` used, re-read on 2026-09-07 and
unchanged.

## How the fork derives identity, by login type

This fork is on the 1.26 login format. The old three-link certificate chain with an
`extraData` blob is gone from the code path a 2168 client can reach. What arrives now
is a single `authInfoJson` carrying an `AuthenticationType` and a `Token`
(`AuthenticationInfo.php` in the pinned protocol package), and
`LoginPacketHandler::handleLogin` branches on that type at
`src/network/mcpe/handler/LoginPacketHandler.php:87` and `:107`.

`AuthenticationType` has three values, `FULL = 0`, `GUEST = 1`, `SELF_SIGNED = 2`. The
fork handles `FULL` and `SELF_SIGNED` and throws on anything else, including `GUEST`
(`LoginPacketHandler.php:134`).

### FULL, which is what a direct connection from a signed-in player uses

```php
$legacyUuid = self::calculateUuidFromXuid($claims->xid);
$username = $claims->xname;
$xuid = $claims->xid;
```

`LoginPacketHandler.php:96-98`. The derivation, at `:76-82`:

```php
private static function calculateUuidFromXuid(string $xuid) : UuidInterface{
	$hash = md5("pocket-auth-1-xuid:" . $xuid, binary: true);
	$hash[6] = chr((ord($hash[6]) & 0x0f) | 0x30); // set version to 3
	$hash[8] = chr((ord($hash[8]) & 0x3f) | 0x80); // set variant to RFC 4122

	return Uuid::fromBytes($hash);
}
```

That is a UUIDv3, MD5 over the literal string `pocket-auth-1-xuid:` concatenated with
the XUID. Deterministic from the XUID and from nothing else. Not from the username.

The token is then verified against a Mojang OpenID key at
`LoginPacketHandler.php:303-314`, and `ProcessOpenIdLoginTask.php:78` sets
`authenticated = true` only if that verification passed.

**`xbox-auth=false` does not skip this.** `NetworkSession::setAuthenticationStatus` at
`src/network/mcpe/NetworkSession.php:914-921` disconnects on any non-null error
unconditionally, before it ever looks at whether auth was required. Offline mode only
controls the branch at `:925-929`, which decides whether an *unauthenticated* session
is allowed to continue. A `FULL` token that fails signature, audience or expiry checks
is rejected on an offline-mode server exactly as it is on an online one. That is worth
stating because it is the reason a proxy cannot simply forge a `FULL` token.

### SELF_SIGNED, which is what a proxied connection uses, and also an unauthenticated direct one

```php
$legacyUuid = Uuid::fromString($claims->leguuid);
$username = $claims->xname;
$xuid = "";
```

`LoginPacketHandler.php:118-120`. Three things follow.

`leguuid` is taken from the token verbatim. The token is self-signed, so this value is
whatever the sender chose. The server does not derive it and cannot check it.

`$xuid = ""` is a literal. `SelfSignedJwtBody` in the pinned protocol package *does*
declare an `xid` property, and its own comment says these fields "seem to be present as
empty strings in a self-signed token for some reason". Nothing in `src/` reads it:
`grep -rn -- '->xid' src/` returns exactly two lines, `LoginPacketHandler.php:96` and
`:98`, both on the `FULL` branch. The declaration of `xid` lives in the vendored
protocol package, not in `src/`.

`grep -rn 'leguuid' src/` returns three lines, all in the same branch: `:115` is an
`Uuid::isValid` guard, `:116` an exception message, and `:118` the only read.

`ProcessSelfSignedLoginTask.php:93` passes a hard-coded `false` as the `authenticated`
argument to the callback. A self-signed login is never authenticated on this fork, by
construction, whatever the token contains.

## What WaterdogPE actually sends downstream

Tier 1, read from source at `23c834e1`.

The proxy terminates the client connection, validates the client's real token, then
builds a **new** login packet for the downstream, signed with the proxy's own keypair.
`LoginData.rebuildLoginPacket` is `LoginData.java:80-95`. Its two load-bearing lines,
`:90-91`, verbatim:

```java
SignedJWT signedPayload = HandshakeUtils.createClientDataToken(this.keyPair, displayName, xuid, uuid, minecraftId);
loginPacket.setAuthPayload(new TokenPayload(signedPayload.serialize(), AuthType.SELF_SIGNED));
```

`AuthType.SELF_SIGNED`, always. There is no path in that method that produces `FULL`.
The `shouldSendCertificateChain` branch above it is the pre-1.26.20 legacy shape. It is
set at `HandshakeUtils.java:168-170` to
`packet.getAuthPayload() instanceof CertificateChainPayload || protocol.isBefore(MINECRAFT_PE_1_26_20)`,
so at 2168 it is false for any client that sent a token payload, which is what a
1.26.4x client sends. Either branch produces `SELF_SIGNED`, so the identity conclusion
does not depend on which one is taken.

The legacy branch would not merely change the identity, it would fail the login
outright: it leaves `Token` empty and puts the chain in `Certificate`
(`LoginSerializer_v818.java:31-35`), and this fork reads only `$authInfo->Token` on
both branches of `handleLogin`. That is a code read of a path a 2168 client does not
take, recorded so nobody later assumes the certificate-chain shape is a working
fallback.

**The fork still carries a class that looks like that fallback and is not one.**
`src/network/mcpe/auth/ProcessLegacyLoginTask.php` exists and is instantiated nowhere:
`grep -rn 'ProcessLegacyLoginTask' src/` returns only its own declaration at `:35`. The
helper it calls, `AuthJwtHelper::validateLegacyAuthToken` at `:121`, carries
`@deprecated` at `:118` and is called from nothing but that dead class. The two are
an island. Anyone grepping for the certificate chain lands on them first and could
reasonably conclude the old path is live. It is not, and no login on this fork can
reach it. Tracked as pmmp-core#32.

`createClientDataToken` builds the claims. `HandshakeUtils.java:97-108`, verbatim and
complete, so it can be diffed against upstream without surprises:

```java
dataChain.addProperty("cpk", publicKeyBase64);
dataChain.addProperty("leguuid", uuid.toString());
dataChain.addProperty("iat", timestamp);
dataChain.addProperty("xname", displayName);
dataChain.addProperty("exp", timestamp + 24 * 3600);
dataChain.addProperty("mid", minecraftId);
dataChain.addProperty("ap", 7);
dataChain.addProperty("iss", "self");
// PMMP seem to require this, but CloudburstMC/Protocol does not.
dataChain.addProperty("aud", "api://auth-minecraft-services/multiplayer");
// Normally "xid" is sent as empty string for self-signed certificates, but we include it anyway
dataChain.addProperty("xid", xuid);
```

Both comments are upstream's. The second one is the whole point: WaterdogPE
went out of its way to forward the XUID in a field the format does not normally carry
it in, and this fork discards it at `LoginPacketHandler.php:120`.

The `aud` claim exists because PMMP requires it: `AuthJwtHelper.php:92-94` rejects any
token whose `aud` is not `api://auth-minecraft-services/multiplayer`, and
`ProcessSelfSignedLoginTask.php:38` is where that constant comes from. WaterdogPE
already accommodates that.

### Where the forwarded `uuid` comes from, and why it matches

`HandshakeUtils.processHandshake` takes the UUID from Cloudburst's validated identity
claims. `HandshakeUtils.java:134-141`, verbatim:

```java
ChainValidationResult result = EncryptionUtils.validatePayload(packet.getAuthPayload());
boolean xboxAuth = result.signed();
ChainValidationResult.IdentityClaims identityClaims = result.identityClaims();
ChainValidationResult.IdentityData identityData = identityClaims.extraData;
ECPublicKey identityPublicKey = (ECPublicKey) identityClaims.parsedIdentityPublicKey();
String xuid = identityData.xuid;
UUID uuid = identityData.identity;
String minecraftId = identityData.minecraftId;
```

And Cloudburst derives that `identity`, for a modern token payload, at
`ChainValidationResult.java:96`:

```java
UUID identity = UUID.nameUUIDFromBytes(("pocket-auth-1-xuid:" + xuid).getBytes(StandardCharsets.UTF_8));
```

`UUID.nameUUIDFromBytes` is MD5 with the version and variant bits forced the same way
the PHP does by hand. Same prefix string, same input, same algorithm.

### The wire shapes line up

Cloudburst writes the auth payload as `{"AuthenticationType": ordinal-1, "Token": ...,
"Certificate": ""}` at `LoginSerializer_v818.java:27-35`. Its `AuthType` enum is
`UNKNOWN, FULL, GUEST, SELF_SIGNED`, so `SELF_SIGNED.ordinal() - 1 == 2`, which is
exactly `AuthenticationType::SELF_SIGNED = 2` in the pinned protocol package. The field
names match `AuthenticationInfo`'s three properties. Nothing has to be configured on
the downstream for the shapes to agree.

## Measured, not read: the two UUID derivations agree

The equality above is the load-bearing claim in this document, so it was measured
rather than argued from source. It was measured twice, by two parties, and **the
stronger run is the second one**, described at the end of this section. The rows below
are the first run, kept because they are the ones the claims in this document were
actually derived from. Read them as the weaker half of the evidence, not the whole of
it.

Both implementations were run on the same three inputs on 2026-09-07.

PHP 8.2, running the fork's `calculateUuidFromXuid` verbatim, in a throwaway
`php:8.2-cli` container:

```
2535428394664352 -> 45a08efc-3dca-368c-9d43-24efc890a9ae
2535428394664353 -> dcf37408-cc4d-3308-b56f-06bc9c9a0c65
                 -> 13cec93e-ba60-30df-9f67-b97138b8516d
```

Java 21, `UUID.nameUUIDFromBytes(("pocket-auth-1-xuid:" + x).getBytes(UTF_8))`, the
exact expression at `ChainValidationResult.java:96`:

```
2535428394664352 -> 45a08efc-3dca-368c-9d43-24efc890a9ae
2535428394664353 -> dcf37408-cc4d-3308-b56f-06bc9c9a0c65
                 -> 13cec93e-ba60-30df-9f67-b97138b8516d
```

Identical on all three. The second input is the negative control: it differs from the
first in one digit and produces a completely unrelated UUID, so the probe discriminates
rather than returning a constant.

This proves the two *algorithms* coincide. It does not prove a proxied login reaches
the downstream at all. That is tier 3 and is not established here.

**QA re-ran this independently and its run is the stronger one.** It reproduced the
three rows above byte-exactly, added three inputs of its own, and asserted the version
nibble and the RFC 4122 variant bits rather than UUID shape. It then broke the
comparison twice to show it discriminates. The first break is the one to know about:
omitting the version and variant forcing yielded `v=2`, `v=7` and `v=9` with wrong
variant bits, while still retaining the prefix `45a08efc-3dca-`, so a lax prefix
comparison would have passed it and a shape-only check would have missed it. Full
verdict on Riftal-Games/pmmp-core#30.

Its six output rows are not reproduced here, and deliberately not reconstructed: the
verdict records the inputs, the bit assertions and that `sort -u` returned 6, but not
the six values themselves. Retyping a table this document did not produce would be the
one defect it could not survive. The verdict is the primary record for that run.

The third row is the empty-XUID case. `13cec93e-ba60-30df-9f67-b97138b8516d` is the
single UUID that `ChainValidationResult.java:96` produces for *every* caller whose XUID
is empty, which is the load-bearing fact behind the proxy `online_mode` hazard covered
in Riftal-Games/pmmp-core#34.

## Method

The fork's paths were read at the tree, at `riftal` head `1e4d7de9`. Upstream paths
were read through `gh api` against `WaterdogPE/WaterdogPE`, `CloudburstMC/Protocol` and
`axolotl-pm/BedrockProtocol`, each at the commit in the table above. No claim rests on a
README, a config comment or a changelog. Where a claim rests on reading code rather than
observing behaviour, it says so.

The one measurement is the UUID equality, run on 2026-09-07 as PHP 8.2 in a throwaway
container against Java 21 on the host, with a negative control.

One caution for anyone extending this. A field being declared in a model is not the
same as the field being read. The `SelfSignedJwtBody` model in the protocol package
declares `xid`, and reading only that model would suggest the fork consumes a proxied
XUID. It does not: the consumer is `LoginPacketHandler`, and on that branch it assigns
a literal. To establish what a value does, find its reads, not its declaration.

## What would settle what is still open

Tier 3, an observed proxied login, needs a proxy image, which does not exist
(riftal-infra#2).

**Set `debug.level` above 1 before running it.** The default is `1`
(`resources/pocketmine.yml:86-88`, whose own comment is "If > 1, it will show debug
messages in the console"), and the first line below is `$this->logger->debug`, so at the
default it never appears. A run at default level produces a log missing it for a reason
that has nothing to do with identity. That matters most for the second bullet, which is
an argument from absence and is only sound once a debug line that *did* appear proves
the channel is reaching the log at all.

When a proxy exists, the specific things to read out of the downstream log are:

- `Xbox Live authenticated: NO` at `NetworkSession.php:935`, confirming the proxied
  session takes the self-signed path. **Debug level.**
- The absence of `Discarding unexpected XUID for non-authenticated player` at `:931`,
  confirming the fork built a plain `PlayerInfo` rather than an `XboxLivePlayerInfo`.
  That one is `warning`, so it would appear at default level, but read it only
  alongside a debug line that did appear. Absence in a log you have not shown to be
  carrying that channel proves nothing.
- The player's UUID as the server reports it, compared against
  `md5v3("pocket-auth-1-xuid:" + xuid)` computed from that player's real XUID. That is
  the one comparison that turns the central claim of this document from tier 1 into
  tier 3.
