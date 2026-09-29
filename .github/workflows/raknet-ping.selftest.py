#!/usr/bin/env python3
"""
Self-test for raknet-ping.py's pong-parsing and identity assertions.

The REACHABLE check exists to prove a client can find and identify our
server, not merely that something answered UDP. raknet-ping.py's retry loop
hides a parse or assertion regression behind a slow timeout unless a fake
responder answers on the FIRST attempt with a specific, deliberately wrong
pong: that is the only way to prove the assertion itself is what fails the
run, rather than the absence of any reply at all.

Every case here drives the real script over loopback UDP with its real CLI,
against bytes built from the wire format documented in raknet-ping.py's own
docstring, so this exercises exactly what CI runs rather than a
reimplementation of it. pmmp-core#14: --expect-motd and --expect-protocol
used to default to unset, so a dropped flag would silently convert this
into a liveness ping. The two "identity" cases at the end exist to prove
--skip-identity-checks only waives those two comparisons and never the
always-on structural checks (edition, non-empty MOTD, numeric protocol).
"""

import importlib.util
import socket
import struct
import subprocess
import sys
import threading
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
SCRIPT = SCRIPT_DIR / "raknet-ping.py"

spec = importlib.util.spec_from_file_location("raknet_ping", SCRIPT)
raknet_ping = importlib.util.module_from_spec(spec)
# An exit on import, even exit 0, would otherwise end this process before any
# case runs, and a zero status would read as a pass.
try:
    spec.loader.exec_module(raknet_ping)
except SystemExit as e:
    print(f"::error::raknet-ping.py exited on import with {e.code!r}; its CLI must run only under __main__")
    sys.exit(1)

MAGIC = raknet_ping.MAGIC
ID_UNCONNECTED_PONG = raknet_ping.ID_UNCONNECTED_PONG

EXPECT_MOTD = "RiftalGames"
EXPECT_PROTOCOL = 2193
VERSION = "1.26.50"

# Every case below must actually run and record a verdict. A harness that
# quietly skips one case (an unhandled exception, a case someone deleted the
# call to but not the docstring for) and still prints a clean summary is the
# exact failure this file exists to catch.
EXPECTED_ASSERTIONS = 14

FAILURES = 0
PASSES = 0


def ok(msg: str) -> None:
    global PASSES
    print(f"  ok    {msg}")
    PASSES += 1


def bad(msg: str, detail: str = "") -> None:
    global FAILURES
    print(f"::error::{msg}")
    if detail:
        print(detail)
    FAILURES += 1


def valid_server_name(motd=EXPECT_MOTD, protocol=str(EXPECT_PROTOCOL), edition="MCPE") -> str:
    return ";".join(
        [edition, motd, protocol, VERSION, "0", "20", "987654321", "sub-motd", "Survival", "1"]
    )


def build_pong(ping_time: int, *, server_id=987654321, magic=None, name=None, name_length=None) -> bytes:
    if magic is None:
        magic = MAGIC
    if name is None:
        name = valid_server_name()
    name_bytes = name.encode("utf-8")
    length = len(name_bytes) if name_length is None else name_length
    return (
        struct.pack(">B", ID_UNCONNECTED_PONG)
        + struct.pack(">q", ping_time)
        + struct.pack(">q", server_id)
        + magic
        + struct.pack(">H", length)
        + name_bytes
    )


def run_case(builder, extra_args, subprocess_timeout=5.0):
    """
    Bind a fake responder to an ephemeral loopback port, run raknet-ping.py
    against it, and return (returncode, stdout, stderr).

    builder(ping_time) -> bytes to send back, or None to send nothing.
    ping_time is read off the real ping the script sends, so an echoed-time
    case can deliberately echo something else.
    """
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(("127.0.0.1", 0))
    host, port = sock.getsockname()

    def responder():
        sock.settimeout(2.0)
        try:
            data, addr = sock.recvfrom(4096)
        except (socket.timeout, OSError):
            return
        ping_time = struct.unpack_from(">q", data, 1)[0]
        reply = builder(ping_time)
        if reply is not None:
            try:
                sock.sendto(reply, addr)
            except OSError:
                pass

    thread = threading.Thread(target=responder, daemon=True)
    thread.start()

    try:
        proc = subprocess.run(
            [
                sys.executable, str(SCRIPT), host, str(port),
                "--attempt-timeout", "0.3",
                "--total-timeout", "0.3",
                *extra_args,
            ],
            capture_output=True, text=True, timeout=subprocess_timeout,
        )
        result = (proc.returncode, proc.stdout, proc.stderr)
    finally:
        sock.close()
        thread.join(timeout=1.0)
    return result


