#!/usr/bin/env bash
# SubRaptor installer
# Checks dependencies and installs whatever is missing from official sources:
#   - system packages (curl, jq, coreutils, column, getent) via apt / dnf / pacman
#   - Go from go.dev (SHA256-verified) if missing or older than 1.21
#   - subfinder, assetfinder via `go install` (upstream repositories)
#   - subraptor and subraptor-lite into ~/.local/bin
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
SELF_NAMES=(subraptor subraptor-lite)
LEGACY_NAME="subraptor-ng"
RC_MARKER="# added by subraptor installer"
CHECK_ONLY=0
ASSUME_YES=0

ORIG_PATH="$PATH"
export PATH="$HOME/go/bin:/usr/local/go/bin:$BIN_DIR:$PATH"

if [ -t 1 ]; then
    B=$'\e[1m'; G=$'\e[32m'; R=$'\e[31m'; Y=$'\e[33m'; C=$'\e[36m'; D=$'\e[2m'; N=$'\e[0m'
else
    B=""; G=""; R=""; Y=""; C=""; D=""; N=""
fi

info() { printf '%s[*]%s %s\n' "$C" "$N" "$*"; }
ok()   { printf '%s[+]%s %s\n' "$G" "$N" "$*"; }
warn() { printf '%s[!]%s %s\n' "$Y" "$N" "$*" >&2; }
die()  { printf '%s[x]%s %s\n' "$R" "$N" "$*" >&2; exit 1; }

usage() {
    cat <<EOF
${B}SubRaptor installer${N}

Usage: $(basename "$0") [options]

Options:
  -c    Check only: show what is installed/missing, change nothing
  -y    Assume "yes" to every confirmation
  -h    Show this help

Run it as a normal user (sudo is requested only when needed).
Place it in the same folder as subraptor.sh and subraptor-lite.sh.
EOF
    exit "${1:-0}"
}

while getopts ":cyh" opt; do
    case "$opt" in
        c) CHECK_ONLY=1 ;;
        y) ASSUME_YES=1 ;;
        h) usage 0 ;;
        *) usage 1 ;;
    esac
done

[ "$(id -u)" -ne 0 ] || die "Do not run as root: Go tools would end up in root's home. Run as a normal user."
[ "$(uname -s)" = "Linux" ] || die "Linux only (SubRaptor relies on getent, timeout and mapfile)."

# Package manager detection
PM=""
if   command -v apt-get >/dev/null 2>&1; then PM="apt"
elif command -v dnf     >/dev/null 2>&1; then PM="dnf"
elif command -v pacman  >/dev/null 2>&1; then PM="pacman"
fi
SUDO=""
command -v sudo >/dev/null 2>&1 && SUDO="sudo"

BASE_CMDS=(curl jq timeout column getent)
GO_TOOLS=(subfinder assetfinder)

tool_spec() {
    case "$1" in
        subfinder)   echo "github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest" ;;
        assetfinder) echo "github.com/tomnomnom/assetfinder@latest" ;;
    esac
}

pkg_for() {
    case "$PM:$1" in
        *:curl)          echo curl ;;
        *:jq)            echo jq ;;
        *:timeout)       echo coreutils ;;
        apt:getent)      echo libc-bin ;;
        dnf:getent)      echo glibc-common ;;
        pacman:getent)   echo glibc ;;
        apt:column)      echo bsdextrautils ;;
        *:column)        echo util-linux ;;
    esac
}

# Go >= 1.21 (newer toolchains are fetched automatically by `go install` when a module needs them)
go_ok() {
    command -v go >/dev/null 2>&1 || return 1
    local v major minor
    v="$(go version 2>/dev/null | sed -nE 's/.*go([0-9]+)\.([0-9]+).*/\1 \2/p')"
    [ -n "$v" ] || return 1
    read -r major minor <<< "$v"
    [ "$major" -gt 1 ] || { [ "$major" -eq 1 ] && [ "$minor" -ge 21 ]; }
}

confirm() {
    [ "$ASSUME_YES" -eq 1 ] && return 0
    local a
    read -r -p "$1 [y/N] " a || return 1
    [[ "$a" =~ ^[yY]$ ]]
}

row() { printf '  %-14s %-10s %s\n' "$1" "$2" "$3"; }


# ── Status ────────────────────────────────────────────────────────────────
MISSING_BASE=(); MISSING_TOOLS=(); NEED_GO=0; SELF_TODO=(); LEGACY_FOUND=0

printf '\n%s%s%s\n' "$B" "SubRaptor installer" "$N"
printf '%s──────────────────────────────────────────────────%s\n' "$D" "$N"
printf '  %s%-14s %-10s %s%s\n' "$B" "COMPONENT" "STATUS" "DETAILS" "$N"

for c in "${BASE_CMDS[@]}"; do
    if command -v "$c" >/dev/null 2>&1; then
        row "$c" "${G}ok${N}" "$(command -v "$c")"
    else
        row "$c" "${Y}missing${N}" "system package"
        MISSING_BASE+=("$c")
    fi
