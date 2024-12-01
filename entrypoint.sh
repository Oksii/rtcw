#!/bin/bash
set -x

# Base directories
GAME_BASE="/home/game"
SETTINGS_BASE="${GAME_BASE}/settings"

# Config defaults with more robust initialization
declare -A CONFIG=(
    [AUTO_UPDATE]="${AUTO_UPDATE:-true}"
    [CHECKVERSION]="${CHECKVERSION:-17}"
    [HOSTNAME]="${HOSTNAME:-RTCW}"
    [SERVERCONF]="${SERVERCONF:-comp}"
    [MAXCLIENTS]="${MAXCLIENTS:-32}"
    [PASSWORD]="${PASSWORD:-}"
    [SCPASSWORD]="${SCPASSWORD:-}"
    [RCONPASSWORD]="${RCONPASSWORD:-}"
    [REFEREEPASSWORD]="${REFEREEPASSWORD:-}"
    [TIMEOUTLIMIT]="${TIMEOUTLIMIT:-1}"
    [REDIRECTURL]="${REDIRECTURL:-http://rtcw.life/files/mapdb}"
    [SETTINGSPAT]="${SETTINGSPAT:-}"
    [SETTINGSBRANCH]="${SETTINGSBRANCH:-main}"
    [SETTINGSURL]="${SETTINGSURL:-https://github.com/Oksii/rtcw-config-priv.git}"
    [MAP_PORT]="${MAP_PORT:-27960}"
    [STARTMAP]="${STARTMAP:-mp_ice}"
    [STATS_SUBMIT]="${STATS_SUBMIT:-0}"
    [STATS_URL]="${STATS_URL:-https://rtcwproapi.donkanator.com/submit}"
    [XMAS_FILE]="${XMAS_FILE:-http://rtcw.life/files/mapdb/mp_gathermas.pk3}"
    [XMAS]="${XMAS:-false}"
)

# Default maps with their packages (readonly for optimization)
readonly declare -A DEFAULT_MAPS=(
    [mp_assault]="mp_pak0" [mp_base]="mp_pak0" [mp_beach]="mp_pak0"
    [mp_castle]="mp_pak0" [mp_depot]="mp_pak0" [mp_destruction]="mp_pak0"
    [mp_sub]="mp_pak0" [mp_village]="mp_pak0" [mp_trenchtoast]="mp_pakmaps0"
    [mp_ice]="mp_pakmaps1" [mp_keep]="mp_pakmaps2" [mp_chateau]="mp_pakmaps3"
    [mp_tram]="mp_pakmaps4" [mp_dam]="mp_pakmaps5" [mp_rocket]="mp_pakmaps6"
)

# Maps to skip global mutations (readonly for optimization)
readonly declare -A SKIP_GLOBAL_MUTATIONS=(
    [mp_beach]=1 [mp_castle]=1 [mp_depot]=1 [mp_destruction]=1
    [mp_sub]=1 [mp_village]=1 [mp_trenchtoast]=1 [mp_keep]=1
    [mp_chateau]=1 [mp_tram]=1 [mp_dam]=1 [mp_rocket]=1
    [bd_bunker_b2]=1 [bp_badplace]=1 [braundorf_b7]=1 [castle2_b3]=1
    [frostafari_revamped_b3]=1 [ge_tundra_b1]=1 [goldrush_b2]=1
    [koth_base_a2]=1 [mp_basement]=1 [mp_ctfmultidemo]=1 [mp_password2_v1]=1
    [mp_science]=1 [mp_sub2_b1]=1 [oasis_b1]=1 [rocket2_b4]=1
    [sub2_b8]=1 [te_adlernest_b1]=1 [te_bremen_b1]=1 [te_chateau]=1
    [te_cipher_b5]=1 [te_delivery_b1]=1 [te_escape2]=1 [te_kungfugrip]=1
    [te_nordic_b2]=1 [te_operation_b4]=1 [te_radar_b1]=1 [timertest6]=1
    [tram2]=1 [ufo_homiefix]=1
)

# Check if a map needs any mutations
needs_mutations() {
    local map=$1
    [[ -f "${SETTINGS_BASE}/map-mutations/${map}.sh" ]] && return 0
    [[ ! ${SKIP_GLOBAL_MUTATIONS[$map]:-0} -eq 1 ]] && 
    [[ -f "${SETTINGS_BASE}/map-mutations/global.sh" ]] && return 0
    return 1
}

# Apply mutations to a map
apply_mutations() {
    local map=$1
    local map_path=$2
    local temp_path="${map_path}.tmp"
    local mutations_applied=0

    if [[ ! ${SKIP_GLOBAL_MUTATIONS[$map]:-0} -eq 1 ]] && 
       [[ -f "${SETTINGS_BASE}/map-mutations/global.sh" ]]; then
        if bash "${SETTINGS_BASE}/map-mutations/global.sh" "${map_path}" "${temp_path}" &&
           [[ -f "${temp_path}" ]]; then
            mutations_applied=1
            mv "${temp_path}" "${map_path}"
        fi
    fi

    if [[ -f "${SETTINGS_BASE}/map-mutations/${map}.sh" ]]; then
        bash "${SETTINGS_BASE}/map-mutations/${map}.sh" "${map_path}"
        mutations_applied=1
    fi

    if ((mutations_applied)); then
        mkdir -p "${GAME_BASE}/rtcwpro/maps"
        mv "${map_path}" "${GAME_BASE}/rtcwpro/maps/${map}.bsp"
        return 0
    fi
    return 1
}

