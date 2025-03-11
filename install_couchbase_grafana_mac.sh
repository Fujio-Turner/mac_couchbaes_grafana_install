#!/bin/bash

# Exit on any error
set -e

# Check if Homebrew is installed
if ! command -v brew &> /dev/null; then
    echo "Homebrew is not installed. Please install Homebrew from https://brew.sh/ and then run this script again."
    exit 1
fi

echo "Starting installation of Couchbase data source plugin for Grafana..."

### Step 1: Check and Install/Upgrade Go (version 1.21 or higher required)
echo "Step 1: Checking for Go..."
if ! command -v go &> /dev/null; then
    echo "Go is not installed. Installing Go..."
    brew install go
else
    GO_VERSION=$(go version | sed -n 's/.*go\([0-9]\+\.[0-9]\+\.[0-9]\+\).*/\1/p')
    if [[ "$GO_VERSION" < "1.21.0" ]]; then
        echo "Go version $GO_VERSION is less than 1.21.0. Upgrading Go..."
        brew upgrade go
    else
        echo "Go version $GO_VERSION is sufficient."
    fi
fi

### Step 2: Check and Install Node.js and Yarn
echo "Step 2: Checking for Node.js and Yarn..."
if ! command -v node &> /dev/null; then
    echo "Node.js is not installed. Installing Node.js..."
    brew install node
else
    echo "Node.js is installed."
fi

if ! command -v yarn &> /dev/null; then
    echo "Yarn is not installed. Installing Yarn..."
    npm install -g yarn
else
    echo "Yarn is installed."
fi

### Step 3: Check and Install Grafana
echo "Step 3: Checking for Grafana..."
if ! brew list grafana &> /dev/null; then
    echo "Grafana is not installed. Installing Grafana..."
    brew install grafana
else
    echo "Grafana is already installed."
fi

### Step 4: Check and Install wget
echo "Step 4: Checking for wget..."
if ! command -v wget &> /dev/null; then
    echo "wget is not installed. Installing wget..."
    brew install wget
else
    echo "wget is installed."
fi

### Step 5: Set Up Plugin Directory
echo "Step 5: Setting up plugin directory..."
PLUGIN_DIR="/usr/local/var/lib/grafana/plugins/couchbase-datasource"
if [ "$1" = "--update" ] || [ ! -d "$PLUGIN_DIR" ]; then
    if [ "$1" = "--update" ] && [ -d "$PLUGIN_DIR" ]; then
        echo "Removing existing plugin directory for update..."
        rm -rf "$PLUGIN_DIR"
    fi
    echo "Downloading Couchbase plugin repository..."
    TMP_DIR=$(mktemp -d)
    wget -O "$TMP_DIR/grafana-plugin.zip" https://github.com/couchbaselabs/grafana-plugin/archive/refs/heads/main.zip
    echo "Extracting the plugin..."
    unzip -q "$TMP_DIR/grafana-plugin.zip" -d "$TMP_DIR"
    echo "Moving plugin to $PLUGIN_DIR..."
    mv "$TMP_DIR/grafana-plugin-main" "$PLUGIN_DIR"
    echo "Cleaning up temporary files..."
    rm -rf "$TMP_DIR"
else
    echo "Plugin directory $PLUGIN_DIR already exists. Skipping download."
    echo "To update the plugin, run the script with the --update flag."
fi

### Step 6: Install Mage if Not Present
echo "Step 6: Checking for Mage..."
if ! command -v mage &> /dev/null; then
    echo "Mage is not installed. Installing Mage..."
    go install github.com/magefile/mage@latest
    export PATH="$HOME/go/bin:$PATH"
else
    echo "Mage is already installed."
fi

### Step 7: Build the Plugin
echo "Step 7: Building the plugin..."
cd "$PLUGIN_DIR"
echo "Building the plugin backend with Mage..."
mage build:backend
echo "Installing frontend dependencies..."
yarn install
echo "Building frontend..."
yarn build
echo "Plugin build complete."

### Step 8: Move Built Files to Root Directory
echo "Step 8: Moving built files to root directory..."
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then
    cp dist/gpx_couchbase_darwin_arm64 ./gpx_couchbase
else
    cp dist/gpx_couchbase_darwin_amd64 ./gpx_couchbase
fi
cp -r dist/* .
chmod +x gpx_couchbase
echo "Built files moved and permissions set."

### Step 9: Configure Grafana to Allow Unsigned Plugins
echo "Step 9: Configuring Grafana..."
GRAFANA_INI="/usr/local/etc/grafana/grafana.ini"
if ! grep -q "allow_loading_unsigned_plugins = couchbase-datasource" "$GRAFANA_INI"; then
    echo "Configuring Grafana to allow unsigned plugins..."
    sed -i '' '/\[plugins\]/a\
allow_loading_unsigned_plugins = couchbase-datasource
' "$GRAFANA_INI"
else
    echo "Grafana already configured to allow unsigned plugins."
fi

### Step 10: Restart Grafana
echo "Step 10: Restarting Grafana to apply changes..."
brew services restart grafana
echo "Grafana restarted."

echo "Couchbase data source plugin installation complete! You can now access it in Grafana."
