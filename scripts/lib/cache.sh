#!/usr/bin/env bash
# Single source of truth for the shared build-cache location and the paths
# derived from it. This provisioner builds the expensive, box-level assets once
# and writes them here; consumer repos (e.g. argus-rtsp-watcher) resolve the SAME
# location by the same convention and read them.
#
# The contract shared with consumers: CACHE_DIR/sdk and CACHE_DIR/toolkit. The
# default location sits parallel to the repo so every sibling checkout agrees on
# it; override with ARGUS_CACHE_DIR (absolute recommended; a relative value is
# resolved against the repo root). BSOE_DIR is builder-only (the huge OS source
# + OE build tree).
#
#   source scripts/lib/cache.sh                 # sets CACHE_DIR SDK_DIR SDK_ENV TOOLKIT_DIR BSOE_DIR
#   bash scripts/lib/cache.sh print <key>       # cache | sdk | sdk-env | toolkit | bsoe

_cache_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${_cache_lib_dir}/../.." && pwd)}"

if [ -n "${ARGUS_CACHE_DIR:-}" ]; then
    case "${ARGUS_CACHE_DIR}" in
        /*) CACHE_DIR="${ARGUS_CACHE_DIR}" ;;
        *)  CACHE_DIR="${REPO_ROOT}/${ARGUS_CACHE_DIR}" ;;
    esac
else
    CACHE_DIR="${REPO_ROOT}/../argus-build-cache"
fi
# Normalize to a clean absolute path without requiring the dir to exist yet; the
# SDK installer bakes this path in, so it must not contain unresolved '..'.
CACHE_DIR="$(realpath -m "${CACHE_DIR}" 2>/dev/null || echo "${CACHE_DIR}")"

SDK_DIR="${CACHE_DIR}/sdk"
SDK_ENV="${SDK_DIR}/environment-setup-aarch64-oe-linux"
TOOLKIT_DIR="${CACHE_DIR}/toolkit"
BSOE_DIR="${CACHE_DIR}/bsoe"

export CACHE_DIR SDK_DIR SDK_ENV TOOLKIT_DIR BSOE_DIR

if [ "${1:-}" = "print" ]; then
    case "${2:-cache}" in
        cache)   echo "${CACHE_DIR}" ;;
        sdk)     echo "${SDK_DIR}" ;;
        sdk-env) echo "${SDK_ENV}" ;;
        toolkit) echo "${TOOLKIT_DIR}" ;;
        bsoe)    echo "${BSOE_DIR}" ;;
        *)       echo "unknown cache key: ${2}" >&2; exit 1 ;;
    esac
fi