# Process a single map
process_map() {
    local map=$1
    local pk3_path=$2
    local temp_dir="${GAME_BASE}/tmp"

    needs_mutations "${map}" || return 0

    mkdir -p "${temp_dir}/maps"
    if unzip -j "${pk3_path}" "maps/${map}.bsp" -d "${temp_dir}/maps/"; then
        apply_mutations "${map}" "${temp_dir}/maps/${map}.bsp"
    fi
    rm -rf "${temp_dir}"
}


# Process custom maps
process_custom_maps() {
    local IFS=':'
    read -ra maps_array <<< "${MAPS:-}"
    
    for map in "${maps_array[@]}"; do
        [[ -z "$map" || -n "${DEFAULT_MAPS[$map]:-}" ]] && continue
        
        if [[ ! -f "${GAME_BASE}/main/${map}.pk3" ]]; then
            if [[ -f "/maps/${map}.pk3" ]]; then
                cp "/maps/${map}.pk3" "${GAME_BASE}/main/${map}.pk3"
            else
                wget -q -O "${GAME_BASE}/main/${map}.pk3" "${CONFIG[REDIRECTURL]}/${map}.pk3" || continue
            fi
        fi
        process_map "${map}" "${GAME_BASE}/main/${map}.pk3"
    done
}


# Update configuration from git
update_config() {
    [[ "${CONFIG[AUTO_UPDATE]}" != "true" ]] && return 0
    
    local auth_url="${CONFIG[SETTINGSURL]}"
    [[ -n "${CONFIG[SETTINGSPAT]}" ]] && 
        auth_url="https://${CONFIG[SETTINGSPAT]}@${CONFIG[SETTINGSURL]#https://}"
    
    if git clone --depth 1 --single-branch --branch "${CONFIG[SETTINGSBRANCH]}" \
        "${auth_url}" "${SETTINGS_BASE}.new" 2>/dev/null; then
        rm -rf "${SETTINGS_BASE}"
        mv "${SETTINGS_BASE}.new" "${SETTINGS_BASE}"
    fi
}


# Update mapscripts and configs
update_game_files() {
    # Update mapscripts and configs
    rm -f "${GAME_BASE}"/rtcwpro/maps/*.{script,spawns}
    cp "${SETTINGS_BASE}"/mapscripts/*.{script,spawns} "${GAME_BASE}/rtcwpro/maps/" 2>/dev/null || true
    
    rm -rf "${GAME_BASE}/rtcwpro/configs/"
    mkdir -p "${GAME_BASE}/rtcwpro/configs/"
    cp "${SETTINGS_BASE}"/configs/*.config "${GAME_BASE}/rtcwpro/configs/"
    
    local server_cfg="${GAME_BASE}/main/server.cfg"
    cp "${SETTINGS_BASE}/server.cfg" "${server_cfg}"
    
    # Process both CONFIG array and environment variables
    while IFS='=' read -r key value; do
        if [[ $key == CONF_* ]]; then
            sed -i "s|%${key}%|${value}|g" "$server_cfg"
        fi
    done < <(env | grep '^CONF_')
    
    # Process CONFIG array values
    for key in "${!CONFIG[@]}"; do
        sed -i "s|%CONF_${key}%|${CONFIG[$key]}|g" "$server_cfg"
    done
    
    # Handle g_needpass
    if [[ -n "${CONFIG[PASSWORD]}" ]]; then
        sed -i 's/%CONF_NEEDPASS%/set g_needpass "1"/g' "$server_cfg"
    else
        sed -i 's/%CONF_NEEDPASS%//g' "$server_cfg"
    fi
    
    # Clean up remaining unreplaced variables and append extra config
    sed -i 's/%CONF_[A-Z_]*%//g' "$server_cfg"
    [[ -f "${GAME_BASE}/extra.cfg" ]] && cat "${GAME_BASE}/extra.cfg" >> "$server_cfg"
}

# Improved CLI args parsing that preserves quotes
parse_cli_args() {
    [[ -z "${ADDITIONAL_CLI_ARGS:-}" ]] && return
    eval "printf '%s\n' $ADDITIONAL_CLI_ARGS"
}

# Main execution
main() {
    update_config
    process_custom_maps

    for map in "${!DEFAULT_MAPS[@]}"; do
        process_map "${map}" "${GAME_BASE}/main/${DEFAULT_MAPS[$map]}.pk3"
    done

    update_game_files

    # Handle XMAS content
    if [[ "${CONFIG[XMAS]}" == "true" ]]; then
        wget -q -O "${GAME_BASE}/rtcwpro/mp_gathermas.pk3" "${CONFIG[XMAS_FILE]}"
        cp "${SETTINGS_BASE}"/xmas/*.{script,spawns} "${GAME_BASE}/rtcwpro/maps/" 2>/dev/null || true
    fi

    # Set up environment
    [[ "${NOQUERY:-}" == "true" ]] && export LD_PRELOAD="${GAME_BASE}/libnoquery.so"

    # Launch server with preserved arguments
    read -ra additional_args < <(parse_cli_args)
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
        +set sv_checkversion "${CONFIG[CHECKVERSION]}" \
        +exec "server.cfg" \
        +map "${CONFIG[STARTMAP]}" \
        "${additional_args[@]}" \
        "$@"
}

main "$@"