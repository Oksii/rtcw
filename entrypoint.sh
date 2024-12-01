#!/bin/bash
set -x

# Base directories
GAME_BASE="/home/game"
SETTINGS_BASE="${GAME_BASE}/settings"

# Combine default maps and skip mutations into a single declaration pass
declare -A CONFIG DEFAULT_MAPS SKIP_GLOBAL_MUTATIONS

# Config defaults
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
    [SETTINGSURL]="${SETTINGSURL:-https://github.com/Oksii/rtcw-config-priv.git}"
    [MAP_PORT]="${MAP_PORT:-27960}"
    [STARTMAP]="${STARTMAP:-mp_ice}"
    [STATS_SUBMIT]="${STATS_SUBMIT:-0}"
    [STATS_URL]="${STATS_URL:-https://rtcwproapi.donkanator.com/submit}"
    [XMAS_FILE]="${XMAS_FILE:-http://rtcw.life/files/mapdb/mp_gathermas.pk3}"
    [XMAS]="${XMAS:-false}"
)

# Maps configuration using a here-doc for better readability
while IFS= read -r line; do
    [[ -n "$line" ]] && eval "DEFAULT_MAPS+=([$line])"
done << 'EOF'
    [mp_assault]=mp_pak0 [mp_base]=mp_pak0 [mp_beach]=mp_pak0
    [mp_castle]=mp_pak0 [mp_depot]=mp_pak0 [mp_destruction]=mp_pak0
    [mp_sub]=mp_pak0 [mp_village]=mp_pak0 [mp_trenchtoast]=mp_pakmaps0
    [mp_ice]=mp_pakmaps1 [mp_keep]=mp_pakmaps2 [mp_chateau]=mp_pakmaps3
    [mp_tram]=mp_pakmaps4 [mp_dam]=mp_pakmaps5 [mp_rocket]=mp_pakmaps6
EOF

# Skip mutations configuration using a here-doc
while IFS= read -r map; do
    [[ -n "$map" ]] && SKIP_GLOBAL_MUTATIONS["$map"]=1
done << 'EOF'
mp_beach mp_castle mp_depot mp_destruction mp_sub mp_village
mp_trenchtoast mp_keep mp_chateau mp_tram mp_dam mp_rocket
bd_bunker_b2 bp_badplace braundorf_b7 castle2_b3 frostafari_revamped_b3
ge_tundra_b1 goldrush_b2 koth_base_a2 mp_basement mp_ctfmultidemo
mp_password2_v1 mp_science mp_sub2_b1 oasis_b1 rocket2_b4 sub2_b8
te_adlernest_b1 te_bremen_b1 te_chateau te_cipher_b5 te_delivery_b1
te_escape2 te_kungfugrip te_nordic_b2 te_operation_b4 te_radar_b1
timertest6 tram2 ufo_homiefix mp_ctfmultidemo_squid mp_sub_squid
EOF

# Check if a map needs any mutations
needs_mutations() {
    local map=$1
    [[ -f "${SETTINGS_BASE}/map-mutations/${map}.sh" ]] && return 0
    [[ ${SKIP_GLOBAL_MUTATIONS[$map]:-0} -ne 1 ]] && 
    [[ -f "${SETTINGS_BASE}/map-mutations/global.sh" ]] && return 0
    return 1
}

# Apply mutations to a map
apply_mutations() {
    local map=$1 map_path=$2
    local temp_path="${map_path}.tmp"
    local mutations_applied=0

    if [[ ${SKIP_GLOBAL_MUTATIONS[$map]:-0} -ne 1 ]] && 
       [[ -f "${SETTINGS_BASE}/map-mutations/global.sh" ]] &&
       bash "${SETTINGS_BASE}/map-mutations/global.sh" "${map_path}" "${temp_path}" &&
       [[ -f "${temp_path}" ]]; then
        mutations_applied=1
        mv "${temp_path}" "${map_path}"
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

process_map() {
    local map=$1 pk3_path=$2
    local temp_dir="${GAME_BASE}/tmp"

    needs_mutations "${map}" || return 0

    mkdir -p "${temp_dir}/maps"
    if unzip -j "${pk3_path}" "maps/${map}.bsp" -d "${temp_dir}/maps/"; then
        apply_mutations "${map}" "${temp_dir}/maps/${map}.bsp"
    fi
    rm -rf "${temp_dir}"
}

process_custom_maps() {
    local IFS=':' map
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
    rm -f "${GAME_BASE}"/rtcwpro/maps/*.{script,spawns}
    cp "${SETTINGS_BASE}"/mapscripts/*.{script,spawns} "${GAME_BASE}/rtcwpro/maps/" 2>/dev/null || true
    
    rm -rf "${GAME_BASE}/rtcwpro/configs/"
    mkdir -p "${GAME_BASE}/rtcwpro/configs/"
    cp "${SETTINGS_BASE}"/configs/*.config "${GAME_BASE}/rtcwpro/configs/"
    
    local server_cfg="${GAME_BASE}/main/server.cfg"
    cp "${SETTINGS_BASE}/server.cfg" "${server_cfg}"
    
    # Process environment variables
    local key value
    while IFS='=' read -r key value; do
        [[ $key == CONF_* ]] && sed -i "s|%${key}%|${value}|g" "$server_cfg"
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
    
    # Cleanup and append .extra cfg 
    sed -i 's/%CONF_[A-Z_]*%//g' "$server_cfg"
    [[ -f "${GAME_BASE}/extra.cfg" ]] && cat "${GAME_BASE}/extra.cfg" >> "$server_cfg"
}

parse_cli_args() {
    [[ -z "${ADDITIONAL_CLI_ARGS:-}" ]] && return
    eval "printf '%s\n' $ADDITIONAL_CLI_ARGS"
}

main() {
    update_config
    process_custom_maps

    local map
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
    local -a additional_args
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