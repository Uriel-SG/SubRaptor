#!/usr/bin/env bash
# SubRaptor - passive subdomain aggregator
# Sources: Subfinder, Assetfinder, crt.sh
set -uo pipefail

# Make Go-installed tools visible (also under sudo, where PATH is restricted)
for _h in "$HOME" "$(getent passwd "${SUDO_USER:-}" 2>/dev/null | cut -d: -f6)"; do
    [ -n "$_h" ] && PATH="$_h/go/bin:$PATH"
done
PATH="/usr/local/go/bin:$PATH"
unset _h

VERSION="2.2.0"
ALL_SOURCES=(subfinder assetfinder crtsh)
SOURCES=("${ALL_SOURCES[@]}")
FORMAT="txt"
OUTFILE=""
RESOLVE=0
QUIET=0
THREADS=20
SRC_TIMEOUT=180

# Colors only when stderr is a terminal
if [ -t 2 ]; then
    B=$'\e[1m'; G=$'\e[32m'; R=$'\e[31m'; Y=$'\e[33m'; C=$'\e[36m'; D=$'\e[2m'; N=$'\e[0m'
else
    B=""; G=""; R=""; Y=""; C=""; D=""; N=""
fi

log()  { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*" >&2; }
fail() { printf '%s[!]%s %s\n' "$R" "$N" "$*" >&2; exit 1; }

usage() {
    cat >&2 <<EOF
${B}SubRaptor v${VERSION}${N} - passive subdomain aggregator

Usage: $(basename "$0") [options] <domain>

Gathers subdomains from Subfinder, Assetfinder and crt.sh,
runs them in parallel, then normalizes and deduplicates the results.
Missing tools are skipped automatically.

Options:
  -o <file>    Save results to a file (in addition to stdout)
  -f <fmt>     Output format: txt (default) | json
  -s <list>    Comma-separated sources: subfinder,assetfinder,crtsh (default: all)
  -r           Resolve subdomains (IPv4) and show their IPs
  -t <n>       Threads for resolution (default: $THREADS)
  -T <sec>     Per-source timeout in seconds (default: $SRC_TIMEOUT)
  -q           Quiet: no banner/summary, results only
  -h, --help   Show this help

Examples:
  $(basename "$0") target.com
  $(basename "$0") -o subdomains.txt target.com
  $(basename "$0") -s subfinder,crtsh -r target.com
  $(basename "$0") -f json -q target.com | jq '.subdomains[].name'
EOF
    exit "${1:-0}"
}

[ "${1:-}" = "--help" ] && usage 0

while getopts ":o:f:s:t:T:rqh" opt; do
    case "$opt" in
        o) OUTFILE="$OPTARG" ;;
        f) FORMAT="$OPTARG" ;;
        s) IFS=',' read -r -a SOURCES <<< "$OPTARG" ;;
        t) THREADS="$OPTARG" ;;
        T) SRC_TIMEOUT="$OPTARG" ;;
        r) RESOLVE=1 ;;
        q) QUIET=1 ;;
        h) usage 0 ;;
        *) usage 1 ;;
    esac
done
shift $((OPTIND - 1))

[ $# -eq 1 ] || usage 1
TARGET="$(printf '%s' "$1" | tr 'A-Z' 'a-z')"

[[ "$FORMAT" =~ ^(txt|json)$ ]] || fail "Invalid format: $FORMAT (use txt or json)"
[[ "$THREADS" =~ ^[0-9]+$ ]] || fail "Invalid thread count: $THREADS"
[[ "$SRC_TIMEOUT" =~ ^[0-9]+$ ]] || fail "Invalid timeout: $SRC_TIMEOUT"
[[ "$TARGET" =~ ^([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}$ ]] || fail "Invalid domain: $TARGET"
command -v timeout >/dev/null 2>&1 || fail "Missing dependency: timeout (coreutils)"

for s in "${SOURCES[@]}"; do
    [[ " ${ALL_SOURCES[*]} " == *" $s "* ]] || fail "Unknown source: $s (valid: ${ALL_SOURCES[*]})"
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export TARGET VERSION SRC_TIMEOUT

# crt.sh fetcher (exported so it can run under timeout)
crtsh_fetch() {
    curl -sS --fail --max-time "$SRC_TIMEOUT" --retry 3 --retry-delay 2 --retry-all-errors \
        -A "SubRaptor/${VERSION}" \
        "https://crt.sh/?q=%25.${TARGET}&output=json" | jq -r '.[].name_value'
}
export -f crtsh_fetch

# run_source <name> <required cmds, space-separated> <command...>
run_source() {
    local name="$1" reqs="$2" cmd rc
    shift 2
    for cmd in $reqs; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            echo "missing" > "$TMP/$name.status"
            return
        fi
    done
    timeout "$SRC_TIMEOUT" "$@" > "$TMP/$name.raw" 2> "$TMP/$name.err"
    rc=$?
    case "$rc" in
        0)   echo "ok" ;;
        124) echo "timeout" ;;
        *)   echo "failed" ;;
    esac > "$TMP/$name.status"
}

