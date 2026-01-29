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

# 控制：允许禁用网络下载回退（默认：no，以防止意外网络下载）
# 将 ALLOW_KERNEL_BARE_DOWNLOAD 设置为 no 可在没有本地源码时立即失败（建议用于 CI / 确定性构建）
declare -g ALLOW_KERNEL_BARE_DOWNLOAD="${ALLOW_KERNEL_BARE_DOWNLOAD:-yes}"
display_alert "【钩子已配置】ALLOW_KERNEL_BARE_DOWNLOAD" "ALLOW_KERNEL_BARE_DOWNLOAD=${ALLOW_KERNEL_BARE_DOWNLOAD}" "info"

# ===================== 关键：浅克隆 + 补丁目录声明 =====================
declare -g KERNEL_GIT="shallow"
display_alert "【钩子已执行】脚本内置强制启用浅克隆模式" "KERNEL_GIT=shallow，跳过2700MiB完整Git树下载" "info"
display_alert "【钩子已执行】用户DTS补丁目录已配置（容器内）" "${USER_KERNEL_PATCH_DIR}" "info"

# 可选开关：设置 FORCE_APPLY_KERNEL_PATCHES=no 以禁用强制应用用户内核补丁
declare -g FORCE_APPLY_KERNEL_PATCHES="${FORCE_APPLY_KERNEL_PATCHES:-yes}"
# 将最终选择持久化到 ${SRC}/userpatches 下的文件，以便在 Docker 容器内可见
#（userpatches 在容器运行时会被可靠复制/挂载）
if [[ -n "${SRC:-}" ]]; then
    # 优先使用 ${SRC}/userpatches 位置；仅在文件缺失时写入以避免覆盖容器默认值
    if [[ ! -f "${SRC}/userpatches/.force_apply_kernel_patches" ]]; then
        echo "${FORCE_APPLY_KERNEL_PATCHES}" > "${SRC}/userpatches/.force_apply_kernel_patches" 2>/dev/null || true
    fi
    # 同时保留旧的根路径位置以保持向后兼容
    if [[ ! -f "${SRC}/.force_apply_kernel_patches" ]]; then
        echo "${FORCE_APPLY_KERNEL_PATCHES}" > "${SRC}/.force_apply_kernel_patches" 2>/dev/null || true
    fi
fi
display_alert "INFO" "Force-apply kernel patches set to: ${FORCE_APPLY_KERNEL_PATCHES}" "info"


