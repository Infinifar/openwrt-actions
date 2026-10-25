#!/bin/bash

set -e

# WSL may append malformed Windows PATH entries (for example "Files/Eclipse").
# GNU find refuses -execdir when any relative PATH component is present.
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Avoid intermittent HTTP/2/TLS failures seen with GitHub through WSL NAT.
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0=http.version
export GIT_CONFIG_VALUE_0=HTTP/1.1

echo "Current dir: $(pwd), Script: $0"

GITHUB_WORKSPACE=$(
    cd "$(dirname "$0")"
    pwd
)
echo "Info: Current path is ${GITHUB_WORKSPACE}"

export GITHUB_WORKSPACE

cd "${GITHUB_WORKSPACE}"

error() {
    local msg=$1
    local exit_code=$2

    echo "Error: ${msg}" >&2

    if [ -n "${exit_code}" ]; then
        exit ${exit_code}
    fi
}

git_fetch_current_branch() {
    local checkout_name=${1:-Git checkout}
    local current_branch fetch_attempt fetch_retries

    current_branch=$(git symbolic-ref --quiet --short HEAD) || error "${checkout_name} is on a detached HEAD." 3
    fetch_retries=${GIT_FETCH_RETRIES:-5}
    case "${fetch_retries}" in
    *[!0-9]* | 0) error "GIT_FETCH_RETRIES must be a positive integer." 2 ;;
    esac

    for fetch_attempt in $(seq 1 "${fetch_retries}"); do
        if git fetch --no-tags origin "${current_branch}"; then
            return
        fi

        if [ "${fetch_attempt}" -lt "${fetch_retries}" ]; then
            echo "Warn: Git fetch attempt ${fetch_attempt}/${fetch_retries} failed; retrying..." >&2
            sleep $((fetch_attempt * 2))
        fi
    done

    error "Unable to fetch origin/${current_branch} after ${fetch_retries} attempts." 4
}

update_wrapper() {
    cd "${GITHUB_WORKSPACE}" || exit 1

    if [ -n "$(git status --porcelain)" ]; then
        error "Refusing to update: the customization repository has uncommitted changes." 3
    fi

    local current_branch
    current_branch=$(git symbolic-ref --quiet --short HEAD) || error "Detached HEAD cannot be updated safely." 3
    echo "Info: Fast-forward ${current_branch} from origin..."
    git_fetch_current_branch "Customization repository"
    git merge --ff-only "origin/${current_branch}"
}

reset_source_checkout() {
    local current_branch
    current_branch=$(git symbolic-ref --quiet --short HEAD) || error "OpenWrt source checkout is on a detached HEAD." 3
    echo "Info: Reset generated OpenWrt source checkout ${current_branch}..."
    git reset --hard "origin/${current_branch}"
}

get_build_jobs() {
    if [ -n "${BUILD_JOBS:-}" ]; then
        case "${BUILD_JOBS}" in
        *[!0-9]* | 0) error "BUILD_JOBS must be a positive integer." 2 ;;
        esac
        echo "${BUILD_JOBS}"
        return
    fi

    local cpu_jobs memory_kb memory_jobs jobs
    cpu_jobs=$(nproc)
    memory_kb=$(awk '/MemAvailable:/ { print $2; exit }' /proc/meminfo)
    memory_jobs=$((memory_kb / 1048576))
    [ "${memory_jobs}" -ge 1 ] || memory_jobs=1
    jobs=${cpu_jobs}
    [ "${memory_jobs}" -ge "${jobs}" ] || jobs=${memory_jobs}
    echo "${jobs}"
}

