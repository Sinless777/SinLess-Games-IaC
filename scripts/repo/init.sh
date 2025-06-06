#!/usr/bin/env bash
#================================================================================
# scripts/repo/init.sh
#
# Purpose: Initialize the local development environment for the repository.
#   1. Ensure Homebrew is available, then install everything listed in files/Brewfile.
#   2. Detect & repair common Linuxbrew permission issues (especially on WSL / Docker).
#   3. Parse files/apt_packages.yaml with **yq** and install the declared deb packages.
#   4. Run *dos2unix* across repository shell‑scripts to avoid CRLF shebang problems.
#
# Usage:
#   chmod +x scripts/repo/init.sh && scripts/repo/init.sh
#================================================================================
set -Eeuo pipefail

###############################################################################
# 0. Pre‑flight - line‑ending hygiene (fixes “/usr/bin/env: ‘bash\r’” errors) #
###############################################################################
REPO_ROOT_DIR="$(realpath "$(dirname "$0")/../..")"
find "$REPO_ROOT_DIR/scripts" -type f -name "*.sh" -exec dos2unix {} + >/dev/null 2>&1 || true

# shellcheck source=../utils/logging.sh
source "$(dirname "$0")/../utils/logging.sh"
log_debug "Repository root resolved to: $REPO_ROOT_DIR"

BREWFILE_PATH="$REPO_ROOT_DIR/files/Brewfile"
log_debug "Brewfile path: $BREWFILE_PATH"

########################################
# Helper - does a command exist?       #
########################################
command_exists() {
  command -v "$1" &>/dev/null
}

###############################################################################
# 1. Homebrew                                                                #
###############################################################################
log_info "Checking Homebrew installation…"
if ! command_exists brew; then
  log_info "Homebrew not found - installing…"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Detect prefix automatically (works for macOS, Linux & WSL)
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv 2>/dev/null || /opt/homebrew/bin/brew shellenv)"
  log_success "Homebrew installed."
else
  log_info "Homebrew present - updating…"
  brew update
  log_success "Homebrew is up to date."
fi

###############################################################################
# 2. brew bundle                                                             #
###############################################################################
if [[ -f "$BREWFILE_PATH" ]]; then
  if [[ ! -r "$BREWFILE_PATH" || ! -w "$BREWFILE_PATH" ]]; then
    log_fatal "Cannot read/write Brewfile ($BREWFILE_PATH) - check permissions."
  fi

  log_info "Installing formulas from Brewfile…"
  if brew_output=$(brew bundle --file="$BREWFILE_PATH" 2>&1); then
    log_success "Brew bundle completed."
  else
    brew_status=$?
    log_error "brew bundle failed (status $brew_status)."
    log_debug "$brew_output"
    if grep -qi "Permission denied" <<<"$brew_output"; then
      log_warn "Permission error detected - attempting ownership repair…"
      LINUXBREW_DIR="$(brew --prefix)"
      sudo chown -R "$(whoami):$(id -gn)" "$LINUXBREW_DIR" && brew bundle --file="$BREWFILE_PATH" && \
        log_success "brew bundle succeeded after permission fix." || \
        log_fatal "brew bundle still failing - investigate manually."
    else
      log_fatal "brew bundle failed - see debug output above."
    fi
  fi
else
  log_warn "No Brewfile at $BREWFILE_PATH - skipping Homebrew packages."
fi

###############################################################################
# 3. APT (Debian/Ubuntu/Kali/WSL)                                            #
###############################################################################
log_info "Checking if APT is available…"
if command_exists apt-get; then
  APT_PACKAGES_FILE="$REPO_ROOT_DIR/files/apt_packages.yaml"
  if [[ -f "$APT_PACKAGES_FILE" ]]; then
    log_info "Using $APT_PACKAGES_FILE for deb-package list."

    # Ensure yq is available (install via brew or apt as fallback)
    if ! command_exists yq; then
      if command_exists brew; then
        brew install yq
      else
        sudo apt-get update -qq && sudo apt-get install -y yq
      fi
    fi

    log_info "Updating local APT cache…"
    sudo apt-get update -qq >/dev/null 2>&1 || log_warn "apt-get update encountered issues."
    sudo apt-get upgrade -y -qq >/dev/null 2>&1 || log_warn "apt-get upgrade encountered issues."
    sudo apt-get dist-upgrade -y -qq >/dev/null 2>&1 || log_warn "apt-get dist-upgrade encountered issues."

    # Read all nested arrays under .packages and flatten
    mapfile -t packages < <(yq eval '.packages[][]' "$APT_PACKAGES_FILE" | sort -u)
    if (( ${#packages[@]} )); then
      log_debug "APT packages to install: ${packages[*]}"
      if ! sudo apt-get install -y "${packages[@]}" >/dev/null 2>&1; then
        log_warn "One or more APT installs failed - continuing."
      fi
      log_success "APT installations complete."
    else
      log_warn "No packages found in YAML file - skipping install step."
    fi

    # House‑keeping
    log_info "Cleaning up APT cache…"
    sudo apt-get autoremove -y >/dev/null 2>&1 || log_warn "autoremove encountered problems."
    sudo apt-get clean        >/dev/null 2>&1 || log_warn "clean encountered problems."
  else
    log_warn "File $APT_PACKAGES_FILE not found - skipping APT section."
  fi
else
  log_warn "APT not available on this host - skipping APT section."
fi

###############################################################################
# 4. Python 3.13 virtual‑environment via pipx + pipenv                       #
###############################################################################
log_info "Checking for Python virtual environment (.venv)…"

# ---------- 4.1 Ensure *pipx* is present ----------
if ! command_exists pipx; then
  log_info "pipx not found - installing…"
  if command_exists brew; then
    brew install pipx && pipx ensurepath
  elif command_exists apt-get; then
    sudo apt-get install -y pipx && pipx ensurepath
  else
    python3 -m pip install --user pipx && pipx ensurepath
  fi
  export PATH="$HOME/.local/bin:$PATH"
  log_success "pipx installed."
fi

# ---------- 4.2 Provision or reuse project‑local .venv ----------
export PIPENV_VENV_IN_PROJECT=1  # forces pipenv to place venv under ./\.venv

if [[ ! -d "$REPO_ROOT_DIR/.venv" ]]; then
  log_info "Creating .venv using python3.13…"

  # Install/upgrade pipenv itself under pipx with python 3.13
  pipx reinstall pipenv --python python3.13 >/dev/null 2>&1 || pipx install --python python3.13 --include-deps pipenv

  # Generate the venv **inside the repo**
  ( cd "$REPO_ROOT_DIR" && pipenv --python 3.13 --site-packages --quiet install --dev )
  log_success "Virtual environment created successfully."
else
  log_info ".venv already present - skipping creation."
fi

# ---------- 4.3 Install Pipfile  ----------
if [[]]

# ---------- 4.x Post‑checks ----------
VENV_PY="$REPO_ROOT_DIR/.venv/bin/python"
VENV_PIP="$REPO_ROOT_DIR/.venv/bin/pip"

if [[ ! -x "$VENV_PY" ]]; then
  log_fatal "Python executable missing in .venv - something went wrong."
fi

if ! "$VENV_PY" --version 2>&1 | grep -q "3\.13"; then
  log_warn "Python inside .venv is NOT 3.13 - check your tool‑chain."
else
  log_success "Verified Python 3.13 present in .venv."
fi

if [[ ! -x "$VENV_PIP" ]]; then
  log_fatal "pip not available in .venv - investigate."
fi


###############################################################################
# Done                                                                       #
###############################################################################
log_success "Repository initialization completed successfully."
