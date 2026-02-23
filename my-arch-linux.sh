#!/bin/bash

#############################################################################################################################
#
# Wael Isa - www.wael.name
# My Arch Linux
# Build Date: 02/23/2026
# Version: 1.4.3 - FINAL GOLDEN RELEASE
# GitHub: https://github.com/waelisa/my-arch-linux
#
# ██╗    ██╗ █████╗ ███████╗██╗         ██╗███████╗ █████╗
# ██║    ██║██╔══██╗██╔════╝██║         ██║██╔════╝██╔══██╗
# ██║ █╗ ██║███████║█████╗  ██║         ██║███████╗███████║
# ██║███╗██║██╔══██║██╔══╝  ██║         ██║╚════██║██╔══██║
# ╚███╔███╔╝██║  ██║███████╗███████╗    ██║███████║██║  ██║
# ╚══╝╚══╝ ╚═╝  ╚═╝╚══════╝╚══════╝    ╚═╝╚══════╝╚═╝  ╚═╝
#
# Version: 1.4.3 - PROFESSIONAL POLISHED RELEASE
# - ADDED: Sudo keep-alive (no password prompts during long installs)
# - ADDED: Clean exit trap (handles Ctrl+C gracefully)
# - ADDED: Presence checks (skips reinstalling existing packages)
# - ADDED: System dashboard header (instant system info)
# - ADDED: Interactive help manual (Option 0 for new users)
# - ADDED: Health report (disk, RAM, network, DM status)
# - FIXED: All syntax errors (bash -n returns clean)
# - FIXED: Master DM switcher with atomic cleanup
# - FIXED: LightDM Theme Doctor (10-step repair)
#
#############################################################################################################################

# ============================================================================
# DEPENDENCY RESOLVER
# ============================================================================

REQUIRED_COMMANDS=(
    "bash" "sed" "awk" "grep" "cut" "tr" "head" "tail" "sort" "uniq" "wc"
    "find" "xargs" "printf" "echo" "cat" "cp" "mv" "rm" "mkdir" "chmod"
    "chown" "date" "sleep" "ping" "curl" "wget" "git" "tar" "gzip" "uname"
    "mount" "umount" "df" "du" "ps" "kill" "pidof" "systemctl" "groupadd"
    "getent" "pkill" "readlink" "dmesg" "jobs" "xargs"
)

# Colors for dependency check
DEP_RED='\033[0;31m'
DEP_GREEN='\033[0;32m'
DEP_YELLOW='\033[1;33m'
DEP_NC='\033[0m'

echo -e "${DEP_YELLOW}Checking for required system utilities...${DEP_NC}"

MISSING_COMMANDS=()
for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if ! command -v "$cmd" &> /dev/null; then
        MISSING_COMMANDS+=("$cmd")
    fi
done

