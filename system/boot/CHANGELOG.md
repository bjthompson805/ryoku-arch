# Changelog: system/boot/

## Unreleased

### Added
- `limine/limine.conf`: Ryoku-branded Limine config (branding string, orange
  accent, Greek Noir palette, timeout, default UKI entry placeholder).
- `limine/default.conf`: UKI build settings (TARGET_OS_NAME, ESP_PATH,
  ENABLE_UKI, CUSTOM_UKI_NAME, snapshot entries, `quiet splash` cmdline).
- `plymouth/ryoku/`: vendored Ryoku Plymouth splash (manifest, script, assets).
- `mkinitcpio/ryoku.conf`: HOOKS drop-in with `plymouth` and `kms`; `encrypt`
  documented as LUKS-only.
