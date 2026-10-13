#!/usr/bin/env bash

APP_VER="1.2.0"
FRP_DEFAULT_VER="0.71.0"
BASE_DIR="/etc/frp-tunnel"
TUN_DIR="$BASE_DIR/tunnels"
CERT_DIR="$BASE_DIR/certs"
LIP_DIR="$BASE_DIR/localip"
HOOK_DIR="$BASE_DIR/hooks"
WD_CONF="$BASE_DIR/watchdog.conf"
BIN_DIR="/usr/local/bin"
FRPS_BIN="$BIN_DIR/frps"
FRPC_BIN="$BIN_DIR/frpc"
SELF_BIN="$BIN_DIR/frp-tunnel"
UNIT_DIR="/etc/systemd/system"
LOG_DIR="/var/log/frp-tunnel"
WD_STATE="/run/frp-tunnel-watchdog"
BACKUP_DIR="/root/frp-tunnel-backups"
ACME_HOME="/root/.acme.sh"
SYSCTL_FILE="/etc/sysctl.d/99-frp-tunnel.conf"
BBR_FILE="/etc/sysctl.d/99-frp-tunnel-bbr.conf"
BBR_MOD_FILE="/etc/modules-load.d/frp-tunnel-bbr.conf"
LIMITS_FILE="/etc/security/limits.d/99-frp-tunnel.conf"
SDLIMIT_FILE="/etc/systemd/system.conf.d/99-frp-tunnel.conf"
SYS_CA="/etc/ssl/certs/ca-certificates.crt"
TLS_SNI="frp-tunnel.internal"
KEY_PREFIX="frpt1:"
GKEY_PREFIX="frpg1:"
GROUP_DIR="$BASE_DIR/groups"
MAX_PORTS=1000
FRP_REPO="https://github.com/fatedier/frp"
ACME_TGZ="https://github.com/acmesh-official/acme.sh/archive/refs/heads/master.tar.gz"
GH_MIRRORS=("https://ghfast.top/" "https://gh-proxy.com/" "https://ghproxy.net/" "https://gh.llkk.cc/")

PAL=(142 218 132 137 141 80 117 216 186 139 73 223 110 181 179 104 168 229 153 182)
LOGO_C=(219 183 147 111 75)
C_SUB=250
C_OK=82
C_ERR=196
C_WARN=208
C_DEF=231
C_DARK=16
C_LIGHT=231
BG_OK=34
BG_ERR=160
BG_TITLE=189
LOGO=(
"██████ █████  █████     ██████ ██  ██ ██   ██ ██   ██ ██████ ██    "
"██     ██  ██ ██  ██      ██   ██  ██ ███  ██ ███  ██ ██     ██    "
"█████  █████  █████       ██   ██  ██ ██ █ ██ ██ █ ██ █████  ██    "
"██     ██ ██  ██          ██   ██  ██ ██  ███ ██  ███ ██     ██    "
"██     ██  ██ ██          ██    ████  ██   ██ ██   ██ ██████ ██████"
)

CI=0
NC=0
PUBIP=""
CHK_PROTOS="tcp"
declare -A T=()
declare -A K=()
declare -A L=()
declare -A LMAP=()
declare -A EXCL=()
PORT_LIST=()
BIND_LIST=()
EXTRA_EXCL=""
TNAMES=()
LNAMES=()

