#!/usr/bin/env bash
#
# Clone or update Xiaomi Android build repositories into a given root directory.
#
# Usage:
#   ./clone_repos.sh [TARGET_ROOT] [BRANCH]
#
# Examples:
#   ./clone_repos.sh .           # clones into current directory, default branch
#   ./clone_repos.sh ~/android13 thirteen
#
# Features:
#   - Idempotent: if the destination directory exists and is a git repo, it will fetch & fast-forward.
#   - Verifies remote URL matches expected (warns if not).
#   - Supports optional branch selection.
#   - Safe: stops on errors (set -euo pipefail).
#   - Optional parallel mode (set PARALLEL=1 env var).
#
# Environment variables:
#   PARALLEL=1        Enable parallel cloning/updating (requires GNU xargs).
#   GIT_DEPTH=1       If set, performs shallow clone with given depth.
#
set -euo pipefail

# ---------- Configuration ----------
# Array of "repo_url|relative/destination/path"
REPOS=(
  "https://github.com/kartik-commits/device_xiaomi_redwood.git|device/xiaomi/redwood"
  "https://github.com/kartik-commits/device_xiaomi_sm7325-common.git|device/xiaomi/sm7325-common"
  "https://github.com/kartik-commits/vendor_xiaomi_redwood.git|vendor/xiaomi/redwood"
  "https://github.com/kartik-commits/vendor_xiaomi_sm7325-common.git|vendor/xiaomi/sm7325-common"
  "https://gitlab.com/kartik-commits/redwood-firmware.git|vendor/xiaomi/redwood-firmware"
  "https://github.com/kartik-commits/hardware_xiaomi.git|hardware/xiaomi"
)

TARGET_ROOT="${1:-.}"
BRANCH="${2:-}"   # optional: if empty, default remote branch is used

GIT_DEPTH="${GIT_DEPTH:-}"
PARALLEL="${PARALLEL:-0}"

# ---------- Functions ----------
log() { printf "[%s] %s\n" "$(date +'%H:%M:%S')" "$*"; }
warn() { printf "[WARN] %s\n" "$*" >&2; }
err() { printf "[ERROR] %s\n" "$*" >&2; }

clone_or_update() {
  local spec="$1"
  local repo url dest depth_args branch_args
  url="${spec%%|*}"
  dest_rel="${spec##*|}"
  dest="${TARGET_ROOT%/}/$dest_rel"

  depth_args=()
  [[ -n "${GIT_DEPTH}" ]] && depth_args=(--depth "$GIT_DEPTH")

  branch_args=()
  [[ -n "${BRANCH}" ]] && branch_args=(-b "$BRANCH")

  if [[ -d "$dest/.git" ]]; then
    log "Updating existing repo: $dest_rel"
    (
      cd "$dest"
      # Validate remote
      current_url="$(git remote get-url origin || true)"
      if [[ "$current_url" != "$url" ]]; then
        warn "Remote URL mismatch in $dest_rel (have: $current_url, expected: $url)"
      fi
      git fetch --all --prune
      # If a branch specified, ensure it exists locally
      if [[ -n "${BRANCH}" ]]; then
        if git rev-parse --verify "$BRANCH" >/dev/null 2>&1; then
          git checkout "$BRANCH"
        else
          git checkout -b "$BRANCH" "origin/$BRANCH"
        fi
      fi
      git pull --ff-only || {
        warn "Fast-forward failed in $dest_rel. Manual merge may be required."
      }
    )
  else
    log "Cloning $url -> $dest_rel"
    mkdir -p "$(dirname "$dest")"
    git clone "${branch_args[@]}" "${depth_args[@]}" "$url" "$dest"
  fi
}

export -f clone_or_update log warn err
export TARGET_ROOT BRANCH GIT_DEPTH

main() {
  log "Target root: $TARGET_ROOT"
  [[ -n "$BRANCH" ]] && log "Requested branch: $BRANCH"
  [[ -n "$GIT_DEPTH" ]] && log "Shallow depth: $GIT_DEPTH"
  if [[ "$PARALLEL" == "1" ]]; then
    log "Running in parallel mode"
    printf "%s\n" "${REPOS[@]}" | xargs -I{} -P "$(nproc || echo 4)" bash -c 'clone_or_update "$@"' _ {}
  else
    for r in "${REPOS[@]}"; do
      clone_or_update "$r"
    done
  fi
  log "All operations completed."
}

main "$@"
