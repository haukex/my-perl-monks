#!/bin/bash
set -euo pipefail
script_dir="$( CDPATH='' cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" && pwd )"

usage() { echo "Usage: $0 NODE_ID" 1>&2; exit 1; }
[[ $# -eq 1 ]] || usage
node_id="$1"

patch_target="$( perl -wM5.014 "-I$script_dir" '-MMyConfig=$PATCH_PATH' \
    -e 'print $PATCH_PATH' )/$node_id.patch"

temp_dir="$( mktemp --directory )"
trap 'set +e; popd >/dev/null; rm -rf "$temp_dir"' EXIT
pushd "$temp_dir"

"$script_dir/doctext.pl" "$node_id" >"$node_id.orig.txt"

cp "$node_id.orig.txt" "$node_id.txt"

# the doctext may have an existing patch applied, if yes, revert it
if [ -e "$patch_target" ]; then
    if patch -R -p1 "$node_id.orig.txt" "$patch_target"; then
        rm -v "$patch_target"
    else
        echo "Failed to revert existing patch - has it been applied?"
        echo "(i.e. you probably need to re-run the scraper first?)"
        exit 1
    fi
fi

vim -c "set nofixeol" -c "set ft=html" "$node_id.txt"

( git diff --no-index "$node_id.orig.txt" "$node_id.txt" || true ) \
    | grep -v '^index' | tee "$node_id.patch"

if perl -wM5.014 -0777 -ne 'exit(/\S/?0:1)' "$node_id.patch"; then
    cp "$node_id.patch" "$patch_target"
    echo "Done, wrote $patch_target"
else
    echo "No diff"
    exit 1
fi

# spell: ignore CDPATH nofixeol