#!/bin/bash
set -euo pipefail
cd -- "$( dirname -- "${BASH_SOURCE[0]}" )"

usage() { echo "Usage: $0 [-d]" 1>&2; exit 1; }
dev_mode=
while getopts "d" opt; do
    case "${opt}" in
        d) dev_mode=1 ;;
        *) usage ;;
    esac
done
shift $((OPTIND-1))
[[ $# -eq 0 ]] || usage

if ! [ -e output/index.html ]; then
    echo "Output directory doesn't seem to exist, generate site first?"
    exit 1
fi

rm -rf output/pagefind

# https://pagefind.app/docs/
npx pagefind --site output --include-characters '!#$%&()*+,-./:;<=>?@[\]^_`{|}~' \
    ${dev_mode:+"--serve"}

# spell: ignore pagefind