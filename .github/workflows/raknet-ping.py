#!/usr/bin/env python3
"""
Send a RakNet unconnected ping and assert the reply is a valid unconnected pong.

This is the REACHABLE check for the Docker image CI. Bedrock is RakNet over UDP,
so a container that publishes 19132/tcp only looks perfectly healthy to every
other check in the workflow while no client can join it. Only a real UDP
round trip catches that.

Wire format is taken from the RakLib version this fork pins in composer.lock
(pocketmine/raklib 1.2.1):

  UnconnectedPing  src/protocol/UnconnectedPing.php
      byte   id = 0x01            (MessageIdentifiers::ID_UNCONNECTED_PING)
      long   sendPingTime         (64-bit big endian)
      bytes  magic                (16 bytes, OfflineMessage::MAGIC)
      long   clientId             (64-bit big endian)

  UnconnectedPong  src/protocol/UnconnectedPong.php
      byte   id = 0x1c            (MessageIdentifiers::ID_UNCONNECTED_PONG)
      long   sendPingTime         (echoed back)
      long   serverId
      bytes  magic                (16 bytes)
      string serverName           (unsigned short big endian length, then bytes)

The serverName field is the semicolon-delimited MOTD string built by
src/network/mcpe/raklib/RakLibInterface.php::setName():

      0 edition ("MCPE")   1 motd   2 protocol   3 version   4 players
      5 max players        6 server id           7 sub-motd  8 gamemode  ...
"""

import argparse
import random
import socket
import struct
import sys
import time

# src/protocol/OfflineMessage.php: private const MAGIC
MAGIC = b"\x00\xff\xff\x00\xfe\xfe\xfe\xfe\xfd\xfd\xfd\xfd\x12\x34\x56\x78"

ID_UNCONNECTED_PING = 0x01
ID_UNCONNECTED_PONG = 0x1C

# Field indexes into the semicolon-delimited serverName string.
FIELD_EDITION = 0
FIELD_MOTD = 1
FIELD_PROTOCOL = 2
FIELD_VERSION = 3


class PongError(Exception):
    pass


def build_ping(send_ping_time: int, client_id: int) -> bytes:
    return (
        struct.pack(">B", ID_UNCONNECTED_PING)
        + struct.pack(">q", send_ping_time)
        + MAGIC
        + struct.pack(">q", client_id)
    )


def parse_pong(data: bytes, expect_ping_time: int) -> str:
    if len(data) < 35:
        raise PongError(f"reply is only {len(data)} bytes, too short to be an unconnected pong")

    # ping_once only calls parse_pong once it has already matched data[0]
    # against ID_UNCONNECTED_PONG, so a repeat of that check here can never
    # fail; anything with the wrong id surfaces as a socket.timeout instead,
    # never reaching this function.
    ping_time = struct.unpack_from(">q", data, 1)[0]
    if ping_time != expect_ping_time:
        raise PongError(
            f"reply echoed sendPingTime {ping_time}, we sent {expect_ping_time}; "
            "this is not a reply to our ping"
        )

    server_id = struct.unpack_from(">q", data, 9)[0]

    magic = data[17:33]
    if magic != MAGIC:
        raise PongError(
            f"reply magic is {magic.hex()}, expected {MAGIC.hex()} "
            "(OfflineMessage::MAGIC); this is not RakNet"
        )

    name_length = struct.unpack_from(">H", data, 33)[0]
    end = 35 + name_length
    if len(data) < end:
        raise PongError(
            f"serverName claims {name_length} bytes but only {len(data) - 35} are present"
        )

    print(f"unconnected pong: serverId={server_id} serverName length={name_length}")
    return data[35:end].decode("utf-8", errors="replace")