init_code_dir() {
    if [ ! -n "${target}" ]; then
        error "Option --target argument is required!" 2
    fi

    echo "Info: Current target is ${target}"

    # export env
    source ${GITHUB_WORKSPACE}/user/${target}/settings.ini

    # init code dir
    target_array=(${target//-/ })
    build_source=${target_array[0]}
    build_type=${target_array[1]}
    code_dir="${build_source}_${build_type}"
    OPENWRT_BUILD_ROOT=${OPENWRT_BUILD_ROOT:-${GITHUB_WORKSPACE}}
    mkdir -p "${OPENWRT_BUILD_ROOT}"
    build_root_path=$(cd "${OPENWRT_BUILD_ROOT}" && pwd -P)
    [ "${build_root_path}" != "/" ] || error "Refusing to use / as OPENWRT_BUILD_ROOT." 3
    code_path="${build_root_path}/${code_dir}"

    echo "Info: Current code_dir is ${code_dir}"
    echo "Info: OpenWrt build path is ${code_path}"
}

clean_package() {
    if [ -d "${code_path}/build_dir" ]; then
        echo "Info: Clean package $1"
        make $1/clean
    fi
}

do_prepare() {
    # clone/update code
    cd "${GITHUB_WORKSPACE}"

    # Restore public, commit-pinned source dependencies without advancing them
    # to a newer upstream revision.
    git submodule sync --recursive
    git submodule update --init --recursive

    if [ ! -d "${code_path}" ]; then
        echo "Info: Clone code ${REPO_URL} ${REPO_BRANCH}..."
        clone_ok=0
        for clone_attempt in 1 2 3; do
            if git clone --depth=1 --single-branch -b "${REPO_BRANCH}" "${REPO_URL}" "${code_path}"; then
                clone_ok=1
                break
            fi

            echo "Warning: Clone attempt ${clone_attempt} failed."
            rm -rf -- "${code_path}"
            sleep 2
        done
        [ "${clone_ok}" -eq 1 ] || error "Unable to clone ${REPO_URL} after 3 attempts." 4
    else
        cd "${code_path}"

        local source_root
        source_root=$(git rev-parse --show-toplevel) || error "${code_path} is not a Git checkout." 3
        [ "$(cd "${source_root}" && pwd -P)" = "$(cd "${code_path}" && pwd -P)" ] || error "Refusing to clean unexpected source path ${source_root}." 3

        # Fetch before cleaning so a transient network failure leaves the
        # previous customized tree intact and safe to retry.
        echo "Info: Update code..."
        git_fetch_current_branch "OpenWrt source checkout"

        # clean feeds
        echo "Info: Clean feeds..."
        ./scripts/feeds clean -a

        # clean tmp
        rm -rf tmp .config

        # clean code
        echo "Info: Clean custom package..."
        git clean -fd

        reset_source_checkout
    fi

    # --------------------- Apply private
    # apply private if exist
    echo "Info: Apply private..."
    cd "${GITHUB_WORKSPACE}"
    if [ "${APPLY_ARCHIVE_CONFIG:-0}" = "1" ]; then
        [ -d "../archive/app_config" ] || error "APPLY_ARCHIVE_CONFIG=1 but ../archive/app_config does not exist." 3
        echo "Info: Explicitly overlay archive app_config..."
        cp -af ../archive/app_config/base/. app_config/
        cp -af ../archive/app_config/ysh/. app_config/
    fi

    # --------------------- Apply patches
    # apply patches
    echo "Info: Apply patches..."
    cd "${GITHUB_WORKSPACE}"
    if [ -n "$(ls -A "user/common/patches" 2>/dev/null)" ]; then
        find "user/common/patches" -type f -name '*.patch' -print0 | sort -z | xargs -I % -t -0 -n 1 sh -c "cat '%'  | patch -d '${code_path}' -p0 --forward"
    fi
    if [ -n "$(ls -A "user/${target}/patches" 2>/dev/null)" ]; then
        find "user/${target}/patches" -type f -name '*.patch' -print0 | sort -z | xargs -I % -t -0 -n 1 sh -c "cat '%'  | patch -d '${code_path}' -p0 --forward"
    fi

    # --------------------- Update feeds
    echo "Info: Update feeds..."
    cd "${code_path}"
    ./scripts/feeds update -a

    # --------------------- Copy custom files
    # apply files...
    echo "Info: Apply files..."
    cd "${GITHUB_WORKSPACE}"
    mkdir -p "${code_path}/files"
    if [ -n "$(ls -A "user/common/files" 2>/dev/null)" ]; then
        cp -af user/common/files/* "${code_path}/files/"
    fi
    if [ -n "$(ls -A "user/${target}/files" 2>/dev/null)" ]; then
        cp -af user/${target}/files/* "${code_path}/files/"
    fi

    # --------------------- Load custom script
    # apply custom.sh
    echo "Info: Apply custom.sh..."
    cd "${code_path}"
    if [ -f "${GITHUB_WORKSPACE}/user/common/custom.sh" ]; then
        /bin/bash "${GITHUB_WORKSPACE}/user/common/custom.sh" ${target}
    fi
    if [ -f "${GITHUB_WORKSPACE}/user/${target}/custom.sh" ]; then
        /bin/bash "${GITHUB_WORKSPACE}/user/${target}/custom.sh"
    fi

    # --------------------- Install feeds
    echo "Info: Install feeds..."
    cd "${code_path}"
    ./scripts/feeds install -a

    # --------------------- Load custom configuration
    echo "Info: Load custom configuration(LOAD_CUSTOM_CONFIG=${LOAD_CUSTOM_CONFIG})..."
    if [ "${LOAD_CUSTOM_CONFIG}" = "true" ]; then
        echo "Apply app_config.sh"
        cd "${code_path}"
        if [ -f "${GITHUB_WORKSPACE}/app_config.sh" ]; then
            /bin/bash "${GITHUB_WORKSPACE}/app_config.sh" ${target}
        fi
    fi

    # --------------------- Copy build config
    cd "${code_path}"
    cp -af ${GITHUB_WORKSPACE}/user/${target}/${DEFCONFIG_FILE} .config
    # apply private if exist
    if [ -f "${GITHUB_WORKSPACE}/app_config/${target}.diff" ]; then
        cp ${GITHUB_WORKSPACE}/app_config/${target}.diff .config
    fi
    echo "Info: Make defconfig..."
    make defconfig
    # A requested theme can be silently removed when a parent dependency is off.
    python3 -B "$GITHUB_WORKSPACE/scripts/validate-argon.py" config .config

    for required_package in \
        beszel-agent \
        luci-app-openclash \
        luci-app-tailscale-community \
        luci-app-zerotier \
        iptables-mod-conntrack-extra \
        kmod-ipt-conntrack-extra \
        tailscale \
        zerotier; do
        if ! grep -Fqx "CONFIG_PACKAGE_${required_package}=y" .config; then
            error "Required package ${required_package} is not selected after make defconfig." 5
        fi
    done
    if grep -Eq '^CONFIG_PACKAGE_luci-app-ssr-plus=[ym]$' .config; then
        error "ShadowSocksR Plus must not be selected." 5
    fi
    if grep -Eq '^CONFIG_PACKAGE_(luci-app-(ssr-plus|nginx|frpc|frps|ddns|ddns-go)|nginx([_-][^=]+)?|frpc|frps|ddns-go|ddns-scripts([_-][^=]+)?)=[ym]$' .config; then
        error "An excluded SSR Plus, nginx, FRP, or DDNS package is selected." 5
    fi
    echo "Info: Required current packages selected; excluded services disabled."

    # Invalidate the previous base-files output only after feeds and .config
    # have been restored. This also recovers from an interrupted prepare run.
    echo "Info: Clean build with previous custom config..."
    clean_package package/base-files
}

do_compile() {
    # make download
    local jobs download_jobs download_retries download_attempt
    local build_retries build_attempt
    local log_root log_file
    jobs=$(get_build_jobs)
    echo "Info: Use ${jobs} parallel build jobs"

    download_jobs=${DOWNLOAD_JOBS:-${jobs}}
    case "${download_jobs}" in
    *[!0-9]* | 0) error "DOWNLOAD_JOBS must be a positive integer." 2 ;;
    esac
    if [ "${download_jobs}" -gt 8 ]; then
        download_jobs=8
    fi

    download_retries=${DOWNLOAD_RETRIES:-3}
    case "${download_retries}" in
    *[!0-9]* | 0) error "DOWNLOAD_RETRIES must be a positive integer." 2 ;;
    esac

    cd "${code_path}"
    download_attempt=1
    while ! make -j"${download_jobs}" download; do
        if [ "${download_attempt}" -ge "${download_retries}" ]; then
            error "Package downloads still failed after ${download_retries} attempts." 1
        fi
        download_attempt=$((download_attempt + 1))
        echo "Warn: Package download failed; retry ${download_attempt}/${download_retries} with ${download_jobs} jobs..."
    done

    # make. Retrying keeps completed outputs and recovers cheaply from transient
    # Go module or source mirror failures.
    cd "${code_path}"
    build_retries=${BUILD_RETRIES:-1}
    case "${build_retries}" in
    *[!0-9]* | 0) error "BUILD_RETRIES must be a positive integer." 2 ;;
    esac

    build_attempt=1
    while true; do
        if make -j"${jobs}"; then
            return
        fi
        if [ "${build_attempt}" -ge "${build_retries}" ]; then
            break
        fi
        build_attempt=$((build_attempt + 1))
        echo "Warn: Parallel build failed; retry ${build_attempt}/${build_retries} with existing outputs..."
    done

    echo "Warn: Parallel build failed; retry with one job and save the verbose log..."
    log_root=${CI_PROJECT_DIR:-${GITHUB_WORKSPACE}}/.ci-logs
    mkdir -p "${log_root}"
    log_file=${log_root}/build-${target:-openwrt}-j1.log

    if make -j1 V=s >"${log_file}" 2>&1; then
        echo "Info: Single-job fallback build succeeded. Log: ${log_file}"
        return
    fi

    echo "Error: Single-job fallback build failed. Last 500 log lines:" >&2
    tail -n 500 "${log_file}" >&2
    echo "Error: Full verbose log saved to ${log_file}" >&2
    return 1
}

do_env() {
    sudo apt update
    sudo apt install -y ack antlr3 aria2 asciidoc autoconf automake autopoint binutils bison build-essential bzip2 ccache cmake cpio curl device-tree-compiler fastjar flex gawk gettext gcc-multilib g++-multilib git gperf haveged help2man intltool libc6-dev-i386 libelf-dev libglib2.0-dev libgmp3-dev libltdl-dev libmpc-dev libmpfr-dev libncurses5-dev libncursesw5-dev libreadline-dev libssl-dev libtool lrzsz mkisofs msmtp nano ninja-build p7zip p7zip-full patch pkgconf python3 python3-pip python3-pyelftools libpython3-dev qemu-utils rsync scons squashfs-tools subversion swig texinfo uglifyjs upx-ucl unzip vim wget xmlto xxd zlib1g-dev clang llvm npm
}

do_help() {
    cat <<EOF
Usage: bash $0 <command> [options]...

commands:
    help, h                display this help text
    update, u              fast-forward this customization repository
    env, e                 init environment, sudo apt install xxx
    prepare, p             update feeds and apply custom setings
    compile, c             make download and make
    all, a                 do prepare and compile

options:
    --target, -t           target to execute, it's a sub dir name in user

examples:
    bash localbuild.sh e
    OPENWRT_BUILD_ROOT=/path/on/wsl/ext4 bash localbuild.sh p -t lede-openclash-x86-amd64
    OPENWRT_BUILD_ROOT=/path/on/wsl/ext4 BUILD_JOBS=6 bash localbuild.sh c -t lede-openclash-x86-amd64
    OPENWRT_BUILD_ROOT=/path/on/wsl/ext4 BUILD_JOBS=6 bash localbuild.sh a -t lede-openclash-x86-amd64
EOF
}

# return code
RET_VAL=0

mode=$1
shift

target=""
while [ -n "$*" ]; do
    arg=$1
    shift
    case "${arg}" in
    --target | -t)
        [ -n "$1" ] || error "Option --target|-t requires an argument" 2
        target=$1
        shift
        ;;
    esac
done

code_dir=""

case "${mode}" in
help | h)
    do_help
    ;;
env | e)
    do_env
    ;;
update | u)
    update_wrapper
    ;;
prepare | p)
    init_code_dir
    do_prepare
    ;;
compile | c)
    init_code_dir
    do_compile
    ;;
all | a)
    init_code_dir
    do_prepare
    do_compile
    ;;
*)
    error "Unknow or unspecified command ${mode}!"
    ;;
esac