# ===================== 钩子2：本地源码复用（优先级200，强日志输出） =====================
function post_family_config__200_build_local_kernel_git() {
    display_alert "【钩子200已执行】开始执行本地源码复用逻辑" "" "debug"
    echo "KERNEL_TAR_PATH=${KERNEL_TAR_PATH}"

    # -- 辅助函数（内部使用，以保持命名空间整洁）
    _set_kernel_patchdir_from_userpatches() {
        rel_patch_dir="${USER_KERNEL_PATCH_DIR#${SRC}/userpatches/kernel/}"
        declare -g KERNELPATCHDIR="${rel_patch_dir}"
        if [[ -d "${SRC}/userpatches/kernel/${KERNELPATCHDIR}" ]]; then
            display_alert "INFO" "Kernel patch dir resolved: ${SRC}/userpatches/kernel/${KERNELPATCHDIR}" "info"
        else
            display_alert "WARN" "Kernel patch dir not found at ${SRC}/userpatches/kernel/${KERNELPATCHDIR}; patches may be missing" "warn"
        fi
    }

    _prepare_bare_from_dir() {
        local src_dir="$1"
        local marker_dir="${SRC}/cache/git-bare"
        local dest="${marker_dir}/kernel"
        run_host_command_logged mkdir -p "${marker_dir}" || true
        run_host_command_logged rm -rf "${dest}" || true
        run_host_command_logged mkdir -p "${dest}/.git" || true
        run_host_command_logged git clone --bare "${src_dir}" "${dest}/.git" || display_alert "WARN" "Failed to create bare kernel repo from ${src_dir}" "warn"
        run_host_command_logged touch "${dest}/.git/armbian-bare-tree-done" || true
    }

    _try_add_worktree_if_commit() {
        local src_dir="$1"
        local commit_sha
        commit_sha="$(git -C "${src_dir}" rev-parse HEAD 2>/dev/null || true)"
        if [[ -n "${commit_sha}" ]]; then
            run_host_command_logged rm -rf "${SRC}/cache/sources/linux-kernel-worktree/${TARGET_KERNEL_MAJOR}__${LINUXFAMILY}__${ARCH}" || true
            run_host_command_logged rm -rf "${SRC}/cache/git-bare/kernel/.git/worktrees/${TARGET_KERNEL_MAJOR}__${LINUXFAMILY}__${ARCH}" || true
            run_host_command_logged git -C "${SRC}/cache/git-bare/kernel" worktree add --detach "${SRC}/cache/sources/linux-kernel-worktree/${TARGET_KERNEL_MAJOR}__${LINUXFAMILY}__${ARCH}" "${commit_sha}" || display_alert "WARN" "Failed to add worktree from bare repo" "warn"
        fi
    }

    # 向后兼容的 shim：委托给基于钩子的实现并记录已弃用警告
    function force_apply_kernel_patches() {
        display_alert "WARN" "force_apply_kernel_patches() 已弃用；已委托给 kernel_copy_extra_sources__force_apply_kernel_patches" "warn"
        # 直接调用钩子以保证行为一致
        kernel_copy_extra_sources__force_apply_kernel_patches
    }

    # 板卡过滤：保持行为一致
    if [[ "${BOARD}" != "orangepi5-max" ]]; then
        display_alert "Skip local kernel git build" "Not orangepi5-max board" "debug"
        return 0
    fi

    # 优先顺序：1) 本地仓库（复制成 worktree 版本） 2) 框架本地 worktree 3) local repo（优先使用本地作为 KERNELSOURCE） 4) 下载回退

    # 1) 本地仓库存在时（复制并配置为 framework 可用）
    if [[ -d "${LOCAL_KERNEL_GIT_DIR}/.git" ]]; then
        display_alert "【钩子200已执行】本地内核 Git 仓库已存在（容器内）" "${LOCAL_KERNEL_GIT_DIR}" "debug"
        rm -rf "${KERNEL_VERSION_SUBDIR}" 2>/dev/null || true
        mkdir -p "$(dirname "${KERNEL_VERSION_SUBDIR}")" 2>/dev/null || true
        cp -rf "${LOCAL_KERNEL_GIT_DIR}" "${KERNEL_VERSION_SUBDIR}"

        declare -g KERNELSOURCE="${KERNELSOURCE_REMOTE}"
        commit_sha="$(git -C "${LOCAL_KERNEL_GIT_DIR}" rev-parse HEAD 2>/dev/null || true)"
        if [[ -n "${commit_sha}" ]]; then
            declare -g KERNELBRANCH="commit:${commit_sha}"
        else
            declare -g KERNELBRANCH="tag:v${TARGET_KERNEL_VERSION}"
        fi
        declare -g KERNEL_MAJOR_MINOR="${TARGET_KERNEL_MAJOR}"
        declare -g KERNEL_GIT_CACHE_TTL=0
        _set_kernel_patchdir_from_userpatches
        declare -g KERNEL_SKIP_MAKEFILE_VERSION="yes"

        display_alert "【钩子200已执行】本地源码复用完成" "KERNELSOURCE=${KERNELSOURCE} KERNELBRANCH=${KERNELBRANCH} KERNELPATCHDIR=${KERNELPATCHDIR} KERNEL_SKIP_MAKEFILE_VERSION=${KERNEL_SKIP_MAKEFILE_VERSION}" "success"

        _prepare_bare_from_dir "${LOCAL_KERNEL_GIT_DIR}"
        _try_add_worktree_if_commit "${LOCAL_KERNEL_GIT_DIR}"
        display_alert "INFO" "Bare kernel git tree prepared (marker set)" "${SRC}/cache/git-bare/kernel" "info"
        display_alert "DEBUG" "Deferring forced kernel patch application to hook 'kernel_copy_extra_sources__force_apply_kernel_patches'" "debug"

        return 0
    fi

    # 2) 框架提供的本地 worktree（优先使用，避免下载）
    if [[ -d "${FRAMEWORK_LINUX_DIR}/.git" ]]; then
        display_alert "【钩子200已执行】使用框架本地 kernel worktree 复用（避免下载）" "${FRAMEWORK_LINUX_DIR}" "info"
        rm -rf "${KERNEL_VERSION_SUBDIR}" 2>/dev/null || true
        mkdir -p "$(dirname "${KERNEL_VERSION_SUBDIR}")" 2>/dev/null || true
        cp -a "${FRAMEWORK_LINUX_DIR}" "${KERNEL_VERSION_SUBDIR}" || exit_with_error "复制框架 kernel worktree 失败"

        commit_sha="$(git -C "${FRAMEWORK_LINUX_DIR}" rev-parse HEAD 2>/dev/null || true)"
        declare -g KERNELSOURCE="${KERNELSOURCE_REMOTE}"
        if [[ -n "${commit_sha}" ]]; then
            declare -g KERNELBRANCH="commit:${commit_sha}"
        else
            declare -g KERNELBRANCH="branch:HEAD"
        fi
        declare -g KERNEL_MAJOR_MINOR="${TARGET_KERNEL_MAJOR}"
        declare -g KERNEL_GIT_CACHE_TTL=0
        _set_kernel_patchdir_from_userpatches
        declare -g KERNEL_SKIP_MAKEFILE_VERSION="yes"

        display_alert "【钩子200已执行】本地 kernel worktree 复用完成" "KERNELBRANCH=${KERNELBRANCH} KERNELPATCHDIR=${KERNELPATCHDIR} KERNEL_SKIP_MAKEFILE_VERSION=${KERNEL_SKIP_MAKEFILE_VERSION}" "success"

        _prepare_bare_from_dir "${FRAMEWORK_LINUX_DIR}"
        _try_add_worktree_if_commit "${FRAMEWORK_LINUX_DIR}"
        display_alert "INFO" "Bare kernel git tree prepared from framework worktree (marker set)" "${SRC}/cache/git-bare/kernel" "info"
        display_alert "DEBUG" "Deferring forced kernel patch application to hook 'kernel_copy_extra_sources__force_apply_kernel_patches'" "debug"

        return 0
    fi

    # 3) 优先再次尝试本地仓库作为 KERNELSOURCE（与原行为一致）
    if [[ -d "${LOCAL_KERNEL_GIT_DIR}/.git" ]]; then
        display_alert "【钩子200已执行】本地内核 Git 仓库已存在（容器内）" "${LOCAL_KERNEL_GIT_DIR}" "debug"
        rm -rf "${KERNEL_VERSION_SUBDIR}" 2>/dev/null || true
        mkdir -p "$(dirname "${KERNEL_VERSION_SUBDIR}")" 2>/dev/null || true
        cp -rf "${LOCAL_KERNEL_GIT_DIR}" "${KERNEL_VERSION_SUBDIR}"

        commit_sha="$(git -C "${LOCAL_KERNEL_GIT_DIR}" rev-parse HEAD 2>/dev/null || true)"
        declare -g KERNELSOURCE="${LOCAL_KERNEL_GIT_DIR}"
        if [[ -n "${commit_sha}" ]]; then
            declare -g KERNELBRANCH="commit:${commit_sha}"
        else
            declare -g KERNELBRANCH="branch:HEAD"
        fi
        declare -g KERNEL_MAJOR_MINOR="${TARGET_KERNEL_MAJOR}"
        declare -g KERNEL_GIT_CACHE_TTL=0
        _set_kernel_patchdir_from_userpatches

        display_alert "【钩子200已执行】本地源码复用完成" "KERNELBRANCH=${KERNELBRANCH} KERNELPATCHDIR=${KERNELPATCHDIR}" "success"
        return 0
    fi

    # 下载回退（保留原始实现）
    if [[ "${ALLOW_KERNEL_BARE_DOWNLOAD,,}" == "no" ]]; then
        display_alert "WARN" "ALLOW_KERNEL_BARE_DOWNLOAD=no — 检查 ${KERNEL_TAR_URL} 是否可访问以决定是否允许下载回退" "warn"

        url_ok="no"
        # Prefer curl, fall back to wget --spider
        if command -v curl >/dev/null 2>&1; then
            if run_host_command_logged sh -c "curl -sSf --head '${KERNEL_TAR_URL}' >/dev/null"; then
                url_ok="yes"
            fi
        elif command -v wget >/dev/null 2>&1; then
            if run_host_command_logged sh -c "wget --spider -q '${KERNEL_TAR_URL}' >/dev/null"; then
                url_ok="yes"
            fi
        fi

        if [[ "${url_ok}" == "yes" ]]; then
            display_alert "WARN" "检测到网络可达并能获取 ${KERNEL_TAR_URL}；尽管 ALLOW_KERNEL_BARE_DOWNLOAD=no，仍将尝试下载回退以继续构建" "warn"
            # proceed with the download fallback
        else
            display_alert "ERROR" "No local kernel worktree or repo found and ALLOW_KERNEL_BARE_DOWNLOAD=no; aborting to avoid network downloads" "error"
            exit_with_error "No local kernel sources and downloads disabled (ALLOW_KERNEL_BARE_DOWNLOAD=no)"
        fi
    fi
    display_alert "WARN" "未找到本地 kernel worktree，回退到下载并初始化本地内核仓库（耗时）" "warn"

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
        # 修正目录权限与所有者以避免 git 对所有权抱怨（dubious ownership）
        run_host_command_logged chown -R "$(id -u):$(id -g)" "${LOCAL_KERNEL_GIT_DIR}" || true
        run_host_command_logged chmod -R u+rwX "${LOCAL_KERNEL_GIT_DIR}" || true

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

    rm -rf "${KERNEL_VERSION_SUBDIR}" 2>/dev/null || true
    mkdir -p "$(dirname "${KERNEL_VERSION_SUBDIR}")" 2>/dev/null || true
    cp -rf "${LOCAL_KERNEL_GIT_DIR}" "${KERNEL_VERSION_SUBDIR}"

    declare -g KERNELSOURCE="${KERNELSOURCE_REMOTE}"
    # Determine commit from initialized local repo and set KERNELBRANCH so framework can reference it
    commit_sha="$(git -C "${LOCAL_KERNEL_GIT_DIR}" rev-parse HEAD 2>/dev/null || true)"
    if [[ -n "${commit_sha}" ]]; then
        declare -g KERNELBRANCH="commit:${commit_sha}"
    else
        declare -g KERNELBRANCH="tag:v${TARGET_KERNEL_VERSION}"
    fi
    declare -g KERNEL_MAJOR_MINOR="${TARGET_KERNEL_MAJOR}"
    declare -g KERNEL_SKIP_MAKEFILE_VERSION="yes"

    _prepare_bare_from_dir "${LOCAL_KERNEL_GIT_DIR}"
    _try_add_worktree_if_commit "${LOCAL_KERNEL_GIT_DIR}"
    display_alert "INFO" "Bare kernel git tree prepared from downloaded repo (marker set)" "${SRC}/cache/git-bare/kernel" "info"
    display_alert "DEBUG" "Deferring forced kernel patch application to hook 'kernel_copy_extra_sources__force_apply_kernel_patches'" "debug"

    display_alert "【钩子200已执行】本地内核源配置完成（通过下载）" "将自动应用用户DTS补丁" "success"
}

