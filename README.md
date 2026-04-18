# Delphi FFmpeg Radio Player

Native Delphi/Pascal internet radio playback built directly on FFmpeg 8 headers and a Windows audio backend. The project centers on a reusable `TRadioPlayer` engine, a reusable console UI layer, and a concrete console player application.

## What Is Included

- `Source/`
  Delphi radio engine units:
  `TRadioPlayer`, stream client, decoder, resampler, PCM buffer, event bus, spectrum analyzer, and audio backends.
- `Headers/`
  FFmpeg 8 Delphi/Pascal header translations used by the player, based on the DelphiFFmpeg.com header set and updated in this repository for FFmpeg 8.0.
- `ConsoleRadioPlayer/`
  A real console radio player built on top of the reusable engine and reusable `TRadioConsoleUI`.
- `build.sh`
  Optional build helper for `Win32` and `Win64`.

## Current Feature Set

- HTTP/HTTPS radio playback through FFmpeg
- MP3 live stream playback verified
- `waveOut` and `WASAPI` output backends
- WASAPI device enumeration and explicit device selection
- WASAPI session or endpoint volume control
- reconnect handling with backoff
- metadata extraction and live updates
- configurable PCM buffer and prebuffer
- advanced runtime stats
- output-aligned VU metering
- output-aligned spectrum analysis
- event bus with dedicated-thread or main-thread dispatch
- reusable console UI component in `Source/Radio.ConsoleUI.pas`

## Project Structure

- `Source/Radio.Player.pas`
  Main player facade and orchestration.
- `Source/Radio.ConsoleUI.pas`
  Reusable TUI-style console UI class for `TRadioPlayer`.
- `Source/Radio.Output.WASAPI.pas`
  WASAPI backend using MfPack translations.
- `Source/Radio.Output.WaveOut.pas`
  Simpler fallback backend.
- `ConsoleRadioPlayer/ConsoleRadioPlayer.dpr`
  Standalone console radio player host.

## Requirements

- Delphi 12 / RAD Studio 12
- FFmpeg 8 runtime DLLs available to the final executable at runtime
- MfPack available locally for the WASAPI backend
  Add `MfPack\src` to the project search path in RAD Studio, or set `MFPACK_DIR` when using `build.sh`.

Optional:

- Embarcadero WinMD package path can still be present, but the audio backend does not depend on it

## Build

### RAD Studio

Open:

```text
ConsoleRadioPlayer\ConsoleRadioPlayer.dpr
```

Project search path should include:

```text
Source
Headers
C:\Path\To\MfPack\src
```

Then build the selected target platform in the normal way from RAD Studio.

### Optional `build.sh` helper

For users who want command-line builds, `build.sh` can compile the project through the Delphi command-line compilers. If MfPack is not in a sibling `..\MfPack` folder, set `MFPACK_DIR` first.

Win64:

```bash
./build.sh ConsoleRadioPlayer/ConsoleRadioPlayer.dpr Win64
```

Win32:

```bash
./build.sh ConsoleRadioPlayer/ConsoleRadioPlayer.dpr Win32
```

Build outputs go to:

- `Bin\win64\`
- `Bin\win32\`

## Run

Default stream:

```text
Bin\win64\ConsoleRadioPlayer.exe
```

Explicit backend, volume mode, buffer, and prebuffer:

```text
Bin\win64\ConsoleRadioPlayer.exe https://stream.radio38.de/radio38-live/mp3-192 wasapi session - 1200 400
```

List WASAPI devices:

```text
Bin\win64\ConsoleRadioPlayer.exe --list-devices
```

## Console Hotkeys

- `q` quit
- `m` mute
- `+` / `-` volume
- `r` restart
- `b` switch backend
- `d` next WASAPI device
- `v` toggle WASAPI volume mode
- `1`..`5` load preset
- `!`..`%` save preset

## Architecture Notes

The codebase is split so FFmpeg-facing ABI usage is isolated from player logic as much as practical:

- `Radio.FFmpeg.Api`
  packet/frame and common API helpers
- `Radio.FFmpeg.Resample`
  `swresample` and sample-layout helpers
- player-facing units
  stream, decode, resample, output, buffering, UI

This keeps future FFmpeg version migration work focused on the adapter layer instead of the whole application.

## Third-Party Sources

- `Headers/`
  Based on the DelphiFFmpeg.com Pascal header translations. These files carry their own header notices and redistribution terms in the source files.
- `MfPack`
  Used as the Windows Core Audio / Media Foundation translation layer for the WASAPI backend during build. This project is not bundled in this repository and should be available as a normal local dependency.
- `FFmpeg` runtime DLLs
  The player loads FFmpeg DLLs at runtime. Their license depends on how those binaries were built.

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Threading Notes

- `TRadioPlayer` exposes snapshot-style events and lock-protected state accessors.
- `EventDispatchMode = redmMainThread` is suitable for GUI or console apps that pump `CheckSynchronize`.
- `TRadioConsoleUI` polls player snapshots directly for rendering and keeps its own mutable UI state protected internally.

## Status

This repository is in a usable V1/V1.5 state for a native Delphi radio player:

- engine and console player are working
- telemetry and diagnostics are in place
- repository layout has been cleaned for normal RAD Studio use

## Remaining Nice-To-Haves

- playlist resolver support for `.pls` / `.m3u`
- richer automated stress tests
- optional GUI component wrappers
- further extraction of `TRadioConsoleUI` into a standalone generic console UI project

## License

No repository license file has been added yet. Pick one before publishing publicly on GitHub.

Important:

- the code in `Source/` and `ConsoleRadioPlayer/` can be licensed separately from the third-party dependencies
- the files in `Headers/` already carry their own notices from DelphiFFmpeg.com and references to FFmpeg's upstream licensing
- the FFmpeg runtime DLLs you distribute may be `LGPL` or `GPL` depending on how they were built