IDENTITY_ARGS = ["--expect-motd", EXPECT_MOTD, "--expect-protocol", str(EXPECT_PROTOCOL)]


def expect_pass(label, builder, extra_args):
    try:
        code, out, err = run_case(builder, extra_args)
    except Exception as e:  # noqa: BLE001 - a crash here is a failed case, not a harness bug
        bad(f"{label}: harness raised {e!r}")
        return
    if code == 0:
        ok(f"{label} -> REACHABLE")
    else:
        bad(f"{label}: expected exit 0, got {code}", out + err)


def expect_fail(label, builder, needle, extra_args):
    try:
        code, out, err = run_case(builder, extra_args)
    except Exception as e:  # noqa: BLE001
        bad(f"{label}: harness raised {e!r}")
        return
    combined = out + err
    if code != 0 and needle in combined:
        ok(f"{label} -> rejected, naming '{needle}'")
    else:
        bad(f"{label}: expected a non-zero exit naming '{needle}', got exit {code}", combined)


expect_pass(
    "correct pong",
    lambda ping_time: build_pong(ping_time),
    IDENTITY_ARGS,
)

expect_fail(
    "wrong magic",
    lambda ping_time: build_pong(ping_time, magic=b"\x00" * 16),
    "OfflineMessage::MAGIC",
    IDENTITY_ARGS,
)

expect_fail(
    "wrong echoed timestamp",
    lambda ping_time: build_pong(ping_time + 1),
    "this is not a reply to our ping",
    IDENTITY_ARGS,
)

expect_fail(
    "truncated serverName",
    lambda ping_time: build_pong(ping_time, name_length=len(valid_server_name().encode("utf-8")) + 50),
    "serverName claims",
    IDENTITY_ARGS,
)

expect_fail(
    "runt packet",
    lambda ping_time: bytes([ID_UNCONNECTED_PONG]) + b"\x00" * 5,
    "too short to be an unconnected pong",
    IDENTITY_ARGS,
)

expect_fail(
    "empty MOTD",
    lambda ping_time: build_pong(ping_time, name=valid_server_name(motd="")),
    "MOTD field is empty",
    IDENTITY_ARGS,
)

expect_fail(
    "wrong MOTD",
    lambda ping_time: build_pong(ping_time, name=valid_server_name(motd="NotRiftal")),
    "MOTD field is 'NotRiftal'",
    IDENTITY_ARGS,
)

expect_fail(
    "protocol 2169 (moved from the pin)",
    lambda ping_time: build_pong(ping_time, name=valid_server_name(protocol="2169")),
    f"protocol field is 2169, expected {EXPECT_PROTOCOL}",
    IDENTITY_ARGS,
)

expect_fail(
    "non-numeric protocol",
    lambda ping_time: build_pong(ping_time, name=valid_server_name(protocol="abc")),
    "expected a positive integer",
    IDENTITY_ARGS,
)

expect_fail(
    "wrong edition",
    lambda ping_time: build_pong(ping_time, name=valid_server_name(edition="MCEE")),
    "edition field is 'MCEE'",
    IDENTITY_ARGS,
)

expect_fail(
    "too few fields",
    lambda ping_time: build_pong(ping_time, name="MCPE;RiftalGames"),
    "need at least 4",
    IDENTITY_ARGS,
)

expect_fail(
    "missing --expect-motd/--expect-protocol with no opt-out",
    lambda ping_time: build_pong(ping_time),
    "--expect-motd and --expect-protocol required unless --skip-identity-checks",
    [],
)

expect_pass(
    "--skip-identity-checks allows omitting both flags",
    lambda ping_time: build_pong(ping_time, name=valid_server_name(motd="Whatever", protocol="1")),
    ["--skip-identity-checks"],
)

expect_fail(
    "--skip-identity-checks still enforces the always-on structural checks",
    lambda ping_time: build_pong(ping_time, name=valid_server_name(edition="MCEE")),
    "edition field is 'MCEE'",
    ["--skip-identity-checks"],
)

print()
ran = PASSES + FAILURES
if ran != EXPECTED_ASSERTIONS:
    print(f"{ran} of {EXPECTED_ASSERTIONS} assertions ran, so one did not run and cannot have passed")
    sys.exit(1)
if FAILURES != 0:
    print(f"{FAILURES} self-test assertion(s) failed. The REACHABLE check has stopped discriminating.")
    sys.exit(1)
print(f"all {PASSES} assertions passed: raknet-ping.py's parsing and identity assertions discriminate correctly.")