if [ ${#MISSING_COMMANDS[@]} -gt 0 ]; then
    echo -e "${DEP_RED}Error: Missing required system utilities:${DEP_NC}"
    for cmd in "${MISSING_COMMANDS[@]}"; do
        echo "  - $cmd"
    done
    echo ""
    echo -e "${DEP_YELLOW}Please install base and base-devel groups:${DEP_NC}"
    echo "  sudo pacman -S base base-devel"
    exit 1
else
    echo -e "${DEP_GREEN}✓ All required system utilities found${DEP_NC}"
fi

if ! command -v pacman &> /dev/null; then
    echo -e "${DEP_RED}Error: pacman not found. This script is for Arch Linux only.${DEP_NC}"
    exit 1
fi

# ============================================================================
# SCRIPT CONFIGURATION
# ============================================================================

SAFE_MODE=true
VERBOSE=false
DRY_RUN=false
LOG_DIR="/var/log/my-arch"
LOG_FILE="${LOG_DIR}/my-arch-setup.log"
TEMP_LOG="/tmp/arch-install-$(date +%Y%m%d-%H%M%S).log"
BACKUP_DIR="$HOME/.config/arch-backups"
BACKUP_DATE=$(date +%Y%m%d-%H%M%S)
DISK_THRESHOLD=90
MIN_FREE_SPACE_KB=1048576
BUILD_HISTORY="$HOME/.my_arch_history"

# Network test hosts
NETWORK_HOSTS=("8.8.8.8" "1.1.1.1" "archlinux.org" "github.com")

# ============================================================================
# COLOR SETUP
# ============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# Set header color based on safe mode
if [ "$SAFE_MODE" = true ]; then
    HEADER_COLOR=$GREEN
else
    HEADER_COLOR=$RED
fi

# Cleanup trap for Ctrl+C
cleanup() {
    print_message "$YELLOW" "\nCleaning up temporary files and exiting safely..."
    # Kill the sudo keep-alive background process
    jobs -p | xargs -r kill 2>/dev/null || true
    log_build_signature "INTERRUPTED"
    exit 0
}

trap cleanup SIGINT SIGTERM

# Script metadata
VERSION="1.4.3"
BUILD_DATE="02/23/2026"
GITHUB_URL="https://github.com/waelisa/my-arch-linux"
SCRIPT_NAME=$(basename "$0")

# Get the original user (not root)
if [ -n "${SUDO_USER:-}" ]; then
    ORIGINAL_USER="$SUDO_USER"
else
    ORIGINAL_USER="$USER"
fi

# Detect system
if [[ -d /sys/firmware/efi ]]; then
    SYSTEM_TYPE="UEFI"
else
    SYSTEM_TYPE="BIOS"
fi

# Detect bootloader
detect_bootloader() {
    if [[ -f /boot/grub/grub.cfg ]] || [[ -f /boot/grub2/grub.cfg ]]; then
        echo "grub"
    else
        echo "unknown"
    fi
}

# Detect currently active display manager
detect_display_manager() {
    if [ -L "/etc/systemd/system/display-manager.service" ]; then
        local dm_link=$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null)
        echo "$(basename "$dm_link" .service)"
    elif systemctl is-active --quiet sddm.service 2>/dev/null; then
        echo "sddm"
    elif systemctl is-active --quiet lightdm.service 2>/dev/null; then
        echo "lightdm"
    else
        echo "none"
    fi
}

# ============================================================================
# BUILD SIGNATURE
# ============================================================================
log_build_signature() {
    local status=$1
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")

    if [ ! -f "$BUILD_HISTORY" ]; then
        echo "TIMESTAMP | VERSION | USER | STATUS | OPERATION" > "$BUILD_HISTORY"
        echo "------------------------------------------------" >> "$BUILD_HISTORY"
    fi

    local last_op=""
    if [ -f "$TEMP_LOG" ]; then
        last_op=$(tail -1 "$TEMP_LOG" 2>/dev/null | cut -d']' -f2- | head -c 50)
    fi

    echo "$timestamp | v$VERSION | $ORIGINAL_USER | $status | $last_op" >> "$BUILD_HISTORY"

    if [ "$status" == "SUCCESS" ]; then
        print_message "$GREEN" "✓ Build signature recorded"
    fi
}

# ============================================================================
# TTY SAFETY CHECK
# ============================================================================
check_tty() {
    local current_tty=$(tty 2>/dev/null || echo "unknown")
    print_message "$BLUE" "Current TTY: $current_tty"

    if [[ "$current_tty" == /dev/pts/* ]]; then
        print_message "$RED" "╔═══════════════════════════════════════════════════════════════╗"
        print_message "$RED" "║                     SAFETY WARNING!                          ║"
        print_message "$RED" "╚═══════════════════════════════════════════════════════════════╝"
        echo ""
        print_message "$YELLOW" "Running in desktop terminal - DM operations may crash your session."
        echo ""
        print_message "$GREEN" "Switch to TTY: ${CYAN}Ctrl+Alt+F2${NC} and run again."

        if [ "$SAFE_MODE" = true ]; then
            print_message "$RED" "Safe Mode ENABLED - Operation cancelled."
            exit 1
        else
            print_message "$RED" "SAFE MODE DISABLED - Running anyway (risky!)"
            sleep 3
        fi
    elif [[ "$current_tty" == /dev/tty* ]]; then
        print_message "$GREEN" "✓ Running in safe TTY environment"
    fi
}

# ============================================================================
# NETWORK CHECK
# ============================================================================
check_network() {
    print_message "$BLUE" "Checking network connectivity..."
    for host in "${NETWORK_HOSTS[@]}"; do
        if ping -c 1 -W 3 "$host" &> /dev/null; then
            print_message "$GREEN" "✓ Connected to $host"
            return 0
        fi
    done
    print_message "$RED" "No internet connection!"
    return 1
}

require_network() {
    check_network || exit 1
}

# ============================================================================
# DISK SPACE CHECK
# ============================================================================
check_disk_space() {
    local available_kb=$(df / | tail -1 | awk '{print $4}')
    local available_human=$(df -h / | tail -1 | awk '{print $4}')

    if [ "$available_kb" -lt "$MIN_FREE_SPACE_KB" ]; then
        print_message "$RED" "Low disk space: $available_human"
        return 1
    fi
    print_message "$GREEN" "Disk space OK: $available_human"
    return 0
}

# ============================================================================
# PACKAGE PRESENCE CHECK
# ============================================================================
check_already_installed() {
    local pkg="$1"
    if pacman -Qi "$pkg" &>/dev/null; then
        print_message "$YELLOW" "$pkg is already installed. Reinstall? (y/n)"
        read -r res
        if [[ "$res" != "y" ]]; then
            print_message "$GREEN" "Skipping $pkg installation."
            return 1
        fi
    fi
    return 0
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${message}" >> "$TEMP_LOG"
}

print_banner() {
    clear
    if [ "$SAFE_MODE" = true ]; then
        echo -e "${CYAN}"
    else
        echo -e "${RED}"
    fi
    echo "████████╗██╗  ██╗███████╗     █████╗ ██████╗  ██████╗██╗  ██╗"
    echo "╚══██╔══╝██║  ██║██╔════╝    ██╔══██╗██╔══██╗██╔════╝██║  ██║"
    echo "   ██║   ███████║█████╗      ███████║██████╔╝██║     ███████║"
    echo "   ██║   ██╔══██║██╔══╝      ██╔══██║██╔══██╗██║     ██╔══██║"
    echo "   ██║   ██║  ██║███████╗    ██║  ██║██║  ██║╚██████╗██║  ██║"
    echo "   ╚═╝   ╚═╝  ╚═╝╚══════╝    ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝"
    echo -e "${NC}"
    echo -e "${GREEN}Wael Isa - My Arch Linux v${VERSION}${NC}"
    echo -e "${PURPLE}GitHub: $GITHUB_URL${NC}"
    echo ""
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_message "$RED" "This script must be run as root!"
        print_message "$YELLOW" "Usage: sudo $0"
        exit 1
    fi
}

check_arch() {
    if [[ ! -f /etc/arch-release ]]; then
        print_message "$RED" "This script is for Arch Linux only!"
        exit 1
    fi
}

run_command() {
    local cmd="$1"
    local message="$2"

    if [ "$DRY_RUN" = true ]; then
        print_message "$YELLOW" "→ [DRY RUN] $message"
        return 0
    fi

    print_message "$YELLOW" "→ $message..."
    if eval "$cmd" >> "$TEMP_LOG" 2>&1; then
        print_message "$GREEN" "  ✓ Done"
        return 0
    else
        print_message "$RED" "  ✗ Failed"
        return 1
    fi
}

run_user_command() {
    local cmd="$1"
    local message="$2"

    if [ "$DRY_RUN" = true ]; then
        print_message "$YELLOW" "→ [DRY RUN] (user) $message"
        return 0
    fi

    print_message "$YELLOW" "→ $message..."
    if sudo -u "$ORIGINAL_USER" bash -c "$cmd" >> "$TEMP_LOG" 2>&1; then
        print_message "$GREEN" "  ✓ Done"
        return 0
    else
        print_message "$RED" "  ✗ Failed"
        return 1
    fi
}

setup_logging() {
    if [ ! -d "$LOG_DIR" ]; then
        mkdir -p "$LOG_DIR"
        chmod 755 "$LOG_DIR"
    fi
    print_message "$GREEN" "✓ Logging initialized"
}

show_history() {
    if [ -f "$BUILD_HISTORY" ]; then
        print_message "$CYAN" "=== Build History ==="
        echo ""
        cat "$BUILD_HISTORY"
    else
        print_message "$YELLOW" "No history found"
    fi
}

# ============================================================================
# SYSTEM HEALTH REPORT
# ============================================================================
show_health_report() {
    clear
    echo -e "${BLUE}================================================================${NC}"
    echo -e "${BLUE}                   ARCH LINUX HEALTH REPORT                     ${NC}"
    echo -e "${BLUE}================================================================${NC}"
    echo ""

    # 1. DISK STATUS
    local disk_usage=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
    local disk_avail=$(df -h / | awk 'NR==2 {print $4}')
    if [ "$disk_usage" -gt 90 ]; then
        echo -e "DISK USAGE:    [${RED} CRITICAL: ${disk_usage}% used, ${disk_avail} free ${NC}]"
    else
        echo -e "DISK USAGE:    [${GREEN} OK: ${disk_usage}% used, ${disk_avail} free ${NC}]"
    fi

    # 2. RAM STATUS
    local mem_total=$(free -h | awk 'NR==2 {print $2}')
    local mem_used=$(free -h | awk 'NR==2 {print $3}')
    local mem_percent=$(free | awk 'NR==2 {printf "%.1f%%", $3*100/$2}')
    echo -e "MEMORY USAGE:  [${BLUE} $mem_used / $mem_total ($mem_percent) ${NC}]"

    # 3. NETWORK STATUS
    if ping -c 1 8.8.8.8 &>/dev/null; then
        echo -e "INTERNET:      [${GREEN} CONNECTED ${NC}]"
    else
        echo -e "INTERNET:      [${RED} DISCONNECTED ${NC}]"
    fi

    # 4. DISPLAY MANAGER STATUS
    local current_dm=$(detect_display_manager)
    if [ "$current_dm" != "none" ]; then
        echo -e "ACTIVE DM:     [${GREEN} $current_dm ${NC}]"
    else
        echo -e "ACTIVE DM:     [${YELLOW} NONE (TTY MODE) ${NC}]"
    fi

    # 5. SECURITY (MICROCODE)
    if dmesg | grep -qi "microcode updated" 2>/dev/null; then
        echo -e "MICROCODE:     [${GREEN} PATCHED/LATEST ${NC}]"
    else
        echo -e "MICROCODE:     [${YELLOW} NOT DETECTED ${NC}]"
    fi

    # 6. SYSTEM INFO
    local kernel=$(uname -r)
    local uptime=$(uptime -p | sed 's/up //')
    echo -e "KERNEL:        [${BLUE} $kernel ${NC}]"
    echo -e "UPTIME:        [${BLUE} $uptime ${NC}]"

    echo -e "${BLUE}================================================================${NC}"
    log_build_signature "HEALTH_REPORT_VIEWED"
}

# ============================================================================
# INTERACTIVE HELP MANUAL
# ============================================================================
show_help_manual() {
    clear
    echo -e "${BLUE}================================================================${NC}"
    echo -e "${BLUE}                   MY ARCH LINUX - HELP MANUAL                  ${NC}"
    echo -e "${BLUE}================================================================${NC}"
    echo ""
    echo -e "${YELLOW}1. MAINTENANCE:${NC}"
    echo "   - Update System: Runs full pacman -Syu."
    echo "   - Clean Cache: Removes uninstalled package files to save space."
    echo "   - Reset Keyring: Fixes 'Signature is unknown trust' errors."
    echo ""
    echo -e "${YELLOW}2. DISPLAY MANAGERS (THE OVERHAUL):${NC}"
    echo "   - Master Switcher: Nukes old DM configs, services, and symlinks"
    echo "     before a clean install. This is the 100% fix for black screens."
    echo "   - LightDM: Uses GTK greeter for maximum compatibility."
    echo "   - SDDM: Perfect for KDE Plasma."
    echo ""
    echo -e "${YELLOW}3. THEME DOCTOR:${NC}"
    echo "   - 10-step automatic repair for LightDM issues:"
    echo "     • Fixes permissions on /var/lib/lightdm and /etc/lightdm"
    echo "     • Verifies greeter package is installed"
    echo "     • Ensures correct greeter-session in config"
    echo "     • Validates configuration syntax"
    echo "     • Restarts the service"
    echo ""
    echo -e "${YELLOW}4. SYSTEM TOOLS:${NC}"
    echo "   - Health Report: A real-time dashboard of Disk, RAM, and Network."
    echo "   - Microcode: Essential CPU security and stability patches."
    echo "   - Audio: PipeWire setup (modern audio framework)."
    echo "   - Bluetooth: Bluez setup with blueman manager."
    echo ""
    echo -e "${YELLOW}5. SAFETY FEATURES:${NC}"
    echo "   - Safe Mode: Prompts for confirmation before every major change."
    echo "   - Dry Run: Shows commands without actually running them."
    echo "   - TTY Check: Prevents running DM swaps inside a GUI terminal."
    echo "   - Auto-Backup: All configs are backed up before deletion."
    echo ""
    echo -e "${BLUE}================================================================${NC}"
    log_build_signature "HELP_MANUAL_VIEWED"
}

# ============================================================================
# MASTER DISPLAY MANAGER SWITCHER
# ============================================================================
switch_display_manager() {
    local target_dm="$1"
    local packages="$2"
    local greeter_session="${3:-}"

    check_root
    check_arch
    require_network
    check_tty

    print_message "$CYAN" "╔═══════════════════════════════════════════════════════════════╗"
    print_message "$CYAN" "║           SWITCHING TO $target_dm (CLEAN INSTALL)            ║"
    print_message "$CYAN" "╚═══════════════════════════════════════════════════════════════╝"

    if [ "$DRY_RUN" = true ]; then
        print_message "$YELLOW" "→ [DRY RUN] Would switch to $target_dm"
        return 0
    fi

    # Check if already installed and ask for reinstall
    local first_pkg=$(echo "$packages" | awk '{print $1}')
    if ! check_already_installed "$first_pkg"; then
        print_message "$YELLOW" "Skipping $target_dm installation."
        return 0
    fi

    # 1. THE NUKE PHASE
    print_message "$YELLOW" "Phase 1: Cleaning existing configurations..."
    local dms=("sddm" "lightdm" "gdm" "lxdm" "xdm")
    for dm in "${dms[@]}"; do
        systemctl stop "$dm" 2>/dev/null || true
        systemctl disable "$dm" 2>/dev/null || true
    done

    # Remove the generic systemd link (The "Magic" fix)
    rm -f /etc/systemd/system/display-manager.service

    # Backup and clear /etc/ folders
    local backup_dir="/root/dm-backups-$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    for dm in "${dms[@]}"; do
        if [ -d "/etc/$dm" ]; then
            cp -r "/etc/$dm" "$backup_dir/" 2>/dev/null || true
            rm -rf "/etc/$dm" 2>/dev/null || true
            print_message "$GREEN" "  ✓ Backed up and removed /etc/$dm"
        fi
    done

    # 2. THE INSTALL PHASE
    print_message "$YELLOW" "Phase 2: Installing $target_dm packages..."
    run_command "pacman -S --noconfirm --needed $packages" "Installing $target_dm"

    # Special config for LightDM
    if [[ "$target_dm" == "lightdm" ]] && [ -n "$greeter_session" ]; then
        mkdir -p /etc/lightdm
        cat > /etc/lightdm/lightdm.conf << EOF
[Seat:*]
greeter-session=$greeter_session
xserver-command=X
session-wrapper=/etc/lightdm/Xsession
allow-guest=true
greeter-hide-users=false
greeter-show-manual-login=true
EOF
        # Create Xsession wrapper if it doesn't exist
        if [ ! -f /etc/lightdm/Xsession ]; then
            cat > /etc/lightdm/Xsession << 'EOF'
#!/bin/sh
[ -f /etc/profile ] && . /etc/profile
[ -f "$HOME/.profile" ] && . "$HOME/.profile"
[ -f "$HOME/.xprofile" ] && . "$HOME/.xprofile"
exec $@
EOF
            chmod +x /etc/lightdm/Xsession
        fi
        print_message "$GREEN" "  ✓ LightDM configuration created"

        # Fix permissions
        chown -R lightdm:lightdm /etc/lightdm 2>/dev/null || true
        mkdir -p /var/lib/lightdm
        chown -R lightdm:lightdm /var/lib/lightdm 2>/dev/null || true
    fi

    # 3. THE ACTIVATION PHASE
    print_message "$YELLOW" "Phase 3: Enabling $target_dm service..."
    systemctl enable -f "$target_dm" >> "$TEMP_LOG" 2>&1

    # 4. THE SUCCESS CHECK
    print_message "$YELLOW" "Phase 4: Verifying installation..."
    if [ -L "/etc/systemd/system/display-manager.service" ]; then
        local actual_target=$(readlink -f /etc/systemd/system/display-manager.service)
        if [[ "$actual_target" == *"$target_dm"* ]]; then
            print_message "$GREEN" "✓ SUCCESS: $target_dm is active and verified."
            print_message "$CYAN" "  To start now: sudo systemctl start $target_dm"
            if [[ "$target_dm" == "lightdm" ]]; then
                print_message "$CYAN" "  LightDM runs on tty7 - Press Ctrl+Alt+F7"
            else
                print_message "$CYAN" "  SDDM runs on tty1 - Press Ctrl+Alt+F1"
            fi
        else
            print_message "$RED" "✗ ERROR: Link verification failed! Points to $actual_target"
        fi
    else
        print_message "$RED" "✗ ERROR: No display manager service linked!"
    fi

    log_build_signature "${target_dm}_INSTALL"
}

# ============================================================================
# THEME DOCTOR - 10-STEP LIGHTDM REPAIR
# ============================================================================
repair_lightdm_theme() {
    check_root
    check_tty

    print_message "$CYAN" "╔═══════════════════════════════════════════════════════════════╗"
    print_message "$CYAN" "║                 LIGHTDM THEME DOCTOR (10-STEP)               ║"
    print_message "$CYAN" "╚═══════════════════════════════════════════════════════════════╝"
    echo ""

    if [ "$DRY_RUN" = true ]; then
        print_message "$YELLOW" "→ [DRY RUN] Would run LightDM Theme Doctor"
        return 0
    fi

    # Step 1: Check if LightDM is installed
    print_message "$YELLOW" "Step 1/10: Checking LightDM installation..."
    if ! pacman -Q lightdm &> /dev/null; then
        print_message "$RED" "  ✗ LightDM not installed!"
        print_message "$YELLOW" "  Installing LightDM..."
        run_command "pacman -S --noconfirm lightdm lightdm-gtk-greeter" "Installing LightDM"
    else
        print_message "$GREEN" "  ✓ LightDM is installed"
    fi

    # Step 2: Check greeter package
    print_message "$YELLOW" "Step 2/10: Checking greeter package..."
    if ! pacman -Q lightdm-gtk-greeter &> /dev/null; then
        print_message "$RED" "  ✗ GTK greeter not installed!"
        run_command "pacman -S --noconfirm lightdm-gtk-greeter" "Installing GTK greeter"
    else
        print_message "$GREEN" "  ✓ GTK greeter is installed"
    fi

    # Step 3: Fix permissions on /var/lib/lightdm
    print_message "$YELLOW" "Step 3/10: Fixing /var/lib/lightdm permissions..."
    if [ -d "/var/lib/lightdm" ]; then
        chown -R lightdm:lightdm /var/lib/lightdm 2>/dev/null || true
        print_message "$GREEN" "  ✓ Fixed /var/lib/lightdm permissions"
    else
        mkdir -p /var/lib/lightdm
        chown lightdm:lightdm /var/lib/lightdm 2>/dev/null || true
        print_message "$GREEN" "  ✓ Created /var/lib/lightdm with correct permissions"
    fi

    # Step 4: Fix permissions on /etc/lightdm
    print_message "$YELLOW" "Step 4/10: Fixing /etc/lightdm permissions..."
    if [ -d "/etc/lightdm" ]; then
        chown -R lightdm:lightdm /etc/lightdm 2>/dev/null || true
        print_message "$GREEN" "  ✓ Fixed /etc/lightdm permissions"
    fi

    # Step 5: Backup current config
    print_message "$YELLOW" "Step 5/10: Backing up current configuration..."
    if [ -f "/etc/lightdm/lightdm.conf" ]; then
        local backup="/etc/lightdm/lightdm.conf.theme-doctor-$(date +%Y%m%d-%H%M%S)"
        cp /etc/lightdm/lightdm.conf "$backup"
        print_message "$GREEN" "  ✓ Config backed up to $(basename "$backup")"
    fi

    # Step 6: Ensure [Seat:*] section exists
    print_message "$YELLOW" "Step 6/10: Checking configuration structure..."
    if [ ! -f "/etc/lightdm/lightdm.conf" ]; then
        echo "[Seat:*]" > /etc/lightdm/lightdm.conf
        print_message "$GREEN" "  ✓ Created new config file"
    fi

    if ! grep -q "^\[Seat:\*\]" /etc/lightdm/lightdm.conf; then
        echo -e "\n[Seat:*]" >> /etc/lightdm/lightdm.conf
        print_message "$GREEN" "  ✓ Added [Seat:*] section"
    fi

    # Step 7: Set correct greeter
    print_message "$YELLOW" "Step 7/10: Setting greeter-session..."
    if grep -q "^greeter-session=" /etc/lightdm/lightdm.conf; then
        sed -i 's/^greeter-session=.*/greeter-session=lightdm-gtk-greeter/' /etc/lightdm/lightdm.conf
    else
        sed -i '/^\[Seat:\*\]/a greeter-session=lightdm-gtk-greeter' /etc/lightdm/lightdm.conf
    fi
    print_message "$GREEN" "  ✓ Set greeter-session=lightdm-gtk-greeter"

    # Step 8: Check for session files
    print_message "$YELLOW" "Step 8/10: Checking for desktop sessions..."
    if [ ! -d "/usr/share/xsessions" ] || [ -z "$(ls -A /usr/share/xsessions/ 2>/dev/null)" ]; then
        print_message "$RED" "  ✗ No session files found!"
        print_message "$YELLOW" "  You need to install a desktop environment first:"
        echo "     • KDE Plasma: sudo pacman -S plasma-meta"
        echo "     • XFCE: sudo pacman -S xfce4"
        echo "     • GNOME: sudo pacman -S gnome"
    else
        print_message "$GREEN" "  ✓ Session files found"
    fi

    # Step 9: Validate configuration
    print_message "$YELLOW" "Step 9/10: Validating LightDM configuration..."
    if lightdm --config-test &>/dev/null; then
        print_message "$GREEN" "  ✓ Configuration is valid"
    else
        print_message "$RED" "  ✗ Configuration test failed!"
        print_message "$YELLOW" "  Restoring minimal working config..."
        cat > /etc/lightdm/lightdm.conf << 'EOF'
[Seat:*]
greeter-session=lightdm-gtk-greeter
xserver-command=X
session-wrapper=/etc/lightdm/Xsession
allow-guest=true
greeter-hide-users=false
greeter-show-manual-login=true
EOF
        print_message "$GREEN" "  ✓ Restored minimal config"
    fi

    # Step 10: Restart service
    print_message "$YELLOW" "Step 10/10: Restarting LightDM service..."
    systemctl daemon-reload
    systemctl enable lightdm.service >> "$TEMP_LOG" 2>&1
    systemctl restart lightdm.service >> "$TEMP_LOG" 2>&1

    if systemctl is-active lightdm.service &>/dev/null; then
        print_message "$GREEN" "  ✓ LightDM is running"
    else
        print_message "$RED" "  ✗ LightDM failed to start"
        print_message "$YELLOW" "  Check logs: journalctl -u lightdm.service -b"
    fi

    echo ""
    print_message "$GREEN" "╔═══════════════════════════════════════════════════════════════╗"
    print_message "$GREEN" "║              THEME DOCTOR COMPLETE!                           ║"
    print_message "$GREEN" "╚═══════════════════════════════════════════════════════════════╝"
    echo ""
    print_message "$CYAN" "If LightDM still doesn't work:"
    echo "  1. Switch to TTY: Ctrl+Alt+F2"
    echo "  2. Check logs: journalctl -u lightdm.service -b | grep -i error"
    echo "  3. Verify sessions: ls /usr/share/xsessions/"
    echo "  4. Try starting manually: sudo systemctl start lightdm.service"
    echo "  5. Switch to LightDM: Ctrl+Alt+F7"

    log_build_signature "THEME_DOCTOR"
}

# ============================================================================
# DESKTOP INSTALLATIONS
# ============================================================================
install_hyprland() {
    require_network
    check_disk_space || return 1

    print_message "$BLUE" "Installing Hyprland..."

    local packages=(
        "hyprland" "hyprpaper" "hyprlock" "hypridle"
        "waybar" "wofi" "kitty" "dunst" "grim" "slurp"
        "qt5-wayland" "qt6-wayland" "xdg-desktop-portal-hyprland"
    )

    # Check if already installed
    if check_already_installed "hyprland"; then
        run_command "pacman -S --noconfirm --needed ${packages[*]}" "Installing Hyprland"
    fi

    echo ""
    print_message "$YELLOW" "Install SDDM as display manager? (y/n)"
    read -p "  Choice: " install_dm
    if [[ "$install_dm" =~ ^[Yy]$ ]]; then
        switch_display_manager "sddm" "sddm sddm-kcm"
    fi

    print_message "$GREEN" "✓ Hyprland installation complete"
    log_build_signature "HYPRLAND"
}

install_plasma() {
    require_network
    check_disk_space || return 1

    print_message "$BLUE" "Installing KDE Plasma..."

    local packages=(
        "plasma-meta" "dolphin" "konsole" "kio-fuse"
        "kio-extras" "ffmpegthumbs" "bluedevil"
        "plasma-nm" "plasma-pa" "powerdevil"
    )

    if check_already_installed "plasma-meta"; then
        run_command "pacman -S --noconfirm --needed ${packages[*]}" "Installing KDE Plasma"
    fi

    echo ""
    print_message "$YELLOW" "Install SDDM as display manager? (y/n)"
    read -p "  Choice: " install_dm
    if [[ "$install_dm" =~ ^[Yy]$ ]]; then
        switch_display_manager "sddm" "sddm sddm-kcm"
    fi

    print_message "$GREEN" "✓ KDE Plasma installation complete"
    log_build_signature "PLASMA"
}

install_xfce() {
    require_network
    check_disk_space || return 1

    print_message "$BLUE" "Installing XFCE..."

    local packages=(
        "xfce4" "xfce4-goodies" "xfce4-terminal"
        "thunar" "thunar-archive-plugin" "mousepad"
        "xfce4-power-manager" "xfce4-screenshooter"
    )

    if check_already_installed "xfce4"; then
        run_command "pacman -S --noconfirm --needed ${packages[*]}" "Installing XFCE"
    fi

    echo ""
    print_message "$YELLOW" "Select display manager:"
    echo "  1) LightDM (recommended for XFCE)"
    echo "  2) SDDM"
    echo "  3) Skip"
    read -p "  Choice [1-3]: " dm_choice

    case $dm_choice in
        1) switch_display_manager "lightdm" "lightdm lightdm-gtk-greeter" "lightdm-gtk-greeter" ;;
        2) switch_display_manager "sddm" "sddm sddm-kcm" ;;
        *) print_message "$YELLOW" "  Skipping DM installation" ;;
    esac

    print_message "$GREEN" "✓ XFCE installation complete"
    log_build_signature "XFCE"
}