done

if go_ok; then
    row "go" "${G}ok${N}" "$(go version | awk '{print $3}')"
elif command -v go >/dev/null 2>&1; then
    row "go" "${Y}too old${N}" "$(go version | awk '{print $3}') (need >= 1.21)"; NEED_GO=1
else
    row "go" "${Y}missing${N}" "official tarball (go.dev)"; NEED_GO=1
fi

for t in "${GO_TOOLS[@]}"; do
    if command -v "$t" >/dev/null 2>&1; then
        row "$t" "${G}ok${N}" "$(command -v "$t")"
    else
        row "$t" "${Y}missing${N}" "go install"
        MISSING_TOOLS+=("$t")
    fi
done

for n in "${SELF_NAMES[@]}"; do
    src="$SCRIPT_DIR/$n.sh"
    if [ ! -f "$src" ]; then
        row "$n" "${R}no source${N}" "$n.sh not found next to install.sh"
    elif [ -x "$BIN_DIR/$n" ] && cmp -s "$src" "$BIN_DIR/$n"; then
        row "$n" "${G}ok${N}" "$BIN_DIR/$n"
    elif [ -x "$BIN_DIR/$n" ]; then
        row "$n" "${Y}outdated${N}" "will update $BIN_DIR/$n"; SELF_TODO+=("$n")
    else
        row "$n" "${Y}missing${N}" "will install to $BIN_DIR"; SELF_TODO+=("$n")
    fi
done
if [ -e "$BIN_DIR/$LEGACY_NAME" ]; then
    row "$LEGACY_NAME" "${Y}legacy${N}" "old name, will be removed"; LEGACY_FOUND=1
fi
printf '%s──────────────────────────────────────────────────%s\n\n' "$D" "$N"

TOTAL_TODO=$(( ${#MISSING_BASE[@]} + ${#MISSING_TOOLS[@]} + NEED_GO + ${#SELF_TODO[@]} + LEGACY_FOUND ))

if [ "$CHECK_ONLY" -eq 1 ]; then
    [ "$TOTAL_TODO" -eq 0 ] && { ok "Everything is in place."; exit 0; }
    warn "$TOTAL_TODO component(s) missing or outdated."; exit 1
fi

if [ "$TOTAL_TODO" -eq 0 ]; then
    ok "Everything is already in place. Nothing to do."
    exit 0
fi

# ── Plan ──────────────────────────────────────────────────────────────────
PKGS=()
for c in "${MISSING_BASE[@]}"; do
    p="$(pkg_for "$c")"
    [ -n "$p" ] || continue
    [[ " ${PKGS[*]-} " == *" $p "* ]] || PKGS+=("$p")
done

if [ "${#MISSING_BASE[@]}" -gt 0 ] && [ -z "$PM" ]; then
    die "No supported package manager (apt/dnf/pacman). Install manually: ${MISSING_BASE[*]}"
fi
if { [ "${#PKGS[@]}" -gt 0 ] || [ "$NEED_GO" -eq 1 ]; } && [ -z "$SUDO" ]; then
    die "sudo is required to install system packages / Go but was not found."
fi

info "Planned actions:"
[ "${#PKGS[@]}" -gt 0 ]          && echo "  - $PM install: ${PKGS[*]}"
[ "$NEED_GO" -eq 1 ]             && echo "  - install latest stable Go from go.dev into /usr/local/go (replaces an existing /usr/local/go)"
[ "${#MISSING_TOOLS[@]}" -gt 0 ] && echo "  - go install: ${MISSING_TOOLS[*]}"
[ "${#SELF_TODO[@]}" -gt 0 ]     && echo "  - copy to $BIN_DIR: ${SELF_TODO[*]}"
[ "$LEGACY_FOUND" -eq 1 ]        && echo "  - remove old $BIN_DIR/$LEGACY_NAME (replaced by subraptor)"
echo
confirm "Proceed?" || die "Aborted."

# ── 1. System packages ────────────────────────────────────────────────────
if [ "${#PKGS[@]}" -gt 0 ]; then
    info "Installing system packages: ${PKGS[*]}"
    case "$PM" in
        apt)
            $SUDO apt-get update -qq
            if ! $SUDO apt-get install -y "${PKGS[@]}"; then
                # older Debian/Ubuntu ship `column` in bsdmainutils instead of bsdextrautils
                $SUDO apt-get install -y "${PKGS[@]/bsdextrautils/bsdmainutils}" \
                    || die "Package installation failed."
            fi ;;
        dnf)    $SUDO dnf install -y "${PKGS[@]}" || die "Package installation failed." ;;
        pacman) $SUDO pacman -S --needed --noconfirm "${PKGS[@]}" || die "Package installation failed." ;;
    esac
    ok "System packages installed"
fi

