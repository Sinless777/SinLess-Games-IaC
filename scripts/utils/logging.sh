#!/usr/bin/env bash
# =============================================================================
# utils/logging.sh
# A tiny colour‑aware logging helper for repository scripts.
# =============================================================================
#  Usage (in any Bash/Z sh script):
#     source "$(dirname "$0")/../utils/logging.sh"
#     log_info    "Something happened"
#     log_success "Finished fine"
#     log_warn    "That was odd…"
#     log_error   "Something failed, but continuing"
#     log_debug   "Deep‑dive details only visible if you care"
#     log_fatal   "Unrecoverable"        # exits 1
# =============================================================================

# ─── Colour palette ───────────────────────────────────────────────────────────
BLUE="\033[0;34m"
YELLOW="\033[0;33m"
GREEN="\033[0;32m"
RED="\033[0;31m"
GREY="\033[0;90m"     # NEW: subdued grey for DEBUG
ITALICS="\033[3m"
BOLD="\033[1m"
RESET="\033[0m"

# ─── Internal helper ─────────────────────────────────────────────────────────
#   _log <colour> <LABEL> <message …>
# ----------------------------------------------------------------------------
_log() {
  local colour="$1" label="$2"; shift 2
  local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
  echo -e "${colour}${BOLD}[${label}] |${RESET} ${timestamp} ${colour}${BOLD}| ${RESET}$*"
}

# ─── Public API ──────────────────────────────────────────────────────────────
log_info()    { _log "$BLUE"   INFO    "$@"; }
log_success() { _log "$GREEN"  SUCCESS "$@"; }
log_warn()    { _log "$YELLOW" WARN    "$@"; }
log_error()   { _log "$RED"    ERROR   "$@"; }
log_debug()   { _log "${GREY}${ITALICS}" DEBUG "$@${RESET}"; }
log_fatal()   { _log "$RED"    FATAL   "$@"; exit 1; }

# vim: set ts=2 sw=2 et:
