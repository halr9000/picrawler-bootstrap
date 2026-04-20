#!/usr/bin/env bash
# =============================================================================
# picrawler-setup.sh
# Base environment setup for Raspberry Pi Zero 2 W (64-bit Raspberry Pi OS)
# + SunFounder PiCrawler
#
# Usage:
#   ./picrawler-setup.sh                          # interactive, all modules
#   ./picrawler-setup.sh --headless               # no prompts, all modules
#   ./picrawler-setup.sh --skip claude,opencode   # skip specific modules
#   ./picrawler-setup.sh --only nvm,node,pnpm     # run only these modules
#   ./picrawler-setup.sh --list                   # print available module names
#   ./picrawler-setup.sh --help
#
# Module names:
#   syspkgs  hwgroups  nvm  node  pnpm  uv  robot-hat  vilib  picrawler
#   i2samp   claude  opencode  interfaces  profile  demos
# =============================================================================

set -euo pipefail

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Config ────────────────────────────────────────────────────────────────────
NODE_VERSION="lts/*"
NVM_VERSION="0.40.1"
INSTALL_DIR="${HOME}"

# Log file for verbose output from long-running installers
LOGFILE="/tmp/picrawler-setup-$(date +%Y%m%d-%H%M%S).log"

# ── Module registry (ordered) ─────────────────────────────────────────────────
# NOTE: 'claude' is excluded by default — Claude Code requires 4 GB RAM minimum
# and has a known aarch64 detection bug (github.com/anthropics/claude-code/issues/3569).
# The Pi Zero 2 W has 512 MB; npm installs OOM. Use claude on a Pi 4/5 instead.
ALL_MODULES=(syspkgs hwgroups nvm node pnpm uv robot-hat vilib picrawler i2samp opencode interfaces profile demos)

# ── Arg parsing ───────────────────────────────────────────────────────────────
HEADLESS=false
SKIP_MODULES=()
ONLY_MODULES=()

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --headless          Non-interactive; auto-answer yes to all prompts
  --skip  <modules>   Comma-separated module names to skip
  --only  <modules>   Comma-separated module names to run (skips all others)
  --list              Print all available module names and exit
  --help              Show this help

Module names: ${ALL_MODULES[*]}

Examples:
  $(basename "$0") --skip claude,opencode
  $(basename "$0") --only nvm,node,pnpm
  $(basename "$0") --headless --skip i2samp,interfaces
EOF
}

parse_csv() {
  local input="$1"
  IFS=',' read -ra ITEMS <<< "$input"
  printf '%s\n' "${ITEMS[@]}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --headless) HEADLESS=true ;;
    --skip)     mapfile -t SKIP_MODULES < <(parse_csv "${2:-}"); shift ;;
    --only)     mapfile -t ONLY_MODULES < <(parse_csv "${2:-}"); shift ;;
    --list)     echo "Available modules: ${ALL_MODULES[*]}"; exit 0 ;;
    --help|-h)  usage; exit 0 ;;
    *)          echo "Unknown option: $1"; usage; exit 1 ;;
  esac
  shift
done