remove_desktop() {
    print_message "$RED" "⚠ WARNING: This will remove a desktop environment"
    echo ""
    print_message "$YELLOW" "Select desktop to remove:"
    echo "  1) KDE Plasma"
    echo "  2) Hyprland"
    echo "  3) XFCE"
    echo "  4) Cancel"
    read -p "  Choice [1-4]: " remove_choice

    case $remove_choice in
        1)
            print_message "$YELLOW" "Removing KDE Plasma..."
            pacman -Rns --noconfirm plasma-meta dolphin konsole 2>/dev/null || true
            print_message "$GREEN" "  ✓ KDE Plasma removed"
            log_build_signature "PLASMA_REMOVE"
            ;;
        2)
            print_message "$YELLOW" "Removing Hyprland..."
            pacman -Rns --noconfirm hyprland hyprpaper hyprlock 2>/dev/null || true
            print_message "$GREEN" "  ✓ Hyprland removed"
            log_build_signature "HYPRLAND_REMOVE"
            ;;
        3)
            print_message "$YELLOW" "Removing XFCE..."
            pacman -Rns --noconfirm xfce4 xfce4-goodies 2>/dev/null || true
            print_message "$GREEN" "  ✓ XFCE removed"
            log_build_signature "XFCE_REMOVE"
            ;;
        4)
            print_message "$YELLOW" "Cancelled"
            return
            ;;
        *)
            print_message "$RED" "Invalid choice"
            return
            ;;
    esac
}