# ── 2. Go (official tarball, checksum verified) ───────────────────────────
if [ "$NEED_GO" -eq 1 ]; then
    case "$(uname -m)" in
        x86_64)        GOARCH="amd64" ;;
        aarch64|arm64) GOARCH="arm64" ;;
        *) die "Unsupported architecture for the official Go tarball: $(uname -m)" ;;
    esac
    info "Fetching latest stable Go release info from go.dev..."
    line="$(curl -fsSL 'https://go.dev/dl/?mode=json' \
        | jq -r --arg a "$GOARCH" '[.[] | select(.stable)][0].files[]
            | select(.os=="linux" and .arch==$a and .kind=="archive")
            | "\(.filename) \(.sha256)"')" || die "Could not reach go.dev"
    [ -n "$line" ] || die "Could not determine the latest Go release for linux/$GOARCH"
    gofile="${line% *}"; gosha="${line#* }"

    tmpd="$(mktemp -d)"
    info "Downloading $gofile..."
    curl -fSL --progress-bar -o "$tmpd/$gofile" "https://go.dev/dl/$gofile" || { rm -rf "$tmpd"; die "Go download failed"; }
    printf '%s  %s\n' "$gosha" "$tmpd/$gofile" | sha256sum -c --quiet - \
        || { rm -rf "$tmpd"; die "Go checksum mismatch - aborting"; }
    ok "Checksum verified"

    $SUDO rm -rf /usr/local/go && $SUDO tar -C /usr/local -xzf "$tmpd/$gofile" \
        || { rm -rf "$tmpd"; die "Go extraction failed"; }
    rm -rf "$tmpd"
    hash -r
    go_ok || die "Go installed but not usable (check /usr/local/go/bin in PATH)"
    ok "Installed $(go version | awk '{print $3}')"
fi

# ── 3. Go tools ───────────────────────────────────────────────────────────
if [ "${#MISSING_TOOLS[@]}" -gt 0 ]; then
    command -v go >/dev/null 2>&1 && PATH="$(go env GOPATH)/bin:$PATH"
    for t in "${MISSING_TOOLS[@]}"; do
        info "Installing $t (go install)..."
        go install "$(tool_spec "$t")" || warn "Failed to install $t"
    done
    hash -r
fi

# ── 4. SubRaptor scripts ──────────────────────────────────────────────────
if [ "${#SELF_TODO[@]}" -gt 0 ]; then
    mkdir -p "$BIN_DIR"
    for n in "${SELF_TODO[@]}"; do
        install -m 755 "$SCRIPT_DIR/$n.sh" "$BIN_DIR/$n" && ok "Installed $BIN_DIR/$n"
    done
fi
if [ "$LEGACY_FOUND" -eq 1 ]; then
    rm -f "$BIN_DIR/$LEGACY_NAME" && ok "Removed old $BIN_DIR/$LEGACY_NAME"
fi

# ── 5. PATH persistence ───────────────────────────────────────────────────
need_path=0
case ":$ORIG_PATH:" in *":$BIN_DIR:"*) ;; *) need_path=1 ;; esac
case ":$ORIG_PATH:" in *":$HOME/go/bin:"*) ;; *) [ -d "$HOME/go/bin" ] && need_path=1 ;; esac
case ":$ORIG_PATH:" in *":/usr/local/go/bin:"*) ;; *) [ -d /usr/local/go/bin ] && need_path=1 ;; esac

if [ "$need_path" -eq 1 ]; then
    case "${SHELL:-}" in */zsh) RC="$HOME/.zshrc" ;; *) RC="$HOME/.bashrc" ;; esac
    if ! grep -qF -e "$RC_MARKER" -e "# added by subraptor-ng installer" "$RC" 2>/dev/null; then
        if confirm "Add ~/.local/bin, ~/go/bin and /usr/local/go/bin to PATH in $RC?"; then
            {
                echo ""
                echo "$RC_MARKER"
                echo 'export PATH="$HOME/.local/bin:$HOME/go/bin:/usr/local/go/bin:$PATH"'
            } >> "$RC"
            ok "PATH updated in $RC (open a new shell or run: source $RC)"
        else
            warn "Skipped. Add these directories to PATH yourself: $BIN_DIR, ~/go/bin, /usr/local/go/bin"
        fi
    fi
fi

# ── Final verification ────────────────────────────────────────────────────
echo
info "Final check:"
FAIL=0
for c in "${BASE_CMDS[@]}" go "${GO_TOOLS[@]}"; do
    if command -v "$c" >/dev/null 2>&1; then row "$c" "${G}ok${N}" ""; else row "$c" "${R}missing${N}" ""; FAIL=1; fi
done
for n in "${SELF_NAMES[@]}"; do
    [ -x "$BIN_DIR/$n" ] && row "$n" "${G}ok${N}" "" || { row "$n" "${R}missing${N}" ""; FAIL=1; }
done
echo
if [ "$FAIL" -eq 0 ]; then
    ok "All set. Run: subraptor <domain>  (or subraptor-lite <domain>) - no sudo needed"
else
    warn "Some components are still missing - see the messages above."
    exit 1
fi
