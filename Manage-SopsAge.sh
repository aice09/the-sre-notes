#!/usr/bin/env bash
# Manage-SopsAge.sh
# SOPS + age manager for Linux and macOS (Bash).
# Press Enter at version prompts to use the latest stable release.
# Does not delete age private keys or unrelated files.

set -o pipefail

APP_NAME="SOPS + age Manager"
USER_BIN="${HOME}/.local/bin"
SYSTEM_BIN="/usr/local/bin"
AGE_KEY_PATH="${HOME}/.config/sops/age/keys.txt"
SOPS_REPO="getsops/sops"
AGE_REPO="FiloSottile/age"
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"

case "$ARCH" in
  x86_64|amd64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  armv7l|armv6l) ARCH="arm" ;;
  *) ARCH="$ARCH" ;;
esac

case "$OS" in
  linux) ;;
  darwin) ;;
  *)
    printf 'Unsupported OS: %s. Use Linux/macOS Bash, WSL, or Git Bash with appropriate binaries.\n' "$OS" >&2
    exit 1
    ;;
esac

TMP_DIR=""

cleanup() {
  if [[ -n "${TMP_DIR:-}" && -d "$TMP_DIR" ]]; then
    rm -rf -- "$TMP_DIR"
  fi
}
trap cleanup EXIT

have_cmd() { command -v "$1" >/dev/null 2>&1; }

path_scope_for_file() {
  local file="$1"
  local dir
  dir="$(dirname "$file")"
  local user_path="${PATH:-}"
  local system_path=""
  local entry

  # Report the scope by checking PATH components, not merely file existence.
  IFS=':' read -r -a entries <<< "$user_path"
  for entry in "${entries[@]}"; do
    [[ -z "$entry" ]] && entry="."
    if [[ "$entry" == "$dir" && -x "$file" ]]; then
      printf 'User PATH: %s\n' "$dir"
      return
    fi
  done

  # Common system-wide PATH directories; output only if the executable is in PATH.
  IFS=':' read -r -a entries <<< "${PATH:-}"
  for entry in "${entries[@]}"; do
    [[ -z "$entry" ]] && entry="."
    case "$entry" in
      /usr/bin|/usr/local/bin|/bin|/opt/homebrew/bin|/usr/sbin|/sbin)
        if [[ "$entry" == "$dir" && -x "$file" ]]; then
          printf 'System PATH: %s\n' "$dir"
          return
        fi
        ;;
    esac
  done
}

get_latest_version() {
  local repo="$1"
  curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" |
    sed -n 's/.*"tag_name":[[:space:]]*"v\{0,1\}\([^"]*\)".*/\1/p' |
    head -n 1
}

ask_version() {
  local name="$1" latest="$2" answer
  if [[ -z "$latest" ]]; then
    printf 'Could not determine latest stable %s version from GitHub.\n' "$name" >&2
    return 1
  fi
  printf '%s latest stable version: %s\n' "$name" "$latest"
  read -r -p "Version to install (press Enter for latest): " answer
  answer="${answer#v}"
  printf '%s' "${answer:-$latest}"
}

choose_install_dir() {
  local scope
  printf '\nInstall scope:\n1. User ($USER_BIN)\n2. System ($SYSTEM_BIN; requires write permission/sudo)\n'
  read -r -p "Choose scope [1]: " scope
  case "$scope" in
    2) printf '%s' "$SYSTEM_BIN" ;;
    *) printf '%s' "$USER_BIN" ;;
  esac
}

