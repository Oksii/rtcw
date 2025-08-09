#!/bin/bash
set -euo pipefail

readonly datapath="${datapath:-/home/game}"

log() { echo "[$(date '+%H:%M:%S')] $*"; }
log_error() { echo "[$(date '+%H:%M:%S')] ERROR: $*" >&2; }

main() {
    log "Fetching latest RTCWPro release"
    
    mkdir -p "${datapath}"
    
    if [[ -f "/rtcwpro/server.zip" ]]; then
        log "Using pre-cached server.zip"
        cp "/rtcwpro/server.zip" "/tmp/server.zip"
        extract_and_cleanup "/tmp/server.zip"
        return 0
    fi
    
    # Fetch latest release info
    log "Fetching latest release info..."
    local release_info
    if ! release_info=$(curl --retry 3 --retry-delay 1 -fsL "https://api.github.com/repos/rtcwmp-com/rtcwPro/releases/latest"); then
        log_error "Failed to fetch latest release info"
        exit 1
    fi
    
    local asset filename download_url
    asset=$(echo "$release_info" | jq -r '.assets[] | select(.name | test("^rtcwpro_[0-9]+_server.+zip$"))')
    
    if [[ -z "$asset" || "$asset" == "null" ]]; then
        log_error "No matching server asset found"
        echo "$release_info" | jq '.assets[].name' >&2
        exit 1
    fi
    
    filename=$(echo "$asset" | jq -r '.name')
    download_url=$(echo "$asset" | jq -r '.browser_download_url')
    
    log "Downloading ${filename}..."
    
    if ! curl --retry 3 --retry-delay 1 -fsL "$download_url" -o "/tmp/${filename}"; then
        log_error "Failed to download ${filename}"
        exit 1
    fi
    
    extract_and_cleanup "/tmp/${filename}"
}

extract_and_cleanup() {
    local archive_path="$1"
    
    if [[ ! -f "$archive_path" ]] || [[ ! -s "$archive_path" ]]; then
        log_error "Archive file is missing or empty: $archive_path"
        exit 1
    fi
    
    log "Extracting RTCWPro files to ${datapath}"
    
    if ! unzip -q "$archive_path" -d "$datapath"; then
        log_error "Failed to extract $archive_path"
        exit 1
    fi
    
    log "Cleaning up unwanted files"
    
    # Remove unwanted files
    rm -rf \
        "$archive_path" \
        "${datapath}/rtcwpro/qagame_mp_x86.dll" \
        "${datapath}/libmysql.dll" \
        "${datapath}/wolfDED.exe" \
        "${datapath}/maps" \
        "${datapath}/configs" \
        "${datapath}/mapConfigs" \
        "${datapath}/rtcwpro/"*.cfg \
        "${datapath}/rtcwpro_127_server/" \
        2>/dev/null || true
    
    chmod 0755 "${datapath}/wolfded.x86" "${datapath}/rtcwpro/qagame.mp.i386.so"
    
    log "RTCWPro setup completed successfully"
}

main