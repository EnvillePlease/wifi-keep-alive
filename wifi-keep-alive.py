#!/usr/bin/env python3
"""
WiFi Keep-Alive Utility

Sends periodic ping requests to a network device to prevent WiFi connections
from entering power-save mode. Designed for low-powered devices like Raspberry Pi
that experience connectivity issues due to aggressive WiFi power management.

Example Usage:
--------------
    python wifi-keep-alive.py 192.168.1.1           # Ping router every 60s (default)
    python wifi-keep-alive.py 8.8.8.8 -i 30         # Ping Google DNS every 30s
    python wifi-keep-alive.py google.com --interval 120  # Ping domain every 2 min
    python wifi-keep-alive.py --help                # Show help message

Requirements:
-------------
    Python 3.6+ (standard library only)

Notes:
------
    Press Ctrl+C to stop gracefully. Works on Windows, macOS, and Linux.
"""

import argparse
import subprocess
import sys
import time
from datetime import datetime

# Cache platform check once at module load (avoids repeated checks in hot loop)
IS_WINDOWS = sys.platform == "win32"
PING_COUNT_FLAG = "-n" if IS_WINDOWS else "-c"
PING_TIMEOUT_FLAG = "-w" if IS_WINDOWS else "-W"


def ping(host: str, count: int = 1, timeout: int = 5) -> bool:
    """
    Ping a host and return True if successful.

    Uses the system's native ping command with a timeout to prevent hanging
    on unreachable hosts. Output is suppressed for cleaner operation.

    Args:
        host: The hostname or IP address to ping.
        count: Number of ping packets to send (default: 1 for efficiency).
        timeout: Seconds to wait for response (default: 5).

    Returns:
        True if the ping succeeded (host reachable), False otherwise.
    """
    # Build command with count and timeout flags
    # Windows timeout is in milliseconds, Unix is in seconds
    timeout_value = str(timeout * 1000) if IS_WINDOWS else str(timeout)
    command = ["ping", PING_COUNT_FLAG, str(count), PING_TIMEOUT_FLAG, timeout_value, host]

    try:
        subprocess.run(
            command,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=True
        )
        return True
    except subprocess.CalledProcessError:
        return False


def main():
    """
    Main entry point: parse arguments and run the keep-alive ping loop.
    """
    parser = argparse.ArgumentParser(
        description="Ping a network device at regular intervals to keep WiFi connection alive."
    )
    parser.add_argument(
        "host",
        help="FQDN or IP address of the network device to ping"
    )
    parser.add_argument(
        "-i", "--interval",
        type=int,
        default=60,
        help="Interval in seconds between pings (default: 60)"
    )
    args = parser.parse_args()

    # Validate interval
    if args.interval < 1:
        print("Error: Interval must be at least 1 second", file=sys.stderr)
        sys.exit(1)

    print(f"Starting keep-alive pings to {args.host} every {args.interval} seconds...")
    print("Press Ctrl+C to stop.\n")

    try:
        while True:
            timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            status = "OK" if ping(args.host) else "FAILED"
            print(f"[{timestamp}] Ping to {args.host}: {status}")
            time.sleep(args.interval)
    except KeyboardInterrupt:
        print("\nStopped.")


if __name__ == "__main__":
    main()