log ""
log "${B}${C}SubRaptor${N} ${D}v${VERSION}${N}"
log "${D}──────────────────────────────────────────${N}"
log "${B}Target  :${N} $TARGET"
log "${B}Sources :${N} ${SOURCES[*]}"
log ""
log "[*] Running sources in parallel (timeout ${SRC_TIMEOUT}s each)..."

for s in "${SOURCES[@]}"; do
    case "$s" in
        subfinder)   run_source subfinder   "subfinder"    subfinder -d "$TARGET" -all -silent & ;;
        assetfinder) run_source assetfinder "assetfinder"  assetfinder --subs-only "$TARGET" & ;;
        crtsh)       run_source crtsh       "curl jq"      bash -c crtsh_fetch & ;;
    esac
done
wait

# Normalize each source: lowercase, strip wildcards, keep only valid hostnames under the target
ESC_TARGET="${TARGET//./\\.}"
normalize() {
    tr -d '\r' \
    | tr 'A-Z' 'a-z' \
    | sed 's/^\*\.//' \
    | grep -E "^[a-z0-9._-]+$" \
    | grep -E "(^|\.)${ESC_TARGET}$" \
    | sort -u
}

for s in "${SOURCES[@]}"; do
    if [ -s "$TMP/$s.raw" ]; then
        normalize < "$TMP/$s.raw" > "$TMP/$s.txt" || true
    else
        : > "$TMP/$s.txt"
    fi
done

cat "$TMP"/*.txt 2>/dev/null | sort -u > "$TMP/all.txt"
mapfile -t SUBS < "$TMP/all.txt"

# Per-source summary (found / unique contribution)
if [ "$QUIET" -eq 0 ]; then
    printf '\n%s%-13s %-9s %7s %8s%s\n' "$B" "SOURCE" "STATUS" "FOUND" "UNIQUE" "$N" >&2
    for s in "${SOURCES[@]}"; do
        st="$(cat "$TMP/$s.status" 2>/dev/null || echo failed)"
        found="$(wc -l < "$TMP/$s.txt")"
        others="$TMP/others.txt"
        : > "$others"
        for o in "${SOURCES[@]}"; do
            [ "$o" != "$s" ] && cat "$TMP/$o.txt" >> "$others"
        done
        sort -u -o "$others" "$others"
        uniq_n="$(comm -23 "$TMP/$s.txt" "$others" | wc -l)"
        case "$st" in
            ok)      col="$G" ;;
            missing) col="$D" ;;
            *)       col="$Y" ;;
        esac
        printf '%-13s %s%-9s%s %7s %8s\n' "$s" "$col" "$st" "$N" "$found" "$uniq_n" >&2
        if [ "$st" = "failed" ] && [ -s "$TMP/$s.err" ]; then
            printf '  %s└ %s%s\n' "$D" "$(tail -n1 "$TMP/$s.err" | cut -c1-100)" "$N" >&2
        fi
    done
    printf '%s──────────────────────────────────────────%s\n' "$D" "$N" >&2
fi

[ "${#SUBS[@]}" -gt 0 ] || fail "No subdomains found for $TARGET"
log "${G}[+]${N} Total unique subdomains: ${B}${#SUBS[@]}${N}"

# Intermediate TSV: subdomain <TAB> ip1,ip2 (empty if unresolved)
resolve_one() {
    local ips
    ips="$(getent ahostsv4 "$1" 2>/dev/null | awk '{print $1}' | sort -u | paste -sd, -)"
    printf '%s\t%s\n' "$1" "$ips"
}
export -f resolve_one

if [ "$RESOLVE" -eq 1 ]; then
    log "[*] Resolving DNS (${THREADS} threads)..."
    TSV="$(printf '%s\n' "${SUBS[@]}" \
        | xargs -P "$THREADS" -I{} bash -c 'resolve_one "$1"' _ {} | sort)"
    ALIVE="$(printf '%s\n' "$TSV" | awk -F'\t' '$2!=""' | wc -l)"
    log "${G}[+]${N} Live: ${B}${ALIVE}${N} / ${#SUBS[@]}"
else
    TSV="$(printf '%s\t\n' "${SUBS[@]}")"
fi

render() {
    case "$FORMAT" in
        json)
            printf '%s\n' "$TSV" | jq -R -s --arg d "$TARGET" '
                { domain: $d,
                  count: (split("\n") | map(select(length>0)) | length),
                  subdomains: ( split("\n") | map(select(length>0) | split("\t")
                      | { name: .[0], ips: ((.[1] // "") | split(",") | map(select(length>0))) }) ) }'
            ;;
        txt)
            if [ "$RESOLVE" -eq 1 ]; then
                printf '%s\n' "$TSV" | awk -F'\t' '{printf "%s\t%s\n", $1, ($2==""?"-":$2)}' | column -t -s $'\t'
            else
                printf '%s\n' "$TSV" | cut -f1
            fi
            ;;
    esac
}

log ""
if [ -n "$OUTFILE" ]; then
    render | tee "$OUTFILE"
    log ""
    log "${G}[+]${N} Saved to ${B}${OUTFILE}${N}"
else
    render
fi
log "${D}──────────────────────────────────────────${N}"
