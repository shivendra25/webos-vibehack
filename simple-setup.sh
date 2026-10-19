#!/usr/bin/env bash
# Simple setup script for webos-vibehack launcher
# Automates as much as possible and guides through manual steps

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
info() { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
warning() { echo -e "${YELLOW}[WARNING]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Check if running as root (we don't want this)
if [[ $EUID -eq 0 ]]; then
   error "This script should not be run as root"
   exit 1
fi

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

info "=== webos-vibehack Simple Setup ==="
info "This script will help you install the Apple TV-style launcher on your LG webOS TV"
info ""

# Step 0: Check prerequisites
info "Step 0: Checking prerequisites"

# Check for git
if ! command -v git &> /dev/null; then
    error "git is required but not installed. Please install git first."
    exit 1
fi

# Check for node/npm
NODE_VERSION=""
if command -v node &> /dev/null; then
    NODE_VERSION=$(node --version)
    info "Node.js found: $NODE_VERSION"
else
    warning "Node.js not found. Please install Node.js (version 18+ recommended)"
    info "On macOS: brew install node"
    info "On Ubuntu/Debian: sudo apt install nodejs npm"
    info "After installing, re-run this script"
    exit 1
fi

if ! command -v npm &> /dev/null; then
    error "npm is required but not installed. Please install npm first."
    exit 1
fi

# Check for python3
if ! command -v python3 &> /dev/null; then
    error "python3 is required but not installed. Please install python3 first."
    exit 1
fi

success "Prerequisites check passed"
info ""

# Step 1: Guide for Developer Mode enabling
info "Step 1: Enable Developer Mode on your LG TV"
info "This step must be done manually on your TV"
info ""
echo "Please follow these steps on your LG TV remote:"
echo "1. Go to Settings → All Settings → General → About This TV"
echo "2. Click OK on 'LG Broadcasting' 5 times in quick succession"
echo "   (Alternative: try clicking on your TV model name 5-7 times)"
echo "3. You should see a popup: 'Developer mode has been turned on'"
echo "4. Go back to Settings → All Settings → General → LG Connect"
echo "5. Ensure 'IP Control' is set to On"
echo "6. Open the LG Content Store and install the 'Developer Mode' app"
echo "7. Launch the Developer Mode app and sign in with your LG Developer account"
echo "   (Create one for free at https://developer.lge.com if needed)"
echo "8. In the Developer Mode app, turn on 'Dev Mode Status' (TV will reboot)"
echo "9. After reboot, open Developer Mode app again and turn on 'Key Server'"
echo "10. Note the IP address and passphrase shown in the app"
info ""
read -p "Have you enabled Developer Mode and noted the IP/passphrase? (y/n): " DEV_MODE_READY
if [[ ! "$DEV_MODE_READY" =~ ^[Yy]$ ]]; then
    warning "Please complete Step 1 and re-run this script"
    exit 1
fi
info ""

# Step 2: Install webOS CLI tools
info "Step 2: Installing webOS CLI tools"
if ! command -v ares-setup-device &> /dev/null; then
    info "Installing @webos-tools/cli globally..."
    if npm install -g @webos-tools/cli; then
        success "webOS CLI tools installed"
    else
        error "Failed to install webOS CLI tools"
        exit 1
    fi
else
    success "webOS CLI tools already installed"
fi
info ""

# Step 3: Set up device connection
info "Step 3: Setting up connection to your TV"
read -p "Enter your TV's IP address (from Developer Mode app): " TV_HOST
if [[ -z "$TV_HOST" ]]; then
    error "IP address is required"
    exit 1
fi

# Check if device already configured
if ares-setup-device -l | grep -q "LG-TV"; then
    info "Device 'LG-TV' already configured. Updating..."
    # We'll update it below
else
    info "Adding new device 'LG-TV'"
    ares-setup-device -a LG-TV -i "{'username':'prisoner', 'host':'$TV_HOST','port':'9922'}"
fi

info "Now we need to retrieve the security key from your TV"
info "Make sure the Developer Mode app is open on your TV with Key Server turned on"
info "You should see a passphrase displayed on the TV screen"
read -p "Press Enter when ready to retrieve the key..."

# Retrieve key with timeout handling
info "Retrieving key from TV (this may take a moment)..."
if output=$(ares-novacom --device LG-TV --getkey 2>&1); then
    success "Key retrieved successfully"
else
    # Check if it's asking for passphrase
    if echo "$output" | grep -q "passphrase"; then
        warning "The TV is asking for a passphrase"
        info "Please look at your TV screen in the Developer Mode app"
        info "You should see a passphrase (like A4A17B) displayed there"
        read -p "Enter the passphrase from your TV: " PASSPHRASE
        if [[ -z "$PASSPHRASE" ]]; then
            error "Passphrase is required"
            exit 1
        fi

        # Try again with passphrase
        info "Retrieving key with passphrase..."
        if output=$(echo "$PASSPHRASE" | ares-novacom --device LG-TV --getkey 2>&1); then
            success "Key retrieved successfully"
        else
            error "Failed to retrieve key: $output"
            exit 1
        fi
    else
        error "Failed to retrieve key: $output"
        exit 1
    fi
fi

# Update device configuration with key and passphrase
info "Updating device configuration..."
# Extract the passphrase from user input or try to get it from the key retrieval process
# For simplicity, we'll ask the user to confirm
read -p "Please re-enter the passphrase from your TV for verification: " PASSPHRASE_CONFIRM
if [[ -z "$PASSPHRASE_CONFIRM" ]]; then
    error "Passphrase is required"
    exit 1
fi

if ares-setup-device -m LG-TV -i "{'privatekey':'LG-TV_webos','passphrase':'$PASSPHRASE_CONFIRM'}"; then
    success "Device configuration updated"
else
    error "Failed to update device configuration"
    exit 1
fi
info ""

# Step 4: Set up Python environment
info "Step 4: Setting up Python environment"
if [ ! -d "venv" ]; then
    info "Creating Python virtual environment..."
    if python3 -m venv venv; then
        success "Virtual environment created"
    else
        error "Failed to create virtual environment"
        exit 1
    fi
else
    success "Virtual environment already exists"
fi

# Activate venv and install dependencies
info "Installing Python dependencies..."
if source venv/bin/activate && pip install -q websockets; then
    success "Python dependencies installed"
else
    error "Failed to install Python dependencies"
    exit 1
fi
info ""

# Step 5: Sync apps and install launcher
info "Step 5: Synchronizing apps and installing launcher"
info "This will:"
info "  - Sync your installed apps from the TV"
info "  - Package the launcher app"
info "  - Install it on your TV"
info "  - Launch it for the first time"
info ""

read -p "Press Enter to continue with app synchronization and installation..."

# Sync apps
info "Syncing apps from TV..."
if venv/bin/python sync-apps.py "$TV_HOST"; then
    success "Apps synchronized successfully"
else
    error "Failed to sync apps"
    exit 1
fi

# Package and install
info "Packaging and installing launcher..."
if ./install.sh; then
    success "Launcher installed and launched successfully!"
else
    error "Failed to install launcher"
    exit 1
fi
info ""

# Step 6: Offer to set up home watcher
info "Step 6: Setting up home button redirection (optional but recommended)"
info "The home watcher enables automatic redirection from LG's home screen to our launcher"
info "When you press Home on your remote:"
info "  - LG's home screen appears briefly (~0.1s)"
info "  - The watcher detects this and launches our launcher"
info "  - You can press Home twice within 3 seconds to stay on LG's home intentionally"
info ""

read -p "Would you like to set up the home watcher as a background service? (y/n): " SETUP_WATCHER
if [[ "$SETUP_WATCHER" =~ ^[Yy]$ ]]; then
    info "Setting up home watcher..."
    if TV_HOST="$TV_HOST" ./home-watch-mac.sh; then
        success "Home watcher installed and started"
        info "Log file: ~/Library/Logs/tv-vibehack-home-watch.log"
        info "To stop later: ./home-watch-mac.sh stop"
        info "To start again: TV_HOST=$TV_HOST ./home-watch-mac.sh start"
    else
        warning "Failed to set up home watcher (you can try manually later)"
        info "You can run manually with: TV_HOST=$TV_HOST venv/bin/python home-watch.py"
    fi
else
    info "Skipping home watcher setup"
    info "You can set it up later with: TV_HOST=$TV_HOST ./home-watch-mac.sh"
    info "Or run manually with: TV_HOST=$TV_HOST venv/bin/python home-watch.py"
fi
info ""

# Final instructions
success "=== Setup Complete! ==="
info ""
info "Your LG TV now has the Apple TV-style launcher installed!"
info ""
info "How to use:"
info "  - Press the '2' key on your remote to launch the launcher from anywhere"
info "    (Hold '2' for 2 seconds while launcher is open to set this shortcut)"
info "  - Press Home once: Brief flash of LG's home → our launcher"
info "  - Press Home twice within 3 seconds: Stay on LG's home intentionally"
info "  - Rearrange apps: Hold OK on a tile until it wiggles, then move with arrows"
info ""
info "Maintenance tips:"
info "  - Monthly: Open Developer Mode app on TV and press 'Extend Session Time'"
info "  - When you install/remove apps: Re-run './install.sh' to update app grid"
info "  - To uninstall: Use Developer Mode app on TV or run 'ares-remove -d LG-TV com.gathin.tvhome'"
info ""
info "Enjoy your clean, ad-free TV experience! 🎉"