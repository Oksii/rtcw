#!/bin/bash
set -x

# Base directories
GAME_BASE="/home/game"
SETTINGS_BASE="${GAME_BASE}/settings"

# Configuration with defaults
declare -A CONFIG=(
    [REDIRECTURL]="http://rtcw.life/files/mapdb"
    [MAP_PORT]="27960"
    [STARTMAP]="mp_ice"
    [HOSTNAME]="RTCW"
    [MAXCLIENTS]="32"
    [PASSWORD]=""
    [RCONPASSWORD]=""
    [REFEREEPASSWORD]=""
    [SCPASSWORD]=""
    [TIMEOUTLIMIT]="1"
    [SERVERCONF]="comp"
    [SETTINGSURL]="https://github.com/Oksii/rtcw-config-priv.git"
    [SETTINGSBRANCH]="main"
    [SETTINGSPAT]=""
    [CONF_CHECKVERSION]="17"
    [STATS_SUBMIT]="0"
    [STATS_URL]="https://rtcwproapi.donkanator.com/submit"
    [AUTO_UPDATE]="true"
    [XMAS]="false"
    [XMAS_FILE]="https://deployment-bucket.rtcw.eu/maps/rtcwpro/mp_gathermas.pk3"
)

# Load environment variables into config
for key in "${!CONFIG[@]}"; do
    CONFIG[$key]=${!key:-${CONFIG[$key]}}
done

# Default maps and their packages
declare -A default_maps=(
    [mp_assault]="mp_pak0" [mp_base]="mp_pak0" [mp_beach]="mp_pak0"
    [mp_castle]="mp_pak0" [mp_depot]="mp_pak0" [mp_destruction]="mp_pak0"
    [mp_sub]="mp_pak0" [mp_village]="mp_pak0" [mp_trenchtoast]="mp_pakmaps0"
    [mp_ice]="mp_pakmaps1" [mp_keep]="mp_pakmaps2" [mp_chateau]="mp_pakmaps3"
    [mp_tram]="mp_pakmaps4" [mp_dam]="mp_pakmaps5" [mp_rocket]="mp_pakmaps6"
)

# Update configuration from git
update_config() {
    [[ "${CONFIG[AUTO_UPDATE]}" != "true" ]] && return 0
    
    echo "Checking for configuration updates..."
    local auth_url="${CONFIG[SETTINGSURL]}"
    [[ -n "${CONFIG[SETTINGSPAT]}" ]] && \
        auth_url="https://${CONFIG[SETTINGSPAT]}@$(echo "${CONFIG[SETTINGSURL]}" | sed 's~https://~~g')"
    
    if git clone --depth 1 --single-branch --branch "${CONFIG[SETTINGSBRANCH]}" "${auth_url}" "${SETTINGS_BASE}.new"; then
        rm -rf "${SETTINGS_BASE}"
        mv "${SETTINGS_BASE}.new" "${SETTINGS_BASE}"
    else
        echo "Warning: Configuration update failed, using existing version"
    fi
}

# Apply map mutations
run_mutations() {
    local map=$1
    local map_mutated=0
    local map_path="${GAME_BASE}/tmp/maps/${map}.bsp"
    local temp_path="${map_path}.tmp"
    
    # Global mutations
    if [[ -f "${SETTINGS_BASE}/map-mutations/global.sh" ]]; then
        bash "${SETTINGS_BASE}/map-mutations/global.sh" "${map_path}" "${temp_path}"
        if [[ -f "${temp_path}" ]]; then
            map_mutated=1
            echo "Applied global mutations to ${map}"
            mv "${temp_path}" "${map_path}"
        fi
    fi
    
    # Map-specific mutations
    if [[ -f "${SETTINGS_BASE}/map-mutations/${map}.sh" ]]; then
        echo "Applying specific mutations to ${map}"
        bash "${SETTINGS_BASE}/map-mutations/${map}.sh" "${map_path}"
        map_mutated=1
    fi
    
    if [[ ${map_mutated} -eq 1 ]]; then
        mkdir -p "${GAME_BASE}/rtcwpro/maps"
        mv "${map_path}" "${GAME_BASE}/rtcwpro/maps/${map}.bsp"
    else
        echo "No mutations applied to ${map}"
    fi
}

