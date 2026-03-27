#!/usr/bin/env bash
set -o errexit

# Install LibreDWG system package for DWG→DXF conversion
apt-get update -qq && apt-get install -y -qq libredwg-tools 2>/dev/null || {
    echo "==> apt install failed (expected on Render free tier), building from source..."

    # Download pre-built LibreDWG from GitHub releases
    LIBREDWG_VERSION="0.13.3"
    LIBREDWG_DIR="$(pwd)/libredwg"

    if [ ! -f "$LIBREDWG_DIR/bin/dwg2dxf" ]; then
        mkdir -p "$LIBREDWG_DIR"

        # Try installing build dependencies and compiling
        apt-get install -y -qq build-essential autoconf automake libtool texinfo 2>/dev/null || true

        curl -sL "https://github.com/LibreDWG/libredwg/releases/download/${LIBREDWG_VERSION}/libredwg-${LIBREDWG_VERSION}.tar.xz" -o /tmp/libredwg.tar.xz
        tar -xf /tmp/libredwg.tar.xz -C /tmp
        cd /tmp/libredwg-${LIBREDWG_VERSION}
        ./configure --prefix="$LIBREDWG_DIR" --disable-shared --disable-python 2>&1 | tail -5
        make -j"$(nproc)" 2>&1 | tail -5
        make install 2>&1 | tail -5
        cd -
        rm -rf /tmp/libredwg*

        echo "==> LibreDWG installed to $LIBREDWG_DIR"
    else
        echo "==> LibreDWG already installed"
    fi

    # Make dwg2dxf available on PATH
    ln -sf "$LIBREDWG_DIR/bin/dwg2dxf" /usr/local/bin/dwg2dxf 2>/dev/null || true
}

# Add LibreDWG to PATH
export PATH="$(pwd)/libredwg/bin:$PATH"

# Save the full path to dwg2dxf for the Python app
DWG2DXF_PATH="$(command -v dwg2dxf 2>/dev/null || echo "$(pwd)/libredwg/bin/dwg2dxf")"
echo "$DWG2DXF_PATH" > /opt/render/project/src/.libredwg_path
echo "==> Wrote dwg2dxf path to /opt/render/project/src/.libredwg_path: $DWG2DXF_PATH"

# Verify dwg2dxf is available
if command -v dwg2dxf &>/dev/null; then
    echo "==> dwg2dxf found: $(which dwg2dxf)"
    dwg2dxf --version 2>&1 || true
else
    echo "WARNING: dwg2dxf not found. DWG upload will not work."
fi

# Install Python dependencies
pip install --upgrade pip
pip install -r requirements.txt

echo "==> Build complete"