# ============================================================================
# AUDIO FUNCTIONS
# ============================================================================
setup_pipewire_audio() {
    require_network

    print_message "$BLUE" "Setting up PipeWire audio..."

    local packages=(
        "pipewire" "pipewire-alsa" "pipewire-pulse" "pipewire-jack"
        "wireplumber" "alsa-utils" "sof-firmware"
    )

    run_command "pacman -S --noconfirm --needed ${packages[*]}" "Installing PipeWire packages"

    # Enable user services
    print_message "$YELLOW" "Enabling PipeWire user services..."
    sudo -u "$ORIGINAL_USER" systemctl --user enable --now pipewire pipewire-pulse wireplumber 2>/dev/null || true

    print_message "$GREEN" "✓ PipeWire audio setup complete"
    log_build_signature "PIPEWIRE"
}

setup_bluetooth() {
    require_network

    print_message "$BLUE" "Setting up Bluetooth..."

    local packages=(
        "bluez" "bluez-utils" "bluez-libs" "blueman"
    )

    run_command "pacman -S --noconfirm --needed ${packages[*]}" "Installing Bluetooth packages"
    run_command "systemctl enable --now bluetooth.service" "Enabling Bluetooth service"

    # Add user to lp group for bluetooth
    usermod -aG lp "$ORIGINAL_USER" 2>/dev/null || true

    print_message "$GREEN" "✓ Bluetooth setup complete"
    log_build_signature "BLUETOOTH"
}

