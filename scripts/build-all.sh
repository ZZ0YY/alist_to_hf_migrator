#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Alist-To-HF Migrator - Build All Platforms
# Builds both Windows and Android and places results in dist/
#
# Prerequisites:
#   - Flutter SDK installed and on PATH
#   - For Windows: running on Windows with desktop enabled
#   - For Android: Java 17+, Android SDK with build tools
# ============================================================================

echo "============================================"
echo "  Alist-To-HF Migrator - Build All"
echo "============================================"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}  $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$PROJECT_DIR"

# Parse arguments
BUILD_WINDOWS=true
BUILD_ANDROID=true

for arg in "$@"; do
    case "$arg" in
        --windows-only)
            BUILD_ANDROID=false
            ;;
        --android-only)
            BUILD_WINDOWS=false
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --windows-only    Build only Windows"
            echo "  --android-only    Build only Android"
            echo "  --help, -h        Show this help"
            exit 0
            ;;
    esac
done

# Create dist directory
mkdir -p dist

FAILED=0
RESULTS=()

# ---------- Build Windows ----------
if [ "$BUILD_WINDOWS" = true ]; then
    echo -e "${CYAN}>>> Building Windows (x64)${NC}"
    echo ""

    if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" || "$OSTYPE" == "cygwin" ]]; then
        # Native Windows: run the batch script
        if cmd //C "scripts\\build-windows.bat"; then
            RESULTS+=("Windows: SUCCESS")
        else
            RESULTS+=("Windows: FAILED")
            FAILED=1
        fi
    else
        log_error "Windows build requires running on Windows."
        log_error "Skipping Windows build (current OS: $OSTYPE)."
        RESULTS+=("Windows: SKIPPED (not Windows)")
    fi
    echo ""
fi

# ---------- Build Android ----------
if [ "$BUILD_ANDROID" = true ]; then
    echo -e "${CYAN}>>> Building Android (APK)${NC}"
    echo ""

    if bash "${SCRIPT_DIR}/build-android.sh"; then
        RESULTS+=("Android: SUCCESS")
    else
        RESULTS+=("Android: FAILED")
        FAILED=1
    fi
    echo ""
fi

# ---------- Summary ----------
echo "============================================"
if [ $FAILED -eq 0 ]; then
    echo -e "  ${GREEN}All Builds Successful!${NC}"
else
    echo -e "  ${RED}Some Builds Failed!${NC}"
fi
echo "============================================"

for result in "${RESULTS[@]}"; do
    echo "  - $result"
done

echo ""
echo "  Output files in dist/:"
if [ -d dist ] && [ -n "$(ls -A dist 2>/dev/null)" ]; then
    ls -lh dist/ | tail -n +2 | while read -r line; do
        echo "    $line"
    done
else
    echo "    (no files)"
fi
echo "============================================"

exit $FAILED
