#!/usr/bin/env bash
set -euo pipefail

# Builds the BrightSign custom aarch64 cross-compile SDK from OS source and
# installs it into the shared cache (CACHE_DIR/sdk), where consumer repos pick it
# up. There is no prebuilt SDK to download -- BrightSign publishes only the OS
# source -- so this provisioner reproduces it: download the OS source, merge the
# bsoe-recipes layer (which adds OpenCV/GStreamer-RTSP/ext-bundle/... to the SDK
# sysroot), and build `brightsign-sdk` in the bsoe-build container.
#
# Heavy and run once per build box: the source download is ~20GB and the SDK
# build takes hours. Every step is idempotent -- an already-installed SDK short-
# circuits the whole script.
#
# Invoked by `make sdk` / `make build`.
# Override: BRIGHTSIGN_OS_VERSION (default 9.1.52), RKNN_TAG (default v2.3.0),
#           ARGUS_CACHE_DIR (cache location).

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/lib/cache.sh"   # sets SDK_DIR, SDK_ENV, BSOE_DIR, CACHE_DIR

BRIGHTSIGN_OS_VERSION="${BRIGHTSIGN_OS_VERSION:-9.1.52}"
OS_MAJOR_MINOR="${BRIGHTSIGN_OS_VERSION%.*}"
RKNN_TAG="${RKNN_TAG:-v2.3.0}"
IMAGE="bsoe-build"
CONTAINER="${CONTAINER:-docker}"

OE_DIR="${BSOE_DIR}/brightsign-oe"
INSTALLER_NAME="brightsign-x86_64-cobra-toolchain-${BRIGHTSIGN_OS_VERSION}.sh"
DEPLOY_INSTALLER="${OE_DIR}/build/tmp-glibc/deploy/sdk/${INSTALLER_NAME}"
CACHED_INSTALLER="${CACHE_DIR}/${INSTALLER_NAME}"
S3_BASE="https://brightsignbiz.s3.amazonaws.com/firmware/opensource/${OS_MAJOR_MINOR}/${BRIGHTSIGN_OS_VERSION}"

# An SDK is usable only if present AND baked for THIS cache's absolute path.
sdk_is_self_consistent() {
    [ -d "${SDK_DIR}/sysroots/aarch64-oe-linux" ] || return 1
    [ -f "${SDK_ENV}" ] || return 1
    grep -q "SDKTARGETSYSROOT=${SDK_DIR}/sysroots/aarch64-oe-linux" "${SDK_ENV}"
}

require() {
    command -v "$1" >/dev/null 2>&1 || { echo "ERROR: $1 is required but not installed" >&2; exit 1; }
}

install_sdk() {
    local installer="$1"
    if [ -e "${SDK_DIR}" ] && ! sdk_is_self_consistent; then
        echo "ERROR: ${SDK_DIR} exists but is not self-consistent for this cache." >&2
        echo "Remove it and re-run: rm -rf ${SDK_DIR}" >&2
        exit 1
    fi
    echo "==> Installing SDK into ${SDK_DIR} (self-relocating)"
    chmod +x "${installer}"
    "${installer}" -y -d "${SDK_DIR}"
    sdk_is_self_consistent || { echo "ERROR: SDK installed but not self-consistent" >&2; exit 1; }
}

fetch_rknn_runtime() {
    local lib="${SDK_DIR}/sysroots/aarch64-oe-linux/usr/lib/librknnrt.so"
    [ -f "${lib}" ] && return 0
    echo "==> Fetching librknnrt.so (${RKNN_TAG}) into the SDK sysroot"
    wget -q -O "${lib}" \
        "https://github.com/airockchip/rknn-toolkit2/raw/${RKNN_TAG}/rknpu2/runtime/Linux/librknn_api/aarch64/librknnrt.so"
}

# 0. Already done?
if sdk_is_self_consistent; then
    echo "==> SDK already installed and self-consistent at ${SDK_DIR}"
    fetch_rknn_runtime
    exit 0
fi