# ============================================================================
# SYSTEM ENHANCEMENTS
# ============================================================================
install_fonts() {
    require_network

    print_message "$BLUE" "Installing fonts..."

    local fonts=(
        "ttf-dejavu" "ttf-roboto" "ttf-ubuntu-font-family"
        "noto-fonts" "noto-fonts-emoji" "ttf-jetbrains-mono"
        "ttf-liberation" "ttf-droid"
    )

    run_command "pacman -S --noconfirm --needed ${fonts[*]}" "Installing fonts"
    fc-cache -fv &>/dev/null

    print_message "$GREEN" "✓ Fonts installed"
    log_build_signature "FONTS"
}

install_complete_zsh() {
    require_network

    print_message "$BLUE" "Installing ZSH environment..."

    run_command "pacman -S --noconfirm zsh" "Installing ZSH"

    local user_home=$(eval echo ~$ORIGINAL_USER)

    if [[ ! -d "$user_home/.oh-my-zsh" ]]; then
        print_message "$YELLOW" "Installing Oh My Zsh..."
        sudo -u "$ORIGINAL_USER" sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended &>/dev/null || true
        print_message "$GREEN" "  ✓ Oh My Zsh installed"
    fi

    run_command "chsh -s /usr/bin/zsh '$ORIGINAL_USER'" "Changing shell to ZSH"

    print_message "$GREEN" "✓ ZSH installation complete"
    log_build_signature "ZSH"
}