ensure_path_setup() {
  local dir="$1" rcfile line
  case ":${PATH:-}:" in
    *":$dir:"*) ;;
    *)
      case "${SHELL##*/}" in
        zsh) rcfile="$HOME/.zshrc" ;;
        *) rcfile="$HOME/.bashrc" ;;
      esac
      line="export PATH=\"\$HOME/.local/bin:\$PATH\""
      if [[ "$dir" == "$USER_BIN" ]]; then
        touch "$rcfile"
        if ! grep -Fq "$line" "$rcfile"; then
          printf '\n# Added by Manage-SopsAge.sh\n%s\n' "$line" >> "$rcfile"
        fi
        export PATH="$dir:$PATH"
        printf 'Added %s to PATH in %s (open a new shell or source the file).\n' "$dir" "$rcfile"
      else
        printf 'System directory selected: %s\n' "$dir"
        printf 'Ensure %s is in system PATH if it is not already.\n' "$dir"
      fi
      ;;
  esac
}

download_file() {
  local url="$1" out="$2"
  curl --fail --location --silent --show-error "$url" -o "$out"
}

install_sops() {
  local latest version asset url target install_dir tmpfile
  have_cmd curl || { echo "curl is required." >&2; return 1; }
  have_cmd tar || { echo "tar is required." >&2; return 1; }
  latest="$(get_latest_version "$SOPS_REPO")"
  version="$(ask_version SOPS "$latest")" || return 1
  install_dir="$(choose_install_dir)"
  target="$install_dir/sops"

  TMP_DIR="$(mktemp -d)"
  mkdir -p "$install_dir" || return 1

  # Official SOPS release asset naming: sops-vVERSION.OS.ARCH
  asset="sops-v${version}.${OS}.${ARCH}"
  url="https://github.com/${SOPS_REPO}/releases/download/v${version}/${asset}"
  tmpfile="$TMP_DIR/sops"
  printf 'Downloading %s\n' "$url"
  download_file "$url" "$tmpfile" || {
    echo "Download failed. Check that this SOPS version has an asset named $asset." >&2
    return 1
  }
  chmod 0755 "$tmpfile"
  if ! "$tmpfile" --version >/dev/null 2>&1; then
    echo "Downloaded SOPS binary failed its version check." >&2
    return 1
  fi

  if [[ "$install_dir" == "$SYSTEM_BIN" && ! -w "$install_dir" ]]; then
    sudo install -m 0755 "$tmpfile" "$target" || return 1
  else
    install -m 0755 "$tmpfile" "$target" || return 1
  fi
  ensure_path_setup "$install_dir"
  printf 'SOPS installed at: %s\n' "$target"
  show_status
}

install_age() {
  local latest version install_dir target_age target_keygen archive url extract_dir found_age found_keygen
  have_cmd curl || { echo "curl is required." >&2; return 1; }
  have_cmd tar || { echo "tar is required." >&2; return 1; }

  latest="$(get_latest_version "$AGE_REPO")"
  version="$(ask_version age "$latest")" || return 1
  install_dir="$(choose_install_dir)"
  target_age="$install_dir/age"
  target_keygen="$install_dir/age-keygen"

  TMP_DIR="$(mktemp -d)"
  archive="$TMP_DIR/age.tar.gz"
  extract_dir="$TMP_DIR/extracted"
  mkdir -p "$install_dir" "$extract_dir" || return 1

  # Official age release archives are named age-vVERSION-OS-ARCH.tar.gz.
  url="https://github.com/${AGE_REPO}/releases/download/v${version}/age-v${version}-${OS}-${ARCH}.tar.gz"
  printf 'Downloading %s\n' "$url"
  if ! download_file "$url" "$archive"; then
    echo "Download failed. This release may not publish an archive for ${OS}/${ARCH}." >&2
    return 1
  fi
  tar -xzf "$archive" -C "$extract_dir" || return 1

  found_age="$(find "$extract_dir" -type f -name age -perm -u+x -print -quit)"
  found_keygen="$(find "$extract_dir" -type f -name age-keygen -perm -u+x -print -quit)"
  [[ -n "$found_age" && -n "$found_keygen" ]] || {
    echo "Could not find both age and age-keygen in the downloaded archive." >&2
    return 1
  }

  if [[ "$install_dir" == "$SYSTEM_BIN" && ! -w "$install_dir" ]]; then
    sudo install -m 0755 "$found_age" "$target_age" || return 1
    sudo install -m 0755 "$found_keygen" "$target_keygen" || return 1
  else
    install -m 0755 "$found_age" "$target_age" || return 1
    install -m 0755 "$found_keygen" "$target_keygen" || return 1
  fi
  ensure_path_setup "$install_dir"
  printf 'age installed at: %s\n' "$target_age"
  printf 'age-keygen installed at: %s\n' "$target_keygen"
  show_status
}

