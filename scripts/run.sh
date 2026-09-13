#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ ! -d "dist/Air Stats.app" ]]; then bash scripts/build.sh; fi
open "dist/Air Stats.app" --args "$@"