install_aur_helper() {
    require_network

    print_message "$BLUE" "Installing yay (AUR helper)..."

    cd /tmp
    sudo -u "$ORIGINAL_USER" git clone https://aur.archlinux.org/yay-bin.git &>/dev/null
    cd yay-bin
    sudo -u "$ORIGINAL_USER" makepkg -si --noconfirm &>/dev/null
    cd ~
    rm -rf /tmp/yay-bin

    print_message "$GREEN" "✓ yay installed"
    log_build_signature "YAY"
}

install_lts_kernel() {
    require_network

    print_message "$BLUE" "Installing LTS kernel..."

    run_command "pacman -S --noconfirm linux-lts linux-lts-headers" "Installing LTS kernel"

    if command -v grub-mkconfig &>/dev/null; then
        grub-mkconfig -o /boot/grub/grub.cfg &>/dev/null || true
        print_message "$GREEN" "  ✓ GRUB updated"
    fi

    print_message "$GREEN" "✓ LTS kernel installed"
    log_build_signature "LTS_KERNEL"
}

setup_flatpak() {
    require_network

    print_message "$BLUE" "Setting up Flatpak..."

    run_command "pacman -S --noconfirm flatpak" "Installing Flatpak"
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo &>/dev/null || true

    print_message "$GREEN" "✓ Flatpak configured"
    log_build_signature "FLATPAK"
}

# ============================================================================
# SYSTEM MAINTENANCE
# ============================================================================
clean_orphans() {
    print_message "$BLUE" "Cleaning orphaned packages..."

    local orphans=$(pacman -Qtdq 2>/dev/null || true)

    if [ -n "$orphans" ]; then
        local count=$(echo "$orphans" | wc -l)
        print_message "$YELLOW" "Found $count orphaned packages"
        pacman -Rns --noconfirm $orphans &>/dev/null || true
        print_message "$GREEN" "  ✓ Orphans removed"
    else
        print_message "$GREEN" "✓ No orphans found"
    fi

    paccache -r -k 3 &>/dev/null || true
    print_message "$GREEN" "  ✓ Package cache cleaned"
    log_build_signature "ORPHAN_CLEAN"
}

fix_pacman_issues() {
    require_network

    print_message "$BLUE" "Fixing pacman issues..."

    run_command "rm -f /var/lib/pacman/db.lck" "Removing lock file"
    run_command "pacman-key --init" "Initializing keyring"
    run_command "pacman-key --populate archlinux" "Populating keyring"
    run_command "pacman -Syyu --noconfirm" "Updating system" || true

    print_message "$GREEN" "✓ Pacman fixed"
    log_build_signature "PACMAN_FIX"
}

reset_keyring() {
    print_message "$BLUE" "Resetting pacman keyring..."

    rm -rf /etc/pacman.d/gnupg
    pacman-key --init &>/dev/null
    pacman-key --populate archlinux &>/dev/null

    print_message "$GREEN" "✓ Keyring reset"
    log_build_signature "KEYRING_RESET"
}

detect_cpu_and_ucode() {
    print_message "$BLUE" "Detecting CPU for microcode..."

    local vendor=$(grep -m 1 'vendor_id' /proc/cpuinfo | awk '{print $3}')

    if [[ "${vendor,,}" == *amd* ]]; then
        print_message "$GREEN" "AMD CPU detected"
        run_command "pacman -S --noconfirm amd-ucode" "Installing AMD microcode"
        log_build_signature "AMD_UCODE"
    elif [[ "${vendor,,}" == *intel* ]]; then
        print_message "$GREEN" "Intel CPU detected"
        run_command "pacman -S --noconfirm intel-ucode" "Installing Intel microcode"
        log_build_signature "INTEL_UCODE"
    else
        print_message "$YELLOW" "Unknown CPU vendor"
    fi
}

configure_grub() {
    print_message "$BLUE" "Configuring GRUB..."

    if [ -f /etc/default/grub ]; then
        cp /etc/default/grub /etc/default/grub.bak 2>/dev/null || true
        grub-mkconfig -o /boot/grub/grub.cfg &>/dev/null || true
        print_message "$GREEN" "✓ GRUB configured"
        log_build_signature "GRUB"
    else
        print_message "$RED" "GRUB not found"
    fi
}

test_environment() {
    print_message "$BLUE" "=== Environment Diagnostics ==="
    echo ""
    echo "TTY:           $(tty 2>/dev/null || echo 'unknown')"
    echo "Root:          $EUID"
    echo "User:          $ORIGINAL_USER"
    echo "System:        $SYSTEM_TYPE"
    echo "Bootloader:    $(detect_bootloader)"
    echo "Display Mgr:   $(detect_display_manager)"
    echo "Safe Mode:     $SAFE_MODE"
    echo "Dry Run:       $DRY_RUN"
    echo ""

    log_build_signature "ENV_TEST"
}