# ── Module gate ────────────────────────────────────────────────────────────────
module_enabled() {
  local name="$1"
  if [[ ${#ONLY_MODULES[@]} -gt 0 ]]; then
    for m in "${ONLY_MODULES[@]}"; do
      [[ "$m" == "$name" ]] && return 0
    done
    return 1
  fi
  for m in "${SKIP_MODULES[@]}"; do
    [[ "$m" == "$name" ]] && return 1
  done
  return 0
}

# ── Helpers ───────────────────────────────────────────────────────────────────
log()     { echo -e "${CYAN}[setup]${RESET} $*" | tee -a "$LOGFILE"; }
ok()      { echo -e "${GREEN}[  ok ]${RESET} $*" | tee -a "$LOGFILE"; }
warn()    { echo -e "${YELLOW}[ warn]${RESET} $*" | tee -a "$LOGFILE"; }
skip()    { echo -e "${YELLOW}[ skip]${RESET} $*" | tee -a "$LOGFILE"; }
die()     { echo -e "${RED}[error]${RESET} $*" | tee -a "$LOGFILE" >&2; exit 1; }
section() {
  echo -e "\n${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}" | tee -a "$LOGFILE"
  echo -e "${BOLD}  $*${RESET}" | tee -a "$LOGFILE"
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}" | tee -a "$LOGFILE"
}

# run_logged: run a command, stream verbose output only to LOGFILE,
# show a spinner on the terminal. On failure, print the tail to stderr.
run_with_spinner() {
  local label="$1"; shift
  local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  local i=0
  echo "" >> "$LOGFILE"
  echo ">>> ${label}: $*" >> "$LOGFILE"
  "$@" >>"$LOGFILE" 2>&1 &
  local pid=$!
  tput civis 2>/dev/null || true
  while kill -0 "$pid" 2>/dev/null; do
    printf "\r  ${CYAN}%s${RESET}  %s" "${frames[$i]}" "$label"
    i=$(( (i+1) % ${#frames[@]} ))
    sleep 0.15
  done
  tput cnorm 2>/dev/null || true
  local exit_code=0
  wait "$pid" || exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    printf "\r  ${RED}✗${RESET}  %-50s\n" "$label"
    echo -e "${RED}[error]${RESET} Command failed (exit ${exit_code}). Last 20 lines of log:" >&2
    tail -20 "$LOGFILE" >&2
    die "See full log: ${LOGFILE}"
  fi
  printf "\r  ${GREEN}✓${RESET}  %-50s\n" "$label"
}

# run_streamed: run a command with output going to BOTH terminal and LOGFILE.
# Use for long installers (SunFounder libs, i2samp) where visibility matters.
run_streamed() {
  local label="$1"; shift
  echo "" >> "$LOGFILE"
  echo ">>> ${label}: $*" >> "$LOGFILE"
  log "${label} (output below — also logged to ${LOGFILE})"
  "$@" 2>&1 | tee -a "$LOGFILE"
  # tee exits 0 even if the command fails; capture via PIPESTATUS
  local exit_code="${PIPESTATUS[0]}"
  [[ $exit_code -eq 0 ]] || die "${label} failed (exit ${exit_code}). See ${LOGFILE}"
}

ask() {
  $HEADLESS && return 0
  local prompt
  printf -v prompt $'  \033[1;33m?\033[0m  %s [Y/n]: ' "$1"
  local response
  read -r -p "$prompt" response
  [[ "${response,,}" != "n" ]]
}

cmd_exists() { command -v "$1" &>/dev/null; }

source_nvm() {
  export NVM_DIR="${HOME}/.nvm"
  [[ -s "${NVM_DIR}/nvm.sh" ]] && source "${NVM_DIR}/nvm.sh" || true
}

source_pnpm() {
  for candidate in \
    "${PNPM_HOME:-}" \
    "${HOME}/.pnpm" \
    "${HOME}/.local/share/pnpm"
  do
    [[ -n "$candidate" && -x "${candidate}/pnpm" ]] && \
      export PNPM_HOME="$candidate" && \
      export PATH="${candidate}:${PATH}" && return 0
  done
  return 1
}

# ── Pre-flight ────────────────────────────────────────────────────────────────
# Initialise log file before first section() call
: > "$LOGFILE"
echo "picrawler-setup started $(date)" >> "$LOGFILE"

section "Pre-flight"
log "Detailed log: ${LOGFILE}"

[[ "${EUID}" -eq 0 ]] && die "Run as your normal user, not root. sudo is invoked internally where needed."

# ── Sudo bootstrap ────────────────────────────────────────────────────────────
if ! sudo -n true 2>/dev/null; then
  log "sudo requires a password. Prompting once now..."
  sudo -v || die "sudo authentication failed – cannot continue"
fi
( while true; do sudo -n true 2>/dev/null; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) &
SUDO_KEEPALIVE_PID=$!
trap 'kill "${SUDO_KEEPALIVE_PID}" 2>/dev/null || true' EXIT
ok "sudo ready – credential keepalive active (pid ${SUDO_KEEPALIVE_PID})"

ARCH="$(uname -m)"
if [[ "$ARCH" != "aarch64" ]]; then
  warn "Architecture is '${ARCH}'; this script targets aarch64 (64-bit Raspberry Pi OS)."
  ask "Continue anyway?" || exit 0
fi

ok "User: ${USER}  Arch: ${ARCH}  Headless: ${HEADLESS}"
[[ ${#SKIP_MODULES[@]} -gt 0 ]] && log "Skipping modules: ${SKIP_MODULES[*]}"
[[ ${#ONLY_MODULES[@]} -gt 0 ]] && log "Running only modules: ${ONLY_MODULES[*]}"

validate_modules() {
  local -a input=("$@")
  for name in "${input[@]}"; do
    local found=false
    for m in "${ALL_MODULES[@]}"; do
      [[ "$m" == "$name" ]] && found=true && break
    done
    $found || die "Unknown module name: '${name}'. Run --list to see valid names."
  done
}
validate_modules "${SKIP_MODULES[@]}" "${ONLY_MODULES[@]}"

# Track overall success for post-install steps
SETUP_ERRORS=0
run_module_safe() {
  local name="$1"
  local fn="install_${name//-/_}"
  if declare -f "$fn" > /dev/null; then
    "$fn" || { warn "Module '${name}' reported an error"; SETUP_ERRORS=$(( SETUP_ERRORS + 1 )); }
  else
    warn "No implementation found for module '${name}' (expected '${fn}')"
  fi
}

# =============================================================================
# MODULE IMPLEMENTATIONS
# =============================================================================

# ── syspkgs ──────────────────────────────────────────────────────────────────
install_syspkgs() {
  section "System packages  [syspkgs]"
  local pkgs=(
    git curl wget build-essential
    python3 python3-pip python3-setuptools python3-smbus python3-dev
    libssl-dev libffi-dev
    i2c-tools ffmpeg
    libopenblas-dev libjpeg-dev zlib1g-dev
  )
  local missing=()
  for pkg in "${pkgs[@]}"; do
    dpkg -s "$pkg" &>/dev/null || missing+=("$pkg")
  done
  if [[ ${#missing[@]} -eq 0 ]]; then
    ok "All system packages already installed"
    return
  fi
  log "Missing: ${missing[*]}"
  if ask "Install missing system packages via apt?"; then
    run_with_spinner "apt update" sudo -n apt-get update -qq
    run_with_spinner "Installing system packages" \
      sudo -n apt-get install -y -qq "${missing[@]}"
    ok "System packages installed"
  else
    warn "Skipping – some later modules may fail"
  fi
}

# ── hwgroups ─────────────────────────────────────────────────────────────────
install_hwgroups() {
  section "Hardware groups (gpio, i2c, spi)  [hwgroups]"

  local needs_groups=false
  for grp in gpio i2c spi; do
    if ! groups "${USER}" | grep -qw "$grp"; then
      needs_groups=true
      break
    fi
  done

  if ! $needs_groups; then
    ok "User ${USER} already in gpio, i2c, spi groups"
  else
    if ask "Add ${USER} to gpio, i2c, spi groups?"; then
      run_with_spinner "Adding user to hardware groups" \
        sudo -n usermod -aG gpio,i2c,spi "${USER}"
      ok "Groups added – will take effect after re-login or reboot"
    else
      warn "Skipping group membership – demos will need sudo to access GPIO"
    fi
  fi

  # Udev rule so /dev/gpiomem stays group-writable after every reboot
  local udev_rule="/etc/udev/rules.d/99-gpio.rules"
  if [[ -f "$udev_rule" ]]; then
    ok "udev rule already present (${udev_rule})"
  else
    if ask "Install udev rule for /dev/gpiomem group access?"; then
      sudo -n tee "$udev_rule" > /dev/null <<'UDEVRULES'
SUBSYSTEM=="bcm2835-gpiomem", KERNEL=="gpiomem", GROUP="gpio", MODE="0660"
SUBSYSTEM=="gpio", KERNEL=="gpiochip*", ACTION=="add", PROGRAM="/bin/sh -c 'chown root:gpio /sys/class/gpio/export /sys/class/gpio/unexport ; chmod 220 /sys/class/gpio/export /sys/class/gpio/unexport'"
SUBSYSTEM=="gpio", KERNEL=="gpio*",  ACTION=="add", PROGRAM="/bin/sh -c 'chown root:gpio /sys%p/active_low /sys%p/direction /sys%p/edge /sys%p/value ; chmod 660 /sys%p/active_low /sys%p/direction /sys%p/edge /sys%p/value'"
SUBSYSTEM=="i2c-dev", GROUP="i2c", MODE="0660"
SUBSYSTEM=="spidev", GROUP="spi", MODE="0660"
UDEVRULES
      run_with_spinner "Reloading udev rules" \
        bash -c "sudo -n udevadm control --reload-rules && sudo -n udevadm trigger"
      ok "udev rule installed and activated"
    else
      warn "Skipping udev rule"
    fi
  fi
}

# ── nvm ───────────────────────────────────────────────────────────────────────
install_nvm() {
  section "nvm  [nvm]"
  source_nvm
  if cmd_exists nvm; then
    ok "nvm already installed ($(nvm --version))"
    return
  fi
  if ask "Install nvm v${NVM_VERSION}?"; then
    run_with_spinner "Downloading nvm installer" \
      bash -c "curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh -o /tmp/nvm-install.sh"
    run_with_spinner "Installing nvm" bash /tmp/nvm-install.sh
    rm -f /tmp/nvm-install.sh
    source_nvm
    ok "nvm $(nvm --version) installed"
  else
    warn "Skipping nvm"
  fi
}

# ── node ──────────────────────────────────────────────────────────────────────
install_node() {
  section "Node.js LTS  [node]"
  source_nvm
  if cmd_exists node; then
    ok "Node.js already installed ($(node --version))"
    return
  fi
  if ! cmd_exists nvm; then
    warn "nvm not available – skipping Node.js (run the 'nvm' module first)"
    return
  fi
  if ask "Install Node.js LTS via nvm?"; then
    run_with_spinner "Installing Node.js LTS (takes a few minutes on Pi Zero 2 W)" \
      bash -c "source '${NVM_DIR}/nvm.sh' && nvm install '${NODE_VERSION}' && nvm alias default '${NODE_VERSION}'"
    source_nvm
    ok "Node.js $(node --version) installed"
  else
    warn "Skipping Node.js"
  fi
}

# ── pnpm ──────────────────────────────────────────────────────────────────────
install_pnpm() {
  section "pnpm  [pnpm]"
  source_pnpm || true
  if cmd_exists pnpm; then
    ok "pnpm already installed ($(pnpm --version))"
    return
  fi
  if ask "Install pnpm?"; then
    run_with_spinner "Installing pnpm" \
      bash -c "curl -fsSL https://get.pnpm.io/install.sh | sh -"
    source_pnpm || true
    ok "pnpm $(pnpm --version 2>/dev/null || echo 'installed') installed"
  else
    warn "Skipping pnpm"
  fi
}

# ── uv ────────────────────────────────────────────────────────────────────────
install_uv() {
  section "uv + uvx  [uv]"
  if cmd_exists uv; then
    ok "uv already installed ($(uv --version))"
    return
  fi
  if ask "Install uv (and uvx) via the official Astral installer?"; then
    run_with_spinner "Installing uv" \
      bash -c "curl -LsSf https://astral.sh/uv/install.sh | sh"
    [[ -f "${HOME}/.local/bin/env" ]] && source "${HOME}/.local/bin/env" || true
    export PATH="${HOME}/.local/bin:${PATH}"
    ok "uv $(uv --version) installed"
  else
    warn "Skipping uv"
  fi
  cmd_exists uvx && ok "uvx available" || true
}

# ── robot-hat ─────────────────────────────────────────────────────────────────
install_robot_hat() {
  section "SunFounder robot-hat  [robot-hat]"
  local dir="${INSTALL_DIR}/robot-hat"
  if pip3 show robot_hat &>/dev/null; then
    ok "robot-hat already installed ($(pip3 show robot_hat | grep ^Version | cut -d' ' -f2))"
    return
  fi
  if ask "Clone and install robot-hat?"; then
    if [[ -d "$dir" ]]; then
      run_with_spinner "Updating robot-hat repo" git -C "$dir" pull --ff-only
    else
      run_with_spinner "Cloning robot-hat" \
        git clone --depth 1 https://github.com/sunfounder/robot-hat.git "$dir"
    fi
    run_streamed "Installing robot-hat" bash -c "cd '${dir}' && sudo -n python3 setup.py install"
    ok "robot-hat installed"
  else
    warn "Skipping robot-hat"
  fi
}

# ── vilib ─────────────────────────────────────────────────────────────────────
install_vilib() {
  section "SunFounder vilib  [vilib]"
  local dir="${INSTALL_DIR}/vilib"
  if pip3 show vilib &>/dev/null; then
    ok "vilib already installed ($(pip3 show vilib | grep ^Version | cut -d' ' -f2))"
    return
  fi
  if ask "Clone and install vilib? (pulls OpenCV + camera deps – slow on Pi Zero)"; then
    if [[ -d "$dir" ]]; then
      run_with_spinner "Updating vilib repo" git -C "$dir" pull --ff-only
    else
      run_with_spinner "Cloning vilib (picamera2 branch)" \
        git clone --depth 1 -b picamera2 https://github.com/sunfounder/vilib.git "$dir"
    fi
    run_streamed "Installing vilib (this takes a while on Pi Zero)" \
      bash -c "cd '${dir}' && sudo -n python3 install.py"
    ok "vilib installed"
  else
    warn "Skipping vilib"
  fi
}

# ── picrawler ─────────────────────────────────────────────────────────────────
install_picrawler() {
  section "SunFounder picrawler  [picrawler]"
  local dir="${INSTALL_DIR}/picrawler"
  if pip3 show picrawler &>/dev/null; then
    ok "picrawler already installed ($(pip3 show picrawler | grep ^Version | cut -d' ' -f2))"
    return
  fi
  if ask "Clone and install picrawler?"; then
    if [[ -d "$dir" ]]; then
      run_with_spinner "Updating picrawler repo" git -C "$dir" pull --ff-only
    else
      run_with_spinner "Cloning picrawler" \
        git clone --depth 1 https://github.com/sunfounder/picrawler.git "$dir"
    fi
    run_streamed "Installing picrawler" \
      bash -c "cd '${dir}' && sudo -n python3 setup.py install"
    ok "picrawler installed"
  else
    warn "Skipping picrawler"
  fi
}

# ── demos ────────────────────────────────────────────────────────────────────
install_demos() {
  section "claw9000-demos  [demos]"
  local dir="${INSTALL_DIR}/claw9000-demos"
  if [[ -d "$dir" ]]; then
    run_with_spinner "Updating claw9000-demos" git -C "$dir" pull --ff-only
    ok "claw9000-demos up to date"
  else
    if ask "Clone claw9000-demos to ${dir}?"; then
      run_with_spinner "Cloning claw9000-demos" \
        git clone --depth 1 https://github.com/halr9000/claw9000-demos.git "$dir"
      ok "claw9000-demos cloned"
    else
      warn "Skipping claw9000-demos"
    fi
  fi
}

# ── i2samp ────────────────────────────────────────────────────────────────────
install_i2samp() {
  section "i2s amplifier / speaker  [i2samp]"

  local boot_config="/boot/firmware/config.txt"
  [[ -f "$boot_config" ]] || boot_config="/boot/config.txt"

  if grep -q "^dtoverlay=hifiberry-dac" "${boot_config}" 2>/dev/null; then
    ok "i2s amplifier already configured (dtoverlay present in ${boot_config})"
    return
  fi

  local script="${INSTALL_DIR}/picrawler/i2samp.sh"
  if [[ ! -f "$script" ]]; then
    warn "i2samp.sh not found at ${script}; install 'picrawler' module first"
    return
  fi

  if ask "Run i2samp.sh to enable speaker support? (reboot required)"; then
    # i2samp.sh uses prompt() which does 'read < /dev/tty' – bypasses all
    # stdin tricks. Patch a temp copy to replace both prompt() conditionals
    # with 'if false' so they never execute.
    local tmp_script
    tmp_script="$(mktemp /tmp/i2samp-XXXXXX.sh)"
    cp "${script}" "${tmp_script}"
    sed -i \
      -e 's|if confirm "Do you wish to test your system now?"|if false  # patched: skip speaker test|' \
      -e 's|if prompt "Would you like to reboot now?"|if false  # patched: skip reboot prompt|' \
      "${tmp_script}"

    # Hidden behind spinner — output goes to LOGFILE only
    run_with_spinner "Installing i2s amplifier" \
      sudo -n bash "${tmp_script}" -y
    rm -f "${tmp_script}"
    ok "i2s amplifier configured – reboot to activate"
  else
    log "Skipping i2s amplifier"
  fi
}

# ── claude ────────────────────────────────────────────────────────────────────
# NOT in ALL_MODULES — kept as a callable function for manual use on Pi 4/5.
# Pi Zero 2 W has 512 MB RAM; Claude Code requires 4 GB minimum and has a
# known aarch64 detection bug: github.com/anthropics/claude-code/issues/3569
# Workaround if you want to try anyway (on a higher-RAM Pi):
#   npm install -g @anthropic-ai/claude-code@0.2.114
install_claude() {
  section "Claude Code  [claude]"
  warn "Claude Code is NOT recommended for Pi Zero 2 W (512 MB RAM; requires 4 GB minimum)"
  warn "Known aarch64 bug: github.com/anthropics/claude-code/issues/3569"
  warn "Workaround on Pi 4/5: npm install -g @anthropic-ai/claude-code@0.2.114"
  if cmd_exists claude; then
    ok "Claude Code already installed ($(claude --version 2>/dev/null || echo 'unknown version'))"
    return
  fi
  if ask "Attempt Claude Code install anyway (likely to fail on Pi Zero 2 W)?"; then
    source_nvm
    if cmd_exists npm; then
      warn "Trying npm install – this may OOM on Pi Zero 2 W..."
      run_with_spinner "Installing Claude Code via npm (pinned workaround version)" \
        npm install -g @anthropic-ai/claude-code@0.2.114
    else
      run_with_spinner "Installing Claude Code via native installer" \
        bash -c "curl -fsSL https://claude.ai/install.sh | sh"
    fi
    export PATH="${HOME}/.local/bin:${PATH}"
    cmd_exists claude && ok "claude installed" || warn "'claude' not in PATH – run: source ~/.bashrc"
  else
    warn "Skipping Claude Code"
  fi
}

# ── opencode ──────────────────────────────────────────────────────────────────
install_opencode() {
  section "opencode  [opencode]"
  if cmd_exists opencode; then
    ok "opencode already installed"
    return
  fi
  if ask "Install opencode-ai?"; then
    source_nvm
    if cmd_exists npm; then
      run_with_spinner "Installing opencode-ai via npm" \
        npm install -g opencode-ai@latest
      ok "opencode installed"
    else
      warn "npm not available – falling back to curl installer"
      if ask "Install opencode via curl installer instead?"; then
        run_with_spinner "Installing opencode via curl" \
          bash -c "curl -fsSL https://opencode.ai/install | bash"
        ok "opencode installed"
      else
        warn "Skipping opencode"
      fi
    fi
  else
    warn "Skipping opencode"
  fi
}

# ── interfaces ────────────────────────────────────────────────────────────────
install_interfaces() {
  section "Raspberry Pi interfaces (I2C, Camera)  [interfaces]"
  if ! cmd_exists raspi-config; then
    warn "raspi-config not found – enable I2C and Camera manually via /boot/config.txt"
    return
  fi
  if ask "Enable I2C interface?"; then
    run_with_spinner "Enabling I2C" sudo -n raspi-config nonint do_i2c 0
    ok "I2C enabled"
  fi
  if ask "Enable legacy camera interface?"; then
    run_with_spinner "Enabling camera" sudo -n raspi-config nonint do_camera 0
    ok "Camera enabled – reboot required"
  fi
}

# ── profile ───────────────────────────────────────────────────────────────────
install_profile() {
  section "Shell PATH consolidation  [profile]"
  local profile="${HOME}/.bashrc"
  local marker="# >>> picrawler-setup managed paths >>>"
  if grep -qF "$marker" "$profile" 2>/dev/null; then
    ok "Shell profile already patched"
    return
  fi
  log "Appending PATH entries to ${profile}"
  cat >> "$profile" <<'SHELLBLOCK'

# >>> picrawler-setup managed paths >>>
export NVM_DIR="${HOME}/.nvm"
[ -s "${NVM_DIR}/nvm.sh" ] && source "${NVM_DIR}/nvm.sh"
[ -s "${NVM_DIR}/bash_completion" ] && source "${NVM_DIR}/bash_completion"

export PNPM_HOME="${HOME}/.local/share/pnpm"
export PATH="${HOME}/.local/bin:${PNPM_HOME}:${PATH}"
# <<< picrawler-setup managed paths <<<
SHELLBLOCK
  ok "Profile updated – run: source ${profile}"
}

# =============================================================================
# RUNNER
# =============================================================================

for mod in "${ALL_MODULES[@]}"; do
  if module_enabled "$mod"; then
    run_module_safe "$mod"
  else
    skip "Module '${mod}' excluded"
  fi
done

# =============================================================================
# SUMMARY
# =============================================================================
section "Summary"

source_nvm
source_pnpm || true
export PATH="${HOME}/.local/bin:${PATH}"

print_status() {
  local label="$1" check_cmd="$2"
  if eval "$check_cmd" &>/dev/null; then
    local ver
    ver="$(eval "$check_cmd" 2>/dev/null | head -1 || true)"
    printf "  ${GREEN}✓${RESET}  %-20s %s\n" "$label" "$ver" | tee -a "$LOGFILE"
  else
    printf "  ${RED}✗${RESET}  %-20s %s\n" "$label" "(not found)" | tee -a "$LOGFILE"
    SETUP_ERRORS=$(( SETUP_ERRORS + 1 ))
  fi
}

print_status "python3"    "python3 --version"
print_status "uv"         "uv --version"
print_status "nvm"        "nvm --version"
print_status "node"       "node --version"
print_status "npm"        "npm --version"
print_status "pnpm"       "pnpm --version"

print_status "opencode"   "opencode --version"
print_status "robot-hat"  "pip3 show robot_hat 2>/dev/null | grep ^Version"
print_status "vilib"      "pip3 show vilib 2>/dev/null | grep ^Version"
print_status "picrawler"  "pip3 show picrawler 2>/dev/null | grep ^Version"

echo
log "Full install log: ${LOGFILE}"
log "Verify I2C after reboot: i2cdetect -y 1"
echo

# =============================================================================
# POST-INSTALL: robot motion smoke test
# =============================================================================
section "Post-install: robot motion smoke test"

if pip3 show picrawler &>/dev/null && [[ -f "${INSTALL_DIR}/claw9000-demos/demos/stand_bob_sit.py" ]]; then
  if ask "Run stand_bob_sit.py smoke test now? (robot will move briefly)"; then
    log "Running stand_bob_sit.py via sudo (group membership may not be active yet in this session)..."
    # Use sudo so GPIO access works even before re-login for group membership
    sudo -n python3 "${INSTALL_DIR}/claw9000-demos/demos/stand_bob_sit.py" 2>&1 | tee -a "$LOGFILE" || \
      warn "Smoke test failed – check log: ${LOGFILE}"
  else
    log "Skipping smoke test. Run manually: sudo python3 ~/claw9000-demos/demos/stand_bob_sit.py"
  fi
elif ! pip3 show picrawler &>/dev/null; then
  log "Skipping smoke test – picrawler not installed"
else
  log "Skipping smoke test – claw9000-demos not found (run --only demos)"
fi

# =============================================================================
# POST-INSTALL: tada systemd unit + reboot
# =============================================================================
TADA_UNIT="picrawler-tada.service"
TADA_UNIT_PATH="/etc/systemd/system/${TADA_UNIT}"
TADA_SOUND="/opt/picrawler/tada.wav"

if [[ $SETUP_ERRORS -eq 0 ]]; then
  ok "All modules completed successfully."

  # ── Generate tada WAV (440 Hz beep sequence) ───────────────────────────────
  section "Post-install: tada sound + reboot  [automatic]"

  if [[ ! -f "$TADA_SOUND" ]]; then
    log "Generating tada sound at ${TADA_SOUND}..."
    sudo -n mkdir -p /opt/picrawler
    # Use Python + scipy if available, else ffmpeg sine tone sequence
    if python3 -c "import scipy, numpy, soundfile" &>/dev/null 2>&1; then
      sudo -n python3 - <<'PYEOF'
import numpy as np, soundfile as sf, os
sr = 44100
def tone(freq, dur, vol=0.4):
    t = np.linspace(0, dur, int(sr*dur), False)
    return (np.sin(2*np.pi*freq*t) * vol * 32767).astype(np.int16)
# Simple ta-da: C5 eighth note, then G5 quarter note
samples = np.concatenate([
    tone(523, 0.12), np.zeros(int(sr*0.05), dtype=np.int16),
    tone(659, 0.12), np.zeros(int(sr*0.05), dtype=np.int16),
    tone(784, 0.40),
])
sf.write('/opt/picrawler/tada.wav', samples, sr, subtype='PCM_16')
PYEOF
    else
      # ffmpeg fallback: two-tone beep
      sudo -n ffmpeg -y -loglevel error \
        -f lavfi -i "sine=frequency=523:duration=0.12" \
        -f lavfi -i "sine=frequency=784:duration=0.40" \
        -filter_complex "[0][1]concat=n=2:v=0:a=1,volume=0.4" \
        "$TADA_SOUND"
    fi
    ok "Tada sound created at ${TADA_SOUND}"
  else
    ok "Tada sound already exists at ${TADA_SOUND}"
  fi

  # ── Install systemd unit ───────────────────────────────────────────────────
  if [[ -f "$TADA_UNIT_PATH" ]]; then
    ok "Systemd unit ${TADA_UNIT} already installed – skipping"
  else
    log "Installing ${TADA_UNIT_PATH}..."
    sudo -n tee "$TADA_UNIT_PATH" > /dev/null <<EOF
[Unit]
Description=PiCrawler startup chime
# Run after sound card and aplay service are up, every boot
After=sound.target auto_sound_card.service aplay.service
Wants=auto_sound_card.service

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 5
ExecStart=/usr/bin/aplay -D default ${TADA_SOUND}
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    sudo -n systemctl daemon-reload
    sudo -n systemctl enable "$TADA_UNIT"
    ok "${TADA_UNIT} installed and enabled"
  fi

  # ── Reboot ─────────────────────────────────────────────────────────────────
  echo
  log "Setup complete. Rebooting in 5 seconds to apply all changes..."
  log "(Press Ctrl-C to cancel)"
  sleep 5
  sudo -n reboot

else
  warn "${SETUP_ERRORS} module(s) had errors – skipping tada unit and reboot."
  warn "Fix the issues above, then re-run. Partial runs are safe (already-installed modules are skipped)."
  echo
  log "Full install log: ${LOGFILE}"
fi
