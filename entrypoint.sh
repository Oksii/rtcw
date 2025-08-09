#!/bin/bash
set -euo pipefail

readonly GAME_BASE="/home/game"
readonly SETTINGS_BASE="${GAME_BASE}/settings"
readonly TEMP_DIR="${GAME_BASE}/tmp"

declare -A CONFIG=(
    [AUTO_UPDATE]="${AUTO_UPDATE:-true}"
    [CHECKVERSION]="${CHECKVERSION:-17}"
    [HOSTNAME]="${HOSTNAME:-RTCW}"
    [SERVERCONF]="${SERVERCONF:-comp}"
    [MAXCLIENTS]="${MAXCLIENTS:-32}"
    [PASSWORD]="${PASSWORD:-}"
    [SCPASSWORD]="${SCPASSWORD:-}"
    [REFPASSWORD]="${REFPASSWORD:-}"
    [RCONPASSWORD]="${RCONPASSWORD:-}"
    [TIMEOUTLIMIT]="${TIMEOUTLIMIT:-1}"
    [REDIRECTURL]="${REDIRECTURL:-http://rtcw.life/files/mapdb}"
    [SETTINGSPAT]="${SETTINGSPAT:-}"
    [SETTINGSBRANCH]="${SETTINGSBRANCH:-main}"
    [SETTINGSURL]="${SETTINGSURL:-https://github.com/Oksii/rtcw-config.git}"
    [MAP_PORT]="${MAP_PORT:-27960}"
    [STARTMAP]="${STARTMAP:-mp_ice}"
    [STATS_SUBMIT]="${STATS_SUBMIT:-0}"
    [STATS_URL]="${STATS_URL:-https://rtcwproapi.donkanator.com/submit}"
    [XMAS_FILE]="${XMAS_FILE:-http://rtcw.life/files/mapdb/mp_gathermas.pk3}"
    [XMAS]="${XMAS:-false}"
    [SKIP_MAP_PROCESSING]="${SKIP_MAP_PROCESSING:-false}"
)

# Default maps lookup
declare -A DEFAULT_MAPS=(
    [mp_assault]=mp_pak0
    [mp_base]=mp_pak0
    [mp_beach]=mp_pak0
    [mp_castle]=mp_pak0
    [mp_depot]=mp_pak0
    [mp_destruction]=mp_pak0
    [mp_sub]=mp_pak0
    [mp_village]=mp_pak0
    [mp_trenchtoast]=mp_pakmaps0
    [mp_ice]=mp_pakmaps1
    [mp_keep]=mp_pakmaps2
    [mp_chateau]=mp_pakmaps3
    [mp_tram]=mp_pakmaps4
    [mp_dam]=mp_pakmaps5
    [mp_rocket]=mp_pakmaps6
)

log() { echo "[$(date '+%H:%M:%S')] $*"; }
log_error() { echo "[$(date '+%H:%M:%S')] ERROR: $*" >&2; }

update_config() {
    [[ "${CONFIG[AUTO_UPDATE]}" != "true" ]] && return 0
    
    log "Updating configuration from git..."
    
    local auth_url="${CONFIG[SETTINGSURL]}"
    [[ -n "${CONFIG[SETTINGSPAT]}" ]] && 
        auth_url="https://${CONFIG[SETTINGSPAT]}@${CONFIG[SETTINGSURL]#https://}"
    
    if git clone --depth 1 --single-branch --branch "${CONFIG[SETTINGSBRANCH]}" \
        "${auth_url}" "${SETTINGS_BASE}.new" 2>/dev/null; then
        rm -rf "${SETTINGS_BASE}"
        mv "${SETTINGS_BASE}.new" "${SETTINGS_BASE}"
        log "Configuration updated successfully"
    else
        log "Warning: Failed to update configuration, using existing"
    fi
}

get_skip_list() {
    local global_sh="${SETTINGS_BASE}/map-mutations/global.sh"
    [[ ! -f "$global_sh" ]] && return
    
    awk '/^default_maps_skip=\(/,/^\)/ {
        if ($0 ~ /"[^"]+"/) {
            gsub(/"/, "")
            gsub(/^[[:space:]]+/, "")
            print
        }
    }' "$global_sh"
}