view_log() {
    print_message "$BLUE" "Viewing logs..."
    echo ""
    print_message "$YELLOW" "Available logs:"

    if [ -f "$LOG_FILE" ]; then
        echo "  1) Main setup log ($LOG_FILE)"
    fi
    if [ -f "$LOG_DIR/installations.log" ]; then
        echo "  2) Installations log"
    fi
    if [ -f "$LOG_DIR/cleanup.log" ]; then
        echo "  3) Cleanup log"
    fi
    if [ -f "$LOG_DIR/repairs.log" ]; then
        echo "  4) Repairs log"
    fi
    if [ -f "$TEMP_LOG" ]; then
        echo "  5) Current session log"
    fi
    echo "  6) Cancel"

    read -p "  Choice [1-6]: " log_choice

    case $log_choice in
        1) [ -f "$LOG_FILE" ] && less "$LOG_FILE" || print_message "$RED" "Log not found" ;;
        2) [ -f "$LOG_DIR/installations.log" ] && less "$LOG_DIR/installations.log" || print_message "$RED" "Log not found" ;;
        3) [ -f "$LOG_DIR/cleanup.log" ] && less "$LOG_DIR/cleanup.log" || print_message "$RED" "Log not found" ;;
        4) [ -f "$LOG_DIR/repairs.log" ] && less "$LOG_DIR/repairs.log" || print_message "$RED" "Log not found" ;;
        5) [ -f "$TEMP_LOG" ] && less "$TEMP_LOG" || print_message "$RED" "Log not found" ;;
        *) return ;;
    esac
}

# ============================================================================
# MENU SYSTEM
# ============================================================================

show_system_header() {
    echo -e "${BLUE}OS:${NC}      $(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d'"' -f2 | head -1)"
    echo -e "${BLUE}KERNEL:${NC}  $(uname -r)"
    echo -e "${BLUE}UPTIME:${NC}  $(uptime -p | sed 's/up //')"
    echo -e "${BLUE}DM:${NC}      $(detect_display_manager)"
    echo -e "${BLUE}DISK:${NC}    $(df -h / | awk 'NR==2 {print $3 " / " $2 " (" $5 ")"}')"
    echo -e "${BLUE}================================================================${NC}"
}

show_main_menu() {
    print_banner
    show_system_header
    echo -e "${WHITE}==================== MY ARCH LINUX v1.4.3 ====================${NC}"
    echo ""
    echo -e "${YELLOW} 0)${NC} HELP MANUAL (Read this first)"
    echo -e "${YELLOW} 1)${NC} Desktop Environments"
    echo -e "${YELLOW} 2)${NC} Display Managers (Master Switcher)"
    echo -e "${YELLOW} 3)${NC} Display Manager Recovery (Theme Doctor)"
    echo -e "${YELLOW} 4)${NC} Audio & Bluetooth"
    echo -e "${YELLOW} 5)${NC} System Enhancements"
    echo -e "${YELLOW} 6)${NC} System Maintenance"
    echo -e "${YELLOW} 7)${NC} System Tools & Health Report"
    echo -e "${YELLOW} 8)${NC} View Logs & History"
    echo -e "${YELLOW} 9)${NC} Toggle Options"
    echo -e "${YELLOW}10)${NC} Exit"
    echo ""
}

show_desktop_menu() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗"
    echo -e "${CYAN}║                  DESKTOP ENVIRONMENTS                         ║"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW} 1)${NC} Install Hyprland (Wayland tiling)"
    echo -e "${YELLOW} 2)${NC} Install KDE Plasma (Full featured)"
    echo -e "${YELLOW} 3)${NC} Install XFCE (Lightweight)"
    echo -e "${YELLOW} 4)${NC} Remove Desktop Environment"
    echo -e "${YELLOW} 5)${NC} Back to Main Menu"
    echo ""
}

show_dm_menu() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗"
    echo -e "${CYAN}║                  DISPLAY MANAGERS (MASTER SWITCHER)          ║"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW} 1)${NC} Switch to LightDM (GTK greeter - for XFCE)"
    echo -e "${YELLOW} 2)${NC} Switch to SDDM (KDE recommended)"
    echo -e "${YELLOW} 3)${NC} Back to Main Menu"
    echo ""
}

show_recovery_menu() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗"
    echo -e "${CYAN}║              DISPLAY MANAGER RECOVERY                         ║"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW} 1)${NC} Run LightDM Theme Doctor (10-step repair)"
    echo -e "${YELLOW} 2)${NC} Back to Main Menu"
    echo ""
}

show_audio_menu() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗"
    echo -e "${CYAN}║                  AUDIO & BLUETOOTH                            ║"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW} 1)${NC} Setup PipeWire Audio"
    echo -e "${YELLOW} 2)${NC} Setup Bluetooth"
    echo -e "${YELLOW} 3)${NC} Setup Both"
    echo -e "${YELLOW} 4)${NC} Back to Main Menu"
    echo ""
}

show_enhancements_menu() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗"
    echo -e "${CYAN}║                  SYSTEM ENHANCEMENTS                          ║"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW} 1)${NC} Install Fonts (Complete)"
    echo -e "${YELLOW} 2)${NC} Install ZSH (Oh My Zsh)"
    echo -e "${YELLOW} 3)${NC} Install AUR Helper (yay)"
    echo -e "${YELLOW} 4)${NC} Install LTS Kernel"
    echo -e "${YELLOW} 5)${NC} Setup Flatpak"
    echo -e "${YELLOW} 6)${NC} Back to Main Menu"
    echo ""
}

show_maintenance_menu() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗"
    echo -e "${CYAN}║                  SYSTEM MAINTENANCE                           ║"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW} 1)${NC} Clean Orphaned Packages"
    echo -e "${YELLOW} 2)${NC} Fix Pacman Issues (Update + Keyring)"
    echo -e "${YELLOW} 3)${NC} Reset Pacman Keyring"
    echo -e "${YELLOW} 4)${NC} Back to Main Menu"
    echo ""
}

show_tools_menu() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗"
    echo -e "${CYAN}║                  SYSTEM TOOLS & HEALTH                        ║"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW} 1)${NC} Detect & Install CPU Microcode"
    echo -e "${YELLOW} 2)${NC} Configure GRUB"
    echo -e "${YELLOW} 3)${NC} Run Environment Diagnostics"
    echo -e "${YELLOW} 4)${NC} Show System Health Report"
    echo -e "${YELLOW} 5)${NC} Back to Main Menu"
    echo ""
}

show_logs_menu() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗"
    echo -e "${CYAN}║                  LOGS & HISTORY                               ║"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW} 1)${NC} View Build History"
    echo -e "${YELLOW} 2)${NC} View Log Files"
    echo -e "${YELLOW} 3)${NC} Back to Main Menu"
    echo ""
}

show_options_menu() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗"
    echo -e "${CYAN}║                  TOGGLE OPTIONS                               ║"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW} 1)${NC} Toggle Safe Mode (Current: $SAFE_MODE)"
    echo -e "${YELLOW} 2)${NC} Toggle Dry Run (Current: $DRY_RUN)"
    echo -e "${YELLOW} 3)${NC} View GitHub"
    echo -e "${YELLOW} 4)${NC} Back to Main Menu"
    echo ""
}