# Process custom maps
process_maps() {
    IFS=':' read -ra MAPS_ARRAY <<< "${MAPS:-}"
    for map in "${MAPS_ARRAY[@]}"; do
        [[ -z "$map" ]] && continue
        
        # Skip default maps
        if [[ -n "${default_maps[$map]:-}" ]]; then
            echo "${map} is a default map so we will not attempt to download"
            continue
        fi
        
        # Download map if needed
        if [[ ! -f "${GAME_BASE}/main/${map}.pk3" ]]; then
            echo "Attempting to download ${map}"
            if [[ -f "/maps/${map}.pk3" ]]; then
                echo "Map ${map} is sourcable locally, copying into place"
                cp "/maps/${map}.pk3" "${GAME_BASE}/main/${map}.pk3.tmp"
            else
                if ! wget -O "${GAME_BASE}/main/${map}.pk3.tmp" "${CONFIG[REDIRECTURL]}/${map}.pk3"; then
                    echo "Failed to download ${map}, skipping mutations"
                    continue
                fi
            fi
            mv "${GAME_BASE}/main/${map}.pk3.tmp" "${GAME_BASE}/main/${map}.pk3"
        fi
        
        # Process map mutations
        rm -rf "${GAME_BASE}/rtcwpro/maps/${map}.bsp"
        mkdir -p "${GAME_BASE}/tmp/"
        if ! unzip "${GAME_BASE}/main/${map}.pk3" -d "${GAME_BASE}/tmp/"; then
            echo "Failed to extract ${map}, skipping mutations"
            rm -rf "${GAME_BASE}/tmp/"
            continue
        fi
        
        run_mutations "${map}"
        rm -rf "${GAME_BASE}/tmp/"
    done
}


# Process default maps
process_default_maps() {
    for map in "${!default_maps[@]}"; do
        rm -rf "${GAME_BASE}/rtcwpro/maps/${map}.bsp"
        echo "Processing default map ${map}"
        mkdir -p "${GAME_BASE}/tmp/maps/"
        unzip -j "main/${default_maps[$map]}.pk3" -d "${GAME_BASE}/tmp/maps/" "maps/${map}.bsp"
        run_mutations "${map}"
        rm -rf "${GAME_BASE}/tmp/"
    done
}

# Update mapscripts and configs
update_game_files() {
    # Clean and update mapscripts
    rm -f "${GAME_BASE}"/rtcwpro/maps/*.{script,spawns}
    for mapscript in "${SETTINGS_BASE}"/mapscripts/*.{script,spawns}; do
        [[ -f "${mapscript}" ]] && cp "${mapscript}" "${GAME_BASE}/rtcwpro/maps/"
    done
    
    # Update configs
    rm -rf "${GAME_BASE}/rtcwpro/configs/"
    mkdir -p "${GAME_BASE}/rtcwpro/configs/"
    cp "${SETTINGS_BASE}"/configs/*.config "${GAME_BASE}/rtcwpro/configs/"
    
    # Update server.cfg with environment variables
    cp "${SETTINGS_BASE}/server.cfg" "${GAME_BASE}/main/server.cfg"
    
    # Handle g_needpass separately since it's conditional
    [[ -n "${CONFIG[PASSWORD]}" ]] && NEEDPASS='set g_needpass "1"' || NEEDPASS=""
    sed -i "s/%CONF_NEEDPASS%/${NEEDPASS}/g" "${GAME_BASE}/main/server.cfg"
    
    # Replace all other CONF_ variables
    for var in "${!CONFIG[@]}"; do
        # Escape any forward slashes in the value to prevent sed errors
        value="${CONFIG[$var]//\//\\/}"
        sed -i "s/%CONF_${var}%/${value}/g" "${GAME_BASE}/main/server.cfg"
    done
    
    # Clean up any remaining unreplaced variables
    sed -i 's/%CONF_[A-Z]*%//g' "${GAME_BASE}/main/server.cfg"
    
    # Append extra configuration if it exists
    [[ -f "${GAME_BASE}/extra.cfg" ]] && \
        cat "${GAME_BASE}/extra.cfg" >> "${GAME_BASE}/main/server.cfg"
}

# Download the mp_gathermas.pk3 file if XMAS is true
download_xmas_files() {
    if [[ "${CONFIG[XMAS]}" == "true" ]]; then
        echo "XMAS is true. Downloading mp_gathermas.pk3..."
        wget -O "${GAME_BASE}/rtcwpro/mp_gathermas.pk3" "${CONFIG[XMAS_FILE]}"
    fi
}

# Move .spawn files from the xmas/ folder to maps/ folder if XMAS is true
move_xmas_spawn_files() {
    if [[ "${CONFIG[XMAS]}" == "true" ]]; then
        echo "XMAS is true. Moving .spawn files from xmas/ to maps/..."
        mkdir -p "${GAME_BASE}/rtcwpro/maps/"
        mv "${GAME_BASE}/xmas/*.spawn" "${GAME_BASE}/rtcwpro/maps/"
    fi
}

# Main execution
update_config
process_maps
process_default_maps
update_game_files
download_xmas_files
move_xmas_spawn_files

# Set up environment for game
[[ "${NOQUERY:-}" == "true" ]] && export LD_PRELOAD="${GAME_BASE}/libnoquery.so"
[[ -n "${CONFIG[PASSWORD]}" ]] && NEEDPASS='set g_needpass "1"'

# Launch the game server
exec "${GAME_BASE}/wolfded.x86" \
    +set dedicated 2 \
    +set fs_game "rtcwpro" \
    +set com_hunkmegs 512 \
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
    +set sv_checkversion "${CONFIG[CONF_CHECKVERSION]}" \
    +exec "server.cfg" \
    +map "${CONFIG[STARTMAP]}" \
    "${@}"