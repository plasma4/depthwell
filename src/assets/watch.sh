#!/bin/bash

# Alternative, unused way to watch changes; switched to having this handled in build.zig

ASEPRITE="/Applications/Aseprite.app/Contents/MacOS/aseprite"
INPUT_FILE="./main.aseprite"
OUTPUT_DIR="./"

echo "Watching for changes in $INPUT_FILE..."

# Monitor the file for changes
fswatch -o "$INPUT_FILE" | while read -r line; do
    "$ASEPRITE" -b "$INPUT_FILE" --layer "main" --save-as "$OUTPUT_DIR/main.png"
    "$ASEPRITE" -b "$INPUT_FILE" --layer "mainMasked" --save-as "$OUTPUT_DIR/mainMasked.png"
    echo "Exported layers!"
done