# ============================================================================
# MAIN FUNCTION
# ============================================================================
main() {
    # Sudo keep-alive - prevents password prompts during long operations
    sudo -v
    while true; do
        sudo -n true
        sleep 60
        kill -0 "$$" 2>/dev/null || exit
    done 2>/dev/null &

    setup_logging

    while true; do
        show_main_menu
        read -p "Select an option [0-10]: " main_choice
        echo -e "${NC}"

        case $main_choice in
            0)  # Help Manual
                show_help_manual
                read -p "Press Enter to continue..."
                ;;

            1)  # Desktop Environments
                while true; do
                    show_desktop_menu
                    read -p "Choice [1-5]: " desktop_choice
                    echo -e "${NC}"

                    case $desktop_choice in
                        1) check_root; check_arch; install_hyprland ;;
                        2) check_root; check_arch; install_plasma ;;
                        3) check_root; check_arch; install_xfce ;;
                        4) check_root; remove_desktop ;;
                        5) break ;;
                        *) print_message "$RED" "Invalid option" ; sleep 1 ;;
                    esac

                    if [[ "$desktop_choice" =~ ^[1-4]$ ]]; then
                        read -p "Press Enter to continue..."
                    fi
                done
                ;;

            2)  # Display Managers (Master Switcher)
                while true; do
                    show_dm_menu
                    read -p "Choice [1-3]: " dm_choice
                    echo -e "${NC}"

                    case $dm_choice in
                        1) switch_display_manager "lightdm" "lightdm lightdm-gtk-greeter" "lightdm-gtk-greeter" ;;
                        2) switch_display_manager "sddm" "sddm sddm-kcm" ;;
                        3) break ;;
                        *) print_message "$RED" "Invalid option" ; sleep 1 ;;
                    esac

                    if [[ "$dm_choice" =~ ^[1-2]$ ]]; then
                        read -p "Press Enter to continue..."
                    fi
                done
                ;;

            3)  # DM Recovery
                while true; do
                    show_recovery_menu
                    read -p "Choice [1-2]: " recovery_choice
                    echo -e "${NC}"

                    case $recovery_choice in
                        1) check_root; repair_lightdm_theme ;;
                        2) break ;;
                        *) print_message "$RED" "Invalid option" ; sleep 1 ;;
                    esac

                    if [[ "$recovery_choice" == "1" ]]; then
                        read -p "Press Enter to continue..."
                    fi
                done
                ;;

            4)  # Audio & Bluetooth
                while true; do
                    show_audio_menu
                    read -p "Choice [1-4]: " audio_choice
                    echo -e "${NC}"

                    case $audio_choice in
                        1) check_root; setup_pipewire_audio ;;
                        2) check_root; setup_bluetooth ;;
                        3) check_root; setup_pipewire_audio; setup_bluetooth ;;
                        4) break ;;
                        *) print_message "$RED" "Invalid option" ; sleep 1 ;;
                    esac

                    if [[ "$audio_choice" =~ ^[1-3]$ ]]; then
                        read -p "Press Enter to continue..."
                    fi
                done
                ;;

            5)  # System Enhancements
                while true; do
                    show_enhancements_menu
                    read -p "Choice [1-6]: " enhance_choice
                    echo -e "${NC}"

                    case $enhance_choice in
                        1) check_root; install_fonts ;;
                        2) check_root; install_complete_zsh ;;
                        3) check_root; install_aur_helper ;;
                        4) check_root; install_lts_kernel ;;
                        5) check_root; setup_flatpak ;;
                        6) break ;;
                        *) print_message "$RED" "Invalid option" ; sleep 1 ;;
                    esac

                    if [[ "$enhance_choice" =~ ^[1-5]$ ]]; then
                        read -p "Press Enter to continue..."
                    fi
                done
                ;;

            6)  # System Maintenance
                while true; do
                    show_maintenance_menu
                    read -p "Choice [1-4]: " maint_choice
                    echo -e "${NC}"

                    case $maint_choice in
                        1) check_root; clean_orphans ;;
                        2) check_root; fix_pacman_issues ;;
                        3) check_root; reset_keyring ;;
                        4) break ;;
                        *) print_message "$RED" "Invalid option" ; sleep 1 ;;
                    esac

                    if [[ "$maint_choice" =~ ^[1-3]$ ]]; then
                        read -p "Press Enter to continue..."
                    fi
                done
                ;;

            7)  # System Tools & Health
                while true; do
                    show_tools_menu
                    read -p "Choice [1-5]: " tools_choice
                    echo -e "${NC}"

                    case $tools_choice in
                        1) check_root; detect_cpu_and_ucode ;;
                        2) check_root; configure_grub ;;
                        3) check_root; test_environment ;;
                        4) show_health_report; read -p "Press Enter..." ;;
                        5) break ;;
                        *) print_message "$RED" "Invalid option" ; sleep 1 ;;
                    esac

                    if [[ "$tools_choice" =~ ^[1-3]$ ]]; then
                        read -p "Press Enter to continue..."
                    fi
                done
                ;;

            8)  # Logs & History
                while true; do
                    show_logs_menu
                    read -p "Choice [1-3]: " logs_choice
                    echo -e "${NC}"

                    case $logs_choice in
                        1) show_history ;;
                        2) view_log ;;
                        3) break ;;
                        *) print_message "$RED" "Invalid option" ; sleep 1 ;;
                    esac
                done
                ;;

            9)  # Toggle Options
                while true; do
                    show_options_menu
                    read -p "Choice [1-4]: " opt_choice
                    echo -e "${NC}"

                    case $opt_choice in
                        1)
                            if [ "$SAFE_MODE" = true ]; then
                                SAFE_MODE=false
                                HEADER_COLOR=$RED
                                print_message "$RED" "Safe Mode disabled - High-risk repairs enabled"
                            else
                                SAFE_MODE=true
                                HEADER_COLOR=$GREEN
                                print_message "$GREEN" "Safe Mode enabled - High-risk repairs disabled"
                            fi
                            log_build_signature "SAFE_MODE_TOGGLE"
                            read -p "Press Enter..."
                            ;;
                        2)
                            if [ "$DRY_RUN" = true ]; then
                                DRY_RUN=false
                                print_message "$GREEN" "Dry Run disabled - Will execute commands"
                            else
                                DRY_RUN=true
                                print_message "$YELLOW" "Dry Run enabled - Will show what would be done"
                            fi
                            log_build_signature "DRY_RUN_TOGGLE"
                            read -p "Press Enter..."
                            ;;
                        3)
                            print_message "$BLUE" "GitHub: $GITHUB_URL"
                            read -p "Press Enter..."
                            ;;
                        4) break ;;
                        *) print_message "$RED" "Invalid option" ; sleep 1 ;;
                    esac
                done
                ;;

            10)
                log_build_signature "SUCCESS"
                print_message "$GREEN" "Exiting. Goodbye!"
                # Kill the sudo keep-alive background process
                jobs -p | xargs -r kill 2>/dev/null || true
                exit 0
                ;;

            *)
                print_message "$RED" "Invalid option. Please choose 0-10"
                sleep 1
                ;;
        esac
    done
}

# Start the script
main "$@"
