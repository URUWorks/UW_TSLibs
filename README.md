# UW_TSLibs

OpenSSL and Hunspell built for [Tero Subtitler](https://github.com/URUWorks/TeroSubtitler),
for Windows (x64 and ARM64) and macOS (universal).

| File | Contents |
|---|---|
| `tslibs_win64.zip` | `libssl-3-x64.dll`, `libcrypto-3-x64.dll`, `libhunspellx64.dll` |
| `tslibs_winarm64.zip` | `libssl-3-arm64.dll`, `libcrypto-3-arm64.dll`, `libhunspellx64.dll` |
| `tslibs_macos.zip` | `libssl.3.dylib`, `libcrypto.3.dylib`, `libhunspellx64.dylib` (arm64 from macOS 11.0, x86_64 from 10.15) |

- The file names are the ones that Free Pascal (`opensslsockets`, FPC 3.2.4 and later) and
  Tero Subtitler look for. On ARM64, Tero Subtitler also loads Hunspell as `libhunspellx64.dll`
  (64 bits).
- Windows: built with MSVC and the static C runtime, so they don't need the Visual C++
  redistributable. The x64 build is checked to import nothing newer than Windows 7.
- macOS: install names `@rpath/<lib>`, `libssl` loads `libcrypto` with `@loader_path`. Put them in
  `Contents/Frameworks` of the app. Ad-hoc signed; sign them again with the app.

## Updates

On day 3 of each month the workflow looks for a new OpenSSL 3.5.x (the LTS branch). If there is
one, it builds everything and tests it on Windows x64, Windows ARM64, macOS Apple Silicon, macOS
under Rosetta and an Intel Mac: the libraries load, a SHA-256, a real HTTPS connection and a spell
check (`tests/libtest.c`). Only if all of it passes is the release `openssl-<version>` published.
A failure doesn't change anything (GitHub emails it).

By hand: Actions > Build > Run workflow (with "publish"; "force" publishes again the same version;
a version can be given).

## Backup: OpenSSL 1.1.1w

The release `frozen` has OpenSSL 1.1.1w (`libssl-1_1-x64.dll`, `libssl.1.1.dylib`) in case of a
problem with OpenSSL 3. Free Pascal loads 3 first and 1.1 only if 3 is not there. OpenSSL 1.1 has
had no security updates since September 2023; use it only as a temporary replacement.

## License

The build scripts are MPL 2.0, as Tero Subtitler. OpenSSL is Apache 2.0, Hunspell MPL 1.1 /
GPL 2.0 / LGPL 2.1; their licenses are included in each zip.
