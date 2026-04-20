# Third-Party Notices

This repository contains or depends on third-party work.

## DelphiFFmpeg.com Headers

The files under `Headers/` are based on the Delphi/Pascal FFmpeg header translations from DelphiFFmpeg.com and were updated in this repository to match FFmpeg 8.1.

These files include their own per-file notices. The current header text in the repository states that redistribution and use in source and binary forms, with or without modification, are permitted if the copyright notice, conditions, and disclaimer are retained.

Source:

- http://www.delphiffmpeg.com

Examples in this repository:

- `Headers/libavcodec.pas`
- `Headers/libswresample.pas`

## FFmpeg

The Pascal headers map to the FFmpeg libraries. FFmpeg's own license is generally `LGPL-2.1-or-later`, but FFmpeg can become `GPL` if built with optional GPL components enabled.

That means the license obligations for the runtime DLLs you ship depend on the exact FFmpeg binaries you distribute, not only on this repository's source code.

Reference:

- https://www.ffmpeg.org/legal.html

## MfPack

The WASAPI backend is built against MfPack as an external dependency. MfPack is not bundled in this repository. In a normal RAD Studio setup, add `MfPack\src` to the project search path. If you use `build.sh`, point `MFPACK_DIR` to your local MfPack clone.

MfPack repository and license:

- https://github.com/FactoryXCode/MfPack
- MPL-2.0

## Practical Guidance

- Keep the notices in `Headers/` intact.
- Mention DelphiFFmpeg.com and MfPack in public documentation.
- Verify the actual FFmpeg DLL license status before distributing binaries.
- Choose a top-level repository license only for the code you authored here, not as a replacement for third-party licenses already attached to included files.
