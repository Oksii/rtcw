# ORIGINAL: [msh100/rtcw](https://github.com/msh100/rtcw)

Minor additions/adjustments to be more consistent with our orchestration needs. 
 * Included activity check for auto restarts via cron and watchtower
 * Host files on S3 rather than rely on steam CDN
 * removed support for PB and vanilla server
 * Allow for .spawns files in mapscript folder
 * Version control via discord bot
 * Allow providing additional launch time args
 * XMAS pack toggling
 * Prepare a list of maps that need processing first by blacklisting skipped maps found in global.sh rather than unzipping every map and throwing it against it. Saves an incredible amount of time booting. 
 * Allow dynamic loading of any CONF_ env var and check against server.cfg 

# RTCW Match Server

This Docker image will download the required RTCW maps as specified in the
`MAPS` environment variable (from `REDIRECTURL`) and then spawn an RtcwPro
1.2.1 server with configuration as defined in the environment variables or
their defaults (refer below).

If you want to avoid downloading maps over HTTP(s), you can mount a volume of
maps to `/maps/`.
The container will first try to copy from pk3s from this directory before
attempting an HTTP(s) download.

All logs are written to STDOUT so can be viewed from `docker logs` or run
without the `-d` Docker run switch.

A server with this image will run v1.41b.

A container using this image will always try and download the latest changes
from whatever `SETTINGSURL` is set to.
By default this is the [rtcw-config](https://github.com/Oksii/rtcw-config)
repository, originally based on
[msh100/rtcw-config](https://github.com/msh100/rtcw-config).


## Example

```
docker run -d \
  -p "10.0.0.1:27960:27960/udp" \
  -e "MAPS=adlernest_b3:te_escape2:te_frostbite" \
  -e "PASSWORD=war" \
  -e "REFEREEPASSWORD=pass123" \
  msh100/rtcw
```

## Configuration Options


Environment Variable | Description                    | Defaults
-------------------- | ------------------------------ | ------------------------
MAPS                 | List of maps seperated by ':'. | Default 6 maps
STARTMAP             | Map server starts on.          | "mp_ice".
REDIRECTURL          | URL of HTTP downloads          | http://rtcw.life/files/mapdb
MAP_PORT             | Container port (internal)      | 27960
NOQUERY              | Disable status queries         | Disabled, set to `true` to enable.
MAXCLIENTS           | Maximum number of players      | 32
AUTO_UPDATE          | Update configurations on restart? | Enabled, set to `false` to enable.
SETTINGSURL          | The git URL (must be HTTP public) for the RTCW settings repository. | https://github.com/Oksii/rtcw-config.git
SETTINGSBRANCH       | The git branch for the RTCW settings repository. | `master`
SETTINGSPAT          | The git PAT for private repositories. | None. 
ADDITIONAL_ARG_CLI   | Set additional launch time args to be executed. | None, ie: +set sv_test 1
XMAS                 | Toggles loading `mp_gathermas.pk3` on and off | Disabled, set to `true` to enable. 
XMAS_FILE            | Sets URL to retrieve `mp_gathermas.pk3` from | http://rtcw.life/files/mapdb/mp_gathermas.pk3


### Configuration parameters for the default `SETTINGSURL`

Environment Variable | Description                    | Defaults
-------------------- | ------------------------------ | ------------------------
PASSWORD             | Server password.               | No password.
RCONPASSWORD         | RCON password.                 | No password (disabled).
REFPASSWORD          | Referee password.              | No password (disabled).
SCPASSWORD           | Shoutcaster password.          | No password (disabled).
HOSTNAME             | Server hostname.               | RTCW
CONF_MOTD            | MOTD line on connect           | Empty.
TIMEOUTLIMIT         | Maximum number of pauses per map side | 1
SERVERCONF           | The value for RtcwPro's `g_customconfig` | `defaultcomp`.
STATS_SUBMIT         | Push stats to an external API? | Disabled, set to `1` to enable.
STATS_URL            | API address to push stats data | `https://rtcwproapi.donkanator.com/submit`


Extra configuration can be prepended to the `server.cfg` by mounting a
configuration at `/home/game/extra.cfg`.
This is generally not recommended, try to use the variables above where
possible or create a custom `SETTINGSURL`.


### Build history
```
Version change: 1.3.1 || 133239597 || hash: 133239597
Version change: 1.4   || 182085729 || hash: 182085729
Version change: 1.4.0.3 || 190781702 || hash: 190781702
Version change: 1.4.0.3 || 190781702 || hash: 190781702
Version change: 1.4.0.3 || 190781702 || hash: 190781702
```