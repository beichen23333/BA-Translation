set -euo pipefail

INFO_JSON_FILE="${1:-info.json}"

# GITHUB
if command -v jq >/dev/null 2>&1; then
    ADDRESSABLE_CATALOG_URL=$(jq -r '.JP.AddressableCatalogUrl' "$INFO_JSON_FILE")
    APK_VERSION_CODE=$(jq -r '.JP.APKVersionCode' "$INFO_JSON_FILE")
    APK_VERSION_NAME=$(jq -r '.JP.APKVersionName' "$INFO_JSON_FILE")
else
# 本地运行
    ADDRESSABLE_CATALOG_URL=$(grep -o '"AddressableCatalogUrl": *"[^"]*' "$INFO_JSON_FILE" | head -1 | sed 's/.*"AddressableCatalogUrl": *"//')
    APK_VERSION_CODE=$(grep -o '"APKVersionCode": *"[^"]*' "$INFO_JSON_FILE" | head -1 | sed 's/.*"APKVersionCode": *"//')
    APK_VERSION_NAME=$(grep -o '"APKVersionName": *"[^"]*' "$INFO_JSON_FILE" | head -1 | sed 's/.*"APKVersionName": *"//')
fi

last_seg() { basename "$1"; }
BUILD_VERSION="${APK_VERSION_NAME}-${APK_VERSION_CODE}($(last_seg "$ADDRESSABLE_CATALOG_URL"))"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "BA_VERSION_NAME=$BUILD_VERSION" >> "$GITHUB_OUTPUT"
else
    echo "BA_VERSION_NAME: $BUILD_VERSION"
fi
