# FRP Tunnel

Single-file Bash manager for FRP tunnels between an Iran server and a Kharej (foreign) server.
It targets Ubuntu/Debian with root access and the current FRP release with TOML configs.

## Run

```bash
chmod +x frp-tunnel.sh
sudo ./frp-tunnel.sh
```

After the first run, the script installs itself as `frp-tunnel`.

## Features

- Two modes: **Reverse** (Kharej connects to Iran, the default) and **Direct** (Iran connects to Kharej, through STCP or a plain proxy)
- **Exit tunnel (users on Iran)**: users stay on the Iran panel and their traffic leaves from Kharej. Two kinds:
  - **Xray exit (recommended)**: the script installs Xray core on the Kharej server by itself (no panel there) and runs a VLESS inbound on `127.0.0.1`. One to four FRP tunnels (tcp, kcp, quic, websocket) carry it to the Iran server, and the Iran panel picks the best working one with an Xray balancer. TCP and UDP both work, so DNS and voice calls work too. When 3x-ui is on the Iran server, the script can add the outbounds, balancer and rule to it by itself, after backing up its database and testing the new config with the panel's own Xray
  - **SOCKS exit**: FRP's SOCKS5 plugin, no Xray on Kharej, TCP only
- Transports: tcp, kcp, quic, websocket, wss (wss uses a socat TLS terminator in front of frps)
- Fast setup: only Tunnel port, Iran/Kharej IP and VPN config ports are asked (TCP by default); protocol, TLS, token, UDP and the 127.0.0.1-only option for a panel on the same server are under Advanced settings
- Firewall ports opened automatically (UFW, firewalld or iptables) and kept open after reboot
- Token auth, TLS (built-in, self-signed with optional mTLS, or Let's Encrypt via acme.sh with Cloudflare DNS or standalone validation), tcpMux, compression, pool count, heartbeat
- Port lists and ranges (`443,2000-2010`) for TCP, UDP or both, with checks for ports already in use
- One systemd service per tunnel (`frp-<name>`) with `Restart=always`
- A connection key that carries all settings and certificates to the other server
- Local IPs over GRE, SIT/6to4 or VXLAN, with matching addresses suggested on both sides, persistence through systemd, and a ping test
- Diagnose tool that explains why a tunnel does not connect (token, firewall, busy ports, TLS)
- Watchdog that checks the FRP admin API, automatic certificate renewal, BBR/sysctl/ulimit tuning, backup and restore, and uninstall
- FRP and Xray downloads from GitHub, a mirror, a direct link or a local file (Xray downloads are checked against their SHA-256 digest)