def ping_once(sock: socket.socket, address, timeout: float) -> str:
    send_ping_time = int(time.time() * 1000)
    client_id = random.getrandbits(63)

    sock.settimeout(timeout)
    sock.sendto(build_ping(send_ping_time, client_id), address)

    deadline = time.monotonic() + timeout
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise socket.timeout("no reply within the per-attempt timeout")
        sock.settimeout(remaining)
        data, source = sock.recvfrom(4096)
        if len(data) > 0 and data[0] == ID_UNCONNECTED_PONG:
            print(f"got {len(data)} bytes from {source[0]}:{source[1]}")
            return parse_pong(data, send_ping_time)
        # Anything else on the socket is not our pong; keep waiting.


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("host")
    parser.add_argument("port", type=int)
    parser.add_argument(
        "--expect-motd",
        help="exact value the MOTD field of the pong must carry "
        "(required unless --skip-identity-checks is given)",
    )
    parser.add_argument(
        "--expect-protocol",
        type=int,
        help="exact value the protocol field of the pong must carry "
        "(required unless --skip-identity-checks is given)",
    )
    parser.add_argument(
        "--skip-identity-checks",
        action="store_true",
        help="allow --expect-motd and --expect-protocol to be omitted, "
        "downgrading REACHABLE to a liveness ping with no identity "
        "assertion. Never use this in CI; it exists for local debugging "
        "against a server whose MOTD or protocol you do not know yet.",
    )
    parser.add_argument(
        "--attempt-timeout",
        type=float,
        default=2.0,
        help="seconds to wait for a reply to a single ping (default: 2)",
    )
    parser.add_argument(
        "--total-timeout",
        type=float,
        default=30.0,
        help="seconds to keep retrying before giving up (default: 30)",
    )
    args = parser.parse_args()

    if not args.skip_identity_checks:
        missing = [
            name
            for name, value in (
                ("--expect-motd", args.expect_motd),
                ("--expect-protocol", args.expect_protocol),
            )
            if value is None
        ]
        if missing:
            parser.error(
                f"{' and '.join(missing)} required unless --skip-identity-checks "
                "is given; a REACHABLE check with no expected identity only "
                "proves something answered UDP, not that it is our server"
            )
    else:
        print(
            "WARNING: --skip-identity-checks set; MOTD and/or protocol are not "
            "being asserted against an expected value. This is a liveness "
            "ping, not a REACHABLE check, and must never run this way in CI.",
            file=sys.stderr,
        )

    address = (args.host, args.port)
    deadline = time.monotonic() + args.total_timeout
    attempt = 0
    last_error = None

    server_name = None
    while time.monotonic() < deadline:
        attempt += 1
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            server_name = ping_once(sock, address, args.attempt_timeout)
            break
        except (socket.timeout, OSError) as e:
            last_error = f"{type(e).__name__}: {e}"
            print(f"attempt {attempt}: no usable reply from {args.host}:{args.port}/udp ({last_error})")
        except PongError as e:
            last_error = str(e)
            print(f"attempt {attempt}: bad reply: {last_error}")
        finally:
            sock.close()
        time.sleep(0.5)

    if server_name is None:
        print(
            f"NOT REACHABLE: no valid RakNet unconnected pong from {args.host}:{args.port}/udp "
            f"after {attempt} attempt(s) in {args.total_timeout}s. Last error: {last_error}",
            file=sys.stderr,
        )
        return 1

    print(f"serverName: {server_name}")
    fields = server_name.split(";")
    for i, value in enumerate(fields):
        print(f"  field[{i}] = {value!r}")

    failures = []

    if len(fields) <= FIELD_VERSION:
        failures.append(
            f"serverName has only {len(fields)} semicolon-delimited fields, "
            f"need at least {FIELD_VERSION + 1}"
        )
    else:
        if fields[FIELD_EDITION] != "MCPE":
            failures.append(
                f"edition field is {fields[FIELD_EDITION]!r}, expected 'MCPE'"
            )
        if fields[FIELD_MOTD] == "":
            failures.append("MOTD field is empty")
        if args.expect_motd is not None and fields[FIELD_MOTD] != args.expect_motd:
            failures.append(
                f"MOTD field is {fields[FIELD_MOTD]!r}, expected {args.expect_motd!r}"
            )
        if not fields[FIELD_PROTOCOL].isdigit() or int(fields[FIELD_PROTOCOL]) <= 0:
            failures.append(
                f"protocol field is {fields[FIELD_PROTOCOL]!r}, expected a positive integer"
            )
        elif args.expect_protocol is not None and int(fields[FIELD_PROTOCOL]) != args.expect_protocol:
            failures.append(
                f"protocol field is {fields[FIELD_PROTOCOL]}, expected {args.expect_protocol}. "
                "The advertised protocol moved. Bump the pin deliberately and tell the proxy."
            )

    if failures:
        for failure in failures:
            print(f"REACHABLE assertion failed: {failure}", file=sys.stderr)
        return 1

    print(
        f"REACHABLE: {args.host}:{args.port}/udp answered with edition={fields[FIELD_EDITION]} "
        f"motd={fields[FIELD_MOTD]!r} protocol={fields[FIELD_PROTOCOL]} "
        f"version={fields[FIELD_VERSION]}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
