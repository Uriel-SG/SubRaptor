#!/bin/bash

if [ -z "$1" ]; then
    echo "Usage: SubRaptor <domain>" >&2
    exit 1
fi

TARGET="$1"

curl -s "https://crt.sh/?q=%.$TARGET&output=json" | \
    jq -r '.[].name_value' 2>/dev/null | \
    tr '\r\n' '\n' | \
    sed 's/^\*\.//' | \
    sort -u
