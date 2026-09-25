# LineageOS 23.2 for Redmi 9 (lancelot)

Build script and manifest for **LineageOS 23.2 (Android 16)** on the Xiaomi Redmi 9
(`lancelot`, MediaTek Helio G80 / MT6768). This is a full device build, not a GSI.

Device, kernel and vendor trees come from [mt6768-dev](https://github.com/mt6768-dev);
MediaTek / Xiaomi glue from [LineageOS](https://github.com/LineageOS).

## Requirements

- Linux x86_64 (tested on Ubuntu 26.04)
- ~250 GB free disk (≈126 GB source + ≈100 GB build output)
- 32 GB RAM **plus** 32 GB swap recommended (less will likely get OOM-killed)
- Tools: `repo git git-lfs python3 ccache zip unzip bc bison flex rsync xxd lz4 zstd make gcc openssl m4`

## Build

```bash
git clone https://github.com/<you>/lancelot-build
cd lancelot-build
./build.sh
```

The first run syncs everything (1–2 h) and builds (4–6 h on 12 cores). Output lands in
`releases/`: the flashable zip, `recovery.img` and `SHA256SUMS`.

| Option | Meaning |
| --- | --- |
| `-d DIR` | source directory (default `./lineage`) |
| `-j N` | parallel jobs (default: auto from CPU/RAM) |
| `-v user\|userdebug\|eng` | build variant (default `userdebug`) |
| `-s` / `-b` | sync only / build only |
| `-c` | `m installclean` before building |

Stopping mid-build (Ctrl+C or a normal shutdown) is safe; run `./build.sh -b` to resume.
Lines like `FAILED: … action cancelled when ninja exited` after an interrupt are not real errors.

## Flashing

> ⚠️ The zip also flashes **Android 12 firmware**: preloader, lk, tee, scp, sspm, spmfw,
> md1img (modem) and logo. Back up your NV partitions (`nvram`, `nvdata`, `nvcfg`,
> `persist`, `proinfo`, `protect1/2`) and current firmware before the first flash.
> Keep the backups private: they contain your IMEI.

Requires an unlocked bootloader.

1. `fastboot flash recovery recovery.img`, then boot to recovery (Vol+ & Power).
2. **Factory reset → Format data** (required when coming from another ROM; wipes everything).
3. **Apply update → Apply from ADB**, then `adb sideload lineage-23.2-*-lancelot.zip`.
4. Reboot.

## Credits

LineageOS, mt6768-dev and everyone who maintains the lancelot / MT6768 trees.