uninstall_sops() {
  local scope target
  printf 'SOPS executable locations:\n'
  command -v sops || true
  printf 'Remove SOPS from:\n1. User install path (%s)\n2. System install path (%s)\n' "$USER_BIN" "$SYSTEM_BIN"
  read -r -p "Choose scope [1]: " scope
  if [[ "$scope" == "2" ]]; then target="$SYSTEM_BIN/sops"; else target="$USER_BIN/sops"; fi

  if [[ -f "$target" ]]; then
    if [[ "$target" == "$SYSTEM_BIN/"* && ! -w "$target" ]]; then
      sudo rm -f -- "$target"
    else
      rm -f -- "$target"
    fi
    printf 'Removed %s\n' "$target"
  else
    printf 'SOPS not found at %s\n' "$target"
  fi
  show_status
}

uninstall_age() {
  local scope dir
  printf 'Remove age from:\n1. User install path (%s)\n2. System install path (%s)\n' "$USER_BIN" "$SYSTEM_BIN"
  read -r -p "Choose scope [1]: " scope
  if [[ "$scope" == "2" ]]; then dir="$SYSTEM_BIN"; else dir="$USER_BIN"; fi

  local removed=0 file
  for file in "$dir/age" "$dir/age-keygen"; do
    if [[ -f "$file" ]]; then
      if [[ "$dir" == "$SYSTEM_BIN" && ! -w "$file" ]]; then
        sudo rm -f -- "$file" || return 1
      else
        rm -f -- "$file" || return 1
      fi
      printf 'Removed %s\n' "$file"
      removed=1
    fi
  done
  if [[ "$removed" -eq 0 ]]; then printf 'age executables not found in %s\n' "$dir"; fi
  printf 'Age private key was preserved: %s\n' "$AGE_KEY_PATH"
  show_status
}

show_status() {
  local sops_user="" sops_system="" age_user="" age_system="" keygen_user="" keygen_system
  [[ -x "$USER_BIN/sops" ]] && sops_user="$USER_BIN"
  [[ -x "$SYSTEM_BIN/sops" ]] && sops_system="$SYSTEM_BIN"
  [[ -x "$USER_BIN/age" || -x "$USER_BIN/age-keygen" ]] && age_user="$USER_BIN"
  [[ -x "$SYSTEM_BIN/age" || -x "$SYSTEM_BIN/age-keygen" ]] && age_system="$SYSTEM_BIN"

  printf '\n--- Installation paths ---\n'
  printf 'SOPS User PATH:    %s\n' "$sops_user"
  printf 'SOPS System PATH:  %s\n' "$sops_system"
  printf 'age User PATH:     %s\n' "$age_user"
  printf 'age System PATH:   %s\n' "$age_system"
}

main_menu() {
  while true; do
    printf '\n===== SOPS + age Manager =====\n'
    printf '1. Install SOPS\n'
    printf '2. Update SOPS\n'
    printf '3. Uninstall SOPS\n'
    printf '4. Install age\n'
    printf '5. Update age\n'
    printf '6. Uninstall age\n'
    printf '7. Show status and installation paths\n'
    printf '9. Exit\n'
    read -r -p 'Select an action: ' choice

    case "$choice" in
      1|2) install_sops ;;
      3) uninstall_sops ;;
      4|5) install_age ;;
      6) uninstall_age ;;
      7) show_status ;;
      9) return 0 ;;
      *) printf 'Invalid choice.\n' ;;
    esac
    read -r -p 'Press Enter to continue...' _
  done
}

main_menu
