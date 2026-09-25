#!/usr/bin/env bash
#
# SPDX-License-Identifier: Apache-2.0
#
# Build LineageOS 23.2 (Android 16) for the Xiaomi Redmi 9 (lancelot).
#
# Usage:
#   ./build.sh [options]
#
# Options:
#   -d, --dir DIR        Source directory (default: ./lineage)
#   -j, --jobs N         Parallel build jobs (default: nproc, capped by RAM)
#   -v, --variant VAR    user | userdebug | eng (default: userdebug)
#   -s, --sync-only      Only sync sources, don't build
#   -b, --build-only     Skip sync, only build
#   -c, --clean          Run 'm installclean' before building
#   -h, --help           Show this help
#
# Re-running is safe: sync is incremental and an interrupted build resumes
# where it stopped.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/lineage"
JOBS=""
VARIANT="userdebug"
DO_SYNC=1
DO_BUILD=1
DO_CLEAN=0

LINEAGE_BRANCH="lineage-23.2"
DEVICE="lancelot"

log()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m==> WARNING:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m==> ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

usage() { sed -n '5,21p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--dir)        SRC_DIR="$(realpath -m "$2")"; shift 2 ;;
        -j|--jobs)       JOBS="$2"; shift 2 ;;
        -v|--variant)    VARIANT="$2"; shift 2 ;;
        -s|--sync-only)  DO_BUILD=0; shift ;;
        -b|--build-only) DO_SYNC=0; shift ;;
        -c|--clean)      DO_CLEAN=1; shift ;;
        -h|--help)       usage ;;
        *) die "Unknown option: $1 (see --help)" ;;
    esac
done

[[ "$VARIANT" =~ ^(user|userdebug|eng)$ ]] || die "Invalid variant: $VARIANT"

check_host() {
    log "Checking host requirements"
    local missing=()
    for t in repo git git-lfs python3 ccache zip unzip bc bison flex rsync xxd lz4 zstd make gcc openssl m4; do
        command -v "$t" >/dev/null || missing+=("$t")
    done
    [[ ${#missing[@]} -eq 0 ]] || die "Missing tools: ${missing[*]}"

    local ram_gb swap_gb free_gb
    ram_gb=$(awk '/MemTotal/ {printf "%d", $2/1048576}' /proc/meminfo)
    swap_gb=$(awk '/SwapTotal/ {printf "%d", $2/1048576}' /proc/meminfo)
    mkdir -p "$SRC_DIR"
    free_gb=$(df -BG --output=avail "$SRC_DIR" | tail -1 | tr -dc '0-9')

    if (( ram_gb + swap_gb < 48 )); then
        warn "RAM+swap is ${ram_gb}+${swap_gb} GB; Android 16 builds may get OOM-killed. 32 GB RAM + 32 GB swap recommended."
    fi
    if [[ ! -d "$SRC_DIR/.repo" ]] && (( free_gb < 250 )); then
        warn "Only ${free_gb} GB free; a full sync + build needs ~250 GB."
    fi

    if [[ -z "$JOBS" ]]; then
        # ~2.5 GB per job keeps soong/ninja from exhausting memory
        local by_ram=$(( (ram_gb + swap_gb / 2) * 10 / 25 ))
        JOBS=$(nproc)
        if (( by_ram < JOBS )); then JOBS=$by_ram; fi
        if (( JOBS < 1 )); then JOBS=1; fi
    fi
}

sync_sources() {
    cd "$SRC_DIR"
    if [[ ! -d .repo ]]; then
        log "Initialising LineageOS $LINEAGE_BRANCH in $SRC_DIR"
        repo init -u https://github.com/LineageOS/android.git -b "$LINEAGE_BRANCH" \
            --git-lfs --partial-clone --clone-filter=blob:none \
            -g default,-darwin,-mips,-notdefault
    fi

    log "Installing local manifest"
    mkdir -p .repo/local_manifests
    cp "$SCRIPT_DIR/manifests/lancelot.xml" .repo/local_manifests/lancelot.xml

    log "Syncing sources (this takes a while the first time)"
    local sync_args=(-c --no-tags --no-clone-bundle --optimized-fetch --force-sync)
    if ! repo sync "${sync_args[@]}" -j8; then
        # Partial-clone checkouts occasionally fail transiently; a second
        # low-parallelism pass fixes them.
        warn "Sync had failures, retrying with -j2"
        repo sync "${sync_args[@]}" -j2 || die "repo sync failed twice"
    fi
}

build() {
    cd "$SRC_DIR"
    [[ -f build/envsetup.sh ]] || die "No source tree in $SRC_DIR (run without --build-only first)"

    export USE_CCACHE=1
    export CCACHE_EXEC="$(command -v ccache)"
    ccache -M 50G >/dev/null

    # envsetup.sh must be sourced from bash; nounset breaks it
    set +u
    # shellcheck disable=SC1091
    source build/envsetup.sh
    # shellcheck disable=SC1091
    source vendor/lineage/vars/aosp_target_release
    lunch "lineage_${DEVICE}-${aosp_target_release}-${VARIANT}"
    set -u

    if (( DO_CLEAN )); then
        log "Running installclean"
        m installclean
    fi

    log "Building with -j$JOBS"
    m bacon -j"$JOBS"

    local out="$SRC_DIR/out/target/product/$DEVICE"
    local zip
    zip=$(ls -t "$out"/lineage-*-"$DEVICE".zip 2>/dev/null | head -1)
    [[ -n "$zip" ]] || die "Build finished but no zip found in $out"

    local rel="$SCRIPT_DIR/releases"
    mkdir -p "$rel"
    ln -f "$zip" "$rel/" 2>/dev/null || cp "$zip" "$rel/"
    ln -f "$out/recovery.img" "$rel/" 2>/dev/null || cp "$out/recovery.img" "$rel/"
    (cd "$rel" && sha256sum "$(basename "$zip")" recovery.img > SHA256SUMS)

    log "Done:"
    ls -lh "$rel"
}

check_host
if (( DO_SYNC ));  then sync_sources; fi
if (( DO_BUILD )); then build; fi
exit 0
