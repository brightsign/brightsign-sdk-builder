#!/usr/bin/env bash
set -euo pipefail

# Provisions the RKNN model-compilation toolchain once per build box: clones
# rknn-toolkit2 + rknn_model_zoo (pinned) into the shared cache and builds the
# host-global rknn_tk2 Docker image. Consumer repos then compile their own models
# against these without re-cloning or rebuilding the image.
#
# Invoked by `make toolkit` / `make build`. Idempotent: existing clone + image
# are left untouched. Override RKNN_TAG (default v2.3.0) or ARGUS_CACHE_DIR.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/lib/cache.sh"   # sets TOOLKIT_DIR, CACHE_DIR

RKNN_TAG="${RKNN_TAG:-v2.3.0}"
CONTAINER="${CONTAINER:-docker}"
IMAGE="rknn_tk2"
TK2_DIR="${TOOLKIT_DIR}/rknn-toolkit2"
ZOO_DIR="${TOOLKIT_DIR}/rknn_model_zoo"

require() {
    command -v "$1" >/dev/null 2>&1 || { echo "ERROR: $1 is required but not installed" >&2; exit 1; }
}

require git
require "${CONTAINER}"
"${CONTAINER}" info >/dev/null 2>&1 || { echo "ERROR: ${CONTAINER} daemon is not running" >&2; exit 1; }

mkdir -p "${TOOLKIT_DIR}"
if [ ! -d "${TK2_DIR}" ]; then
    echo "==> Cloning rknn-toolkit2 (${RKNN_TAG})"
    git clone --depth 1 --branch "${RKNN_TAG}" https://github.com/airockchip/rknn-toolkit2.git "${TK2_DIR}"
else
    echo "==> rknn-toolkit2 present"
fi
if [ ! -d "${ZOO_DIR}" ]; then
    echo "==> Cloning rknn_model_zoo (${RKNN_TAG})"
    git clone --depth 1 --branch "${RKNN_TAG}" https://github.com/airockchip/rknn_model_zoo.git "${ZOO_DIR}"
else
    echo "==> rknn_model_zoo present"
fi

if "${CONTAINER}" image inspect "${IMAGE}" >/dev/null 2>&1; then
    echo "==> ${IMAGE} image present"
else
    dockerfile_dir="${TK2_DIR}/rknn-toolkit2/docker/docker_file/ubuntu_20_04_cp38"
    dockerfile="Dockerfile_ubuntu_20_04_for_cp38"
    if [ ! -f "${dockerfile_dir}/${dockerfile}" ]; then
        echo "ERROR: toolkit Dockerfile not found at ${dockerfile_dir}/${dockerfile}" >&2
        exit 1
    fi
    echo "==> Building ${IMAGE} image (large; one-time per box)"
    ( cd "${dockerfile_dir}" && "${CONTAINER}" build --rm -t "${IMAGE}" -f "${dockerfile}" . )
fi

echo "==> Toolkit ready: ${TOOLKIT_DIR} + ${IMAGE} image"