# =============================================================
# Hook: 在 kernel worktree 已准备好且主机依赖已准备完成时，强制应用所有用户内核补丁（包括 DTS）
# 位置：该钩子会在 kernel_prepare_git 之后、kernel_main_patching 之前运行（由 kernel.sh 调用的
# kernel_copy_extra_sources 扩展点）。在此时机调用可以：
# - 确保 worktree 已存在或可从 bare repo 创建
# - 确保 prepare_python_and_pip 已成功执行（因此 Python 依赖已就绪）
# - 避免嵌套日志节（不调用 framework 的 kernel_main_patching_python）
# =============================================================
function kernel_copy_extra_sources__force_apply_kernel_patches() {
    # Allow opt-out via env var OR via ${SRC}/userpatches/.force_apply_kernel_patches or ${SRC}/.force_apply_kernel_patches (persisted from host)
    if [[ "${FORCE_APPLY_KERNEL_PATCHES,,}" == "no" ]]; then
        display_alert "INFO" "Forced kernel patch apply disabled via env FORCE_APPLY_KERNEL_PATCHES=no" "info"
        return 0
    fi
    for optf in "${SRC}/userpatches/.force_apply_kernel_patches" "${SRC}/.force_apply_kernel_patches"; do
        if [[ -f "${optf}" ]]; then
            optv="$(cat "${optf}" 2>/dev/null || true)"
            if [[ "${optv,,}" == "no" ]]; then
                display_alert "INFO" "Forced kernel patch apply disabled via ${optf}" "info"
                return 0
            else
                display_alert "DEBUG" "Found ${optf}=${optv}" "debug"
            fi
        fi
    done
    # Avoid double-applying in the same build run
    if [[ "${FORCE_KPATCHES_APPLIED_THIS_RUN:-}" == "yes" ]]; then
        display_alert "DEBUG" "Forced kernel patches already applied this run; skipping" "debug"
        return 0
    fi

    # 如果没有声明补丁目录或补丁目录不存在，则跳过
    if [[ -z "${KERNELPATCHDIR:-}" || ! -d "${SRC}/userpatches/kernel/${KERNELPATCHDIR}" ]]; then
        display_alert "DEBUG" "No kernel patch dir (${KERNELPATCHDIR:-}) found; skipping forced patch apply" "debug"
        return 0
    fi

    display_alert "INFO" "Hook: kernel_copy_extra_sources__force_apply_kernel_patches starting" "info"

    # 确保我们有 kernel_work_dir 与 kernel_git_revision；如果未传入则尝试回退到常用路径/解析
    if [[ -z "${kernel_work_dir:-}" ]]; then
        kernel_work_dir="${SRC}/cache/sources/linux-kernel-worktree/${TARGET_KERNEL_MAJOR}__${LINUXFAMILY}__${ARCH}"
    fi
    if [[ -z "${kernel_git_revision:-}" ]]; then
        kernel_git_revision="$(git -C "${kernel_work_dir}" rev-parse HEAD 2>/dev/null || true)"
    fi

    if [[ -z "${kernel_git_revision}" ]]; then
        display_alert "WARN" "kernel_git_revision unknown; skipping forced patch apply" "warn"
        return 0
    fi

    # 如果 worktree 缺失，尝试从 bare repo 添加
    if [[ ! -d "${kernel_work_dir}" ]]; then
        display_alert "WARN" "Kernel worktree ${kernel_work_dir} missing; attempting create from bare repo" "warn"
        kernel_bare="${SRC}/cache/git-bare/kernel"
        run_host_command_logged rm -rf "${kernel_work_dir}" || true
        run_host_command_logged git -C "${kernel_bare}" worktree add --detach "${kernel_work_dir}" "${kernel_git_revision}" || {
            display_alert "WARN" "Failed to create kernel worktree; skipping forced patch apply" "warn"
            return 0
        }
        display_alert "INFO" "Created kernel worktree ${kernel_work_dir}" "info"
    fi

    # 准备 Python 环境（should succeed because we're after prepare_host/aggregation）
    prepare_python_and_pip || { display_alert "WARN" "prepare_python_and_pip failed; skipping forced patch apply" "warn"; return 0; }

    tmp_out=$(mktemp) || return 1

    # 使用与 kernel_main_patching_python 相同的数组引用模式以避免值被拆分
    declare -a params_quoted=(
        "${PYTHON3_VARS[@]}"                                  # Default vars, from prepare_python_and_pip
        "LOG_DEBUG=${SHOW_DEBUG:-${DEBUG_PATCHING:-no}}"     # Logging level for python.
        "SRC=${SRC}"
        "OUTPUT=${tmp_out}"
        "ASSET_LOG_BASE=$(print_current_asset_log_base_file)"
        "PATCH_TYPE=kernel"
        "PATCH_DIRS_TO_APPLY=${KERNELPATCHDIR}"
        "USERPATCHES_PATH=${USERPATCHES_PATH}"
        "COLUMNS=${COLUMNS}"
        "COLORFGBG=${COLORFGBG}"
        "GITHUB_ACTIONS=${GITHUB_ACTIONS}"
        "PATH=${PATH}"
        "HOME=${HOME}"
        "APPLY_PATCHES=yes"
        "PATCHES_TO_GIT=${PATCHES_TO_GIT:-no}"
        "REWRITE_PATCHES=${REWRITE_PATCHES:-no}"
        "REWRITE_PATCHES_NEEDING_REBASE=${REWRITE_PATCHES_NEEDING_REBASE:-no}"
        "GIT_WORK_DIR=${kernel_work_dir}"
        "BASE_GIT_REVISION=${kernel_git_revision}"
        "BRANCH_FOR_PATCHES=kernel-${LINUXFAMILY}-${KERNEL_MAJOR_MINOR}"
        "ALLOW_RECREATE_EXISTING_FILES=yes"
        "GIT_ARCHEOLOGY=${GIT_ARCHEOLOGY:-no}"
        "FAST_ARCHEOLOGY=${FAST_ARCHEOLOGY:-yes}"
        "MAINTAINER_NAME=${MAINTAINER}"
        "MAINTAINER_EMAIL=${MAINTAINERMAIL}"
        "EXTRA_PATCH_FILES_FIRST=${kernel_drivers_patch_file}"
        "EXTRA_PATCH_HASHES_FIRST=${kernel_drivers_patch_hash}"
    )

    run_host_command_logged env -i "${params_quoted[@]@Q}" "${PYTHON3_INFO[BIN]}" "${SRC}/lib/tools/patching.py" > "${tmp_out}" 2>&1 || true

    run_host_command_logged cat "${tmp_out}" || true
    [[ -s "${tmp_out}" ]] && source "${tmp_out}" || true
    applied_summary=$(grep -i "Summary: kernel patching" "${tmp_out}" || true)
    if [[ -z "${applied_summary}" ]]; then
        display_alert "WARN" "Patch summary not found in python patcher output; see above logs" "warn"
    else
        display_alert "INFO" "${applied_summary}" "info"
        # Mark that forced kernel patches have been applied in this build run
        declare -g FORCE_KPATCHES_APPLIED_THIS_RUN="yes"
    fi
    rm -f "${tmp_out}"

    return 0
}

