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
- **Exit tunnel (users on Iran)**: users stay on the Iran panel and their traffic leaves from Kharej. The Kharej server runs only FRP with its SOCKS5 plugin, published on Iran at `127.0.0.1` with a random user and password. The script prints the 3x-ui outbound JSON and the DNS-over-HTTPS steps. Only TCP is carried, so UDP voice calls and games do not work through it
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
- FRP downloads from GitHub, a mirror, a direct link or a local file
