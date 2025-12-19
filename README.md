# WiFi Keep-Alive

A lightweight Python utility that prevents WiFi connections from entering power-save mode by sending periodic ping requests to a network device.

## The Problem

Low-powered devices like Raspberry Pi, IoT devices, and embedded systems often experience WiFi connectivity issues due to aggressive power management. When the WiFi adapter enters power-save mode, it can cause:

- **Dropped SSH connections** - Frustrating disconnections during remote work
- **Delayed network responses** - High latency when the adapter "wakes up"
- **Unreachable services** - Web servers, APIs, or other services become temporarily unavailable
- **Missed notifications** - Home automation or monitoring systems fail to respond

This is especially common on:
- Raspberry Pi (all models)
- Orange Pi and similar SBCs
- ESP32/ESP8266 devices
- Any device using USB WiFi adapters
- Networks with aggressive idle timeouts

## The Solution

WiFi Keep-Alive sends regular ICMP ping requests to a specified network device (your router, a DNS server, etc.), keeping the WiFi connection active and preventing the adapter from entering power-save mode.

## Features

- ✅ **Zero dependencies** - Uses only Python standard library
- ✅ **Cross-platform** - Works on Linux, macOS, and Windows
- ✅ **Lightweight** - Minimal CPU and memory footprint
- ✅ **Configurable** - Adjustable ping interval
- ✅ **Timeout protection** - Pings won't hang on unreachable hosts
- ✅ **Timestamped output** - Easy log analysis with timestamps
- ✅ **Systemd ready** - Includes installer for running as a service

## Requirements

- Python 3.6 or higher
- Network access (ability to send ICMP ping packets)

## Installation

### Option 1: Clone the Repository

```bash
git clone https://github.com/EnvillePlease/wifi-keep-alive.git
cd wifi-keep-alive
```

### Option 2: Download Directly

```bash
wget https://raw.githubusercontent.com/EnvillePlease/wifi-keep-alive/main/wifi-keep-alive.py
chmod +x wifi-keep-alive.py
```

## Usage

### Running from Terminal

Basic usage - ping your router every 60 seconds (default):

```bash
python3 wifi-keep-alive.py 192.168.1.1
```

Ping Google's DNS server every 30 seconds:

```bash
python3 wifi-keep-alive.py 8.8.8.8 -i 30
```

Ping a domain name with a 2-minute interval:

```bash
python3 wifi-keep-alive.py google.com --interval 120
```

Show help message:

```bash
python3 wifi-keep-alive.py --help
```

### Command Line Options

| Option | Description | Default |
|--------|-------------|---------|
| `host` | IP address or hostname to ping (required) | - |
| `-i`, `--interval` | Seconds between ping tests | 60 |

### Example Output

```
Starting keep-alive pings to 192.168.1.1 every 60 seconds...
Press Ctrl+C to stop.

[2025-12-19 10:30:00] Ping to 192.168.1.1: OK
[2025-12-19 10:31:00] Ping to 192.168.1.1: OK
[2025-12-19 10:32:00] Ping to 192.168.1.1: OK
^C
Stopped.
```

## Running as a Systemd Service (Raspberry Pi)

For Raspberry Pi or other Linux systems running systemd, you can install WiFi Keep-Alive as a background service that starts automatically at boot.

### Requirements

- Raspberry Pi OS Bookworm (version 12) or higher
- Root/sudo access

### Installation

1. **Run the setup script:**

   ```bash
   sudo ./setup-service.sh
   ```

2. **Follow the prompts:**
   - **Service user**: Username to run the service (default: `wifi-keepalive`)
   - **Target host**: IP or hostname to ping (e.g., `192.168.1.1`)
   - **Interval**: Seconds between pings (default: `60`)

3. **Verify the service is running:**

   ```bash
   sudo systemctl status wifi-keep-alive
   ```

### Service Management

```bash
# Check service status
sudo systemctl status wifi-keep-alive

# View live logs
sudo journalctl -u wifi-keep-alive -f

# Stop the service
sudo systemctl stop wifi-keep-alive

# Start the service
sudo systemctl start wifi-keep-alive

# Restart the service
sudo systemctl restart wifi-keep-alive

# Disable auto-start at boot
sudo systemctl disable wifi-keep-alive

# Enable auto-start at boot
sudo systemctl enable wifi-keep-alive
```

### Uninstallation

```bash
sudo ./setup-service.sh --uninstall
```

This will:
- Stop and disable the service
- Remove the systemd service file
- Remove the installed script
- Optionally remove the service user

## Choosing a Target Host

The target host should be a device that:

1. **Is always available** - Your router is usually the best choice
2. **Responds to ping** - Some devices/firewalls block ICMP
3. **Is on your local network** - Reduces latency and external dependencies

Recommended targets:

| Target | IP Address | Notes |
|--------|------------|-------|
| Your router | `192.168.1.1` | Best choice, always available |
| Google DNS | `8.8.8.8` | Reliable, but requires internet |
| Cloudflare DNS | `1.1.1.1` | Fast, reliable public DNS |
| Gateway | Check with `ip route` | Your network's default gateway |

To find your router's IP address:

```bash
# Linux/macOS
ip route | grep default | awk '{print $3}'

# or
netstat -rn | grep default
```

## Choosing an Interval

The default 60-second interval works well for most situations. Consider:

| Interval | Use Case |
|----------|----------|
| 30 seconds | Aggressive networks with short idle timeouts |
| 60 seconds | General purpose (default) |
| 120 seconds | Conservative, minimal network traffic |
| 300 seconds | Very relaxed networks |

**Note:** Shorter intervals mean more network traffic but more reliable connections.

## Troubleshooting

### Permission Denied

If you get permission errors when running the script:

```bash
chmod +x wifi-keep-alive.py
```

### Ping Requires Root

On some systems, ping requires elevated privileges. The systemd service handles this automatically with `CAP_NET_RAW`. For manual execution:

```bash
sudo python3 wifi-keep-alive.py 192.168.1.1
```

### Service Won't Start

Check the service logs for errors:

```bash
sudo journalctl -u wifi-keep-alive -n 50
```

Common issues:
- Invalid host address
- Network not available at boot (service starts too early)
- Python not found

### WiFi Still Disconnecting

If WiFi still disconnects, you may also need to disable power management at the driver level:

```bash
# Check current power management status
iwconfig wlan0 | grep "Power Management"

# Disable power management (temporary)
sudo iwconfig wlan0 power off

# Make permanent (add to /etc/rc.local or create a systemd service)
```

## How It Works

1. The script runs in an infinite loop
2. Every `interval` seconds, it sends 4 ICMP ping packets to the target host
3. The ping activity keeps the WiFi adapter active
4. If a ping fails, it logs the failure but continues running
5. Press `Ctrl+C` to stop gracefully

## License

MIT License - See [LICENSE](LICENSE) for details.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Related Projects

- [Network Manager](https://networkmanager.dev/) - Full network management solution
- [wavemon](https://github.com/uoaerg/wavemon) - Wireless network monitor
