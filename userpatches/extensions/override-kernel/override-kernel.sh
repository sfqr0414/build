#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
# 目录防删保护 + 钩子强识别 + Docker路径适配

# ===================== 【核心配置变量】 =====================
declare -g TARGET_KERNEL_VERSION="6.18.3"
declare -g TARGET_KERNEL_MAJOR="${TARGET_KERNEL_VERSION%.*}"
declare -g KERNEL_MAJOR_X="${TARGET_KERNEL_MAJOR%%.*}"
declare -g LOCAL_KERNEL_GIT_DIR="${SRC}/cache/downloads/local-kernel-git/linux-${TARGET_KERNEL_VERSION}"
declare -g KERNEL_TAR_URL="https://cdn.kernel.org/pub/linux/kernel/v${KERNEL_MAJOR_X}.x/linux-${TARGET_KERNEL_VERSION}.tar.xz"
declare -g KERNEL_TAR_PATH="${SRC}/cache/downloads/linux-${TARGET_KERNEL_VERSION}.tar.xz"
declare -g KERNELSOURCE_REMOTE="https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git"
declare -g FRAMEWORK_LINUX_DIR="${SRC}/cache/sources/${LINUXSOURCEDIR}"
declare -g KERNEL_VERSION_SUBDIR="${SRC}/cache/sources/linux-kernel-worktree/6.18__rockchip64__arm64"
declare -g USER_KERNEL_PATCH_DIR="${SRC}/userpatches/kernel/archive/rockchip64-${TARGET_KERNEL_MAJOR}"

# ===================== 关键：浅克隆 + 补丁目录声明 =====================
declare -g KERNEL_GIT="shallow"
display_alert "【钩子已执行】脚本内置强制启用浅克隆模式" "KERNEL_GIT=shallow，跳过2700MiB完整Git树下载" "info"
display_alert "【钩子已执行】用户DTS补丁目录已配置（容器内）" "${USER_KERNEL_PATCH_DIR}" "info"

# ===================== 钩子2：本地源码复用（优先级200，强日志输出） =====================
function post_family_config__200_build_local_kernel_git() {
    display_alert "【钩子200已执行】开始执行本地源码复用逻辑" "" "debug"
    echo "KERNEL_TAR_PATH=${KERNEL_TAR_PATH}"

    if [[ "${BOARD}" != "orangepi5-max" ]]; then
        display_alert "Skip local kernel git build" "Not orangepi5-max board" "debug"
        return 0
    fi

    # 本地仓库已存在，安全复用
    if [[ -d "${LOCAL_KERNEL_GIT_DIR}/.git" ]]; then
        display_alert "【钩子200已执行】本地内核 Git 仓库已存在（容器内）" "${LOCAL_KERNEL_GIT_DIR}" "debug"
        rm -rf "${KERNEL_VERSION_SUBDIR}" 2>/dev/null || true
        mkdir -p "$(dirname "${KERNEL_VERSION_SUBDIR}")" 2>/dev/null || true
        cp -rf "${LOCAL_KERNEL_GIT_DIR}" "${KERNEL_VERSION_SUBDIR}"
        
        declare -g KERNELSOURCE="${KERNELSOURCE_REMOTE}"
        declare -g KERNELBRANCH="tag:v${TARGET_KERNEL_VERSION}"
        declare -g KERNEL_MAJOR_MINOR="${TARGET_KERNEL_MAJOR}"
        
        display_alert "【钩子200已执行】本地源码复用完成" "将自动应用用户DTS补丁" "success"
        return 0
    fi

    # 下载压缩包、创建本地仓库、初始化Git
    if [[ ! -f "${KERNEL_TAR_PATH}" ]]; then
        display_alert "【钩子200已执行】开始下载 Linux ${TARGET_KERNEL_VERSION} 压缩包" "${KERNEL_TAR_URL}" "info"
        mkdir -p "$(dirname "${KERNEL_TAR_PATH}")" || exit 1
        run_host_command_logged wget -q -O "${KERNEL_TAR_PATH}" "${KERNEL_TAR_URL}" || {
            exit_with_error "压缩包下载失败，请检查网络"
        }
    fi

    display_alert "【钩子200已执行】创建本地 Git 仓库目录（容器内）" "${LOCAL_KERNEL_GIT_DIR}" "info"
    rm -rf "${LOCAL_KERNEL_GIT_DIR}"
    mkdir -p "${LOCAL_KERNEL_GIT_DIR}" || exit 1

    display_alert "【钩子200已执行】解压压缩包到本地 Git 目录（容器内）" "${LOCAL_KERNEL_GIT_DIR}" "info"
    run_host_command_logged tar -xJf "${KERNEL_TAR_PATH}" -C "${LOCAL_KERNEL_GIT_DIR}" --strip-components=1 || {
        exit_with_error "压缩包解压失败"
    }

    display_alert "【钩子200已执行】初始化本地 Git 仓库" "v${TARGET_KERNEL_VERSION}" "info"
    (
        cd "${LOCAL_KERNEL_GIT_DIR}" || exit 1
        git init -q
        git config user.name "Armbian Build"
        git config user.email "build@armbian.local"
        git add .
        git commit -q -m "Linux kernel ${TARGET_KERNEL_VERSION} initial commit"
        git checkout -q -b "v${TARGET_KERNEL_VERSION}"
        git tag -a "v${TARGET_KERNEL_VERSION}" -m "Linux kernel ${TARGET_KERNEL_VERSION} tag"
    ) || {
        exit_with_error "Git 仓库初始化失败"
    }

    # 复用至内核子目录
    rm -rf "${KERNEL_VERSION_SUBDIR}" 2>/dev/null || true
    mkdir -p "$(dirname "${KERNEL_VERSION_SUBDIR}")" 2>/dev/null || true
    cp -rf "${LOCAL_KERNEL_GIT_DIR}" "${KERNEL_VERSION_SUBDIR}"

    declare -g KERNELSOURCE="${KERNELSOURCE_REMOTE}"
    declare -g KERNELBRANCH="tag:v${TARGET_KERNEL_VERSION}"
    declare -g KERNEL_MAJOR_MINOR="${TARGET_KERNEL_MAJOR}"

    display_alert "【钩子200已执行】本地内核源配置完成" "将自动应用用户DTS补丁" "success"
}