needs_mutations() {
    local map="$1"
    
    # Has specific mutation script
    [[ -f "${SETTINGS_BASE}/map-mutations/${map}.sh" ]] && return 0
    
    # Not in skip list and has global mutations
    if [[ -f "${SETTINGS_BASE}/map-mutations/global.sh" ]]; then
        local skip_list
        skip_list=$(get_skip_list)
        ! echo "$skip_list" | grep -q "^${map}$" && return 0
    fi
    
    return 1
}

apply_mutations() {
    local map="$1" map_path="$2"
    local temp_path="${map_path}.tmp"
    local mutations_applied=0

    if [[ -f "${SETTINGS_BASE}/map-mutations/${map}.sh" ]]; then
        bash "${SETTINGS_BASE}/map-mutations/${map}.sh" "${map_path}"
        mutations_applied=1
    fi

    local skip_list
    skip_list=$(get_skip_list)
    if ! echo "$skip_list" | grep -q "^${map}$" && 
       [[ -f "${SETTINGS_BASE}/map-mutations/global.sh" ]] &&
       bash "${SETTINGS_BASE}/map-mutations/global.sh" "${map_path}" "${temp_path}" &&
       [[ -f "${temp_path}" ]]; then
        mv "${temp_path}" "${map_path}"
        mutations_applied=1
    fi

    if ((mutations_applied)); then
        mkdir -p "${GAME_BASE}/rtcwpro/maps"
        mv "${map_path}" "${GAME_BASE}/rtcwpro/maps/${map}.bsp"
        return 0
    fi
    return 1
}

process_map() {
    local map="$1" pk3_path="$2"

    needs_mutations "${map}" || return 0

    local temp_dir="${TEMP_DIR}"
    mkdir -p "${temp_dir}/maps"
    
    if unzip -j "${pk3_path}" "maps/${map}.bsp" -d "${temp_dir}/maps/"; then
        apply_mutations "${map}" "${temp_dir}/maps/${map}.bsp"
    fi
    rm -rf "${temp_dir}"
}

download_custom_maps() {
    [[ -z "${MAPS:-}" ]] && return 0
    
    log "Downloading custom maps"
    IFS=':' read -ra custom_maps <<< "$MAPS"
    
    for map in "${custom_maps[@]}"; do
        [[ -z "$map" || -n "${DEFAULT_MAPS[$map]:-}" ]] && continue
        
        local map_file="${GAME_BASE}/main/${map}.pk3"
        [[ -f "$map_file" ]] && continue
        
        # Check for local copy first
        if [[ -f "/maps/${map}.pk3" ]]; then
            log "Using local copy of $map"
            cp "/maps/${map}.pk3" "$map_file"
            continue
        fi
        
        log "Downloading custom map: $map"
        if curl --retry 3 --retry-delay 1 -fsL "${CONFIG[REDIRECTURL]}/${map}.pk3" -o "$map_file"; then
            log "Downloaded $map successfully"
        else
            log_error "Failed to download $map"
        fi
    done
}

process_maps() {
    log "Processing maps (SKIP_MAP_PROCESSING=${CONFIG[SKIP_MAP_PROCESSING]})"
    
    if [[ "${CONFIG[SKIP_MAP_PROCESSING]}" == "true" ]]; then
        log "Optimized mode: Processing only mp_ice with mp_ice.sh"
        
        if [[ -f "${SETTINGS_BASE}/map-mutations/mp_ice.sh" && -f "${GAME_BASE}/main/${DEFAULT_MAPS[mp_ice]}.pk3" ]]; then
            process_map "mp_ice" "${GAME_BASE}/main/${DEFAULT_MAPS[mp_ice]}.pk3"
            log "mp_ice processed with specific mutations only"
        else
            log "mp_ice.sh or pak file not found, skipping processing"
        fi
        return
    fi
    
    log "Full processing mode: Processing all maps with mutations"
    
    if [[ -n "${MAPS:-}" ]]; then
        IFS=':' read -ra custom_maps <<< "$MAPS"
        for map in "${custom_maps[@]}"; do
            [[ -z "$map" || -n "${DEFAULT_MAPS[$map]:-}" ]] && continue
            local map_file="${GAME_BASE}/main/${map}.pk3"
            [[ -f "$map_file" ]] && process_map "$map" "$map_file"
        done
    fi
    
    for map in "${!DEFAULT_MAPS[@]}"; do
        local pk3_file="${GAME_BASE}/main/${DEFAULT_MAPS[$map]}.pk3"
        [[ -f "$pk3_file" ]] && process_map "$map" "$pk3_file"
    done
}

