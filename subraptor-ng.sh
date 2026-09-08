#!/bin/bash

# Show help if -h, --help, or no argument is passed
if [ "$1" == "-h" ] || [ "$1" == "--help" ] || [ -z "$1" ]; then
    echo "Usage: subraptor-ng <domain>"
    echo "Example: subraptor-ng target.com"
    echo "Description: Gathers subdomains by aggregating Subfinder, Assetfinder, Amass, and crt.sh, automatically removing duplicates."
    echo "Saving output: subraptor-ng target.com > subdomains.txt"
    exit 0
fi

TARGET="$1"
TMP_OUT=$(mktemp)

# 1. Subfinder
if command -v subfinder &> /dev/null; then
    subfinder -d "$TARGET" -all -silent >> "$TMP_OUT" 2>/dev/null
fi

# 2. Assetfinder
if command -v assetfinder &> /dev/null; then
    assetfinder --subs-only "$TARGET" >> "$TMP_OUT" 2>/dev/null
fi

# 3. Amass
if command -v amass &> /dev/null; then
    amass enum -passive -d "$TARGET" >> "$TMP_OUT" 2>/dev/null
fi

# 4. crt.sh (embedded)
curl -s "https://crt.sh/?q=%.$TARGET&output=json" | \
    jq -r '.[].name_value' 2>/dev/null | \
    tr '\r\n' '\n' | \
    sed 's/^\*\.//' >> "$TMP_OUT"

# Remove empty lines, sort, and strip duplicates sending clean output to stdout
grep -vE '^\s*$' "$TMP_OUT" | sort -u

# Cleanup temporary file
rm -f "$TMP_OUT"
