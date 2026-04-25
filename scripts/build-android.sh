#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Alist-To-HF Migrator - Android Build Script
# Builds the Flutter Android APK and copies it to dist/
# ============================================================================

echo "============================================"
echo "  Alist-To-HF Migrator - Android Build"
echo "============================================"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info()  { echo -e "${GREEN}[INFO]${NC}  $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
log_step()  { echo -e "${YELLOW}[$1]${NC}  $2"; }

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$PROJECT_DIR"

# Extract version from pubspec.yaml
VERSION=$(grep -m1 'version:' pubspec.yaml | grep -v 'sdk:' | sed 's/.*version:\s*//' | sed 's/+.*//' || true)

if [ -z "$VERSION" ]; then
    log_error "Could not extract version from pubspec.yaml"
    exit 1
fi

log_info "Version: $VERSION"
echo ""

# Create dist directory
mkdir -p dist

# Step 1: Get dependencies
log_step "1/3" "Running flutter pub get..."
if ! flutter pub get; then
    log_error "flutter pub get failed"
    exit 1
fi
log_info "Dependencies resolved"
echo ""

# Step 2: Build
log_step "2/3" "Building Android APK (release)..."
if ! flutter build apk --release; then
    log_error "flutter build apk failed"
    exit 1
fi
log_info "Build completed"
echo ""

# Step 3: Copy to dist
log_step "3/3" "Copying APK to dist/..."
APK_NAME="alist-to-hf-migrator-${VERSION}-android.apk"
SOURCE_APK="build/app/outputs/flutter-apk/app-release.apk"

if [ ! -f "$SOURCE_APK" ]; then
    log_error "APK not found: $SOURCE_APK"
    exit 1
fi

cp "$SOURCE_APK" "dist/${APK_NAME}"
log_info "APK copied: dist/${APK_NAME}"
echo ""

# Summary
echo "============================================"
echo "  Build Successful!"
echo "============================================"
echo "  Output: dist/${APK_NAME}"
echo "  Size:   $(du -h "dist/${APK_NAME}" | cut -f1)"
echo "============================================"
