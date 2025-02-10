#!/bin/bash

SCRIPT_NAME="SubRaptor.sh"
INSTALL_PATH="/usr/local/bin/SubRaptor"

if ! command -v jq &> /dev/null; then
    echo "🔧 Installing jq (required for JSON parsing)..."
    sudo apt-get update -qq && sudo apt-get install -y jq > /dev/null 2>&1
    echo "✅ jq installed successfully!"
fi

echo "🚀 Installing SubRaptor..."
sudo cp "$SCRIPT_NAME" "$INSTALL_PATH"
sudo chmod +x "$INSTALL_PATH"

echo "✅ Installation complete! You can now run 'SubRaptor <target>' from anywhere."
