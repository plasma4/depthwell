#!/usr/bin/env bash

# 1. run build
# 2. move local main bookmark to point at the working change
# 3. push changes remotely to Git

set -euo pipefail

# The exported WASM is larger than jj's 1MiB default snapshot limit, and every build gives it a new content-hashed name.
# Without this override jj skips it with a warning and pushes a dist/ with no WASM (or you'd have to tune local settings)!
jj() {
    command jj --config snapshot.max-new-file-size=8MiB "$@"
}

# build!
./build.sh

# sanity: verify WASM production!
if ! compgen -G 'dist/assets/main-*.wasm' > /dev/null; then
    echo "Error: no dist/assets/main-*.wasm after build; push stopped." >&2
    exit 1
fi

# jj VCS verification!
if ! status_output=$(jj status 2>&1); then
    printf '%s\n' "$status_output" >&2
    exit 1
fi

if grep -Fq 'Refused to snapshot' <<< "$status_output"; then
    echo "Error: jj skipped a file during snapshot; push stopped." >&2
    printf '%s\n' "$status_output" >&2
    exit 1
fi

# move the local benchmark and push
jj bookmark move main
jj git push

# please consult README on how to reconcile VSCode/VSCodium diffs after committing
