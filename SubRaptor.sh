#!/usr/bin/env bash
# SubRaptor - passive subdomain enumeration via Certificate Transparency (crt.sh)
set -uo pipefail

VERSION="1.1.0"
FORMAT="txt"
OUTFILE=""
RESOLVE=0
QUIET=0
THREADS=20

# Colors only when stderr is a terminal
if [ -t 2 ]; then
    B=$'\e[1m'; G=$'\e[32m'; R=$'\e[31m'; C=$'\e[36m'; D=$'\e[2m'; N=$'\e[0m'
else
    B=""; G=""; R=""; C=""; D=""; N=""
fi

log()  { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*" >&2; }
fail() { printf '%s[!]%s %s\n' "$R" "$N" "$*" >&2; exit 1; }

usage() {
    cat >&2 <<EOF
${B}SubRaptor v${VERSION}${N} - passive subdomain enumeration (crt.sh)

Usage: $(basename "$0") [options] <domain>

Options:
  -o <file>    Save results to a file (in addition to stdout)
  -f <fmt>     Output format: txt (default) | json
  -r           Resolve subdomains (IPv4) and show their IPs
  -t <n>       Threads for resolution (default: $THREADS)
  -q           Quiet: no banner/summary, results only
  -h           Show this help

Examples:
  $(basename "$0") example.com
  $(basename "$0") -r -o subs.txt example.com
  $(basename "$0") -f json -q example.com | jq .
EOF
    exit "${1:-0}"
}

while getopts ":o:f:t:rqh" opt; do
    case "$opt" in
        o) OUTFILE="$OPTARG" ;;
        f) FORMAT="$OPTARG" ;;
        t) THREADS="$OPTARG" ;;
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
[[ "$TARGET" =~ ^([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}$ ]] || fail "Invalid domain: $TARGET"

for dep in curl jq; do
    command -v "$dep" >/dev/null 2>&1 || fail "Missing dependency: $dep"
done

log ""
log "${B}${C}SubRaptor${N} ${D}v${VERSION}${N}"
log "${D}────────────────────────────────────${N}"
log "${B}Target :${N} $TARGET"
log "${B}Source :${N} crt.sh (Certificate Transparency)"
log ""
log "[*] Querying crt.sh..."

RAW="$(curl -sS --fail --max-time 90 --retry 3 --retry-delay 2 --retry-all-errors \
    -A "SubRaptor/${VERSION}" \
    "https://crt.sh/?q=%25.${TARGET}&output=json" 2>&1)" \
    || fail "Request to crt.sh failed (service is often overloaded, try again): ${RAW}"

[ -n "$RAW" ] || fail "Empty response from crt.sh"

ESC_TARGET="${TARGET//./\\.}"
mapfile -t SUBS < <(
    printf '%s' "$RAW" \
    | jq -r '.[].name_value' 2>/dev/null \
    | tr -d '\r' \
    | tr 'A-Z' 'a-z' \
    | sed 's/^\*\.//' \
    | grep -E "^[a-z0-9._-]+$" \
    | grep -E "(^|\.)${ESC_TARGET}$" \
    | sort -u
)

[ "${#SUBS[@]}" -gt 0 ] || fail "No subdomains found for $TARGET"
log "${G}[+]${N} Found ${B}${#SUBS[@]}${N} unique subdomains"

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
log "${D}────────────────────────────────────${N}"
