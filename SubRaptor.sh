#!/bin/bash

if [ -z "$1" ]; then
    echo "Usage: SubRaptor <target>"
    exit 1
fi

if [ "$1" == "-h" ]; then
    echo "Usage: SubRaptor <target>"
    exit 0
fi

file_json="/tmp/$1.json"

echo "🔍 Searching subdomains for: $1..."
if ! curl --silent --fail --output "$file_json" "https://crt.sh/?q=%25.$1&output=json"; then
    echo "❌ Error: Unable to fetch data."
    exit 1
fi

if [ ! -s "$file_json" ]; then
    echo "❌ Error: No results found."
    rm -f "$file_json"
    exit 1
fi

echo -e "\n🎯 Found Subdomains:"
cat "$file_json" | jq -r '.[].name_value' | grep "$1" | sort -u

rm -f "$file_json"
