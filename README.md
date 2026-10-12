# FRP Tunnel

Single-file Bash manager for FRP tunnels between an Iran server and a foreign server.
It targets Ubuntu/Debian with root access and the current FRP release with TOML configs.

## Run

```bash
chmod +x frp-tunnel.sh
sudo ./frp-tunnel.sh
```

After the first run, the script installs itself as `frp-tunnel`.

## Features

- Two modes: **Reverse**, where Iran runs frps and Foreign connects, and **Direct**, where Foreign runs frps and Iran connects through an STCP visitor or a plain proxy
- Transports: tcp, kcp, quic, websocket, wss (wss uses a socat TLS terminator in front of frps)
- Token auth, TLS (built-in, self-signed with optional mTLS, or Let's Encrypt via acme.sh with Cloudflare DNS or standalone validation), tcpMux, compression, pool count, heartbeat
- Port lists and ranges (`443,2000-2010`) for TCP, UDP or both, with checks for ports already in use
- One systemd service per tunnel (`frp-<name>`) with `Restart=always`
- A connection key that carries all settings and certificates to the other server
- Local IPs over GRE, SIT/6to4 or VXLAN, with matching addresses suggested on both sides, persistence through systemd, and a ping test
- Watchdog that checks the FRP admin API, automatic certificate renewal, BBR/sysctl/ulimit tuning, backup and restore, and uninstall
- FRP downloads from GitHub, a mirror, a direct link or a local file