cnext() { NC=${PAL[CI % ${#PAL[@]}]}; CI=$((CI + 1)); }
say() { cnext; printf '  \e[38;5;%sm%s\e[0m\n' "$NC" "$*"; }
ok() { printf '  \e[38;5;%sm✔ %s\e[0m\n' "$C_OK" "$*"; }
err() { printf '  \e[38;5;%sm✘ %s\e[0m\n' "$C_ERR" "$*"; }
warn() { printf '  \e[38;5;%sm! %s\e[0m\n' "$C_WARN" "$*"; }
info() { cnext; printf '  \e[38;5;%sm• %s\e[0m\n' "$NC" "$*"; }
blank() { printf '\n'; }
kv() { cnext; printf '  \e[38;5;%sm%-20s %s\e[0m\n' "$NC" "$1" "$2"; }
item() { cnext; printf '  \e[38;5;%sm%3s) %s\e[0m\n' "$NC" "$1" "$2"; }
section() { cnext; printf '\n  \e[1;38;5;%sm%s\e[0m\n' "$NC" "$1"; }
title() { printf '\n  \e[1;48;5;%sm\e[38;5;%sm %-66s \e[0m\n\n' "$BG_TITLE" "$C_DARK" "$1"; }
on_int() { printf '\e[0m\n'; exit 130; }

banner() {
    local v cnt act
    if frp_installed; then
        v=$(frp_version)
        cnt=$(tunnel_names | grep -c .)
        act=$(active_tunnels | grep -c .)
        printf '  \e[1;48;5;%sm\e[38;5;%sm  %-66s\e[0m\n' "$BG_OK" "$C_DARK" "FRP INSTALLED  v${v:-?}    tunnels: $cnt    active: $act"
    else
        printf '  \e[1;48;5;%sm\e[38;5;%sm  %-66s\e[0m\n' "$BG_ERR" "$C_LIGHT" "FRP NOT INSTALLED"
    fi
}

header() {
    clear 2>/dev/null || printf '\033c'
    CI=0
    printf '\n'
    local i
    for i in "${!LOGO[@]}"; do
        printf '  \e[38;5;%sm%s\e[0m\n' "${LOGO_C[i]}" "${LOGO[i]}"
    done
    printf '  \e[38;5;%sm%-58s%10s\e[0m\n\n' "$C_SUB" "Iran <-> Kharej tunnel manager" "v$APP_VER"
    banner
    [ -n "$1" ] && title "$1"
}

read_line() {
    local __l
    if ! IFS= read -r __l; then
        printf '\e[0m\n'
        exit 0
    fi
    __l=${__l#"${__l%%[![:space:]]*}"}
    __l=${__l%"${__l##*[![:space:]]}"}
    printf -v "$1" '%s' "$__l"
}

trim() {
    local s=$1
    s=${s#"${s%%[![:space:]]*}"}
    s=${s%"${s##*[![:space:]]}"}
    printf '%s' "$s"
}

prompt() {
    if [ -n "$3" ]; then
        printf '  \e[38;5;%sm%s \e[38;5;%sm(%s)\e[38;5;%sm: \e[0m' "$1" "$2" "$C_DEF" "$3" "$1"
    else
        printf '  \e[38;5;%sm%s: \e[0m' "$1" "$2"
    fi
}

ask() {
    local __n=$1 __q=$2 __d=$3 __v=$4 __m=${5:-Invalid value} __i __c __o=0
    if [ "${__v:0:1}" = "?" ]; then
        __o=1
        __v=${__v:1}
    fi
    cnext
    __c=$NC
    while :; do
        prompt "$__c" "$__q" "$__d"
        read_line __i
        [ -z "$__i" ] && __i=$__d
        if [ -z "$__i" ]; then
            if [ "$__o" = 1 ]; then
                printf -v "$__n" '%s' ""
                return 0
            fi
            err "A value is required"
            continue
        fi
        if [ -n "$__v" ] && ! "$__v" "$__i"; then
            [ "$__m" != "-" ] && err "$__m"
            continue
        fi
        printf -v "$__n" '%s' "$__i"
        return 0
    done
}

choose() {
    local __n=$1 __t=$2 __d=$3 __i __c __k
    shift 3
    local -a __o=("$@")
    [ -n "$__t" ] && section "$__t"
    for __k in "${!__o[@]}"; do
        item "$((__k + 1))" "${__o[__k]}"
    done
    cnext
    __c=$NC
    while :; do
        prompt "$__c" "Select" "$__d"
        read_line __i
        [ -z "$__i" ] && __i=$__d
        if [[ $__i =~ ^[0-9]{1,3}$ ]] && ((10#$__i >= 1 && 10#$__i <= ${#__o[@]})); then
            printf -v "$__n" '%s' "$((10#$__i))"
            return 0
        fi
        err "Enter a number from 1 to ${#__o[@]}"
    done
}

menu_pick() {
    local __n=$1 __max=$2 __i __c
    cnext
    __c=$NC
    blank
    while :; do
        prompt "$__c" "Select" ""
        read_line __i
        if [[ $__i =~ ^[0-9]{1,3}$ ]] && ((10#$__i <= __max)); then
            printf -v "$__n" '%s' "$((10#$__i))"
            return 0
        fi
        err "Enter a number from 0 to $__max"
    done
}

confirm() {
    local q=$1 d=${2:-n} i c hint
    cnext
    c=$NC
    if [ "$d" = y ]; then hint="Y/n"; else hint="y/N"; fi
    while :; do
        prompt "$c" "$q" "$hint"
        read_line i
        i=${i,,}
        [ -z "$i" ] && i=$d
        case $i in
            y | yes) return 0 ;;
            n | no) return 1 ;;
        esac
        err "Please answer y or n"
    done
}

pause() {
    local _p
    cnext
    printf '\n  \e[38;5;%sm%s\e[0m' "$NC" "Press Enter to continue..."
    IFS= read -r _p || exit 0
}

yn() { if [ "$1" = y ]; then printf 'on'; else printf 'off'; fi; }
tf() { if [ "$1" = y ]; then printf 'true'; else printf 'false'; fi; }

is_ipv4() {
    local o='(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])'
    [[ $1 =~ ^$o\.$o\.$o\.$o$ ]]
}

is_ipv6() {
    local a=$1 g n=0 x at
    [[ $a == *:* ]] || return 1
    [[ $a =~ ^[0-9A-Fa-f:]+$ ]] || return 1
    [[ $a == *:::* ]] && return 1
    at=${a//::/@}
    at=${at//[^@]/}
    ((${#at} <= 1)) || return 1
    if [[ $a == :* && $a != ::* ]] || [[ $a == *: && $a != *:: ]]; then
        return 1
    fi
    IFS=: read -ra g <<<"$a"
    for x in "${g[@]}"; do
        [ -z "$x" ] && continue
        ((${#x} <= 4)) || return 1
        n=$((n + 1))
    done
    if [ -n "$at" ]; then ((n <= 7)); else ((n == 8)); fi
}

is_ip() { is_ipv4 "$1" || is_ipv6 "$1"; }

is_domain() {
    ((${#1} <= 253)) && [[ $1 =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$ ]]
}

is_host() { is_ip "$1" || is_domain "$1"; }
is_port() { [[ $1 =~ ^[1-9][0-9]{0,4}$ ]] && (($1 <= 65535)); }
is_name() { [[ $1 =~ ^[a-z0-9]([a-z0-9-]{0,10}[a-z0-9])?$ ]]; }
is_lip_name() { [[ $1 =~ ^[a-z0-9]{1,10}$ ]]; }
is_token() { [[ $1 =~ ^[A-Za-z0-9._-]{8,128}$ ]]; }
is_ver() { [[ $1 =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; }
is_email() { [[ $1 =~ ^[A-Za-z0-9._%+-]+@([A-Za-z0-9-]+\.)+[A-Za-z]{2,63}$ ]]; }
is_cf_token() { [[ $1 =~ ^[A-Za-z0-9_-]{20,128}$ ]]; }
is_zone_id() { [[ $1 =~ ^[A-Fa-f0-9]{32}$ ]]; }
is_b64() { [[ $1 =~ ^[A-Za-z0-9+/]+=*$ ]]; }
is_url() {
    local r='^https?://[A-Za-z0-9.-]+(:[0-9]{1,5})?(/[A-Za-z0-9._~:/?#@!$&()*+,;=%-]*)?$'
    [[ $1 =~ $r ]]
}
is_path() { [ -e "$1" ]; }
is_cert_file() { [ -f "$1" ] && openssl x509 -noout -in "$1" >/dev/null 2>&1; }
is_key_file() { [ -f "$1" ] && openssl pkey -noout -in "$1" >/dev/null 2>&1; }

num_range() {
    [[ $1 =~ ^[0-9]{1,8}$ ]] && ((10#$1 >= $2 && 10#$1 <= $3))
}
v_pool() { num_range "$1" 0 100; }
v_hb() { num_range "$1" 0 3600; }
v_vni() { num_range "$1" 1 16777215; }
v_interval() { num_range "$1" 10 3600; }
v_fails() { num_range "$1" 1 20; }

is_cidr4() {
    [[ $1 == */* ]] || return 1
    is_ipv4 "${1%/*}" && num_range "${1##*/}" 8 32
}

is_cidr6() {
    [[ $1 == */* ]] || return 1
    is_ipv6 "${1%/*}" && num_range "${1##*/}" 8 128
}

v_addr4() { if [[ $1 == */* ]]; then is_cidr4 "$1"; else is_ipv4 "$1"; fi; }
v_addr6() { if [[ $1 == */* ]]; then is_cidr6 "$1"; else is_ipv6 "$1"; fi; }

rand_str() {
    local n=${1:-32} s=""
    while ((${#s} < n)); do
        s+=$(head -c 512 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9')
    done
    printf '%s' "${s:0:n}"
}

trunc() {
    local s=$1 n=$2
    if ((${#s} > n)); then printf '%s~' "${s:0:n-1}"; else printf '%s' "$s"; fi
}

short_list() {
    local -a a
    read -ra a <<<"$1"
    if ((${#a[@]} > 8)); then
        printf '%s ... (+%s more)' "${a[*]:0:8}" "$((${#a[@]} - 8))"
    else
        printf '%s' "${a[*]}"
    fi
}

apt_install() {
    export DEBIAN_FRONTEND=noninteractive
    apt-get install -y -qq "$@" >/dev/null 2>&1 && return 0
    apt-get update -qq >/dev/null 2>&1
    apt-get install -y -qq "$@" >/dev/null 2>&1
}

need_pkg() {
    command -v "$1" >/dev/null 2>&1 && return 0
    info "Installing $2 ..."
    if apt_install "$2" && command -v "$1" >/dev/null 2>&1; then
        ok "$2 installed"
        return 0
    fi
    err "Could not install $2"
    return 1
}

check_os() {
    local id="" like=""
    if [ -r /etc/os-release ]; then
        id=$(. /etc/os-release && printf '%s' "$ID")
        like=$(. /etc/os-release && printf '%s' "$ID_LIKE")
    fi
    case "$id $like" in
        *ubuntu* | *debian*) return 0 ;;
    esac
    warn "This script is built for Ubuntu/Debian. Detected: ${id:-unknown}"
    confirm "Continue anyway?" n || exit 1
}

ensure_deps() {
    local -A map=([curl]=curl [tar]=tar [gzip]=gzip [openssl]=openssl [ip]=iproute2 [ss]=iproute2 [ping]=iputils-ping [base64]=coreutils [sha256sum]=coreutils [awk]=gawk [find]=findutils)
    local -a need=()
    local c p
    for c in "${!map[@]}"; do
        command -v "$c" >/dev/null 2>&1 && continue
        p=${map[$c]}
        [[ " ${need[*]} " == *" $p "* ]] || need+=("$p")
    done
    [ -f "$SYS_CA" ] || need+=(ca-certificates)
    ((${#need[@]})) || return 0
    printf '  \e[38;5;%sm• %s\e[0m\n' "${PAL[6]}" "Installing dependencies: ${need[*]}"
    if ! apt_install "${need[@]}"; then
        warn "Some dependencies could not be installed: ${need[*]}"
        sleep 2
    fi
}

init_dirs() {
    mkdir -p "$TUN_DIR" "$CERT_DIR/self" "$CERT_DIR/le" "$LIP_DIR" "$HOOK_DIR" "$LOG_DIR" "$GROUP_DIR"
    chmod 700 "$BASE_DIR" "$TUN_DIR" "$CERT_DIR"
}

self_install() {
    local src
    src=$(readlink -f "$0" 2>/dev/null)
    [ -n "$src" ] && [ -f "$src" ] || return 0
    [ "$src" = "$SELF_BIN" ] && return 0
    head -n 1 "$src" 2>/dev/null | grep -q bash || return 0
    if ! cmp -s "$src" "$SELF_BIN" 2>/dev/null; then
        cp -f "$src" "$SELF_BIN" 2>/dev/null && chmod 755 "$SELF_BIN"
    fi
}

detect_ip4() {
    ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i = 1; i <= NF; i++) if ($i == "src") { print $(i + 1); exit }}'
}

default_iface() {
    ip -4 route show default 2>/dev/null | awk '{for (i = 1; i <= NF; i++) if ($i == "dev") { print $(i + 1); exit }}'
}

get_public_ip() {
    [ -n "$PUBIP" ] && return 0
    local u ip
    for u in https://api.ipify.org https://ipv4.icanhazip.com https://ifconfig.me/ip; do
        ip=$(curl -4 -fsS -m 4 "$u" 2>/dev/null | tr -d '[:space:]')
        if is_ipv4 "$ip"; then
            PUBIP=$ip
            return 0
        fi
    done
    PUBIP=$(detect_ip4)
}

scan_listen() {
    local p n
    LMAP=()
    while read -r p n; do
        [ -n "$p" ] && [ -z "${LMAP[$p]}" ] && LMAP[$p]=${n:-?}
    done < <(ss -H -ln"$1"p 2>/dev/null | awk '{n = split($4, a, ":"); p = a[n]; proc = "?"; if (match($0, /users:\(\("[^"]+"/)) proc = substr($0, RSTART + 9, RLENGTH - 10); print p, proc}')
}

port_owner() {
    scan_listen "${2:0:1}"
    if [ -n "${LMAP[$1]}" ]; then
        printf '%s' "${LMAP[$1]}"
        return 0
    fi
    return 1
}

parse_ports() {
    local spec=${1//[[:space:]]/} tok a b p
    local -A seen=()
    local -a toks
    PORT_LIST=()
    [ -n "$spec" ] || return 1
    [[ $spec =~ ^[0-9]+(-[0-9]+)?(,[0-9]+(-[0-9]+)?)*$ ]] || return 1
    IFS=, read -ra toks <<<"$spec"
    for tok in "${toks[@]}"; do
        if [[ $tok =~ ^([0-9]{1,5})-([0-9]{1,5})$ ]]; then
            a=$((10#${BASH_REMATCH[1]}))
            b=$((10#${BASH_REMATCH[2]}))
        elif [[ $tok =~ ^[0-9]{1,5}$ ]]; then
            a=$((10#$tok))
            b=$a
        else
            return 1
        fi
        ((a >= 1 && b <= 65535 && a <= b)) || return 1
        ((b - a + 1 <= MAX_PORTS)) || return 1
        for ((p = a; p <= b; p++)); do
            if [ -z "${seen[$p]}" ]; then
                seen[$p]=1
                PORT_LIST+=("$p")
            fi
        done
        ((${#PORT_LIST[@]} <= MAX_PORTS)) || return 1
    done
    ((${#PORT_LIST[@]} > 0))
}

ports_compact() {
    local -a s
    local out="" start="" prev="" p
    if (($#)); then
        mapfile -t s < <(printf '%s\n' "$@" | sort -n)
    else
        mapfile -t s < <(printf '%s\n' "${PORT_LIST[@]}" | sort -n)
    fi
    for p in "${s[@]}" ""; do
        if [ -n "$start" ] && { [ -z "$p" ] || ((p != prev + 1)); }; then
            if ((start == prev)); then out+="${out:+,}$start"; else out+="${out:+,}$start-$prev"; fi
            start=""
        fi
        [ -z "$p" ] && break
        [ -z "$start" ] && start=$p
        prev=$p
    done
    printf '%s' "$out"
}

busy_ports() {
    local type=$1 out="" p t
    for t in tcp udp; do
        [[ $type == both || $type == "$t" ]] || continue
        scan_listen "${t:0:1}"
        for p in "${PORT_LIST[@]}"; do
            [ -n "${EXCL[$p/$t]}" ] && continue
            [ -n "${LMAP[$p]}" ] && out+="$p/$t:${LMAP[$p]} "
        done
    done
    printf '%s' "${out% }"
}

idle_ports() {
    local type=$1 out="" p t
    for t in tcp udp; do
        [[ $type == both || $type == "$t" ]] || continue
        scan_listen "${t:0:1}"
        for p in "${PORT_LIST[@]}"; do
            [ -z "${LMAP[$p]}" ] && out+="$p/$t "
        done
    done
    printf '%s' "${out% }"
}

alloc_port() {
    local p=$1 ex=" $2 " used
    used=" $(grep -hoE '^(ADMIN_PORT|PADMIN_PORT|INT_PORT|BIND_PORT)=[0-9]+' "$TUN_DIR"/*/tunnel.conf 2>/dev/null | cut -d= -f2 | tr '\n' ' ') "
    scan_listen t
    while ((p < 65000)); do
        if [[ $used != *" $p "* && $ex != *" $p "* ]] && [ -z "${LMAP[$p]}" ]; then
            printf '%s' "$p"
            return 0
        fi
        p=$((p + 1))
    done
    return 1
}

svc_state() {
    local s
    s=$(systemctl is-active "$1" 2>/dev/null | head -n 1)
    printf '%s' "${s:-unknown}"
}

svc_enabled() {
    local s
    s=$(systemctl is-enabled "$1" 2>/dev/null | head -n 1)
    printf '%s' "${s:-disabled}"
}

state_color() {
    case $1 in
        active | enabled) printf '%s' "$C_OK" ;;
        activating | reloading | deactivating) printf '%s' "$C_WARN" ;;
        *) printf '%s' "$C_ERR" ;;
    esac
}

ufw_active() {
    command -v ufw >/dev/null 2>&1 && LC_ALL=C LANG=C LANGUAGE='' ufw status 2>/dev/null | grep -q '^Status: active'
}

download() {
    info "Downloading: $1"
    rm -f "$2"
    if curl -fL --connect-timeout 15 --retry 2 --retry-delay 2 --progress-bar -o "$2" "$1" && [ -s "$2" ]; then
        return 0
    fi
    err "Download failed"
    return 1
}

pick_mirror() {
    local __n=$1 __c __p
    local -a opts=("${GH_MIRRORS[@]}" "Custom mirror prefix")
    choose __c "Mirror" 1 "${opts[@]}"
    if ((__c <= ${#GH_MIRRORS[@]})); then
        printf -v "$__n" '%s' "${GH_MIRRORS[__c - 1]}"
        return 0
    fi
    ask __p "Mirror prefix" "" is_url "Enter a valid http(s) URL"
    [[ $__p == */ ]] || __p+="/"
    printf -v "$__n" '%s' "$__p"
}

frp_arch() {
    case $(uname -m) in
        x86_64 | amd64) printf 'amd64' ;;
        aarch64 | arm64) printf 'arm64' ;;
        armv7* | armv6*) printf 'arm' ;;
        *) return 1 ;;
    esac
}

frp_installed() { [ -x "$FRPS_BIN" ] && [ -x "$FRPC_BIN" ]; }

frp_version() { "$FRPS_BIN" --version 2>/dev/null | head -n 1 | tr -d 'v[:space:]'; }

need_frp() {
    frp_installed && return 0
    warn "FRP is not installed"
    if confirm "Install it now?" y; then
        frp_menu
    fi
    frp_installed
}

frp_latest() {
    local pre=$1 v
    v=$(curl -fsSL -m 10 "${pre}https://api.github.com/repos/fatedier/frp/releases/latest" 2>/dev/null | grep -m 1 '"tag_name"' | sed -E 's/.*"v?([0-9.]+)".*/\1/')
    if ! is_ver "$v"; then
        v=$(curl -fsI -m 10 "${pre}$FRP_REPO/releases/latest" 2>/dev/null | tr -d '\r' | grep -i '^location:' | sed -E 's#.*/tag/v?([0-9.]+).*#\1#')
    fi
    is_ver "$v" && printf '%s' "$v"
}

frp_install_from() {
    local src=$1 tmp s c v n
    local -a act=()
    tmp=$(mktemp -d)
    if [ -d "$src" ]; then
        s=$(find "$src" -maxdepth 2 -type f -name frps | head -n 1)
        c=$(find "$src" -maxdepth 2 -type f -name frpc | head -n 1)
    else
        if ! tar -xzf "$src" -C "$tmp" 2>/dev/null; then
            err "Invalid archive, a .tar.gz file is expected"
            rm -rf "$tmp"
            return 1
        fi
        s=$(find "$tmp" -type f -name frps | head -n 1)
        c=$(find "$tmp" -type f -name frpc | head -n 1)
    fi
    if [ -z "$s" ] || [ -z "$c" ]; then
        err "frps / frpc binaries were not found"
        rm -rf "$tmp"
        return 1
    fi
    chmod +x "$s" "$c" 2>/dev/null
    if ! v=$("$s" --version 2>/dev/null) || ! "$c" --version >/dev/null 2>&1; then
        err "The binaries cannot run on this server (wrong architecture?)"
        rm -rf "$tmp"
        return 1
    fi
    mapfile -t act < <(active_tunnels)
    if cp -f "$s" "$FRPS_BIN.new" && cp -f "$c" "$FRPC_BIN.new" && chmod 755 "$FRPS_BIN.new" "$FRPC_BIN.new" &&
        mv -f "$FRPS_BIN.new" "$FRPS_BIN" && mv -f "$FRPC_BIN.new" "$FRPC_BIN"; then
        rm -rf "$tmp"
        ok "FRP v${v#v} installed to $BIN_DIR"
    else
        rm -f "$FRPS_BIN.new" "$FRPC_BIN.new"
        rm -rf "$tmp"
        err "Could not copy binaries to $BIN_DIR"
        return 1
    fi
    for n in "${act[@]}"; do
        systemctl restart "frp-$n.service" >/dev/null 2>&1
    done
    ((${#act[@]})) && ok "Restarted ${#act[@]} running tunnel(s)"
    return 0
}

frp_menu() {
    local arch src pre ver url path tmp c det
    while :; do
        header "INSTALL / UPDATE FRP"
        if frp_installed; then kv "Installed version" "v$(frp_version)"; else kv "Installed version" "none"; fi
        if ! arch=$(frp_arch); then
            err "Unsupported architecture: $(uname -m)"
            pause
            return 1
        fi
        kv "Architecture" "linux_$arch"
        choose src "Download source" 1 "GitHub" "Mirror" "Direct link" "Local file" "Back"
        [ "$src" = 5 ] && return 0
        tmp=$(mktemp -d)
        path="$tmp/frp.tar.gz"
        case $src in
            1 | 2)
                pre=""
                [ "$src" = 2 ] && pick_mirror pre
                info "Checking the latest release ..."
                det=$(frp_latest "$pre")
                if [ -z "$det" ]; then
                    warn "Could not detect the latest version"
                    det=$FRP_DEFAULT_VER
                fi
                ask ver "Version" "$det" is_ver "Use a version like $FRP_DEFAULT_VER"
                url="${pre}$FRP_REPO/releases/download/v$ver/frp_${ver}_linux_${arch}.tar.gz"
                download "$url" "$path" || path=""
                ;;
            3)
                ask url "Download link to .tar.gz" "" is_url "Enter a valid http(s) URL"
                download "$url" "$path" || path=""
                ;;
            4)
                ask path "Path to archive or folder" "" is_path "File or folder not found"
                ;;
        esac
        if [ -n "$path" ] && frp_install_from "$path"; then
            rm -rf "$tmp"
            pause
            return 0
        fi
        rm -rf "$tmp"
        confirm "Try another source?" y || return 1
    done
}

write_hooks() {
    mkdir -p "$HOOK_DIR"
    cat >"$HOOK_DIR/cert-reload.sh" <<EOF
#!/usr/bin/env bash
D="\$1"
for m in $TUN_DIR/*/tunnel.conf; do
    [ -f "\$m" ] || continue
    n=\$(sed -n 's/^NAME=//p' "\$m" | head -n 1)
    c=\$(sed -n 's/^CERT_MODE=//p' "\$m" | head -n 1)
    r=\$(sed -n 's/^CERT_REF=//p' "\$m" | head -n 1)
    [ "\$c" = le ] || continue
    [ -z "\$D" ] || [ "\$r" = "\$D" ] || continue
    systemctl is-active --quiet "frp-\$n.service" && systemctl restart "frp-\$n.service"
done
exit 0
EOF
    cat >"$HOOK_DIR/watchdog.sh" <<EOF
#!/usr/bin/env bash
TD="$TUN_DIR"
LOG="$LOG_DIR/watchdog.log"
ST="$WD_STATE"
FAILS=3
[ -f "$WD_CONF" ] && FAILS=\$(sed -n 's/^FAILS=//p' "$WD_CONF" | head -n 1)
[[ \$FAILS =~ ^[0-9]+\$ ]] || FAILS=3
mkdir -p "\$ST" "\$(dirname "\$LOG")"
g() { sed -n "s/^\$1=//p" "\$2" | head -n 1; }
lg() { printf '%s %s\n' "\$(date '+%F %T')" "\$*" >>"\$LOG"; }
chk() {
    local out total run
    out=\$(curl -s -m 5 -u "\$2:\$3" "http://127.0.0.1:\$1\$4") || return 1
    [ -n "\$out" ] || return 1
    [ "\$4" = /api/serverinfo ] && return 0
    total=\$(grep -o '"status":"[^"]*"' <<<"\$out" | wc -l)
    run=\$(grep -o '"status":"running"' <<<"\$out" | wc -l)
    if [ "\$5" = 1 ]; then
        [ "\$total" -gt 0 ] && [ "\$run" -gt 0 ]
    else
        [ "\$total" -eq 0 ] || [ "\$run" -gt 0 ]
    fi
}
fail() {
    local c
    c=\$(cat "\$ST/\$1" 2>/dev/null)
    c=\$((\${c:-0} + 1))
    if [ "\$c" -ge "\$FAILS" ]; then
        systemctl restart "\$2"
        lg "\$3: health check failed \$c times, \$2 restarted"
        rm -f "\$ST/\$1"
    else
        printf '%s' "\$c" >"\$ST/\$1"
    fi
}
for m in "\$TD"/*/tunnel.conf; do
    [ -f "\$m" ] || continue
    n=\$(g NAME "\$m")
    s=\$(g SIDE "\$m")
    svc="frp-\$n.service"
    systemctl is-enabled --quiet "\$svc" 2>/dev/null || continue
    st=\$(systemctl is-active "\$svc" 2>/dev/null)
    if [ "\$st" = failed ]; then
        systemctl restart "\$svc"
        lg "\$n: service had failed, restarted"
        rm -f "\$ST/\$n" "\$ST/\$n-p"
        continue
    fi
    [ "\$st" = active ] || continue
    for u in "frp-\$n-provider.service" "frp-\$n-wss.service"; do
        [ -f "$UNIT_DIR/\$u" ] || continue
        if ! systemctl is-active --quiet "\$u"; then
            systemctl restart "\$u"
            lg "\$n: \$u was down, restarted"
        fi
    done
    e=0
    if [ "\$s" = server ]; then
        p=/api/serverinfo
    else
        p=/api/status
        { [ "\$(g MODE "\$m")" = reverse ] || [ "\$(g METHOD "\$m")" = proxy ]; } && e=1
    fi
    if chk "\$(g ADMIN_PORT "\$m")" "\$(g ADMIN_USER "\$m")" "\$(g ADMIN_PASS "\$m")" "\$p" "\$e"; then
        rm -f "\$ST/\$n"
    else
        fail "\$n" "\$svc" "\$n"
    fi
    pp=\$(g PADMIN_PORT "\$m")
    if [ -n "\$pp" ] && [ -f "$UNIT_DIR/frp-\$n-provider.service" ]; then
        if chk "\$pp" "\$(g ADMIN_USER "\$m")" "\$(g ADMIN_PASS "\$m")" /api/status 1; then
            rm -f "\$ST/\$n-p"
        else
            fail "\$n-p" "frp-\$n-provider.service" "\$n"
        fi
    fi
done
exit 0
EOF
    chmod 755 "$HOOK_DIR/cert-reload.sh" "$HOOK_DIR/watchdog.sh"
}

cert_expiry() {
    local end e
    CE_DATE=""
    CE_DAYS=""
    end=$(openssl x509 -enddate -noout -in "$1" 2>/dev/null) || return 1
    end=${end#notAfter=}
    e=$(date -d "$end" +%s 2>/dev/null) || return 1
    CE_DATE=$(date -d "$end" +%F)
    CE_DAYS=$(((e - $(date +%s)) / 86400))
}

days_color() {
    if (($1 <= 0)); then printf '%s' "$C_ERR"; elif (($1 < 15)); then printf '%s' "$C_WARN"; else printf '%s' "$NC"; fi
}

cert_main_file() {
    local d=$1 f
    for f in "$d/server.crt" "$d/client.crt" "$d/ca.crt" "$d/fullchain.pem"; do
        [ -f "$f" ] && {
            printf '%s' "$f"
            return 0
        }
    done
    return 1
}

cert_list() {
    local d
    CL_TYPE=()
    CL_NAME=()
    CL_FILE=()
    for d in "$CERT_DIR"/le/*/ "$CERT_DIR"/self/*/; do
        [ -d "$d" ] || continue
        d=${d%/}
        local f
        f=$(cert_main_file "$d") || continue
        CL_FILE+=("$f")
        CL_NAME+=("${d##*/}")
        if [[ $d == "$CERT_DIR/le/"* ]]; then CL_TYPE+=("le"); else CL_TYPE+=("self"); fi
    done
    ((${#CL_NAME[@]} > 0))
}

cert_users() {
    local m out=""
    for m in "$TUN_DIR"/*/tunnel.conf; do
        [ -f "$m" ] || continue
        if grep -qx "CERT_MODE=$1" "$m" && grep -qx "CERT_REF=$2" "$m"; then
            out+="$(sed -n 's/^NAME=//p' "$m" | head -n 1) "
        fi
    done
    printf '%s' "${out% }"
}

cert_brief() {
    cert_list || return 0
    local i out="" dc
    cnext
    printf '  \e[38;5;%smCertificates:\e[0m' "$NC"
    for i in "${!CL_NAME[@]}"; do
        ((i >= 4)) && {
            printf ' \e[38;5;%sm+%s\e[0m' "$NC" "$((${#CL_NAME[@]} - 4))"
            break
        }
        cert_expiry "${CL_FILE[i]}" || continue
        dc=$(days_color "$CE_DAYS")
        printf ' \e[38;5;%sm%s\e[0m \e[38;5;%sm%sd\e[0m' "$NC" "$(trunc "${CL_NAME[i]}" 18)" "$dc" "$CE_DAYS"
    done
    printf '\n'
}

cert_table() {
    if ! cert_list; then
        info "No certificates yet"
        return 1
    fi
    local i dc u
    cnext
    printf '  \e[1;38;5;%sm%-3s %-5s %-26s %-11s %-6s %s\e[0m\n' "$NC" "#" "TYPE" "NAME" "EXPIRES" "DAYS" "USED BY"
    for i in "${!CL_NAME[@]}"; do
        cert_expiry "${CL_FILE[i]}"
        cnext
        dc=$(days_color "${CE_DAYS:-0}")
        u=$(cert_users "${CL_TYPE[i]}" "${CL_NAME[i]}")
        printf '  \e[38;5;%sm%-3s %-5s %-26s %-11s\e[0m \e[38;5;%sm%-6s\e[0m \e[38;5;%sm%s\e[0m\n' "$NC" "$((i + 1))" "${CL_TYPE[i]}" "$(trunc "${CL_NAME[i]}" 26)" "${CE_DATE:--}" "$dc" "${CE_DAYS:--}" "$NC" "$(trunc "${u:--}" 20)"
    done
    return 0
}

cert_self_create() {
    local n=$1 host=$2 d="$CERT_DIR/self/$1" san="DNS:$TLS_SNI" tmp
    if is_ip "$host"; then
        san+=",IP:$host"
    elif is_domain "$host"; then
        san+=",DNS:$host"
    fi
    mkdir -p "$d"
    chmod 700 "$d"
    tmp=$(mktemp -d)
    cat >"$tmp/ca.cnf" <<EOF
[req]
distinguished_name = dn
prompt = no
x509_extensions = v3
[dn]
CN = FRP Tunnel CA $n
[v3]
basicConstraints = critical,CA:TRUE
keyUsage = critical,keyCertSign,cRLSign
subjectKeyIdentifier = hash
EOF
    printf 'basicConstraints = CA:FALSE\nkeyUsage = critical,digitalSignature\nextendedKeyUsage = serverAuth\nsubjectAltName = %s\n' "$san" >"$tmp/srv.ext"
    printf 'basicConstraints = CA:FALSE\nkeyUsage = critical,digitalSignature\nextendedKeyUsage = clientAuth\nsubjectAltName = DNS:frp-client\n' >"$tmp/cli.ext"
    if openssl ecparam -name prime256v1 -genkey -noout -out "$d/ca.key" 2>/dev/null &&
        openssl req -x509 -new -key "$d/ca.key" -sha256 -days 3650 -config "$tmp/ca.cnf" -out "$d/ca.crt" 2>/dev/null &&
        openssl ecparam -name prime256v1 -genkey -noout -out "$d/server.key" 2>/dev/null &&
        openssl req -new -key "$d/server.key" -subj "/CN=$TLS_SNI" -out "$tmp/srv.csr" 2>/dev/null &&
        openssl x509 -req -in "$tmp/srv.csr" -CA "$d/ca.crt" -CAkey "$d/ca.key" -CAcreateserial -CAserial "$tmp/ca.srl" -days 3650 -sha256 -extfile "$tmp/srv.ext" -out "$d/server.crt" 2>/dev/null &&
        openssl ecparam -name prime256v1 -genkey -noout -out "$d/client.key" 2>/dev/null &&
        openssl req -new -key "$d/client.key" -subj "/CN=frp-client" -out "$tmp/cli.csr" 2>/dev/null &&
        openssl x509 -req -in "$tmp/cli.csr" -CA "$d/ca.crt" -CAkey "$d/ca.key" -CAserial "$tmp/ca.srl" -days 3650 -sha256 -extfile "$tmp/cli.ext" -out "$d/client.crt" 2>/dev/null; then
        chmod 600 "$d"/*.key
        rm -rf "$tmp"
        ok "Self-signed certificate set '$n' created"
        return 0
    fi
    rm -rf "$tmp"
    rm -rf "$d"
    err "Failed to create certificates"
    return 1
}

acme_installed() { [ -x "$ACME_HOME/acme.sh" ]; }

acme_timer_install() {
    cat >"$UNIT_DIR/frp-tunnel-acme.service" <<EOF
[Unit]
Description=FRP Tunnel certificate renewal
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$ACME_HOME/acme.sh --cron --home $ACME_HOME
EOF
    cat >"$UNIT_DIR/frp-tunnel-acme.timer" <<EOF
[Unit]
Description=FRP Tunnel certificate renewal timer

[Timer]
OnCalendar=*-*-* 03:17:00
RandomizedDelaySec=1h
Persistent=true

[Install]
WantedBy=timers.target
EOF
    systemctl daemon-reload >/dev/null 2>&1
    systemctl enable --now frp-tunnel-acme.timer >/dev/null 2>&1
}

acme_install() {
    local src pre url f tmp dir email log
    section "Install acme.sh"
    while :; do
        choose src "acme.sh source" 1 "GitHub" "Mirror" "Direct link" "Local file" "Cancel"
        [ "$src" = 5 ] && return 1
        tmp=$(mktemp -d)
        f="$tmp/acme.tar.gz"
        case $src in
            1) download "$ACME_TGZ" "$f" || f="" ;;
            2)
                pick_mirror pre
                download "${pre}$ACME_TGZ" "$f" || f=""
                ;;
            3)
                ask url "Archive link to .tar.gz" "" is_url "Enter a valid http(s) URL"
                download "$url" "$f" || f=""
                ;;
            4) ask f "Path to acme.sh archive or folder" "" is_path "File or folder not found" ;;
        esac
        dir=""
        if [ -n "$f" ] && [ -d "$f" ]; then
            dir=$f
        elif [ -n "$f" ]; then
            mkdir -p "$tmp/x"
            tar -xzf "$f" -C "$tmp/x" 2>/dev/null || err "Invalid archive, a .tar.gz file is expected"
            dir=$(find "$tmp/x" -maxdepth 3 -type f -name acme.sh 2>/dev/null | head -n 1)
            dir=${dir%/acme.sh}
        fi
        if [ -n "$dir" ] && [ -f "$dir/acme.sh" ]; then
            ask email "Account email, optional" "" "?is_email" "Enter a valid email"
            log="$tmp/install.log"
            if (cd "$dir" && sh ./acme.sh --install --home "$ACME_HOME" --nocron --noprofile ${email:+--accountemail "$email"}) >"$log" 2>&1 && acme_installed; then
                "$ACME_HOME/acme.sh" --set-default-ca --server letsencrypt --home "$ACME_HOME" >/dev/null 2>&1
                acme_timer_install
                rm -rf "$tmp"
                ok "acme.sh installed"
                return 0
            fi
            err "acme.sh installation failed"
            tail -n 5 "$log" 2>/dev/null | sed 's/^/    /'
        elif [ -n "$f" ]; then
            err "acme.sh was not found in the archive"
        fi
        rm -rf "$tmp"
        confirm "Try another source?" y || return 1
    done
}

le_install_cert() {
    local dom=$1 d="$CERT_DIR/le/$1"
    mkdir -p "$d"
    chmod 700 "$d"
    if ! "$ACME_HOME/acme.sh" --install-cert -d "$dom" --ecc --home "$ACME_HOME" \
        --key-file "$d/privkey.pem" --fullchain-file "$d/fullchain.pem" \
        --reloadcmd "$HOOK_DIR/cert-reload.sh $dom" >/dev/null 2>&1 || [ ! -s "$d/fullchain.pem" ]; then
        err "Could not install the certificate files"
        return 1
    fi
    chmod 600 "$d/privkey.pem"
    acme_timer_install
    ok "Certificate saved to $d"
}

le_issue() {
    local dom=$1 m tok zone o rc
    local -a args
    acme_installed || acme_install || return 1
    choose m "Validation method" 1 "DNS (Cloudflare API token)" "Standalone (port 80)"
    args=(--issue -d "$dom" --keylength ec-256 --server letsencrypt --home "$ACME_HOME")
    if [ "$m" = 1 ]; then
        if grep -q '^SAVED_CF_Token=' "$ACME_HOME/account.conf" 2>/dev/null && confirm "Use the saved Cloudflare token?" y; then
            :
        else
            ask tok "Cloudflare API token" "" is_cf_token "Invalid token format"
            ask zone "Cloudflare Zone ID, optional" "" "?is_zone_id" "Zone ID is 32 hex characters"
            export CF_Token="$tok"
            if [ -n "$zone" ]; then export CF_Zone_ID="$zone"; else unset CF_Zone_ID; fi
        fi
        args+=(--dns dns_cf)
    else
        if o=$(port_owner 80 tcp); then
            err "Port 80 is in use by $o. Stop it first, then try again."
            return 1
        fi
        need_pkg socat socat || return 1
        fw_sync "frp-tunnel-acme" "$CERT_DIR/le/port80.fw" "" "tcp|80|"
        args+=(--standalone --httpport 80)
        warn "Port 80 must be reachable from the internet, also for future renewals"
    fi
    info "Requesting a certificate for $dom ..."
    "$ACME_HOME/acme.sh" "${args[@]}"
    rc=$?
    unset CF_Token CF_Zone_ID
    if [ "$rc" -ne 0 ] && [ "$rc" -ne 2 ]; then
        err "Certificate request failed, code $rc"
        return 1
    fi
    le_install_cert "$dom"
}

pick_cert() {
    local __n=$1 __f=$2 __i __c
    cert_table || return 1
    cnext
    __c=$NC
    blank
    while :; do
        prompt "$__c" "Certificate number, 0 to go back" ""
        read_line __i
        [ "$__i" = 0 ] && return 1
        if [[ $__i =~ ^[0-9]{1,3}$ ]] && ((10#$__i >= 1 && 10#$__i <= ${#CL_NAME[@]})); then
            __i=$((10#$__i - 1))
            if [ -n "$__f" ] && [ "${CL_TYPE[__i]}" != "$__f" ]; then
                err "Select a $__f certificate"
                continue
            fi
            printf -v "$__n" '%s' "$__i"
            return 0
        fi
        err "Enter a number from the list"
    done
}

cert_menu_self() {
    local n h
    header "SELF-SIGNED CERTIFICATE"
    ask n "Set name" "" v_new_set "-"
    get_public_ip
    ask h "Server IP or domain for the certificate" "$PUBIP" "?is_host" "Enter a valid IP or domain"
    cert_self_create "$n" "$h"
    pause
}

v_new_set() {
    is_name "$1" || {
        err "Use 1-12 characters: a-z, 0-9, -"
        return 1
    }
    [ -e "$CERT_DIR/self/$1" ] && {
        err "Set '$1' already exists"
        return 1
    }
    return 0
}

cert_menu_le() {
    local dom
    header "LET'S ENCRYPT"
    ask dom "Domain" "" is_domain "Enter a valid domain like tunnel.example.com"
    le_issue "$dom"
    pause
}

cert_menu_renew() {
    local i dom
    header "RENEW CERTIFICATE"
    if ! acme_installed; then
        warn "acme.sh is not installed"
        pause
        return
    fi
    pick_cert i le || return
    dom=${CL_NAME[i]}
    info "Renewing $dom ..."
    if "$ACME_HOME/acme.sh" --renew -d "$dom" --ecc --force --home "$ACME_HOME"; then
        ok "Certificate renewed and tunnels reloaded"
    else
        err "Renewal failed"
    fi
    pause
}

cert_menu_delete() {
    local i u
    header "DELETE CERTIFICATE"
    pick_cert i || return
    u=$(cert_users "${CL_TYPE[i]}" "${CL_NAME[i]}")
    [ -n "$u" ] && warn "Used by tunnels: $u"
    if confirm "Delete ${CL_TYPE[i]} certificate '${CL_NAME[i]}'?" n; then
        if [ "${CL_TYPE[i]}" = le ] && acme_installed; then
            "$ACME_HOME/acme.sh" --remove -d "${CL_NAME[i]}" --ecc --home "$ACME_HOME" >/dev/null 2>&1
        fi
        rm -rf "${CERT_DIR:?}/${CL_TYPE[i]}/${CL_NAME[i]}"
        ok "Certificate deleted"
    fi
    pause
}

cert_menu() {
    local c
    while :; do
        header "CERTIFICATES"
        cert_table
        if acme_installed; then kv "acme.sh" "installed"; else kv "acme.sh" "not installed"; fi
        blank
        item 1 "Create self-signed"
        item 2 "Issue Let's Encrypt"
        item 3 "Renew Let's Encrypt"
        item 4 "Delete certificate"
        item 5 "Install acme.sh"
        item 0 "Back"
        menu_pick c 5
        case $c in
            1) cert_menu_self ;;
            2) cert_menu_le ;;
            3) cert_menu_renew ;;
            4) cert_menu_delete ;;
            5)
                header "INSTALL ACME.SH"
                acme_install
                pause
                ;;
            0) return ;;
        esac
    done
}

ipt() { "$@" >/dev/null 2>&1; }

fw_kind() {
    if ufw_active; then
        printf 'ufw'
    elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
        printf 'firewalld'
    elif command -v iptables >/dev/null 2>&1 && iptables -w 10 -S INPUT 2>/dev/null | grep -qE '^-P INPUT (DROP|REJECT)|-j (DROP|REJECT)'; then
        printf 'iptables'
    elif command -v nft >/dev/null 2>&1 && nft list ruleset 2>/dev/null | grep -qE 'hook input .*policy (drop|reject)'; then
        printf 'nftables'
    else
        printf 'none'
    fi
}

fw_label() {
    local p port src
    IFS='|' read -r p port src <<<"$1"
    if [ -z "$src" ]; then
        printf '%s/%s' "${port/:/-}" "$p"
    elif [ -n "$port" ]; then
        printf '%s %s from %s' "$p" "${port/:/-}" "$src"
    else
        printf '%s from %s' "$p" "$src"
    fi
}

fw_in() {
    local x=$1 y
    shift
    for y in "$@"; do
        [ "$x" = "$y" ] && return 0
    done
    return 1
}

fw_ufw_args() {
    local p port src
    IFS='|' read -r p port src <<<"$1"
    if [ -z "$src" ]; then
        UFW_ARGS=("$port/$p")
    elif [ -n "$port" ]; then
        UFW_ARGS=(proto "$p" from "$src" to any port "$port")
    else
        UFW_ARGS=(proto "$p" from "$src")
    fi
}

fw_rich() {
    local p port src
    IFS='|' read -r p port src <<<"$1"
    if [ -n "$port" ]; then
        printf 'rule family="ipv4" source address="%s" port port="%s" protocol="%s" accept' "$src" "${port/:/-}" "$p"
    else
        printf 'rule family="ipv4" source address="%s" protocol value="%s" accept' "$src" "$p"
    fi
}

fw_ipt_args() {
    local p port src
    IFS='|' read -r p port src <<<"$1"
    IPT_ARGS=(INPUT)
    case $p in
        gre) IPT_ARGS+=(-p 47) ;;
        ipv6) IPT_ARGS+=(-p 41) ;;
        *) IPT_ARGS+=(-p "$p") ;;
    esac
    [ -n "$src" ] && IPT_ARGS+=(-s "$src")
    [ -n "$port" ] && IPT_ARGS+=(--dport "$port")
    IPT_ARGS+=(-m comment --comment "$2" -j ACCEPT)
}

fw_ipt_clear() {
    local cmd line
    local -a a
    for cmd in iptables ip6tables; do
        command -v "$cmd" >/dev/null 2>&1 || continue
        while IFS= read -r line; do
            line=${line//\"/}
            [[ "$line " == *"--comment $1 "* ]] || continue
            read -ra a <<<"${line/#-A INPUT/-D INPUT}"
            "$cmd" -w 10 "${a[@]}" >/dev/null 2>&1
        done < <("$cmd" -w 10 -S INPUT 2>/dev/null)
    done
}

fw_add() {
    local kind=$1 spec=$2 out rule port p src
    IFS='|' read -r p port src <<<"$spec"
    case $kind in
        ufw)
            fw_ufw_args "$spec"
            out=$(LC_ALL=C LANG=C LANGUAGE='' ufw allow "${UFW_ARGS[@]}" 2>&1) || return 1
            [[ $out == *"Rule added"* ]] && return 0
            return 2
            ;;
        firewalld)
            if [ -z "$src" ]; then
                firewall-cmd -q --query-port="${port/:/-}/$p" 2>/dev/null && return 2
                firewall-cmd -q --add-port="${port/:/-}/$p" && firewall-cmd -q --permanent --add-port="${port/:/-}/$p" && return 0
                return 1
            fi
            rule=$(fw_rich "$spec")
            firewall-cmd -q --query-rich-rule="$rule" 2>/dev/null && return 2
            firewall-cmd -q --add-rich-rule="$rule" && firewall-cmd -q --permanent --add-rich-rule="$rule" && return 0
            return 1
            ;;
    esac
    return 1
}

fw_del() {
    local kind=$1 spec=$2 rule port p src
    IFS='|' read -r p port src <<<"$spec"
    case $kind in
        ufw)
            command -v ufw >/dev/null 2>&1 || return 0
            fw_ufw_args "$spec"
            LC_ALL=C LANG=C LANGUAGE='' ufw --force delete allow "${UFW_ARGS[@]}" >/dev/null 2>&1
            ;;
        firewalld)
            command -v firewall-cmd >/dev/null 2>&1 || return 0
            if [ -z "$src" ]; then
                firewall-cmd -q --remove-port="${port/:/-}/$p" >/dev/null 2>&1
                firewall-cmd -q --permanent --remove-port="${port/:/-}/$p" >/dev/null 2>&1
            else
                rule=$(fw_rich "$spec")
                firewall-cmd -q --remove-rich-rule="$rule" >/dev/null 2>&1
                firewall-cmd -q --permanent --remove-rich-rule="$rule" >/dev/null 2>&1
            fi
            ;;
    esac
    return 0
}

fw_sync() {
    local lock=/run/frp-tunnel-fw.lock
    if command -v flock >/dev/null 2>&1; then
        {
            flock -w 60 9
            fw_sync_run "$@"
        } 9>"$lock"
    else
        fw_sync_run "$@"
    fi
}

fw_sync_run() {
    local tag=$1 st=$2 quiet=$3 kind line k s rc
    shift 3
    local -a want=() have=() keep=() added=() failed=() labels=()
    local -A pre=() had=()
    for s in "$@"; do
        [ -n "$s" ] && want+=("$s")
    done
    kind=$(fw_kind)
    [ -f "$st" ] && mapfile -t have <"$st"
    for line in "${have[@]}"; do
        [ -n "$line" ] || continue
        k=${line%%|*}
        s=${line#*|}
        if fw_in "$s" "${want[@]}"; then
            if [ "$k" = "$kind" ]; then
                had[$s]=1
            elif [ "$kind" = none ] || [ "$kind" = nftables ]; then
                keep+=("$line")
            else
                fw_del "$k" "$s"
            fi
        else
            fw_del "$k" "$s"
        fi
    done
    if [ "$kind" = iptables ]; then
        for s in "${want[@]}"; do
            fw_ipt_args "$s" "$tag"
            iptables -w 10 -C "${IPT_ARGS[@]}" >/dev/null 2>&1 && pre[$s]=1
        done
    fi
    command -v iptables >/dev/null 2>&1 && fw_ipt_clear "$tag"
    for s in "${want[@]}"; do
        case $kind in
            none | nftables) ;;
            iptables)
                fw_ipt_args "$s" "$tag"
                if iptables -w 10 -I "${IPT_ARGS[@]}" >/dev/null 2>&1; then
                    [ -n "${pre[$s]}" ] || added+=("$(fw_label "$s")")
                else
                    failed+=("$(fw_label "$s")")
                fi
                [[ $s == *"|" ]] && command -v ip6tables >/dev/null 2>&1 && ipt ip6tables -w 10 -I "${IPT_ARGS[@]}"
                ;;
            *)
                fw_add "$kind" "$s"
                rc=$?
                case $rc in
                    0)
                        keep+=("$kind|$s")
                        [ -n "${had[$s]}" ] || added+=("$(fw_label "$s")")
                        ;;
                    2) [ -n "${had[$s]}" ] && keep+=("$kind|$s") ;;
                    *)
                        [ -n "${had[$s]}" ] && keep+=("$kind|$s")
                        failed+=("$(fw_label "$s")")
                        ;;
                esac
                ;;
        esac
    done
    if ((${#keep[@]})); then
        printf '%s\n' "${keep[@]}" >"$st" 2>/dev/null
    else
        rm -f "$st"
    fi
    [ "$quiet" = q ] && return 0
    ((${#want[@]})) || return 0
    for s in "${want[@]}"; do labels+=("$(fw_label "$s")"); done
    case $kind in
        none)
            info "No active firewall on this server. If your provider has a firewall panel, open: ${labels[*]}"
            return 0
            ;;
        nftables)
            warn "An nftables firewall is active. Open these ports in it: ${labels[*]}"
            return 0
            ;;
    esac
    ((${#added[@]})) && ok "Firewall $kind: opened ${added[*]}"
    ((${#failed[@]})) && warn "Firewall $kind: could not open ${failed[*]}"
    if ((${#added[@]} == 0 && ${#failed[@]} == 0)); then
        info "Firewall $kind: needed ports are already open"
    fi
    return 0
}

fw_specs_tunnel() {
    local tok t
    local -a toks rules=()
    if [ "${T[SIDE]}" = server ]; then
        rules+=("tcp|${T[BIND_PORT]}|")
        [[ ${T[PROTO]} == kcp || ${T[PROTO]} == quic ]] && rules+=("udp|${T[BIND_PORT]}|")
    fi
    if bind_here && [ "${T[LISTEN]}" != local ] && parse_ports "${T[PORTS]}" && bind_port_list; then
        IFS=, read -ra toks <<<"$(ports_compact "${BIND_LIST[@]}")"
        for tok in "${toks[@]}"; do
            for t in tcp udp; do
                [[ ${T[PTYPE]} == both || ${T[PTYPE]} == "$t" ]] && rules+=("$t|${tok/-/:}|")
            done
        done
    fi
    ((${#rules[@]})) && printf '%s\n' "${rules[@]}"
    return 0
}

fw_specs_lip() {
    case ${L[TYPE]} in
        gre) printf 'gre||%s\n' "${L[REMOTE]}" ;;
        sit) printf 'ipv6||%s\n' "${L[REMOTE]}" ;;
        vxlan) printf 'udp|%s|%s\n' "${L[DPORT]}" "${L[REMOTE]}" ;;
    esac
}

fw_tunnel_apply() {
    local -a specs=()
    [ "$2" = clear ] || mapfile -t specs < <(fw_specs_tunnel)
    fw_sync "frp-tunnel:$1" "$TUN_DIR/$1/fw.state" "$3" "${specs[@]}"
}

fw_lip_apply() {
    local -a specs=()
    [ "$2" = clear ] || mapfile -t specs < <(fw_specs_lip)
    fw_sync "frp-tunnel-lip:$1" "$LIP_DIR/$1.fw" "$3" "${specs[@]}"
}

fw_cli() {
    case $1 in
        --fw-sync)
            tunnel_load "$2" && fw_tunnel_apply "$2" sync q
            ;;
        --fw-sync-lip)
            lip_load_file "$LIP_DIR/$2.conf" && fw_lip_apply "$2" sync q
            ;;
    esac
    return 0
}

fw_exec_pre() {
    [ -x "$SELF_BIN" ] && printf 'ExecStartPre=-%s %s %s\n' "$SELF_BIN" "$1" "$2"
    return 0
}

META_KEYS=(NAME PFX ROLE MODE METHOD SIDE PROTO BIND_ADDR BIND_PORT INT_PORT PUB_ADDR SERVER_ADDR SERVER_PORT TOKEN TLS CERT_MODE CERT_REF MTLS TCPMUX COMPRESS POOL HB_INT HB_TO PORTS PTYPE ROFF LISTEN TARGET_IP RESTRICT SK ADMIN_PORT ADMIN_USER ADMIN_PASS PADMIN_PORT LIP GROUP CREATED)

tunnel_names() {
    local f
    for f in "$TUN_DIR"/*/tunnel.conf; do
        [ -f "$f" ] || continue
        f=${f%/tunnel.conf}
        printf '%s\n' "${f##*/}"
    done
}

active_tunnels() {
    local n
    while read -r n; do
        [ -n "$n" ] && systemctl is-active --quiet "frp-$n.service" 2>/dev/null && printf '%s\n' "$n"
    done < <(tunnel_names)
}

save_meta() {
    local f="$TUN_DIR/${T[NAME]}/tunnel.conf" k
    mkdir -p "${f%/*}"
    chmod 700 "${f%/*}"
    for k in "${META_KEYS[@]}"; do
        printf '%s=%s\n' "$k" "${T[$k]}"
    done >"$f"
    chmod 600 "$f"
}

load_meta() {
    local line k
    T=()
    [ -f "$1" ] || return 1
    while IFS= read -r line; do
        k=${line%%=*}
        [[ $k =~ ^[A-Z_0-9]+$ ]] && T[$k]=${line#*=}
    done <"$1"
    [ -n "${T[NAME]}" ]
}

tunnel_load() { load_meta "$TUN_DIR/$1/tunnel.conf"; }

derive_side() {
    if [ "${T[MODE]}" = reverse ]; then
        T[METHOD]=proxy
        if [ "${T[ROLE]}" = iran ]; then T[SIDE]=server; else T[SIDE]=client; fi
    else
        if [ "${T[ROLE]}" = foreign ]; then T[SIDE]=server; else T[SIDE]=client; fi
    fi
}

bind_here() {
    case "${T[MODE]}:${T[METHOD]}:${T[SIDE]}" in
        reverse:*:server | direct:stcp:client | direct:proxy:server) return 0 ;;
    esac
    return 1
}

has_proxies_here() {
    case "${T[MODE]}:${T[METHOD]}:${T[SIDE]}" in
        reverse:*:client | direct:stcp:server | direct:proxy:client) return 0 ;;
    esac
    return 1
}

roff() {
    local r=${T[ROFF]:-0} s=1
    [[ $r =~ ^-?[0-9]{1,5}$ ]] || r=0
    if [[ $r == -* ]]; then
        s=-1
        r=${r#-}
    fi
    printf '%s' "$((s * 10#$r))"
}

bind_port_list() {
    local r p q
    r=$(roff)
    BIND_LIST=()
    for p in "${PORT_LIST[@]}"; do
        q=$((p + r))
        ((q >= 1 && q <= 65535)) || return 1
        BIND_LIST+=("$q")
    done
    return 0
}

hb_val() { if [ "${1:-0}" = 0 ]; then printf '%s' "-1"; else printf '%s' "$1"; fi; }

cert_paths() {
    local d
    CP_CA=""
    CP_SCRT=""
    CP_SKEY=""
    CP_CCRT=""
    CP_CKEY=""
    case ${T[CERT_MODE]} in
        self)
            d="$CERT_DIR/self/${T[CERT_REF]}"
            CP_CA="$d/ca.crt"
            CP_SCRT="$d/server.crt"
            CP_SKEY="$d/server.key"
            CP_CCRT="$d/client.crt"
            CP_CKEY="$d/client.key"
            ;;
        le)
            d="$CERT_DIR/le/${T[CERT_REF]}"
            CP_CA="$SYS_CA"
            CP_SCRT="$d/fullchain.pem"
            CP_SKEY="$d/privkey.pem"
            ;;
    esac
}

toml_tail() {
    printf 'webServer.addr = "127.0.0.1"\nwebServer.port = %s\nwebServer.user = "%s"\nwebServer.password = "%s"\n' "$1" "${T[ADMIN_USER]}" "${T[ADMIN_PASS]}"
    printf 'log.to = "console"\nlog.level = "info"\nlog.disablePrintColor = true\n'
}

toml_transport() {
    printf 'auth.method = "token"\nauth.token = "%s"\n' "${T[TOKEN]}"
    printf 'transport.tcpMux = %s\n' "$(tf "${T[TCPMUX]}")"
}

allow_ports_toml() {
    local out="" tok
    local -a toks
    bind_port_list
    IFS=, read -ra toks <<<"$(ports_compact "${BIND_LIST[@]}")"
    for tok in "${toks[@]}"; do
        if [[ $tok == *-* ]]; then
            out+="${out:+, }{ start = ${tok%-*}, end = ${tok#*-} }"
        else
            out+="${out:+, }{ single = $tok }"
        fi
    done
    printf '%s' "$out"
}

gen_frps() {
    if [ "${T[PROTO]}" = wss ]; then
        printf 'bindAddr = "127.0.0.1"\nbindPort = %s\n' "${T[INT_PORT]}"
    else
        printf 'bindAddr = "%s"\nbindPort = %s\n' "${T[BIND_ADDR]}" "${T[BIND_PORT]}"
        [ "${T[PROTO]}" = kcp ] && printf 'kcpBindPort = %s\n' "${T[BIND_PORT]}"
        [ "${T[PROTO]}" = quic ] && printf 'quicBindPort = %s\n' "${T[BIND_PORT]}"
    fi
    if [ "${T[LISTEN]}" = local ]; then
        printf 'proxyBindAddr = "127.0.0.1"\n'
    else
        printf 'proxyBindAddr = "0.0.0.0"\n'
    fi
    toml_transport
    printf 'transport.maxPoolCount = %s\n' "${T[POOL]}"
    printf 'transport.heartbeatTimeout = %s\n' "$(hb_val "${T[HB_TO]}")"
    if [ "${T[TLS]}" = y ] && [ "${T[PROTO]}" != wss ]; then
        printf 'transport.tls.force = true\n'
        cert_paths
        if [ "${T[CERT_MODE]}" = self ] || [ "${T[CERT_MODE]}" = le ]; then
            printf 'transport.tls.certFile = "%s"\ntransport.tls.keyFile = "%s"\n' "$CP_SCRT" "$CP_SKEY"
        fi
        if [ "${T[CERT_MODE]}" = self ] && [ "${T[MTLS]}" = y ]; then
            printf 'transport.tls.trustedCaFile = "%s"\n' "$CP_CA"
        fi
    fi
    toml_tail "${T[ADMIN_PORT]}"
    if [ "${T[RESTRICT]}" = y ] && [ "${T[METHOD]}" != stcp ] && ((${#PORT_LIST[@]})); then
        printf 'allowPorts = [ %s ]\n' "$(allow_ports_toml)"
    fi
}

client_tls_toml() {
    if [ "${T[TLS]}" != y ] && [ "${T[PROTO]}" != wss ]; then
        printf 'transport.tls.enable = false\n'
        return
    fi
    printf 'transport.tls.enable = true\n'
    cert_paths
    case ${T[CERT_MODE]} in
        self)
            [ -f "$CP_CA" ] && printf 'transport.tls.trustedCaFile = "%s"\ntransport.tls.serverName = "%s"\n' "$CP_CA" "$TLS_SNI"
            [ "${T[MTLS]}" = y ] && printf 'transport.tls.certFile = "%s"\ntransport.tls.keyFile = "%s"\n' "$CP_CCRT" "$CP_CKEY"
            ;;
        le)
            printf 'transport.tls.trustedCaFile = "%s"\ntransport.tls.serverName = "%s"\n' "$SYS_CA" "${T[CERT_REF]}"
            ;;
    esac
}

gen_client_head() {
    printf 'serverAddr = "%s"\nserverPort = %s\nloginFailExit = false\n' "$1" "$2"
    toml_transport
    printf 'transport.protocol = "%s"\n' "$3"
    printf 'transport.poolCount = %s\n' "${T[POOL]}"
    printf 'transport.heartbeatInterval = %s\n' "$(hb_val "${T[HB_INT]}")"
    printf 'transport.heartbeatTimeout = %s\n' "$(hb_val "${T[HB_TO]}")"
    printf 'transport.dialServerTimeout = 10\n'
}

gen_proxies() {
    local kind=$1 p t typ r
    r=$(roff)
    for t in tcp udp; do
        [[ ${T[PTYPE]} == both || ${T[PTYPE]} == "$t" ]] || continue
        typ=$t
        if [ "$kind" = stcp ]; then
            if [ "$t" = tcp ]; then typ=stcp; else typ=sudp; fi
        fi
        for p in "${PORT_LIST[@]}"; do
            printf '\n[[proxies]]\nname = "%s-%s-%s"\ntype = "%s"\nlocalIP = "%s"\nlocalPort = %s\n' "${T[PFX]}" "$typ" "$p" "$typ" "${T[TARGET_IP]}" "$p"
            if [ "$kind" = stcp ]; then
                printf 'secretKey = "%s"\n' "${T[SK]}"
            else
                printf 'remotePort = %s\n' "$((p + r))"
            fi
            [ "${T[COMPRESS]}" = y ] && printf 'transport.useCompression = true\n'
        done
    done
}

gen_visitors() {
    local p t typ ba=0.0.0.0 r
    r=$(roff)
    [ "${T[LISTEN]}" = local ] && ba=127.0.0.1
    for t in tcp udp; do
        [[ ${T[PTYPE]} == both || ${T[PTYPE]} == "$t" ]] || continue
        if [ "$t" = tcp ]; then typ=stcp; else typ=sudp; fi
        for p in "${PORT_LIST[@]}"; do
            printf '\n[[visitors]]\nname = "%s-v%s-%s"\ntype = "%s"\nserverName = "%s-%s-%s"\nsecretKey = "%s"\nbindAddr = "%s"\nbindPort = %s\n' "${T[PFX]}" "$typ" "$p" "$typ" "${T[PFX]}" "$typ" "$p" "${T[SK]}" "$ba" "$((p + r))"
            [ "${T[COMPRESS]}" = y ] && printf 'transport.useCompression = true\n'
        done
    done
}

gen_frpc() {
    gen_client_head "${T[SERVER_ADDR]}" "${T[SERVER_PORT]}" "${T[PROTO]}"
    client_tls_toml
    toml_tail "${T[ADMIN_PORT]}"
    if [ "${T[METHOD]}" = stcp ]; then gen_visitors; else gen_proxies proxy; fi
}

gen_provider() {
    local addr=127.0.0.1 port=${T[BIND_PORT]}
    if [ "${T[PROTO]}" = wss ]; then
        port=${T[INT_PORT]}
    elif [ "${T[BIND_ADDR]}" != 0.0.0.0 ] && [ "${T[BIND_ADDR]}" != "::" ]; then
        addr=${T[BIND_ADDR]}
    fi
    gen_client_head "$addr" "$port" tcp
    if [ "${T[TLS]}" = y ] && [ "${T[PROTO]}" != wss ]; then
        printf 'transport.tls.enable = true\n'
        cert_paths
        if [ "${T[CERT_MODE]}" = self ] && [ "${T[MTLS]}" = y ]; then
            printf 'transport.tls.certFile = "%s"\ntransport.tls.keyFile = "%s"\n' "$CP_CCRT" "$CP_CKEY"
        fi
    else
        printf 'transport.tls.enable = false\n'
    fi
    toml_tail "${T[PADMIN_PORT]}"
    gen_proxies stcp
}

wss_exec() {
    local listen="OPENSSL-LISTEN:${T[BIND_PORT]},reuseaddr,fork" sock
    cert_paths
    if [ "${T[BIND_ADDR]}" != 0.0.0.0 ] && [ "${T[BIND_ADDR]}" != "::" ]; then
        if is_ipv6 "${T[BIND_ADDR]}"; then listen+=",pf=ip6,bind=[${T[BIND_ADDR]}]"; else listen+=",bind=${T[BIND_ADDR]}"; fi
    elif [ -f /proc/net/if_inet6 ]; then
        listen+=",pf=ip6,ipv6only=0"
    fi
    listen+=",cert=$CP_SCRT,key=$CP_SKEY"
    if [ "${T[CERT_MODE]}" = self ] && [ "${T[MTLS]}" = y ]; then
        listen+=",cafile=$CP_CA,verify=1"
    else
        listen+=",verify=0"
    fi
    sock=$(command -v socat || printf '/usr/bin/socat')
    printf '%s %s TCP:127.0.0.1:%s,nodelay' "$sock" "$listen" "${T[INT_PORT]}"
}

unit_companion() {
    cat <<EOF
[Unit]
Description=FRP Tunnel ${T[NAME]} $1
After=network-online.target frp-${T[NAME]}.service
PartOf=frp-${T[NAME]}.service
StartLimitIntervalSec=0

[Service]
Type=simple
ExecStart=$2
Restart=always
RestartSec=3
LimitNOFILE=1048576
EOF
}

write_units() {
    local n=${T[NAME]} d="$TUN_DIR/${T[NAME]}" bin cfg after="" wants=""
    rm -f "$UNIT_DIR/frp-$n-provider.service" "$UNIT_DIR/frp-$n-wss.service"
    if [ "${T[SIDE]}" = server ]; then
        bin=$FRPS_BIN
        cfg="$d/frps.toml"
        if [ "${T[METHOD]}" = stcp ]; then
            unit_companion provider "$FRPC_BIN -c $d/provider.toml" >"$UNIT_DIR/frp-$n-provider.service"
            wants+=" frp-$n-provider.service"
        fi
        if [ "${T[PROTO]}" = wss ]; then
            unit_companion "wss terminator" "$(wss_exec)" >"$UNIT_DIR/frp-$n-wss.service"
            wants+=" frp-$n-wss.service"
        fi
    else
        bin=$FRPC_BIN
        cfg="$d/frpc.toml"
    fi
    if [ -n "${T[LIP]}" ] && [ -f "$UNIT_DIR/frp-lip-${T[LIP]}.service" ]; then
        after=" frp-lip-${T[LIP]}.service"
        wants+=" frp-lip-${T[LIP]}.service"
    fi
    cat >"$UNIT_DIR/frp-$n.service" <<EOF
[Unit]
Description=FRP Tunnel $n ($(side_role "${T[ROLE]}"))
After=network-online.target$after
Wants=network-online.target$wants
StartLimitIntervalSec=0

[Service]
Type=simple
$(fw_exec_pre --fw-sync "$n")
ExecStart=$bin -c $cfg
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
}

tunnel_defaults() {
    T[TCPMUX]=${T[TCPMUX]:-y}
    T[COMPRESS]=${T[COMPRESS]:-n}
    T[POOL]=${T[POOL]:-5}
    T[HB_INT]=${T[HB_INT]:-30}
    T[HB_TO]=${T[HB_TO]:-90}
    T[TARGET_IP]=${T[TARGET_IP]:-127.0.0.1}
    T[RESTRICT]=${T[RESTRICT]:-y}
    T[BIND_ADDR]=${T[BIND_ADDR]:-0.0.0.0}
    T[PTYPE]=${T[PTYPE]:-tcp}
    T[LISTEN]=${T[LISTEN]:-public}
    T[ROFF]=$(roff)
    T[MTLS]=${T[MTLS]:-n}
}

tunnel_finalize() {
    local ex
    tunnel_defaults
    T[PFX]=${T[PFX]:-${T[NAME]}}
    parse_ports "${T[PORTS]}" || PORT_LIST=()
    bind_port_list
    ex=" ${PORT_LIST[*]} ${BIND_LIST[*]} ${T[BIND_PORT]} $EXTRA_EXCL "
    if [ "${T[METHOD]}" = stcp ]; then
        [ -n "${T[SK]}" ] || T[SK]=$(rand_str 24)
    else
        T[SK]=""
    fi
    if [ "${T[SIDE]}" = server ] && [ "${T[PROTO]}" = wss ]; then
        [ -n "${T[INT_PORT]}" ] || T[INT_PORT]=$(alloc_port 17000 "$ex")
    else
        T[INT_PORT]=""
    fi
    ex+="${T[INT_PORT]} "
    [ -n "${T[ADMIN_PORT]}" ] || T[ADMIN_PORT]=$(alloc_port 7400 "$ex")
    ex+="${T[ADMIN_PORT]} "
    if [ "${T[SIDE]}" = server ] && [ "${T[METHOD]}" = stcp ]; then
        [ -n "${T[PADMIN_PORT]}" ] || T[PADMIN_PORT]=$(alloc_port 7400 "$ex")
    else
        T[PADMIN_PORT]=""
    fi
    T[ADMIN_USER]=${T[ADMIN_USER]:-admin}
    [ -n "${T[ADMIN_PASS]}" ] || T[ADMIN_PASS]=$(rand_str 20)
    [ -n "${T[CREATED]}" ] || T[CREATED]=$(date '+%F %T')
    if [ "${T[SIDE]}" = server ]; then
        T[SERVER_ADDR]=""
        T[SERVER_PORT]=""
    fi
}

tunnel_apply() {
    local n=${T[NAME]} d="$TUN_DIR/${T[NAME]}" f b out st
    tunnel_finalize
    if [ "${T[SIDE]}" = server ] && [ "${T[PROTO]}" = wss ]; then
        need_pkg socat socat || return 1
    fi
    save_meta
    rm -f "$d"/*.toml
    if [ "${T[SIDE]}" = server ]; then
        gen_frps >"$d/frps.toml"
        [ "${T[METHOD]}" = stcp ] && gen_provider >"$d/provider.toml"
    else
        gen_frpc >"$d/frpc.toml"
    fi
    chmod 600 "$d"/*.toml
    for f in "$d"/*.toml; do
        if [ "${f##*/}" = frps.toml ]; then b=$FRPS_BIN; else b=$FRPC_BIN; fi
        if ! out=$("$b" verify -c "$f" 2>&1); then
            err "Config check failed: ${f##*/}"
            printf '%s\n' "$out" | tail -n 6 | sed 's/^/    /'
            return 1
        fi
    done
    ok "Config files verified"
    fw_tunnel_apply "$n" sync
    write_units
    systemctl daemon-reload >/dev/null 2>&1
    systemctl enable "frp-$n.service" >/dev/null 2>&1
    systemctl restart "frp-$n.service" >/dev/null 2>&1
    sleep 2
    st=$(svc_state "frp-$n.service")
    if [ "$st" = active ]; then
        ok "Service frp-$n is running"
    else
        err "Service frp-$n is $st"
        journalctl -u "frp-$n.service" -n 8 --no-pager -o cat 2>/dev/null | sed 's/^/    /'
    fi
    return 0
}

tunnel_remove() {
    local n=$1 u
    for u in "frp-$n.service" "frp-$n-provider.service" "frp-$n-wss.service"; do
        systemctl disable --now "$u" >/dev/null 2>&1
        rm -f "$UNIT_DIR/$u"
    done
    fw_tunnel_apply "$n" clear q
    systemctl daemon-reload >/dev/null 2>&1
    systemctl reset-failed "frp-$n.service" >/dev/null 2>&1
    rm -rf "${TUN_DIR:?}/$n" "${WD_STATE:?}/$n"
}

key_make() {
    printf '%s%s' "$KEY_PREFIX" "$(key_lines | gzip -9c | base64 -w0)"
}

key_lines() {
    local addr port
    local -a a
    cert_paths
    if [ "${T[SIDE]}" = server ]; then
        addr=${T[PUB_ADDR]}
        port=${T[BIND_PORT]}
    else
        addr=${T[SERVER_ADDR]}
        port=${T[SERVER_PORT]}
    fi
    a=("V=1" "NAME=${T[NAME]}" "PFX=${T[PFX]}" "ROLE=${T[ROLE]}" "MODE=${T[MODE]}" "METHOD=${T[METHOD]}" "PROTO=${T[PROTO]}"
        "ADDR=$addr" "PORT=$port" "TOKEN=${T[TOKEN]}" "TLS=${T[TLS]}" "CERT=${T[CERT_MODE]}" "REF=${T[CERT_REF]}"
        "MTLS=${T[MTLS]}" "TCPMUX=${T[TCPMUX]}" "COMPRESS=${T[COMPRESS]}" "POOL=${T[POOL]}" "HB_INT=${T[HB_INT]}"
        "HB_TO=${T[HB_TO]}" "PORTS=${T[PORTS]}" "PTYPE=${T[PTYPE]}" "SK=${T[SK]}" "RESTRICT=${T[RESTRICT]}" "ROFF=$(roff)")
    if [ "${T[CERT_MODE]}" = self ] && [ "${T[SIDE]}" = server ]; then
        [ -f "$CP_CA" ] && a+=("CA=$(base64 -w0 <"$CP_CA")")
        if [ "${T[MTLS]}" = y ] && [ -f "$CP_CCRT" ] && [ -f "$CP_CKEY" ]; then
            a+=("CCRT=$(base64 -w0 <"$CP_CCRT")" "CKEY=$(base64 -w0 <"$CP_CKEY")")
        fi
    fi
    printf '%s\n' "${a[@]}"
}

key_valid() {
    [ "${K[V]}" = 1 ] || return 1
    is_name "${K[NAME]}" || return 1
    [ -z "${K[PFX]}" ] || is_name "${K[PFX]}" || return 1
    [[ ${K[ROLE]} =~ ^(iran|foreign)$ && ${K[MODE]} =~ ^(reverse|direct)$ && ${K[METHOD]} =~ ^(proxy|stcp)$ ]] || return 1
    [[ ${K[PROTO]} =~ ^(tcp|kcp|quic|websocket|wss)$ ]] || return 1
    is_host "${K[ADDR]}" && is_port "${K[PORT]}" && is_token "${K[TOKEN]}" || return 1
    [[ ${K[TLS]} =~ ^[yn]$ && ${K[CERT]} =~ ^(none|builtin|self|le)$ && ${K[MTLS]} =~ ^[yn]$ ]] || return 1
    [[ ${K[TCPMUX]} =~ ^[yn]$ && ${K[COMPRESS]} =~ ^[yn]$ && ${K[RESTRICT]} =~ ^[yn]$ ]] || return 1
    v_pool "${K[POOL]}" && v_hb "${K[HB_INT]}" && v_hb "${K[HB_TO]}" || return 1
    [[ ${K[PTYPE]} =~ ^(tcp|udp|both)$ ]] || return 1
    [ -z "${K[ROFF]}" ] || [[ ${K[ROFF]} =~ ^-?[0-9]{1,5}$ ]] || return 1
    parse_ports "${K[PORTS]}" || return 1
    [ -z "${K[SK]}" ] || is_token "${K[SK]}" || return 1
    case ${K[CERT]} in
        self) is_name "${K[REF]}" || return 1 ;;
        le) is_domain "${K[REF]}" || return 1 ;;
    esac
    local x
    for x in CA CCRT CKEY; do
        [ -z "${K[$x]}" ] || is_b64 "${K[$x]}" || return 1
    done
    return 0
}

key_load() {
    local line k
    K=()
    while IFS= read -r line; do
        k=${line%%=*}
        [[ $k =~ ^[A-Z_]+$ ]] && K[$k]=${line#*=}
    done <<<"$1"
}

key_decode() {
    local s=${1#"$2"}
    is_b64 "$s" || return 1
    printf '%s' "$s" | base64 -d 2>/dev/null | gzip -dc 2>/dev/null
}

key_parse() {
    local data
    K=()
    [[ $1 == "$GKEY_PREFIX"* ]] && return 2
    [[ $1 == "$KEY_PREFIX"* ]] || return 1
    data=$(key_decode "$1" "$KEY_PREFIX") || return 1
    key_load "$data"
    key_valid
}

key_prompt() {
    local c k
    cnext
    c=$NC
    while :; do
        printf '  \e[38;5;%sm%s\e[0m\n  ' "$c" "Connection key from the $(other_role) server, Enter to skip:"
        if ! IFS= read -r -e k; then
            printf '\e[0m\n'
            exit 0
        fi
        k=${k//[[:space:]]/}
        [ -z "$k" ] && return 1
        key_parse "$k"
        case $? in
            0) ;;
            2)
                err "This is a multi-protocol key. Use Multi-protocol tunnel in the main menu."
                continue
                ;;
            *)
                err "Invalid connection key"
                continue
                ;;
        esac
        if [ -n "${T[ROLE]}" ] && [ "${K[ROLE]}" = "${T[ROLE]}" ]; then
            warn "This key comes from the $(side_role "${K[ROLE]}") server, so this server is set to $(other_role)"
        fi
        return 0
    done
}

key_apply() {
    if [ "${K[ROLE]}" = iran ]; then T[ROLE]=foreign; else T[ROLE]=iran; fi
    T[MODE]=${K[MODE]}
    derive_side
    T[METHOD]=${K[METHOD]}
    local k
    for k in PROTO TOKEN TLS MTLS TCPMUX COMPRESS POOL HB_INT HB_TO PORTS PTYPE SK RESTRICT ROFF; do
        T[$k]=${K[$k]}
    done
    T[PFX]=${K[PFX]:-${K[NAME]}}
    T[CERT_MODE]=${K[CERT]}
    T[CERT_REF]=${K[REF]}
    if [ "${T[SIDE]}" = client ]; then
        T[SERVER_ADDR]=${K[ADDR]}
        T[SERVER_PORT]=${K[PORT]}
    else
        T[BIND_PORT]=${K[PORT]}
        T[PUB_ADDR]=${K[ADDR]}
    fi
}

key_write_certs() {
    local d
    T[CERT_REF]=${T[NAME]}
    if [ -e "$CERT_DIR/self/${T[CERT_REF]}/ca.key" ]; then
        T[CERT_REF]="${T[NAME]:0:8}$(head -c 64 /dev/urandom | LC_ALL=C tr -dc 'a-z0-9' | head -c 4)"
    fi
    d="$CERT_DIR/self/${T[CERT_REF]}"
    rm -rf "$d"
    mkdir -p "$d"
    chmod 700 "$d"
    if [ -n "${K[CA]}" ]; then
        printf '%s' "${K[CA]}" | base64 -d >"$d/ca.crt" 2>/dev/null
        is_cert_file "$d/ca.crt" || {
            err "The CA certificate in the key is invalid"
            return 1
        }
    fi
    if [ -n "${K[CCRT]}" ] && [ -n "${K[CKEY]}" ]; then
        printf '%s' "${K[CCRT]}" | base64 -d >"$d/client.crt" 2>/dev/null
        printf '%s' "${K[CKEY]}" | base64 -d >"$d/client.key" 2>/dev/null
        chmod 600 "$d/client.key"
        if ! is_cert_file "$d/client.crt" || ! is_key_file "$d/client.key"; then
            err "The client certificate in the key is invalid"
            return 1
        fi
    fi
    if [ "${T[MTLS]}" = y ] && [ ! -f "$d/client.crt" ]; then
        err "mTLS is enabled but the key has no client certificate"
        return 1
    fi
    [ -f "$d/ca.crt" ] && ok "Certificates imported from the key"
    return 0
}

key_differs() {
    local p
    if [ "${T[SIDE]}" = server ]; then p=${T[BIND_PORT]}; else p=${T[SERVER_PORT]}; fi
    [ "$p" != "${K[PORT]}" ] && return 0
    [ "${T[PORTS]}" != "${K[PORTS]}" ] && return 0
    [ "${T[PTYPE]}" != "${K[PTYPE]}" ] && return 0
    [ "${T[SIDE]}" = server ] && [ "${T[CERT_MODE]}" = self ] && return 0
    return 1
}

key_show() {
    local k f="$TUN_DIR/${T[NAME]}/connection.key"
    k=$(key_make)
    printf '%s\n' "$k" >"$f"
    chmod 600 "$f"
    section "Connection key for the $(other_role) server"
    cnext
    printf '\n\e[38;5;%sm%s\e[0m\n\n' "$NC" "$k"
    info "On the $(other_role) server: Create tunnel, then paste this key"
    info "Saved to $f"
    warn "Keep this key private. It contains the token and certificates."
}

v_new_name() {
    is_name "$1" || {
        err "Use 1-12 characters: a-z, 0-9, -"
        return 1
    }
    [ -e "$TUN_DIR/$1" ] && {
        err "Tunnel '$1' already exists"
        return 1
    }
    return 0
}

v_bind_port() {
    local t o
    is_port "$1" || {
        err "Port must be between 1 and 65535"
        return 1
    }
    for t in $CHK_PROTOS; do
        [ -n "${EXCL[$1/$t]}" ] && continue
        if o=$(port_owner "$1" "$t"); then
            err "Port $1/$t is already in use by $o"
            return 1
        fi
    done
    return 0
}

own_ports_hit() {
    local p x
    for p in "${PORT_LIST[@]}"; do
        for x in "${T[BIND_PORT]}" "${T[INT_PORT]}" "${T[ADMIN_PORT]}" "${T[PADMIN_PORT]}"; do
            if [ -n "$x" ] && [ "$p" = "$x" ]; then
                printf '%s' "$p"
                return 0
            fi
        done
    done
    return 1
}

v_ports_bind() {
    local b x
    local -a orig
    parse_ports "$1" || {
        err "Use ports like 443,8080,2000-2010 (max $MAX_PORTS)"
        return 1
    }
    if ! bind_port_list; then
        err "With this tunnel's port mapping these ports go past 65535"
        return 1
    fi
    orig=("${PORT_LIST[@]}")
    PORT_LIST=("${BIND_LIST[@]}")
    if [ "${T[SIDE]}" = server ] && x=$(own_ports_hit); then
        PORT_LIST=("${orig[@]}")
        err "Port $x is used by the tunnel itself"
        return 1
    fi
    b=$(busy_ports "${T[PTYPE]}")
    PORT_LIST=("${orig[@]}")
    if [ -n "$b" ]; then
        warn "Already in use: $(short_list "$b")"
        confirm "Use these ports anyway?" n || return 1
    fi
    return 0
}

v_ports_target() {
    local f
    parse_ports "$1" || {
        err "Use ports like 443,8080,2000-2010 (max $MAX_PORTS)"
        return 1
    }
    case ${T[TARGET_IP]} in
        127.* | ::1 | localhost)
            f=$(idle_ports "${T[PTYPE]}")
            [ -n "$f" ] && warn "No local service is listening on: $(short_list "$f")"
            ;;
    esac
    return 0
}

next_name() {
    local i=1
    while [ -e "$TUN_DIR/tun$i" ]; do i=$((i + 1)); done
    printf 'tun%s' "$i"
}

side_role() { if [ "$1" = iran ]; then printf 'Iran'; else printf 'Kharej'; fi; }
other_role() { if [ "${T[ROLE]}" = iran ]; then printf 'Kharej'; else printf 'Iran'; fi; }

step_name() {
    local d=${K[NAME]}
    { [ -z "$d" ] || [ -e "$TUN_DIR/$d" ]; } && d=$(next_name)
    ask "T[NAME]" "Tunnel name" "$d" v_new_name "-"
}

step_role() {
    local c
    choose c "This server is" 1 "Iran" "Kharej"
    if [ "$c" = 1 ]; then T[ROLE]=iran; else T[ROLE]=foreign; fi
}

step_mode() {
    local c
    choose c "Tunnel mode" 1 "Reverse (Kharej connects to Iran)" "Direct (Iran connects to Kharej)"
    if [ "$c" = 1 ]; then T[MODE]=reverse; else T[MODE]=direct; fi
    derive_side
    if [ "${T[MODE]}" = direct ]; then
        choose c "Direct method" 1 "STCP (Kharej ports on Iran)" "Plain proxy (Iran ports on Kharej)"
        if [ "$c" = 1 ]; then T[METHOD]=stcp; else T[METHOD]=proxy; fi
    fi
    if [ "${T[SIDE]}" = server ]; then
        info "This server waits for the $(other_role) server to connect"
    else
        info "This server connects to the $(other_role) server"
    fi
}

step_proto() {
    local c d=1 i
    local -a p=(tcp kcp quic websocket wss)
    for i in "${!p[@]}"; do [ "${p[i]}" = "${T[PROTO]}" ] && d=$((i + 1)); done
    choose c "Tunnel protocol" "$d" "tcp" "kcp" "quic" "websocket" "wss"
    T[PROTO]=${p[c - 1]}
}

lip_any() { compgen -G "$LIP_DIR/*.conf" >/dev/null; }

lip_pick_addr() {
    local mode=$1 f c i
    local -a opt=() addr=() nm=()
    for f in "$LIP_DIR"/*.conf; do
        [ -f "$f" ] || continue
        lip_load_file "$f" || continue
        if [ "$mode" = peer ]; then
            [ -n "${L[PEER4]}" ] && opt+=("${L[NAME]}  ${L[PEER4]}") && addr+=("${L[PEER4]}") && nm+=("${L[NAME]}")
            [ -n "${L[PEER6]}" ] && opt+=("${L[NAME]}  ${L[PEER6]}") && addr+=("${L[PEER6]}") && nm+=("${L[NAME]}")
        else
            [ -n "${L[V4]}" ] && opt+=("${L[NAME]}  ${L[V4]%/*}") && addr+=("${L[V4]%/*}") && nm+=("${L[NAME]}")
            [ -n "${L[V6]}" ] && opt+=("${L[NAME]}  ${L[V6]%/*}") && addr+=("${L[V6]%/*}") && nm+=("${L[NAME]}")
        fi
    done
    ((${#opt[@]})) || return 1
    choose c "Local IP" 1 "${opt[@]}"
    i=$((c - 1))
    LIP_ADDR=${addr[i]}
    T[LIP]=${nm[i]}
}

step_endpoint() {
    local d me
    me=$(side_role "${T[ROLE]}")
    if [ "${T[SIDE]}" = server ]; then
        T[BIND_ADDR]=${T[BIND_ADDR]:-0.0.0.0}
        if lip_any; then
            if confirm "Accept tunnel connections only on a local IP?" "$([ -n "${T[LIP]}" ] && echo y || echo n)"; then
                lip_pick_addr own && T[BIND_ADDR]=$LIP_ADDR
            else
                T[BIND_ADDR]=0.0.0.0
                T[LIP]=""
            fi
        fi
        case ${T[PROTO]} in
            kcp | quic) CHK_PROTOS="tcp udp" ;;
            *) CHK_PROTOS="tcp" ;;
        esac
        d=${T[BIND_PORT]}
        if [ -z "$d" ]; then
            if [ "${T[PROTO]}" = wss ]; then d=$(alloc_port 8443); else d=$(alloc_port 7000); fi
        fi
        ask "T[BIND_PORT]" "Tunnel port" "$d" v_bind_port "-"
        if [ "${T[BIND_ADDR]}" != 0.0.0.0 ]; then
            d=${T[BIND_ADDR]}
        else
            d=${T[PUB_ADDR]}
            [ -z "$d" ] && get_public_ip && d=$PUBIP
        fi
        ask "T[PUB_ADDR]" "$me IP" "$d" is_host "Enter a valid IP or domain"
    else
        if lip_any && confirm "Connect through a local IP?" "$([ -n "${T[LIP]}" ] && echo y || echo n)"; then
            lip_pick_addr peer && T[SERVER_ADDR]=$LIP_ADDR
        else
            T[LIP]=""
            ask "T[SERVER_ADDR]" "$(other_role) IP" "${T[SERVER_ADDR]}" is_host "Enter a valid IP or domain"
        fi
        d=${T[SERVER_PORT]}
        if [ -z "$d" ]; then
            if [ "${T[PROTO]}" = wss ]; then d=8443; else d=7000; fi
        fi
        ask "T[SERVER_PORT]" "Tunnel port" "$d" is_port "Port must be between 1 and 65535"
    fi
}

step_token() {
    if [ "${T[SIDE]}" = server ]; then
        ask "T[TOKEN]" "Tunnel token" "${T[TOKEN]:-$(rand_str 32)}" is_token "Use 8-128 characters: A-Z a-z 0-9 . _ -"
    elif [ -n "${T[TOKEN]}" ]; then
        ask "T[TOKEN]" "Tunnel token" "${T[TOKEN]}" is_token "Use 8-128 characters: A-Z a-z 0-9 . _ -"
    else
        info "If the $(other_role) server already has this tunnel, type its token here"
        ask "T[TOKEN]" "Tunnel token, same on both servers" "$(rand_str 32)" is_token "Use 8-128 characters: A-Z a-z 0-9 . _ -"
    fi
}

tls_self() {
    local fk=$1 d f
    if [ "${T[SIDE]}" = server ]; then
        if [ "$fk" != y ]; then
            if confirm "Enable mTLS with client certificates?" "${T[MTLS]:-n}"; then T[MTLS]=y; else T[MTLS]=n; fi
        fi
        T[CERT_REF]=${T[CERT_REF]:-${T[NAME]}}
        d="$CERT_DIR/self/${T[CERT_REF]}"
        if [ -f "$d/ca.key" ] && [ -f "$d/server.crt" ] && [ -f "$d/client.crt" ]; then
            info "Using certificate set '${T[CERT_REF]}'"
            return 0
        fi
        [ -e "$d" ] && rm -rf "$d"
        cert_self_create "${T[CERT_REF]}" "${T[PUB_ADDR]}"
        return
    fi
    if [ "$fk" = y ]; then
        key_write_certs
        return
    fi
    if confirm "Does the $(other_role) server use mTLS?" "${T[MTLS]:-n}"; then T[MTLS]=y; else T[MTLS]=n; fi
    T[CERT_REF]=${T[CERT_REF]:-${T[NAME]}}
    d="$CERT_DIR/self/${T[CERT_REF]}"
    if [ -f "$d/ca.key" ]; then
        info "Using local certificate set '${T[CERT_REF]}'"
        return 0
    fi
    info "Tip: pasting the connection key of the $(other_role) server sets this up automatically"
    mkdir -p "$d"
    chmod 700 "$d"
    ask f "CA certificate file, empty = no verify" "$([ -f "$d/ca.crt" ] && echo "$d/ca.crt")" "?is_cert_file" "Not a valid certificate file"
    if [ -n "$f" ]; then
        [ "$f" -ef "$d/ca.crt" ] || cp -f "$f" "$d/ca.crt"
    else
        rm -f "$d/ca.crt"
    fi
    if [ "${T[MTLS]}" = y ]; then
        ask f "Client certificate file" "$([ -f "$d/client.crt" ] && echo "$d/client.crt")" is_cert_file "Not a valid certificate file"
        [ "$f" -ef "$d/client.crt" ] || cp -f "$f" "$d/client.crt"
        ask f "Client key file" "$([ -f "$d/client.key" ] && echo "$d/client.key")" is_key_file "Not a valid private key file"
        [ "$f" -ef "$d/client.key" ] || cp -f "$f" "$d/client.key"
        chmod 600 "$d/client.key"
    fi
    return 0
}

tls_fallback() {
    if [ "${T[PROTO]}" = wss ]; then
        confirm "Use a self-signed certificate instead?" y || return 1
        T[CERT_MODE]=self
        T[CERT_REF]=""
        tls_self n
    else
        confirm "Use the built-in FRP certificate instead?" y || return 1
        T[CERT_MODE]=builtin
        T[CERT_REF]=""
        T[MTLS]=n
    fi
}

tls_le() {
    if [ "${T[SIDE]}" = server ]; then
        ask "T[CERT_REF]" "Domain" "${T[CERT_REF]}" is_domain "Enter a valid domain like tunnel.example.com"
        if [ -s "$CERT_DIR/le/${T[CERT_REF]}/fullchain.pem" ]; then
            info "Using the existing certificate for ${T[CERT_REF]}"
            return 0
        fi
        le_issue "${T[CERT_REF]}" && return 0
        tls_fallback
        return
    fi
    ask "T[CERT_REF]" "Domain of the $(other_role) server" "${T[CERT_REF]}" is_domain "Enter a valid domain like tunnel.example.com"
}

step_tls() {
    local fk=$1 c d
    if [ "$fk" != y ]; then
        if [ "${T[PROTO]}" = wss ]; then
            T[TLS]=y
            info "wss always uses TLS"
            d=1
            [ "${T[CERT_MODE]}" = le ] && d=2
            choose c "Certificate" "$d" "Self-signed" "Let's Encrypt"
            if [ "$c" = 1 ]; then T[CERT_MODE]=self; else T[CERT_MODE]=le; fi
        elif confirm "Encrypt the tunnel with TLS?" "$([ "${T[TLS]}" = n ] && echo n || echo y)"; then
            T[TLS]=y
            case ${T[CERT_MODE]} in self) d=2 ;; le) d=3 ;; *) d=1 ;; esac
            choose c "Certificate" "$d" "Built-in FRP" "Self-signed" "Let's Encrypt"
            case $c in
                1) T[CERT_MODE]=builtin ;;
                2) T[CERT_MODE]=self ;;
                3) T[CERT_MODE]=le ;;
            esac
        else
            T[TLS]=n
            T[CERT_MODE]=none
        fi
        [ "${T[CERT_MODE]}" = self ] || T[MTLS]=n
        if [ "${T[CERT_MODE]}" != "${T[_OLD_CERT]}" ]; then T[CERT_REF]=""; fi
    fi
    case ${T[CERT_MODE]} in
        self) tls_self "$fk" ;;
        le) tls_le "$fk" ;;
        *)
            T[CERT_REF]=""
            T[MTLS]=n
            return 0
            ;;
    esac
}

step_port_type() {
    local c d=1
    case ${T[PTYPE]} in udp) d=2 ;; both) d=3 ;; esac
    choose c "VPN config port type" "$d" "TCP" "UDP" "TCP + UDP"
    case $c in
        1) T[PTYPE]=tcp ;;
        2) T[PTYPE]=udp ;;
        3) T[PTYPE]=both ;;
    esac
}

step_service_ip() {
    has_proxies_here || return 0
    ask "T[TARGET_IP]" "VPN service IP" "${T[TARGET_IP]:-127.0.0.1}" is_ip "Enter a valid IP"
}

step_advanced() {
    tunnel_defaults
    step_tls n || return 1
    step_service_ip
    if confirm "Enable tcpMux?" "${T[TCPMUX]}"; then T[TCPMUX]=y; else T[TCPMUX]=n; fi
    if confirm "Enable compression?" "${T[COMPRESS]}"; then T[COMPRESS]=y; else T[COMPRESS]=n; fi
    ask "T[POOL]" "Pool count" "${T[POOL]}" v_pool "Enter a number from 0 to 100"
    ask "T[HB_INT]" "Heartbeat interval sec, 0 = off" "${T[HB_INT]}" v_hb "Enter a number from 0 to 3600"
    ask "T[HB_TO]" "Heartbeat timeout sec, 0 = off" "${T[HB_TO]}" v_hb "Enter a number from 0 to 3600"
    if [ "${T[HB_INT]}" != 0 ] && [ "${T[HB_TO]}" != 0 ] && ((10#${T[HB_TO]} <= 10#${T[HB_INT]})); then
        warn "Heartbeat timeout should be larger than the interval"
    fi
    if [ "${T[SIDE]}" = server ] && [ "${T[METHOD]}" != stcp ]; then
        if confirm "Allow only the listed VPN config ports on this server?" "${T[RESTRICT]}"; then T[RESTRICT]=y; else T[RESTRICT]=n; fi
    fi
    return 0
}

step_listen() {
    local c d=1
    if ! bind_here; then
        T[LISTEN]=public
        return 0
    fi
    [ "${T[LISTEN]}" = local ] && d=2
    choose c "Who connects to the VPN config ports" "$d" "VPN users (open to the internet)" "Only the panel on this server (127.0.0.1)"
    if [ "$c" = 2 ]; then T[LISTEN]=local; else T[LISTEN]=public; fi
}

step_ports() {
    blank
    if bind_here; then
        if [ "${T[LISTEN]}" = local ]; then
            info "These ports will be available on 127.0.0.1 of this server"
        else
            info "These ports will be opened on this server for VPN users"
        fi
        ask "T[PORTS]" "VPN config ports, e.g. 443,8080,2000-2010" "${T[PORTS]}" v_ports_bind "-"
    else
        info "Ports of the VPN configs (inbounds) running on this server"
        ask "T[PORTS]" "VPN config ports, e.g. 443,8080,2000-2010" "${T[PORTS]}" v_ports_target "-"
    fi
    parse_ports "${T[PORTS]}"
    T[PORTS]=$(ports_compact)
}

tls_label() {
    if [ "${T[TLS]}" != y ] && [ "${T[PROTO]}" != wss ]; then
        printf 'off'
        return
    fi
    case ${T[CERT_MODE]} in
        builtin) printf 'on, built-in' ;;
        self) printf 'on, self-signed %s%s' "${T[CERT_REF]}" "$([ "${T[MTLS]}" = y ] && echo ', mTLS')" ;;
        le) printf "on, Let's Encrypt %s" "${T[CERT_REF]}" ;;
        *) printf 'on' ;;
    esac
}

mode_label() {
    if [ "${T[MODE]}" = reverse ]; then
        printf 'Reverse, Kharej connects to Iran'
    elif [ "${T[METHOD]}" = stcp ]; then
        printf 'Direct STCP, Iran connects to Kharej'
    else
        printf 'Direct plain proxy, Iran connects to Kharej'
    fi
}

endpoint_label() {
    if [ "${T[SIDE]}" = server ]; then
        printf 'port %s, %s IP %s' "${T[BIND_PORT]}" "$(side_role "${T[ROLE]}")" "${T[PUB_ADDR]}"
    else
        printf '%s IP %s, port %s' "$(other_role)" "${T[SERVER_ADDR]}" "${T[SERVER_PORT]}"
    fi
}

adv_label() {
    printf 'mux %s, zip %s, pool %s, heartbeat %s/%s' "$(yn "${T[TCPMUX]}")" "$(yn "${T[COMPRESS]}")" "${T[POOL]}" "${T[HB_INT]}" "${T[HB_TO]}"
}

tunnel_summary() {
    section "Summary"
    kv "Tunnel name" "${T[NAME]}"
    kv "This server" "$(side_role "${T[ROLE]}"), $([ "${T[SIDE]}" = server ] && echo 'tunnel server' || echo 'tunnel client')"
    kv "Mode" "$(mode_label)"
    kv "Tunnel protocol" "${T[PROTO]}"
    if [ "${T[SIDE]}" = server ]; then
        kv "Tunnel port" "${T[BIND_PORT]}"
        kv "$(side_role "${T[ROLE]}") IP" "${T[PUB_ADDR]}"
        [ "${T[BIND_ADDR]}" != 0.0.0.0 ] && kv "Listen on" "${T[BIND_ADDR]}"
    else
        kv "$(other_role) IP" "${T[SERVER_ADDR]}"
        kv "Tunnel port" "${T[SERVER_PORT]}"
    fi
    [ -n "${T[LIP]}" ] && kv "Local IP link" "${T[LIP]}"
    kv "Tunnel token" "${T[TOKEN]}"
    kv "TLS" "$(tls_label)"
    kv "VPN config ports" "${T[PORTS]} ${T[PTYPE]}"
    if [ "$(roff)" != 0 ] && parse_ports "${T[PORTS]}" && bind_port_list; then
        kv "$([ "${T[MODE]}" = reverse ] || [ "${T[METHOD]}" = stcp ] && echo Iran || echo Kharej) ports" "$(ports_compact "${BIND_LIST[@]}")"
    fi
    [ -n "${T[GROUP]}" ] && kv "Multi-protocol group" "${T[GROUP]}"
    if bind_here; then
        if [ "${T[LISTEN]}" = local ]; then kv "VPN ports access" "127.0.0.1 only"; else kv "VPN ports access" "open to the internet"; fi
    fi
    has_proxies_here && kv "VPN service IP" "${T[TARGET_IP]}"
    kv "Advanced" "$(adv_label)"
}

net_offer() {
    [ -f "$SYSCTL_FILE" ] && [ -f "$BBR_FILE" ] && return 0
    confirm "Apply network optimizations: BBR, sysctl, ulimit?" n || return 0
    net_bbr
    net_sysctl
    net_ulimit
}

tunnel_create() {
    local fk=n adv=n
    need_frp || return
    header "CREATE TUNNEL"
    T=()
    K=()
    EXCL=()
    step_role
    blank
    if key_prompt; then
        fk=y
        key_apply
        ok "Key accepted: $(mode_label)"
    fi
    step_name
    if [ "$fk" = n ]; then
        T[MODE]=reverse
        derive_side
        T[PROTO]=tcp
        T[TLS]=y
        T[CERT_MODE]=builtin
        if confirm "Advanced settings?" n; then
            adv=y
            section "Advanced"
            step_mode
            if [ "${T[METHOD]}" = stcp ] && [ "${T[SIDE]}" = client ]; then
                err "STCP needs the connection key from the Kharej server"
                info "Create this tunnel on the Kharej server first, then paste its key here"
                pause
                return
            fi
            step_proto
        fi
    fi
    section "Connection"
    step_endpoint
    if [ "$fk" = n ]; then
        if [ "${T[SIDE]}" = client ] || [ "$adv" = y ]; then
            step_token
        else
            T[TOKEN]=$(rand_str 32)
        fi
    fi
    if [ "$adv" = y ]; then
        section "Advanced"
        if ! step_advanced; then
            err "TLS setup failed, tunnel was not created"
            pause
            return
        fi
    elif [ "$fk" = y ] && ! step_tls y; then
        err "TLS setup failed, tunnel was not created"
        pause
        return
    fi
    tunnel_defaults
    section "VPN configs"
    if [ "$adv" = y ]; then
        step_port_type
        step_listen
    fi
    step_ports
    tunnel_summary
    blank
    if ! confirm "Create this tunnel?" y; then
        warn "Cancelled"
        pause
        return
    fi
    blank
    if tunnel_apply; then
        ok "Tunnel '${T[NAME]}' created"
        if [ "$fk" = n ]; then
            key_show
        elif key_differs; then
            warn "Some settings differ from the key. On the $(other_role) server, delete this tunnel and create it again with this key."
            key_show
        else
            info "Done. No need to paste anything on the $(other_role) server."
        fi
        net_offer
    else
        err "Tunnel files were saved but the service was not started. Use Edit to fix it."
    fi
    pause
}

tunnel_table() {
    local i n st en
    mapfile -t TNAMES < <(tunnel_names)
    if ((${#TNAMES[@]} == 0)); then
        warn "No tunnels yet"
        return 1
    fi
    cnext
    printf '  \e[1;38;5;%sm%-3s %-12s %-8s %-8s %-9s %-14s %-9s %s\e[0m\n' "$NC" "#" "NAME" "SERVER" "MODE" "PROTO" "VPN PORTS" "STATUS" "BOOT"
    for i in "${!TNAMES[@]}"; do
        n=${TNAMES[i]}
        tunnel_load "$n" || continue
        st=$(svc_state "frp-$n.service")
        en=$(svc_enabled "frp-$n.service")
        cnext
        printf '  \e[38;5;%sm%-3s %-12s %-8s %-8s %-9s %-14s\e[0m \e[38;5;%sm%-9s\e[0m\e[38;5;%sm%s\e[0m\n' \
            "$NC" "$((i + 1))" "$n" "$(side_role "${T[ROLE]}")" "${T[MODE]}" "${T[PROTO]}" "$(trunc "${T[PORTS]}" 14)" \
            "$(state_color "$st")" "$st" "$(state_color "$en")" "$en"
    done
    return 0
}

pick_tunnel() {
    local __n=$1 __all=$2 __i __c __h="Tunnel number, 0 to go back"
    tunnel_table || {
        pause
        return 1
    }
    [ -n "$__all" ] && __h="Tunnel number, a = all, 0 to go back"
    cnext
    __c=$NC
    blank
    while :; do
        prompt "$__c" "$__h" ""
        read_line __i
        __i=${__i,,}
        [ "$__i" = 0 ] && return 1
        if [ -n "$__all" ] && [ "$__i" = a ]; then
            printf -v "$__n" '%s' "*"
            return 0
        fi
        if [[ $__i =~ ^[0-9]{1,3}$ ]] && ((10#$__i >= 1 && 10#$__i <= ${#TNAMES[@]})); then
            printf -v "$__n" '%s' "${TNAMES[10#$__i - 1]}"
            return 0
        fi
        err "Enter a number from the list"
    done
}

tunnel_details() {
    local n=$1 u st
    tunnel_load "$n" || return
    header "TUNNEL: $n"
    tunnel_summary
    section "Services"
    for u in "frp-$n.service" "frp-$n-provider.service" "frp-$n-wss.service"; do
        [ -f "$UNIT_DIR/$u" ] || continue
        st=$(svc_state "$u")
        cnext
        printf '  \e[38;5;%sm%-20s\e[0m \e[38;5;%sm%s\e[0m \e[38;5;%sm/ %s\e[0m\n' "$NC" "$u" "$(state_color "$st")" "$st" "$NC" "$(svc_enabled "$u")"
    done
    kv "Admin API" "http://127.0.0.1:${T[ADMIN_PORT]}  ${T[ADMIN_USER]} / ${T[ADMIN_PASS]}"
    if [ -n "${T[GROUP]}" ] && [ -d "$GROUP_DIR/${T[GROUP]}" ]; then
        local gf
        for gf in "$GROUP_DIR/${T[GROUP]}"/*.json; do
            [ -f "$gf" ] && kv "Xray config" "$gf"
        done
    fi
    kv "Created" "${T[CREATED]}"
    cert_paths
    if [ "${T[CERT_MODE]}" = self ] || [ "${T[CERT_MODE]}" = le ]; then
        local f
        f=$(cert_main_file "$CERT_DIR/${T[CERT_MODE]}/${T[CERT_REF]}") && cert_expiry "$f" && kv "Certificate expires" "$CE_DATE, $CE_DAYS days"
    fi
    if [ -n "${T[GROUP]}" ] && [ "${T[ROLE]}" = iran ] && [ -f "$GROUP_DIR/${T[GROUP]}.conf" ]; then
        group_key_show "${T[GROUP]}"
    else
        key_show
    fi
    pause
}

tunnels_menu() {
    local n
    while :; do
        header "TUNNELS"
        pick_tunnel n || return
        tunnel_details "$n"
    done
}

tunnel_edit() {
    local n c old
    need_frp || return
    header "EDIT TUNNEL"
    pick_tunnel n || return
    tunnel_load "$n" || return
    tunnel_defaults
    EXCL=()
    K=()
    if parse_ports "${T[PORTS]}" && bind_port_list; then
        for c in "${BIND_LIST[@]}"; do
            [ "${T[PTYPE]}" != udp ] && EXCL[$c/tcp]=1
            [ "${T[PTYPE]}" != tcp ] && EXCL[$c/udp]=1
        done
    fi
    if [ "${T[SIDE]}" = server ]; then
        [ -n "${T[BIND_PORT]}" ] && EXCL[${T[BIND_PORT]}/tcp]=1
        [[ ${T[PROTO]} == kcp || ${T[PROTO]} == quic ]] && EXCL[${T[BIND_PORT]}/udp]=1
        [ -n "${T[INT_PORT]}" ] && EXCL[${T[INT_PORT]}/tcp]=1
    fi
    while :; do
        header "EDIT: $n"
        item 1 "Tunnel port & IP     $(endpoint_label)"
        item 2 "VPN config ports     ${T[PORTS]} ${T[PTYPE]}$([ "$(roff)" != 0 ] && printf ', mapped %+d' "$(roff)")"
        item 3 "Advanced settings    ${T[PROTO]}, TLS $(tls_label)"
        item 4 "Save and apply"
        item 0 "Cancel"
        menu_pick c 4
        blank
        case $c in
            1) step_endpoint ;;
            2)
                step_port_type
                step_listen
                step_ports
                ;;
            3)
                old=${T[PROTO]}
                step_proto
                if [ "$old" != "${T[PROTO]}" ]; then
                    [ "${T[SIDE]}" = server ] && step_endpoint
                    [ "${T[PROTO]}" = wss ] || T[INT_PORT]=""
                fi
                step_token
                T[_OLD_CERT]=${T[CERT_MODE]}
                if ! step_advanced; then
                    warn "TLS setup failed"
                    pause
                fi
                unset 'T[_OLD_CERT]'
                ;;
            4)
                if tunnel_apply; then
                    ok "Tunnel '$n' updated"
                    warn "Make the same change on the $(other_role) server with Edit, or delete the tunnel there and create it again with this key"
                    key_show
                fi
                pause
                return
                ;;
            0) return ;;
        esac
    done
}

tunnel_delete() {
    local n m r g x
    header "DELETE TUNNEL"
    pick_tunnel n || return
    tunnel_load "$n"
    m=${T[CERT_MODE]}
    r=${T[CERT_REF]}
    g=${T[GROUP]}
    if [ -n "$g" ] && [ -f "$GROUP_DIR/$g.conf" ] && confirm "Delete all tunnels of multi-protocol group '$g'?" y; then
        for x in $(group_members "$g"); do
            tunnel_remove "$x"
            ok "Tunnel '$x' deleted"
        done
        rm -rf "${GROUP_DIR:?}/$g.conf" "${GROUP_DIR:?}/$g"
        pause
        return
    fi
    if confirm "Delete tunnel '$n'?" n; then
        tunnel_remove "$n"
        ok "Tunnel '$n' deleted"
        if [ "$m" = self ] && [ -n "$r" ] && [ -d "$CERT_DIR/self/$r" ] && [ -z "$(cert_users self "$r")" ]; then
            confirm "Also delete its certificate set '$r'?" n && rm -rf "${CERT_DIR:?}/self/$r" && ok "Certificate set deleted"
        fi
    fi
    pause
}

svc_menu() {
    local c n x act
    local -a acts=(start stop restart enable disable) list
    while :; do
        header "SERVICE CONTROL"
        item 1 "Start"
        item 2 "Stop"
        item 3 "Restart"
        item 4 "Enable on boot"
        item 5 "Disable on boot"
        item 0 "Back"
        menu_pick c 5
        [ "$c" = 0 ] && return
        act=${acts[c - 1]}
        blank
        pick_tunnel n all || continue
        if [ "$n" = "*" ]; then list=("${TNAMES[@]}"); else list=("$n"); fi
        blank
        for x in "${list[@]}"; do
            if systemctl "$act" "frp-$x.service" >/dev/null 2>&1; then
                ok "$act frp-$x"
            else
                err "$act frp-$x failed"
            fi
        done
        pause
    done
}

live_log() {
    info "Press Ctrl+C to stop"
    blank
    trap ':' INT
    journalctl -f -n 50 -o short-iso -u "frp-$1.service" -u "frp-$1-provider.service" -u "frp-$1-wss.service"
    trap on_int INT
}

logs_menu() {
    local n c
    header "LOGS & STATUS"
    pick_tunnel n || return
    while :; do
        header "LOGS: $n"
        item 1 "Live log"
        item 2 "Service status"
        item 3 "Last 100 lines"
        item 4 "Watchdog log"
        item 0 "Back"
        menu_pick c 4
        blank
        case $c in
            1) live_log "$n" ;;
            2)
                systemctl status "frp-$n.service" --no-pager -l 2>&1 | head -n 25
                for c in provider wss; do
                    [ -f "$UNIT_DIR/frp-$n-$c.service" ] && blank && systemctl status "frp-$n-$c.service" --no-pager -l 2>&1 | head -n 12
                done
                pause
                ;;
            3)
                journalctl -n 100 --no-pager -o short-iso -u "frp-$n.service" -u "frp-$n-provider.service" -u "frp-$n-wss.service" 2>&1
                pause
                ;;
            4)
                if [ -s "$LOG_DIR/watchdog.log" ]; then tail -n 40 "$LOG_DIR/watchdog.log"; else info "Watchdog log is empty"; fi
                pause
                ;;
            0) return ;;
        esac
    done
}

declare -A GH=()
GSEC=()
GPROTOS=()

is_group_name() { [[ $1 =~ ^[a-z0-9]{1,7}$ ]]; }
is_uuid() { [[ $1 =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; }

proto_suffix() {
    if [ "$1" = websocket ]; then printf 'ws'; else printf '%s' "$1"; fi
}

gen_uuid() {
    local u
    local h
    u=$(cat /proc/sys/kernel/random/uuid 2>/dev/null)
    if ! is_uuid "$u"; then
        h=$(openssl rand -hex 16)
        u="${h:0:8}-${h:8:4}-4${h:13:3}-a${h:17:3}-${h:20:12}"
    fi
    printf '%s' "$u"
}

group_members() {
    sed -n 's/^TUNNELS=//p' "$GROUP_DIR/$1.conf" 2>/dev/null | head -n 1 | tr ',' ' '
}

group_get() {
    sed -n "s/^$2=//p" "$GROUP_DIR/$1.conf" 2>/dev/null | head -n 1
}

group_taken() {
    local p
    [ -e "$GROUP_DIR/$1.conf" ] && return 0
    for p in tcp kcp quic ws; do
        [ -e "$TUN_DIR/$1-$p" ] && return 0
    done
    return 1
}

v_new_group() {
    is_group_name "$1" || {
        err "Use 1-7 characters: a-z, 0-9"
        return 1
    }
    if group_taken "$1"; then
        err "Group '$1' already exists"
        return 1
    fi
    return 0
}

next_group() {
    local i=1 g=multi
    while group_taken "$g"; do
        i=$((i + 1))
        g="multi$i"
    done
    printf '%s' "$g"
}

v_protos() {
    local x plist=" "
    local -a a
    IFS=, read -ra a <<<"${1//[[:space:]]/}"
    if ((${#a[@]} < 2 || ${#a[@]} > 4)); then
        err "Pick 2 to 4 of: tcp, kcp, quic, websocket"
        return 1
    fi
    for x in "${a[@]}"; do
        [ "$x" = ws ] && x=websocket
        if [[ ! $x =~ ^(tcp|kcp|quic|websocket)$ ]]; then
            err "Unknown protocol: ${x:-empty}"
            return 1
        fi
        if [[ $plist == *" $x "* ]]; then
            err "Protocol listed twice: $x"
            return 1
        fi
        plist+="$x "
    done
    read -ra GPROTOS <<<"$plist"
    return 0
}

free_run() {
    local p=$1 n=$2 i ok
    scan_listen t
    while ((p + n - 1 <= 65535)); do
        ok=1
        for ((i = 0; i < n; i++)); do
            if [ -n "${LMAP[$((p + i))]}" ] || [[ " $3 " == *" $((p + i)) "* ]]; then
                ok=0
                p=$((p + i + 1))
                break
            fi
        done
        if [ "$ok" = 1 ]; then
            printf '%s' "$p"
            return 0
        fi
    done
    return 1
}

v_panel_base() {
    local i p o
    is_port "$1" || {
        err "Port must be between 1 and 65535"
        return 1
    }
    if (($1 + ${#GPROTOS[@]} - 1 > 65535)); then
        err "Not enough ports after $1"
        return 1
    fi
    for ((i = 0; i < ${#GPROTOS[@]}; i++)); do
        p=$(($1 + i))
        if o=$(port_owner "$p" tcp); then
            err "Port $p is already in use by $o"
            return 1
        fi
    done
    return 0
}

alloc_tunnel_port() {
    local p=$1 x
    while :; do
        x=$(alloc_port "$p" "$3") || return 1
        if [[ $2 == kcp || $2 == quic ]]; then
            scan_listen u
            if [ -n "${LMAP[$x]}" ]; then
                p=$((x + 1))
                continue
            fi
        fi
        printf '%s' "$x"
        return 0
    done
}

group_key_make() {
    local g=$1 x
    {
        printf 'V=1\nGROUP=%s\nUUID=%s\nXPORT=%s\n' "$g" "$(group_get "$g" UUID)" "$(group_get "$g" XPORT)"
        for x in $(group_members "$g"); do
            tunnel_load "$x" || continue
            printf -- '---\n'
            key_lines
        done
    } | gzip -9c | base64 -w0 | sed "s/^/$GKEY_PREFIX/"
}

group_key_parse() {
    local data line k n=-1 i
    GH=()
    GSEC=()
    [[ $1 == "$GKEY_PREFIX"* ]] || return 1
    data=$(key_decode "$1" "$GKEY_PREFIX") || return 1
    while IFS= read -r line; do
        if [ "$line" = "---" ]; then
            n=$((n + 1))
            GSEC[n]=""
            continue
        fi
        if ((n < 0)); then
            k=${line%%=*}
            [[ $k =~ ^[A-Z_]+$ ]] && GH[$k]=${line#*=}
        else
            GSEC[n]+="$line"$'\n'
        fi
    done <<<"$data"
    [ "${GH[V]}" = 1 ] && is_group_name "${GH[GROUP]}" && is_uuid "${GH[UUID]}" && is_port "${GH[XPORT]}" || return 1
    ((${#GSEC[@]} >= 2 && ${#GSEC[@]} <= 4)) || return 1
    for ((i = 0; i < ${#GSEC[@]}; i++)); do
        key_load "${GSEC[i]}"
        key_valid || return 1
        [ "${K[ROLE]}" = iran ] && [ "${K[MODE]}" = reverse ] || return 1
    done
    return 0
}

group_key_show() {
    local g=$1 k f="$GROUP_DIR/$1/connection.key"
    k=$(group_key_make "$g")
    mkdir -p "$GROUP_DIR/$g"
    printf '%s\n' "$k" >"$f"
    chmod 600 "$f"
    section "Multi-protocol key for the Kharej server"
    cnext
    printf '\n\e[38;5;%sm%s\e[0m\n\n' "$NC" "$k"
    info "Saved to $f"
    warn "Keep this key private. It contains the tunnel token and the VLESS UUID."
}

group_write() {
    local g=$1 role=$2 uuid=$3 xport=$4 base=$5 protos=$6 members=$7
    mkdir -p "$GROUP_DIR/$g"
    chmod 700 "$GROUP_DIR" "$GROUP_DIR/$g"
    printf 'GROUP=%s\nROLE=%s\nUUID=%s\nXPORT=%s\nBASE=%s\nPROTOS=%s\nTUNNELS=%s\nCREATED=%s\n' \
        "$g" "$role" "$uuid" "$xport" "$base" "$protos" "$members" "$(date '+%F %T')" >"$GROUP_DIR/$g.conf"
    chmod 600 "$GROUP_DIR/$g.conf"
}

iran_xray_json() {
    local g=$1 uuid=$2 base=$3 i n first sep
    shift 3
    n=$#
    first="$g-$(proto_suffix "$1")"
    printf '{\n  "outbounds": [\n'
    for ((i = 0; i < n; i++)); do
        sep=","
        ((i == n - 1)) && sep=""
        printf '    {"tag": "%s-%s", "protocol": "vless", "settings": {"vnext": [{"address": "127.0.0.1", "port": %s, "users": [{"id": "%s", "encryption": "none"}]}]}, "streamSettings": {"network": "tcp", "security": "none"}}%s\n' \
            "$g" "$(proto_suffix "$1")" "$((base + i))" "$uuid" "$sep"
        shift
    done
    printf '  ],\n'
    printf '  "observatory": {"subjectSelector": ["%s-"], "probeURL": "https://www.google.com/generate_204", "probeInterval": "15s", "enableConcurrency": true},\n' "$g"
    printf '  "routing": {\n'
    printf '    "balancers": [{"tag": "%s-auto", "selector": ["%s-"], "strategy": {"type": "leastPing"}, "fallbackTag": "%s"}],\n' "$g" "$g" "$first"
    printf '    "rules": [{"type": "field", "network": "tcp,udp", "balancerTag": "%s-auto"}]\n' "$g"
    printf '  }\n}\n'
}

kharej_xray_json() {
    local g=$1 uuid=$2 xport=$3
    printf '{\n  "log": {"loglevel": "warning"},\n  "inbounds": [\n'
    printf '    {"tag": "%s-in", "listen": "127.0.0.1", "port": %s, "protocol": "vless", "settings": {"clients": [{"id": "%s"}], "decryption": "none"}, "streamSettings": {"network": "tcp", "security": "none"}}\n' "$g" "$xport" "$uuid"
    printf '  ],\n  "outbounds": [\n    {"tag": "direct", "protocol": "freedom"}\n  ]\n}\n'
}

kharej_inbound_guide() {
    if [ -n "$3" ]; then section "Xray inbound on this server"; else section "Xray inbound on the Kharej server"; fi
    info "Create one VLESS inbound in your Kharej panel or Xray:"
    kv "Listen IP" "127.0.0.1"
    kv "Port" "$2"
    kv "Protocol" "vless, transmission TCP, security none"
    kv "Client ID (UUID)" "$1"
    [ -n "$3" ] && kv "Full Xray config" "$3"
}

iran_panel_guide() {
    local g=$1 f=$2 first=$3
    section "Iran panel setup"
    info "Xray config with outbounds, balancer, observatory and rule:"
    kv "File" "$f"
    say "1. In the panel add the outbounds from the file (3x-ui: Outbounds, JSON tab, one line each)"
    say "2. Add a balancer: tag $g-auto, strategy Least ping, selector $g-, fallback $first"
    say "3. Add a routing rule: network tcp,udp to balancer $g-auto, keep it below block and direct rules"
    say "4. Set the observatory probe interval to 15s, then Save and restart Xray"
    info "Marzban: paste the parts of the file into Core Settings"
}

multi_create_iran() {
    local g ip xport base tp next ex i x sfx uuid token members="" f
    local -a protos tports names
    section "Multi-protocol tunnel on Iran"
    ask g "Group name" "$(next_group)" v_new_group "-"
    ask x "Protocols" "tcp,kcp,quic,websocket" v_protos "-"
    protos=("${GPROTOS[@]}")
    get_public_ip
    ask ip "Iran IP" "$PUBIP" is_host "Enter a valid IP or domain"
    ask xport "Kharej VPN inbound port" "10808" is_port "Port must be between 1 and 65535"
    ask base "First Iran panel port" "$(free_run 10808 "${#protos[@]}")" v_panel_base "-"
    ex=""
    for ((i = 0; i < ${#protos[@]}; i++)); do ex+=" $((base + i))"; done
    next=7000
    for x in "${protos[@]}"; do
        tp=$(alloc_tunnel_port "$next" "$x" "$ex") || {
            err "No free tunnel port found"
            return 1
        }
        tports+=("$tp")
        ex+=" $tp"
        next=$((tp + 1))
    done
    section "Summary"
    for ((i = 0; i < ${#protos[@]}; i++)); do
        names+=("$g-$(proto_suffix "${protos[i]}")")
        kv "${names[i]}" "${protos[i]}, tunnel port ${tports[i]}, panel 127.0.0.1:$((base + i)) -> Kharej $xport"
    done
    kv "Iran IP" "$ip"
    blank
    confirm "Create these tunnels?" y || {
        warn "Cancelled"
        return 1
    }
    blank
    uuid=$(gen_uuid)
    token=$(rand_str 32)
    EXTRA_EXCL=$ex
    for ((i = 0; i < ${#protos[@]}; i++)); do
        T=()
        T[NAME]=${names[i]}
        T[ROLE]=iran
        T[MODE]=reverse
        derive_side
        T[PROTO]=${protos[i]}
        T[BIND_ADDR]=0.0.0.0
        T[BIND_PORT]=${tports[i]}
        T[PUB_ADDR]=$ip
        T[TOKEN]=$token
        T[TLS]=y
        T[CERT_MODE]=builtin
        T[PORTS]=$xport
        T[PTYPE]=tcp
        T[ROFF]=$((base + i - xport))
        T[LISTEN]=local
        T[RESTRICT]=y
        T[GROUP]=$g
        tunnel_defaults
        say "Creating ${names[i]} (${protos[i]})"
        if tunnel_apply; then
            members+="${members:+,}${names[i]}"
        else
            err "Tunnel ${names[i]} was not started"
        fi
    done
    EXTRA_EXCL=""
    [ -n "$members" ] || return 1
    group_write "$g" iran "$uuid" "$xport" "$base" "$(
        IFS=,
        printf '%s' "${protos[*]}"
    )" "$members"
    f="$GROUP_DIR/$g/iran-xray.json"
    iran_xray_json "$g" "$uuid" "$base" "${protos[@]}" >"$f"
    chmod 600 "$f"
    ok "Multi-protocol group '$g' created"
    group_key_show "$g"
    section "Next steps"
    say "On the Kharej server: Multi-protocol tunnel, Kharej, paste the key above"
    kharej_inbound_guide "$uuid" "$xport" ""
    iran_panel_guide "$g" "$f" "${names[0]}"
}

multi_import_kharej() {
    local c k g ip i sfx members="" f n
    cnext
    c=$NC
    while :; do
        printf '  \e[38;5;%sm%s\e[0m\n  ' "$c" "Multi-protocol key from the Iran server, Enter to cancel:"
        if ! IFS= read -r -e k; then
            printf '\e[0m\n'
            exit 0
        fi
        k=${k//[[:space:]]/}
        [ -z "$k" ] && return 1
        if [[ $k == "$KEY_PREFIX"* ]]; then
            err "This is a single tunnel key. Use Create tunnel in the main menu."
            continue
        fi
        group_key_parse "$k" && break
        err "Invalid multi-protocol key"
    done
    g=${GH[GROUP]}
    if group_taken "$g"; then
        err "Group '$g' already exists on this server. Delete it first with Delete tunnel, then paste the key again."
        return 1
    fi
    n=${#GSEC[@]}
    key_load "${GSEC[0]}"
    ok "Key accepted: $n tunnels for group '$g'"
    ask ip "Iran IP" "${K[ADDR]}" is_host "Enter a valid IP or domain"
    section "Summary"
    for ((i = 0; i < n; i++)); do
        key_load "${GSEC[i]}"
        sfx=${K[NAME]##*-}
        kv "$g-$sfx" "${K[PROTO]}, Iran $ip:${K[PORT]} -> this server 127.0.0.1:${GH[XPORT]}"
    done
    if ! port_owner "${GH[XPORT]}" tcp >/dev/null; then
        warn "Nothing listens on port ${GH[XPORT]} yet. Create the Xray inbound shown below."
    fi
    blank
    confirm "Create these tunnels?" y || {
        warn "Cancelled"
        return 1
    }
    blank
    for ((i = 0; i < n; i++)); do
        key_load "${GSEC[i]}"
        T=()
        key_apply
        sfx=${K[NAME]##*-}
        T[NAME]="$g-$sfx"
        T[SERVER_ADDR]=$ip
        T[TARGET_IP]=127.0.0.1
        T[GROUP]=$g
        tunnel_defaults
        say "Creating ${T[NAME]} (${T[PROTO]})"
        if tunnel_apply; then
            members+="${members:+,}${T[NAME]}"
        else
            err "Tunnel ${T[NAME]} was not started"
        fi
    done
    [ -n "$members" ] || return 1
    group_write "$g" foreign "${GH[UUID]}" "${GH[XPORT]}" "" "" "$members"
    f="$GROUP_DIR/$g/kharej-xray.json"
    kharej_xray_json "$g" "${GH[UUID]}" "${GH[XPORT]}" >"$f"
    chmod 600 "$f"
    ok "Multi-protocol group '$g' created"
    kharej_inbound_guide "${GH[UUID]}" "${GH[XPORT]}" "$f"
    info "Done. No need to paste anything on the Iran server."
}

multi_menu() {
    local c
    need_frp || return
    header "MULTI-PROTOCOL TUNNEL"
    info "One tunnel per protocol. Xray on the Iran panel picks the best one automatically."
    choose c "This server is" 1 "Iran" "Kharej"
    blank
    if [ "$c" = 1 ]; then
        multi_create_iran
    else
        multi_import_kharej
    fi
    pause
}

LIP_KEYS=(NAME TYPE ROLE IFACE LOCAL REMOTE V4 PEER4 V6 PEER6 MTU VNI DPORT DEV CREATED)

lip_load_file() {
    local line k
    L=()
    [ -f "$1" ] || return 1
    while IFS= read -r line; do
        k=${line%%=*}
        [[ $k =~ ^[A-Z_0-9]+$ ]] && L[$k]=${line#*=}
    done <"$1"
    [ -n "${L[NAME]}" ]
}

lip_names() {
    local f
    for f in "$LIP_DIR"/*.conf; do
        [ -f "$f" ] || continue
        f=${f%.conf}
        printf '%s\n' "${f##*/}"
    done
}

lip_next_name() {
    local i=1
    while [ -e "$LIP_DIR/lip$i.conf" ]; do i=$((i + 1)); done
    printf 'lip%s' "$i"
}

v_new_lip() {
    is_lip_name "$1" || {
        err "Use 1-10 characters: a-z, 0-9"
        return 1
    }
    [ -e "$LIP_DIR/$1.conf" ] && {
        err "Local IP '$1' already exists"
        return 1
    }
    return 0
}

v_remote_ip() {
    is_ipv4 "$1" || {
        err "Enter a valid IPv4"
        return 1
    }
    [ "$1" = "${L[LOCAL]}" ] && {
        err "$(lip_other) IP must differ from $(lip_me) IP"
        return 1
    }
    return 0
}

v_iface() { ip link show "$1" >/dev/null 2>&1; }
lip_me() { if [ "${L[ROLE]}" = iran ]; then printf 'Iran'; else printf 'Kharej'; fi; }
lip_other() { if [ "${L[ROLE]}" = iran ]; then printf 'Kharej'; else printf 'Iran'; fi; }

lip_mtu_calc() {
    local dev=${L[DEV]:-$(default_iface)} m=1500 o=24
    [ -n "$dev" ] && [ -r "/sys/class/net/$dev/mtu" ] && m=$(cat "/sys/class/net/$dev/mtu")
    case ${L[TYPE]} in
        sit) o=20 ;;
        vxlan) o=50 ;;
    esac
    LIP_MTU_MAX=9000
    [ "${L[TYPE]}" = vxlan ] && LIP_MTU_MAX=$((m - o))
    L[MTU]=$((m - o))
    ((L[MTU] < 1280)) && L[MTU]=1280
    ((L[MTU] > LIP_MTU_MAX)) && L[MTU]=$LIP_MTU_MAX
}

v_lip_mtu() { num_range "$1" 1280 "$LIP_MTU_MAX"; }

lip_suggest() {
    local lo=$1 hi=$2 h x y z t=0 p6
    if [[ $lo > $hi ]]; then
        x=$lo
        lo=$hi
        hi=$x
    fi
    h=$(printf '%s|%s' "$lo" "$hi" | sha256sum | cut -c1-24)
    x=$((16#${h:0:2} % 200 + 30))
    y=$((16#${h:2:2}))
    z=$((16#${h:4:2} & 252))
    while ip -4 addr show 2>/dev/null | grep -q "inet 10\.$x\.$y\." && ((t < 64)); do
        y=$(((y + 1) % 256))
        t=$((t + 1))
    done
    p6="fd${h:6:2}:${h:8:4}:${h:12:4}:${h:16:4}"
    if [ "${L[ROLE]}" = iran ]; then
        SUG_MY4="10.$x.$y.$((z + 1))/30"
        SUG_PEER4="10.$x.$y.$((z + 2))"
        SUG_MY6="$p6::1/64"
        SUG_PEER6="$p6::2"
    else
        SUG_MY4="10.$x.$y.$((z + 2))/30"
        SUG_PEER4="10.$x.$y.$((z + 1))"
        SUG_MY6="$p6::2/64"
        SUG_PEER6="$p6::1"
    fi
    SUG_VNI=$((16#${h:20:4} + 100))
}

lip_script() {
    cat <<EOF
#!/usr/bin/env bash
IFACE="${L[IFACE]}"
TYPE="${L[TYPE]}"
LOCAL="${L[LOCAL]}"
REMOTE="${L[REMOTE]}"
V4="${L[V4]}"
V6="${L[V6]}"
MTU="${L[MTU]}"
VNI="${L[VNI]}"
DPORT="${L[DPORT]}"
DEV="${L[DEV]}"
down() {
    ip link show "\$IFACE" >/dev/null 2>&1 && ip link del "\$IFACE"
    return 0
}
up() {
    down
    case "\$TYPE" in
        gre)
            modprobe ip_gre 2>/dev/null
            ip tunnel add "\$IFACE" mode gre local "\$LOCAL" remote "\$REMOTE" ttl 255 || return 1
            ;;
        sit)
            modprobe sit 2>/dev/null
            ip tunnel add "\$IFACE" mode sit local "\$LOCAL" remote "\$REMOTE" ttl 255 || return 1
            ;;
        vxlan)
            modprobe vxlan 2>/dev/null
            ip link add "\$IFACE" type vxlan id "\$VNI" local "\$LOCAL" remote "\$REMOTE" dstport "\$DPORT" \${DEV:+dev "\$DEV"} || return 1
            ;;
    esac
    ip link set "\$IFACE" mtu "\$MTU" || return 1
    [ -z "\$V6" ] || sysctl -qw "net.ipv6.conf.\$IFACE.disable_ipv6=0" 2>/dev/null
    [ -z "\$V4" ] || ip addr add "\$V4" dev "\$IFACE" || return 1
    [ -z "\$V6" ] || ip -6 addr add "\$V6" dev "\$IFACE" || return 1
    ip link set "\$IFACE" up
}
case "\$1" in
    up) up ;;
    down) down ;;
    restart)
        down
        up
        ;;
    *)
        echo "usage: \$0 up|down|restart"
        exit 1
        ;;
esac
EOF
}

lip_unit() {
    cat <<EOF
[Unit]
Description=FRP Tunnel local IP ${L[NAME]} (${L[TYPE]})
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
$(fw_exec_pre --fw-sync-lip "${L[NAME]}")
ExecStart=$LIP_DIR/${L[NAME]}.sh up
ExecStop=$LIP_DIR/${L[NAME]}.sh down

[Install]
WantedBy=multi-user.target
EOF
}

lip_apply() {
    local k n=${L[NAME]}
    for k in "${LIP_KEYS[@]}"; do
        printf '%s=%s\n' "$k" "${L[$k]}"
    done >"$LIP_DIR/$n.conf"
    lip_script >"$LIP_DIR/$n.sh"
    chmod 600 "$LIP_DIR/$n.conf"
    chmod 755 "$LIP_DIR/$n.sh"
    lip_unit >"$UNIT_DIR/frp-lip-$n.service"
    fw_lip_apply "$n" sync
    systemctl daemon-reload >/dev/null 2>&1
    systemctl enable "frp-lip-$n.service" >/dev/null 2>&1
    systemctl restart "frp-lip-$n.service" >/dev/null 2>&1
    sleep 1
    if ip link show "${L[IFACE]}" 2>/dev/null | grep -q 'UP'; then
        ok "Interface ${L[IFACE]} is up"
        return 0
    fi
    err "Interface ${L[IFACE]} did not come up"
    journalctl -u "frp-lip-$n.service" -n 6 --no-pager -o cat 2>/dev/null | sed 's/^/    /'
    return 1
}

lip_ping() {
    local ok6=1 ok4=1 tf
    tf=$(mktemp)
    if [ -n "${L[PEER4]}" ]; then
        info "Ping ${L[PEER4]} ..."
        if ping -c 4 -W 2 "${L[PEER4]}" >"$tf" 2>&1; then
            ok "Reply from ${L[PEER4]}, rtt min/avg/max $(grep -E 'rtt|round-trip' "$tf" | sed 's/.*= //' | cut -d/ -f1-3) ms"
            ok4=0
        else
            err "No reply from ${L[PEER4]}"
        fi
    fi
    if [ -n "${L[PEER6]}" ]; then
        info "Ping ${L[PEER6]} ..."
        if ping -6 -c 4 -W 2 "${L[PEER6]}" >"$tf" 2>&1 || ping6 -c 4 -W 2 "${L[PEER6]}" >"$tf" 2>&1; then
            ok "Reply from ${L[PEER6]}, rtt min/avg/max $(grep -E 'rtt|round-trip' "$tf" | sed 's/.*= //' | cut -d/ -f1-3) ms"
            ok6=0
        else
            err "No reply from ${L[PEER6]}"
        fi
    fi
    rm -f "$tf"
    if [ "$ok4" = 1 ] && [ "$ok6" = 1 ]; then
        warn "Make sure the same local IP is created on the $(lip_other) server"
    fi
}

lip_create() {
    local c d
    header "CREATE LOCAL IP"
    L=()
    ask "L[NAME]" "Local IP name" "$(lip_next_name)" v_new_lip "-"
    choose c "Local IP type" 1 "GRE (IPv4)" "SIT / 6to4 (IPv6)" "VXLAN (IPv4)"
    case $c in
        1)
            L[TYPE]=gre
            L[IFACE]="fgre-${L[NAME]}"
            ;;
        2)
            L[TYPE]=sit
            L[IFACE]="fsit-${L[NAME]}"
            ;;
        3)
            L[TYPE]=vxlan
            L[IFACE]="fvx-${L[NAME]}"
            ;;
    esac
    choose c "This server is" 1 "Iran" "Kharej"
    if [ "$c" = 1 ]; then L[ROLE]=iran; else L[ROLE]=foreign; fi
    section "Public IPs"
    ask "L[LOCAL]" "$(lip_me) IP" "$(detect_ip4)" is_ipv4 "Enter a valid IPv4"
    ip -4 addr show 2>/dev/null | grep -q "inet ${L[LOCAL]}/" || warn "${L[LOCAL]} is not assigned to any interface here"
    ask "L[REMOTE]" "$(lip_other) IP" "" v_remote_ip "-"
    lip_suggest "${L[LOCAL]}" "${L[REMOTE]}"
    section "Local IPs"
    info "Suggested values match on both servers automatically"
    if [ "${L[TYPE]}" != sit ]; then
        ask "L[V4]" "$(lip_me) local IPv4" "$SUG_MY4" v_addr4 "Enter an IPv4 like 10.20.30.1/30"
        [[ ${L[V4]} == */* ]] || L[V4]="${L[V4]}/30"
        ask "L[PEER4]" "$(lip_other) local IPv4" "$SUG_PEER4" is_ipv4 "Enter a valid IPv4"
        if confirm "Add IPv6 too?" n; then
            ask "L[V6]" "$(lip_me) local IPv6" "$SUG_MY6" v_addr6 "Enter an IPv6 like fd00:1::1/64"
            ask "L[PEER6]" "$(lip_other) local IPv6" "$SUG_PEER6" is_ipv6 "Enter a valid IPv6"
        fi
    else
        ask "L[V6]" "$(lip_me) local IPv6" "$SUG_MY6" v_addr6 "Enter an IPv6 like fd00:1::1/64"
        ask "L[PEER6]" "$(lip_other) local IPv6" "$SUG_PEER6" is_ipv6 "Enter a valid IPv6"
    fi
    [ -n "${L[V6]}" ] && [[ ${L[V6]} != */* ]] && L[V6]="${L[V6]}/64"
    section "Link"
    if [ "${L[TYPE]}" = vxlan ]; then
        ask "L[VNI]" "VXLAN ID" "$SUG_VNI" v_vni "Enter a number from 1 to 16777215"
        ask "L[DPORT]" "VXLAN UDP port" "4789" is_port "Port must be between 1 and 65535"
        d=$(default_iface)
        ask "L[DEV]" "Network interface" "$d" v_iface "Interface not found"
    fi
    lip_mtu_calc
    if ((LIP_MTU_MAX < 1280)); then
        err "The interface MTU is too small for ${L[TYPE]}"
        pause
        return
    fi
    ask "L[MTU]" "MTU" "${L[MTU]}" v_lip_mtu "Enter a number from 1280 to $LIP_MTU_MAX"
    L[CREATED]=$(date '+%F %T')
    section "Summary"
    kv "Name / interface" "${L[NAME]} / ${L[IFACE]}"
    kv "Type" "${L[TYPE]}"
    kv "$(lip_me) IP" "${L[LOCAL]}"
    kv "$(lip_other) IP" "${L[REMOTE]}"
    [ -n "${L[V4]}" ] && kv "Local IPv4" "${L[V4]}, $(lip_other) ${L[PEER4]}"
    [ -n "${L[V6]}" ] && kv "Local IPv6" "${L[V6]}, $(lip_other) ${L[PEER6]}"
    kv "MTU" "${L[MTU]}"
    [ "${L[TYPE]}" = vxlan ] && kv "VXLAN" "id ${L[VNI]}, port ${L[DPORT]}, dev ${L[DEV]}"
    blank
    if ! confirm "Create this local IP?" y; then
        warn "Cancelled"
        pause
        return
    fi
    blank
    if lip_apply; then
        info "Run the same setup on the $(lip_other) server, the suggested values will match"
        confirm "Test with ping now?" y && lip_ping
    fi
    pause
}

lip_table() {
    local i n st a p
    mapfile -t LNAMES < <(lip_names)
    if ((${#LNAMES[@]} == 0)); then
        info "No local IPs yet"
        return 1
    fi
    cnext
    printf '  \e[1;38;5;%sm%-3s %-10s %-6s %-23s %-23s %s\e[0m\n' "$NC" "#" "NAME" "TYPE" "THIS SERVER" "OTHER SERVER" "STATE"
    for i in "${!LNAMES[@]}"; do
        lip_load_file "$LIP_DIR/${LNAMES[i]}.conf" || continue
        if ip link show "${L[IFACE]}" 2>/dev/null | grep -q 'UP'; then st=up; else st=down; fi
        cnext
        a=${L[V4]%/*}
        p=${L[PEER4]}
        [ -z "$a" ] && a=${L[V6]%/*} && p=${L[PEER6]}
        printf '  \e[38;5;%sm%-3s %-10s %-6s %-23s %-23s\e[0m \e[38;5;%sm%s\e[0m\n' "$NC" "$((i + 1))" "${L[NAME]}" "${L[TYPE]}" "$a" "$p" "$([ $st = up ] && echo "$C_OK" || echo "$C_ERR")" "$st"
        if [ -n "${L[V4]}" ] && [ -n "${L[V6]}" ]; then
            printf '  \e[38;5;%sm%-3s %-10s %-6s %-23s %-23s\e[0m\n' "$NC" "" "" "" "${L[V6]%/*}" "${L[PEER6]}"
        fi
    done
    return 0
}

pick_lip() {
    local __n=$1 __i __c
    cnext
    __c=$NC
    blank
    while :; do
        prompt "$__c" "Local IP number, 0 to go back" ""
        read_line __i
        [ "$__i" = 0 ] && return 1
        if [[ $__i =~ ^[0-9]{1,3}$ ]] && ((10#$__i >= 1 && 10#$__i <= ${#LNAMES[@]})); then
            printf -v "$__n" '%s' "${LNAMES[10#$__i - 1]}"
            return 0
        fi
        err "Enter a number from the list"
    done
}

lip_users() {
    local m out=""
    for m in "$TUN_DIR"/*/tunnel.conf; do
        [ -f "$m" ] || continue
        grep -qx "LIP=$1" "$m" && out+="$(sed -n 's/^NAME=//p' "$m" | head -n 1) "
    done
    printf '%s' "${out% }"
}

lip_menu() {
    local c n u
    while :; do
        header "LOCAL IP"
        lip_table
        blank
        item 1 "Create local IP"
        item 2 "Ping test"
        item 3 "Restart local IP"
        item 4 "Delete local IP"
        item 0 "Back"
        menu_pick c 4
        case $c in
            1) lip_create ;;
            2 | 3 | 4)
                ((${#LNAMES[@]})) || {
                    warn "No local IPs yet"
                    pause
                    continue
                }
                pick_lip n || continue
                lip_load_file "$LIP_DIR/$n.conf" || continue
                blank
                case $c in
                    2) lip_ping ;;
                    3)
                        if systemctl restart "frp-lip-$n.service" >/dev/null 2>&1; then ok "Local IP '$n' restarted"; else err "Restart failed"; fi
                        ;;
                    4)
                        u=$(lip_users "$n")
                        [ -n "$u" ] && warn "Used by tunnels: $u"
                        if confirm "Delete local IP '$n'?" n; then
                            fw_lip_apply "$n" clear q
                            systemctl disable --now "frp-lip-$n.service" >/dev/null 2>&1
                            [ -x "$LIP_DIR/$n.sh" ] && "$LIP_DIR/$n.sh" down
                            rm -f "$UNIT_DIR/frp-lip-$n.service" "$LIP_DIR/$n.conf" "$LIP_DIR/$n.sh"
                            systemctl daemon-reload >/dev/null 2>&1
                            ok "Local IP '$n' deleted"
                        fi
                        ;;
                esac
                pause
                ;;
            0) return ;;
        esac
    done
}

net_bbr() {
    modprobe tcp_bbr 2>/dev/null
    if ! grep -qw bbr /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
        err "BBR is not supported by this kernel ($(uname -r))"
        return 1
    fi
    printf 'net.core.default_qdisc = fq\nnet.ipv4.tcp_congestion_control = bbr\n' >"$BBR_FILE"
    printf 'tcp_bbr\n' >"$BBR_MOD_FILE"
    sysctl -e -p "$BBR_FILE" >/dev/null 2>&1
    if [ "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)" = bbr ]; then
        ok "BBR enabled"
    else
        err "Could not enable BBR"
    fi
}

net_sysctl() {
    cat >"$SYSCTL_FILE" <<'EOF'
fs.file-max = 2097152
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 250000
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.rmem_default = 1048576
net.core.wmem_default = 1048576
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5
EOF
    if sysctl -e -p "$SYSCTL_FILE" >/dev/null 2>&1; then
        ok "Sysctl tuning applied"
    else
        warn "Sysctl tuning saved, some keys are not supported here"
    fi
}

net_ulimit() {
    printf '* soft nofile 1048576\n* hard nofile 1048576\nroot soft nofile 1048576\nroot hard nofile 1048576\n' >"$LIMITS_FILE"
    mkdir -p "${SDLIMIT_FILE%/*}"
    printf '[Manager]\nDefaultLimitNOFILE=1048576\n' >"$SDLIMIT_FILE"
    systemctl daemon-reexec >/dev/null 2>&1
    ok "Open files limit raised to 1048576, new sessions will use it"
}

net_revert() {
    rm -f "$SYSCTL_FILE" "$BBR_FILE" "$BBR_MOD_FILE" "$LIMITS_FILE" "$SDLIMIT_FILE"
    sysctl --system >/dev/null 2>&1
    systemctl daemon-reexec >/dev/null 2>&1
    ok "Network optimizations removed, a reboot restores kernel defaults"
}

net_menu() {
    local c
    while :; do
        header "NETWORK OPTIMIZE"
        kv "Congestion control" "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)"
        kv "Queue discipline" "$(sysctl -n net.core.default_qdisc 2>/dev/null)"
        kv "Sysctl tuning" "$([ -f "$SYSCTL_FILE" ] && echo applied || echo 'not applied')"
        kv "Open files limit" "$([ -f "$LIMITS_FILE" ] && echo 1048576 || ulimit -n)"
        blank
        item 1 "Enable BBR"
        item 2 "Apply sysctl tuning"
        item 3 "Raise ulimit"
        item 4 "Apply all"
        item 5 "Revert all"
        item 0 "Back"
        menu_pick c 5
        blank
        case $c in
            1) net_bbr ;;
            2) net_sysctl ;;
            3) net_ulimit ;;
            4)
                net_bbr
                net_sysctl
                net_ulimit
                ;;
            5) confirm "Remove all network optimizations?" n && net_revert ;;
            0) return ;;
        esac
        pause
    done
}

wd_load() {
    WD_INTERVAL=60
    WD_FAILS=3
    if [ -f "$WD_CONF" ]; then
        local v
        v=$(sed -n 's/^INTERVAL=//p' "$WD_CONF" | head -n 1)
        v_interval "$v" && WD_INTERVAL=$v
        v=$(sed -n 's/^FAILS=//p' "$WD_CONF" | head -n 1)
        v_fails "$v" && WD_FAILS=$v
    fi
}

wd_enable() {
    write_hooks
    printf 'INTERVAL=%s\nFAILS=%s\n' "$WD_INTERVAL" "$WD_FAILS" >"$WD_CONF"
    cat >"$UNIT_DIR/frp-tunnel-watchdog.service" <<EOF
[Unit]
Description=FRP Tunnel watchdog

[Service]
Type=oneshot
ExecStart=$HOOK_DIR/watchdog.sh
EOF
    cat >"$UNIT_DIR/frp-tunnel-watchdog.timer" <<EOF
[Unit]
Description=FRP Tunnel watchdog timer

[Timer]
OnActiveSec=60
OnUnitActiveSec=$WD_INTERVAL
AccuracySec=5

[Install]
WantedBy=timers.target
EOF
    systemctl daemon-reload >/dev/null 2>&1
    if systemctl enable frp-tunnel-watchdog.timer >/dev/null 2>&1 && systemctl restart frp-tunnel-watchdog.timer >/dev/null 2>&1; then
        ok "Watchdog enabled, checks every ${WD_INTERVAL}s"
        info "Stopped tunnels are left alone, only failed or unhealthy ones are restarted"
    else
        err "Could not enable the watchdog timer"
    fi
}

wd_disable() {
    systemctl disable --now frp-tunnel-watchdog.timer >/dev/null 2>&1
    rm -f "$UNIT_DIR/frp-tunnel-watchdog.timer" "$UNIT_DIR/frp-tunnel-watchdog.service"
    systemctl daemon-reload >/dev/null 2>&1
    ok "Watchdog disabled"
}

wd_menu() {
    local c st
    while :; do
        wd_load
        header "WATCHDOG"
        st=$(svc_state frp-tunnel-watchdog.timer)
        cnext
        printf '  \e[38;5;%sm%-20s\e[0m \e[38;5;%sm%s\e[0m\n' "$NC" "Status" "$(state_color "$st")" "$st"
        kv "Check interval" "${WD_INTERVAL}s"
        kv "Restart after" "$WD_FAILS failed checks"
        kv "Checks" "service state + FRP admin API"
        blank
        item 1 "Enable"
        item 2 "Disable"
        item 3 "Settings"
        item 4 "View log"
        item 0 "Back"
        menu_pick c 4
        blank
        case $c in
            1) wd_enable ;;
            2) wd_disable ;;
            3)
                ask WD_INTERVAL "Check interval sec" "$WD_INTERVAL" v_interval "Enter a number from 10 to 3600"
                ask WD_FAILS "Failed checks before restart" "$WD_FAILS" v_fails "Enter a number from 1 to 20"
                printf 'INTERVAL=%s\nFAILS=%s\n' "$WD_INTERVAL" "$WD_FAILS" >"$WD_CONF"
                if [ -f "$UNIT_DIR/frp-tunnel-watchdog.timer" ]; then wd_enable; else ok "Settings saved"; fi
                ;;
            4)
                if [ -s "$LOG_DIR/watchdog.log" ]; then tail -n 40 "$LOG_DIR/watchdog.log"; else info "Watchdog log is empty"; fi
                ;;
            0) return ;;
        esac
        pause
    done
}

backup_list() {
    BNAMES=()
    local f
    for f in "$BACKUP_DIR"/frp-tunnel-*.tar.gz; do
        [ -f "$f" ] && BNAMES+=("$f")
    done
    ((${#BNAMES[@]} > 0))
}

backup_create() {
    local f u
    local -a items=()
    mkdir -p "$BACKUP_DIR"
    chmod 700 "$BACKUP_DIR"
    f="$BACKUP_DIR/frp-tunnel-$(date +%Y%m%d-%H%M%S).tar.gz"
    [ -d "$BASE_DIR" ] && items+=("${BASE_DIR#/}")
    for u in "$UNIT_DIR"/frp-*.service "$UNIT_DIR"/frp-tunnel-*.timer; do
        [ -f "$u" ] && items+=("${u#/}")
    done
    for u in "$SYSCTL_FILE" "$BBR_FILE" "$BBR_MOD_FILE" "$LIMITS_FILE" "$SDLIMIT_FILE"; do
        [ -f "$u" ] && items+=("${u#/}")
    done
    if acme_installed && confirm "Include acme.sh data?" y; then
        items+=("${ACME_HOME#/}")
    fi
    if ((${#items[@]} == 0)); then
        warn "Nothing to back up"
        return 1
    fi
    if tar -czf "$f" -C / "${items[@]}" 2>/dev/null; then
        chmod 600 "$f"
        ok "Backup saved: $f ($(du -h "$f" | cut -f1))"
        return 0
    fi
    rm -f "$f"
    err "Backup failed"
    return 1
}

backup_safe() {
    local e r='^(etc/frp-tunnel(/.*)?|etc/systemd/system/frp-[A-Za-z0-9.-]+\.(service|timer)|etc/sysctl\.d/99-frp-tunnel(-bbr)?\.conf|etc/modules-load\.d/frp-tunnel-bbr\.conf|etc/security/limits\.d/99-frp-tunnel\.conf|etc/systemd/system\.conf\.d/99-frp-tunnel\.conf|root/\.acme\.sh(/.*)?)$'
    tar -tzf "$1" >/dev/null 2>&1 || return 1
    while IFS= read -r e; do
        [[ $e == *..* ]] && return 1
        [[ $e =~ $r ]] || return 1
    done < <(tar -tzf "$1" 2>/dev/null)
    return 0
}

backup_restore() {
    local i c f n
    if backup_list; then
        section "Backups"
        for i in "${!BNAMES[@]}"; do
            item "$((i + 1))" "${BNAMES[i]##*/}  $(du -h "${BNAMES[i]}" | cut -f1)"
        done
        item "$((${#BNAMES[@]} + 1))" "Other file"
        menu_pick c "$((${#BNAMES[@]} + 1))"
        [ "$c" = 0 ] && return
        if ((c <= ${#BNAMES[@]})); then f=${BNAMES[c - 1]}; else ask f "Backup file path" "" is_path "File not found"; fi
    else
        ask f "Backup file path" "" is_path "File not found"
    fi
    if ! backup_safe "$f"; then
        err "This is not a valid FRP Tunnel backup"
        return 1
    fi
    confirm "Current configs will be overwritten. Continue?" n || return 0
    while read -r n; do
        [ -n "$n" ] && systemctl stop "frp-$n.service" >/dev/null 2>&1
    done < <(tunnel_names)
    if ! tar -xzf "$f" -C / 2>/dev/null; then
        err "Restore failed"
        return 1
    fi
    write_hooks
    systemctl daemon-reload >/dev/null 2>&1
    while read -r n; do
        [ -n "$n" ] || continue
        systemctl enable "frp-lip-$n.service" >/dev/null 2>&1
        systemctl restart "frp-lip-$n.service" >/dev/null 2>&1
    done < <(lip_names)
    if frp_installed; then
        while read -r n; do
            [ -n "$n" ] || continue
            systemctl enable "frp-$n.service" >/dev/null 2>&1
            systemctl restart "frp-$n.service" >/dev/null 2>&1
        done < <(tunnel_names)
    else
        warn "FRP is not installed. Install it to start the restored tunnels."
    fi
    for n in frp-tunnel-watchdog.timer frp-tunnel-acme.timer; do
        [ -f "$UNIT_DIR/$n" ] && systemctl enable --now "$n" >/dev/null 2>&1
    done
    sysctl --system >/dev/null 2>&1
    ok "Backup restored"
}

backup_menu() {
    local c i
    while :; do
        header "BACKUP & RESTORE"
        if backup_list; then kv "Backups" "${#BNAMES[@]} in $BACKUP_DIR"; else kv "Backups" "none"; fi
        blank
        item 1 "Create backup"
        item 2 "Restore backup"
        item 3 "Delete backup"
        item 0 "Back"
        menu_pick c 3
        blank
        case $c in
            1) backup_create ;;
            2) backup_restore ;;
            3)
                if backup_list; then
                    for i in "${!BNAMES[@]}"; do item "$((i + 1))" "${BNAMES[i]##*/}"; done
                    menu_pick i "${#BNAMES[@]}"
                    if [ "$i" != 0 ] && confirm "Delete ${BNAMES[i - 1]##*/}?" n; then
                        rm -f "${BNAMES[i - 1]}"
                        ok "Backup deleted"
                    fi
                else
                    info "No backups"
                fi
                ;;
            0) return ;;
        esac
        pause
    done
}

uninstall_all() {
    local n u
    header "UNINSTALL"
    warn "This removes all tunnels, local IPs, certificates, services and FRP binaries."
    confirm "Continue?" n || return
    confirm "Create a backup first?" y && backup_create
    while read -r n; do
        [ -n "$n" ] && tunnel_remove "$n"
    done < <(tunnel_names)
    while read -r n; do
        [ -n "$n" ] || continue
        fw_lip_apply "$n" clear q
        systemctl disable --now "frp-lip-$n.service" >/dev/null 2>&1
        [ -x "$LIP_DIR/$n.sh" ] && "$LIP_DIR/$n.sh" down
        rm -f "$UNIT_DIR/frp-lip-$n.service"
    done < <(lip_names)
    for u in frp-tunnel-watchdog.timer frp-tunnel-watchdog.service frp-tunnel-acme.timer frp-tunnel-acme.service; do
        systemctl disable --now "$u" >/dev/null 2>&1
        rm -f "$UNIT_DIR/$u"
    done
    systemctl daemon-reload >/dev/null 2>&1
    if acme_installed && confirm "Remove acme.sh too?" n; then
        "$ACME_HOME/acme.sh" --uninstall --home "$ACME_HOME" >/dev/null 2>&1
        rm -rf "$ACME_HOME"
    fi
    if [ -f "$SYSCTL_FILE" ] || [ -f "$BBR_FILE" ] || [ -f "$LIMITS_FILE" ]; then
        confirm "Remove network optimizations?" n && net_revert
    fi
    fw_sync "frp-tunnel-acme" "$CERT_DIR/le/port80.fw" q
    rm -rf "${BASE_DIR:?}" "$LOG_DIR" "$WD_STATE"
    rm -f "$FRPS_BIN" "$FRPC_BIN" "$SELF_BIN"
    ok "FRP Tunnel has been removed"
    [ -d "$BACKUP_DIR" ] && info "Backups are kept in $BACKUP_DIR"
    printf '\e[0m\n'
    exit 0
}

main_menu() {
    local c
    header
    cert_brief
    blank
    item 1 "Install / Update FRP"
    item 2 "Create tunnel"
    item 3 "Multi-protocol tunnel"
    item 4 "Tunnels"
    item 5 "Edit tunnel"
    item 6 "Delete tunnel"
    item 7 "Service control"
    item 8 "Logs & status"
    item 9 "Local IP"
    item 10 "Certificates"
    item 11 "Network optimize"
    item 12 "Watchdog"
    item 13 "Backup & restore"
    item 14 "Uninstall"
    item 0 "Exit"
    menu_pick c 14
    case $c in
        1) frp_menu ;;
        2) tunnel_create ;;
        3) multi_menu ;;
        4) tunnels_menu ;;
        5) tunnel_edit ;;
        6) tunnel_delete ;;
        7) svc_menu ;;
        8) logs_menu ;;
        9) lip_menu ;;
        10) cert_menu ;;
        11) net_menu ;;
        12) wd_menu ;;
        13) backup_menu ;;
        14) uninstall_all ;;
        0)
            printf '\e[0m\n'
            exit 0
            ;;
    esac
}

usage() {
    printf 'FRP Tunnel v%s\n\nUsage: frp-tunnel [option]\n\n  -h, --help       Show this help\n  -v, --version    Show version\n\nRun without options to open the menu.\n' "$APP_VER"
}

main() {
    case $1 in
        --fw-sync)
            [ "$(id -u)" -eq 0 ] && is_name "$2" && fw_cli "$1" "$2"
            exit 0
            ;;
        --fw-sync-lip)
            [ "$(id -u)" -eq 0 ] && is_lip_name "$2" && fw_cli "$1" "$2"
            exit 0
            ;;
        -v | --version)
            printf '%s\n' "$APP_VER"
            exit 0
            ;;
        -h | --help)
            usage
            exit 0
            ;;
    esac
    if [ "$(id -u)" -ne 0 ]; then
        err "Please run as root"
        exit 1
    fi
    command -v systemctl >/dev/null 2>&1 || {
        err "systemd is required"
        exit 1
    }
    trap on_int INT
    check_os
    ensure_deps
    init_dirs
    self_install
    write_hooks
    while :; do
        main_menu
    done
}

if [[ ${BASH_SOURCE[0]:-$0} == "$0" ]]; then
    main "$@"
fi