update_game_files() {
    log "Updating game files and configurations"
    
    # Copy mapscripts
    rm -f "${GAME_BASE}"/rtcwpro/maps/*.{script,spawns} 2>/dev/null || true
    if [[ -d "${SETTINGS_BASE}/mapscripts" ]]; then
        cp "${SETTINGS_BASE}"/mapscripts/*.{script,spawns} "${GAME_BASE}/rtcwpro/maps/" 2>/dev/null || true
    fi
    
    # Copy configs
    rm -rf "${GAME_BASE}/rtcwpro/configs/" 2>/dev/null || true
    mkdir -p "${GAME_BASE}/rtcwpro/configs/"
    if [[ -d "${SETTINGS_BASE}/configs" ]]; then
        cp "${SETTINGS_BASE}"/configs/*.config "${GAME_BASE}/rtcwpro/configs/" 2>/dev/null || true
    fi
    
    # Process server.cfg
    local server_cfg="${GAME_BASE}/main/server.cfg"
    if [[ -f "${SETTINGS_BASE}/server.cfg" ]]; then
        cp "${SETTINGS_BASE}/server.cfg" "$server_cfg"
        
        while IFS='=' read -r key value; do
            [[ $key == CONF_* ]] && sed -i "s|%${key}%|${value}|g" "$server_cfg"
        done < <(env | grep '^CONF_' || true)
        
        for key in "${!CONFIG[@]}"; do
            sed -i "s|%CONF_${key}%|${CONFIG[$key]}|g" "$server_cfg"
        done
        
        if [[ -n "${CONFIG[PASSWORD]}" ]]; then
            sed -i 's/%CONF_NEEDPASS%/set g_needpass "1"/g' "$server_cfg"
        else
            sed -i 's/%CONF_NEEDPASS%//g' "$server_cfg"
        fi
        
        # Clean up unused placeholders
        sed -i 's/%CONF_[A-Z_]*%//g' "$server_cfg"
        
        # Append extra config if exists
        [[ -f "${GAME_BASE}/extra.cfg" ]] && cat "${GAME_BASE}/extra.cfg" >> "$server_cfg"
        
        log "Server configuration updated"
    fi
}

setup_xmas_content() {
    [[ "${CONFIG[XMAS]}" != "true" ]] && return 0
    
    log "Setting up XMAS content"
    curl --retry 3 --retry-delay 1 -fsL "${CONFIG[XMAS_FILE]}" \
        -o "${GAME_BASE}/rtcwpro/mp_gathermas.pk3" &
    
    if [[ -d "${SETTINGS_BASE}/xmas" ]]; then
        cp "${SETTINGS_BASE}"/xmas/*.{script,spawns} "${GAME_BASE}/rtcwpro/maps/" 2>/dev/null || true
    fi
    
    wait
    log "XMAS content setup complete"
}

parse_additional_args() {
    [[ -z "${ADDITIONAL_CLI_ARGS:-}" ]] && return
    eval "echo $ADDITIONAL_CLI_ARGS"
}

main() {
    log "Starting RTCW server setup (SKIP_MAP_PROCESSING=${CONFIG[SKIP_MAP_PROCESSING]})"
    
    update_config
    download_custom_maps
    process_maps
    update_game_files
    setup_xmas_content
    
    local additional_args
    additional_args=$(parse_additional_args)
    
    log "Launching RTCW server"
    log "Port: ${CONFIG[MAP_PORT]}, Max clients: ${CONFIG[MAXCLIENTS]}, Start map: ${CONFIG[STARTMAP]}"
    
    exec "${GAME_BASE}/wolfded.x86" \
        +set dedicated 2 \
        +set fs_game "rtcwpro" \
        +set com_hunkmegs 256 \
        +set vm_game 0 \
        +set ttycon 0 \
        +set net_ip 0.0.0.0 \
        +set net_port "${CONFIG[MAP_PORT]}" \
        +set sv_maxclients "${CONFIG[MAXCLIENTS]}" \
        +set fs_basepath "${GAME_BASE}" \
        +set fs_homepath "${GAME_BASE}" \
        +set sv_GameConfig "${CONFIG[SERVERCONF]}" \
        +set sv_authenabled 0 \
        +set sv_AuthStrictMode 0 \
        +set sv_checkversion "${CONFIG[CHECKVERSION]}" \
        +exec "server.cfg" \
        +map "${CONFIG[STARTMAP]}" \
        ${additional_args} \
        "$@"
}

main "$@"