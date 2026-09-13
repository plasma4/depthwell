#!/bin/bash

# 1. run build
# 2. move local main bookmark to point at the working change
# 3. push changes remotely to Git

# The exported WASM is larger than jj's 1MiB default snapshot limit, and every build gives it a new content-hashed name.
# Without this override jj skips it with a warning and pushes a dist/ with no WASM (or you'd have to tune local settings)!
JJ="jj --config snapshot.max-new-file-size=8MiB"

./build.sh || exit 1

if ! ls dist/assets/main-*.wasm > /dev/null 2>&1; then
    echo "Error: no dist/assets/main-*.wasm after build; push stopped."
    exit 1
fi

if $JJ status 2>&1 | grep -q "Refused to snapshot"; then
    echo "Error: jj skipped a file during snapshot; push stopped."
    $JJ status
    exit 1
fi

$JJ b m main && $JJ git push
