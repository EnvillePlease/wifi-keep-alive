#!/usr/bin/env python3
"""
WiFi Keep-Alive Utility

This script sends periodic ping requests to a specified network device to prevent
WiFi connections from going idle and disconnecting. Useful for maintaining
persistent connections on networks with aggressive idle timeouts.

Example Usage:
--------------
    # Ping your router every 60 seconds (default interval)
    python wifi-keep-alive.py 192.168.1.1

    # Ping Google DNS every 30 seconds
    python wifi-keep-alive.py 8.8.8.8 -i 30

    # Ping a domain name with a 2-minute interval
    python wifi-keep-alive.py google.com --interval 120

    # Show help message
    python wifi-keep-alive.py --help

Requirements:
-------------
    - Python 3.6+
    - No external dependencies (uses only standard library)

Notes:
------
    - Press Ctrl+C to stop the script gracefully
    - Works on Windows, macOS, and Linux
"""

import argparse
import subprocess
import sys
import time


def ping(host: str, count: int = 4) -> bool:
    """
    Ping a host and return True if successful.

    Sends ICMP echo requests to the specified host using the system's
    native ping command. The output is suppressed for cleaner operation.

    Args:
        host: The hostname or IP address to ping.
        count: Number of ping packets to send (default: 4).

    Returns:
        True if the ping was successful (host is reachable), False otherwise.
    """
    # Windows uses "-n" for count, while Unix-like systems use "-c"
    param = "-n" if sys.platform == "win32" else "-c"
    command = ["ping", param, str(count), host]

    try:
        # Run the ping command, suppressing stdout/stderr for clean output
        subprocess.run(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
        return True
    except subprocess.CalledProcessError:
        # Ping failed - host unreachable or network error
        return False


def main():
    """
    Main entry point for the WiFi keep-alive utility.

    Parses command-line arguments and runs an infinite loop that pings
    the specified host at regular intervals until interrupted by the user.
    """
    # Set up command-line argument parsing
    parser = argparse.ArgumentParser(
        description="Ping a network device at regular intervals to keep WiFi connection alive."
    )

    # Required positional argument: the target host to ping
    parser.add_argument(
        "host",
        help="FQDN or IP address of the network device to ping"
    )

    # Optional argument: interval between pings (in seconds)
    parser.add_argument(
        "-i", "--interval",
        type=int,
        default=60,
        help="Interval in seconds between ping tests (default: 60)"
    )

    args = parser.parse_args()

    # Display startup message with configuration
    print(f"Starting keep-alive pings to {args.host} every {args.interval} seconds...")
    print("Press Ctrl+C to stop.")

    try:
        # Main loop: continuously ping the host at the specified interval
        while True:
            success = ping(args.host)
            status = "OK" if success else "FAILED"
            print(f"Ping to {args.host}: {status}")

            # Wait for the specified interval before the next ping
            time.sleep(args.interval)

    except KeyboardInterrupt:
        # Handle graceful shutdown when user presses Ctrl+C
        print("\nStopped.")


# Standard Python idiom: only run main() when script is executed directly
if __name__ == "__main__":
    main()