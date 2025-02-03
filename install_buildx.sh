#!/bin/bash

# Function to test directory permissions and buildx installation
test_and_install_buildx() {
    echo "Starting buildx installation diagnostics..."
    
    # Test directory creation
    echo "Step 1: Testing directory creation..."
    if ! sudo mkdir -p /usr/local/lib/docker/cli-plugins; then
        echo "ERROR: Failed to create directory"
        return 1
    fi
    echo "Directory creation successful"

    # Test directory write permissions
    echo "Step 2: Testing directory permissions..."
    if ! sudo touch /usr/local/lib/docker/cli-plugins/test; then
        echo "ERROR: Cannot write to directory"
        return 1
    fi
    sudo rm /usr/local/lib/docker/cli-plugins/test
    echo "Directory permissions verified"

    # Download buildx to temporary location
    echo "Step 3: Downloading buildx..."
    TEMP_DIR=$(mktemp -d)
    BUILDX_URL="https://github.com/docker/buildx/releases/download/v0.12.1/buildx-v0.12.1.linux-amd64"
    
    if ! curl -L ${BUILDX_URL} -o ${TEMP_DIR}/docker-buildx; then
        echo "ERROR: Failed to download buildx"
        rm -rf ${TEMP_DIR}
        return 1
    fi
    echo "Download successful"

    # Move buildx to final location
    echo "Step 4: Installing buildx..."
    if ! sudo mv ${TEMP_DIR}/docker-buildx /usr/local/lib/docker/cli-plugins/docker-buildx; then
        echo "ERROR: Failed to move buildx to final location"
        rm -rf ${TEMP_DIR}
        return 1
    fi

    # Set permissions
    echo "Step 5: Setting permissions..."
    if ! sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-buildx; then
        echo "ERROR: Failed to set executable permissions"
        return 1
    fi

    # Cleanup
    rm -rf ${TEMP_DIR}
    
    # Verify installation
    echo "Step 6: Verifying installation..."
    if [ -x "/usr/local/lib/docker/cli-plugins/docker-buildx" ]; then
        echo "Buildx installation completed successfully"
        return 0
    else
        echo "ERROR: Installation verification failed"
        return 1
    fi
}

# Main execution
echo "Starting buildx installation process..."
if [ -f "/usr/local/lib/docker/cli-plugins/docker-buildx" ]; then
    echo "Buildx is already installed"
else
    if test_and_install_buildx; then
        echo "Installation completed successfully"
    else
        echo "Installation failed"
        exit 1
    fi
fi
