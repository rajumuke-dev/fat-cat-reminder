# Fat Cat Reminder

macOS menu-bar app: after a work interval it covers the screen with a transparent-background video of a fat cat that walks around, lies down, and reminds you to rest or drink water.

## Build
```
./build.sh        # builds and installs ~/Applications/FatCatReminder.app
```

## Cat clips (not included)
The app expects three transparent HEVC clips in `Resources/`: `cat-walk.mov` (loop), `cat-settle.mov` (plays once), `cat-sit.mov` (loop).
Make them from a video you have the rights to:
```
FULL_FRAME=1 tools/make-cat-video.sh <video> walk|sit [start_sec] [duration_sec]
```
Without clips the app still runs but shows no cat.

## Config (env vars)
`REST_WORK` (25 min), `REST_WATER` (40 min), `REST_BREAK` (5 min), `REST_WATER_BREAK` (30 s), `REST_IDLE` (3 min).
Flags: `--rest-now`, `--water-now`.