# 1. Install from an already-built installer if we have one.
for installer in "${CACHED_INSTALLER}" "${DEPLOY_INSTALLER}"; do
    if [ -f "${installer}" ]; then
        echo "==> Found prebuilt installer: ${installer}"
        install_sdk "${installer}"
        fetch_rknn_runtime
        echo "==> SDK ready at ${SDK_DIR}"
        exit 0
    fi
done

# 2. Otherwise build it from source.
require "${CONTAINER}"
require wget
require git
require rsync
"${CONTAINER}" info >/dev/null 2>&1 || { echo "ERROR: ${CONTAINER} daemon is not running" >&2; exit 1; }

# 2a. Download + extract OS source (once per box).
if [ ! -d "${OE_DIR}" ]; then
    echo "==> Downloading BrightSign OS ${BRIGHTSIGN_OS_VERSION} source (~20GB) into ${BSOE_DIR}"
    mkdir -p "${BSOE_DIR}"
    ( cd "${BSOE_DIR}"
      wget --progress=dot:giga "${S3_BASE}/brightsign-${BRIGHTSIGN_OS_VERSION}-src-dl.tar.gz"
      wget --progress=dot:mega "${S3_BASE}/brightsign-${BRIGHTSIGN_OS_VERSION}-src-oe.tar.gz"
      echo "==> Extracting source archives"
      tar -xzf "brightsign-${BRIGHTSIGN_OS_VERSION}-src-dl.tar.gz"
      tar -xzf "brightsign-${BRIGHTSIGN_OS_VERSION}-src-oe.tar.gz"
      rm -f "brightsign-${BRIGHTSIGN_OS_VERSION}-src-dl.tar.gz" "brightsign-${BRIGHTSIGN_OS_VERSION}-src-oe.tar.gz" )
    if [ ! -d "${OE_DIR}" ]; then
        echo "ERROR: expected ${OE_DIR} after extraction; archive layout unexpected" >&2
        exit 1
    fi
fi

# 2b. Merge this repo's recipe layer (adds OpenCV/GStreamer-RTSP/ext-bundle/...).
echo "==> Merging bsoe-recipes layer into the OE tree"
rsync -a "${REPO_ROOT}/bsoe-recipes/" "${OE_DIR}/"

# 2c. Build the OE build-environment image.
if ! "${CONTAINER}" image inspect "${IMAGE}" >/dev/null 2>&1; then
    echo "==> Building ${IMAGE} container image"
    "${CONTAINER}" build --rm \
        --build-arg USER_ID="$(id -u)" --build-arg GROUP_ID="$(id -g)" \
        --ulimit memlock=-1:-1 \
        -t "${IMAGE}" "${REPO_ROOT}"
fi

# 2d. Build the SDK (hours).
# DEPLOY_FOR_TFTPBOOT=0 disables bsbb's post-build publish of boot images to
# /srv/tftp/${USER}/${MACHINE}; that path is not mounted/writable in the container
# (and is irrelevant to an SDK build), so without this the build aborts at the end
# with "mkdir: cannot create directory '/srv/tftp//cobra': Permission denied".
echo "==> Building the BrightSign SDK (MACHINE=cobra ./bsbb brightsign-sdk) -- this takes hours"
"${CONTAINER}" run --rm \
    -v "${OE_DIR}:/home/builder/bsoe" \
    --ulimit memlock=-1:-1 \
    "${IMAGE}" \
    bash -c "cd /home/builder/bsoe/build && DEPLOY_FOR_TFTPBOOT=0 MACHINE=cobra ./bsbb brightsign-sdk"

if [ ! -f "${DEPLOY_INSTALLER}" ]; then
    echo "ERROR: SDK build did not produce ${DEPLOY_INSTALLER}" >&2
    exit 1
fi

# 2e. Keep a copy of the installer in the cache root, then install it.
cp -f "${DEPLOY_INSTALLER}" "${CACHED_INSTALLER}"
install_sdk "${CACHED_INSTALLER}"
fetch_rknn_runtime
echo "==> SDK ready at ${SDK_DIR}"
