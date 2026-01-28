#!/usr/bin/env bash
set -euo pipefail

cleanup() {
    exit_code=${1:-$?}
    DOWNLOAD_DIR="${SCRIPT_WORK_DIR}/cache/downloads/local-kernel-git"

    mv "${BAORDS_DIR}.bak" "${BAORDS_DIR}"

    if [[ "$exit_code" -ne 0 ]]; then
        echo "❌ Script exited abnormally"
    fi
    exit "$exit_code"
}

trap 'cleanup $?' EXIT INT TERM QUIT

SCRIPT_WORK_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "${SCRIPT_WORK_DIR}" || exit 1

rm -rf "${SCRIPT_WORK_DIR}/output/cache" \
       "${SCRIPT_WORK_DIR}/.dockerignore" \
       "${SCRIPT_WORK_DIR}/output/logs" \
       "${SCRIPT_WORK_DIR}/build-image.log"

BAORDS_DIR="${SCRIPT_WORK_DIR}/config/boards"
mv "${BAORDS_DIR}" "${BAORDS_DIR}.bak"

./compile.sh build \
    BOARD=orangepi5-max \
    BRANCH=edge \
    BUILD_DESKTOP=yes \
    BUILD_MINIMAL=no \
    DESKTOP_APPGROUPS_SELECTED='browsers chat desktop_tools editors email internet multimedia office programming remote_desktop' \
    DESKTOP_ENVIRONMENT=gnome \
    DESKTOP_ENVIRONMENT_CONFIG_NAME=config_base \
    KERNEL_CONFIGURE=no \
    RELEASE=plucky \
    ENABLE_EXTENSIONS='override-kernel bcmdhd-install preset-firstrun' \
2>&1 | tee >(sed 's/\x1B\[[0-9;]*[a-zA-Z]//g' > build-image.log)
