# WQFiles integrated runtime

Base: `9e388f9d30bacc97e53a522b1897607021e43344`.
Branch: `experiment/wqfiles-full-integration`.
Upstream: `kolbicz/WQFiles`, commit
`bb81069401875a470a032830b8e6bc934fbd9146` (0.9.8).

All upstream source, transitive headers, tests, resources, license and release
metadata are included under `Vendor/WQFiles`. `UPSTREAM.json` records the
original inventory and hashes with LF normalization. The target compiles all
upstream implementations, including `main.m` through `WQEmbedded.m`.

## Entry points and host adaptations

- Open **3105 Settings → WQFiles → WQFiles · Files, Apps, Cleaner & Backups**
  on iOS 26 or newer. This opens the original UIKit application screens,
  including startup health, Files, Apps, Cleaner, backups/restores, editors,
  archive/sharing, logs, scan consent/progress/cancellation and recovery.
- SwiftUI remains the application entry point. The original `main` is compiled
  as `WQStandaloneMain`; the embedded factory registers the same providers,
  scan callbacks and cleanup operations without launching another application.
- Embedded design changes rebuild the hosted child controller through a
  notification. The original scene delegate remains compiled.
- WQFiles localization lives in a separate resource bundle so its keys do not
  collide with 3105. The embedded language picker uses that bundle's languages.
- 3105 initializes WQFiles providers at startup. On iOS 26+, container
  enumeration uses the dynamic WQAccess enumerator, metadata reads use
  `wq_read`, identity resolution uses the original label/LaunchServices chain,
  and effective access first attempts the original `wq_grant` implementation.
  The original lower-iOS discovery route remains available.
- Access no longer requires `fileExists` before invoking providers. MCM
  activation failure is propagated. Swift access bodies retain their session
  for the duration of the operation.
- The experimental build disables removal/stripping of unused functions, and
  verifies linked access, recovery, health, enumeration, write and purge symbols.

The host bundle ID and experimental App Group remain those configured by 3105.
The signer must grant an actually usable App Group. The reference's App Group
and signing identity are not substituted into the host.

## Verification and its limits

`build-wqfiles-full-integration.yml` runs three independent jobs:

1. Build the actual 3105 device target, package its unsigned experimental IPA,
   verify runtime symbols and bundled localization, and publish its build log.
2. Run the original complete macOS regression suite, including access mutation,
   recovery, scans, Apps copy/restore, archive, SQLite, media, localization,
   LaunchServices and strict arm64 iOS syntax/link checks.
3. Launch an iOS Simulator app linked to the complete embedded runtime. It
   loads the UIKit host and performs real create/write/read, stale-save
   rejection, tree measurement and copy operations on local files. It writes a
   machine-readable JSON result. No access implementation is mocked in this
   smoke test.

The simulator cannot validate the device's private daemon authorization or
sandbox escape. A successful build or simulator test does not establish
functional equivalence on an iPhone. Device validation on the user's iPhone 13
Pro Max, iOS 27.2.1, remains a separate required step after authorized signing
and installation. Until that run is observed, device parity is **not claimed**.

## Device validation

Install the experimental IPA with signing that preserves the host configuration
and supplies a usable App Group. Open the integrated WQFiles screen and retain
the startup health result and Log. Verify container discovery, effective access,
LaunchServices labels, an app bundle where supported, and scan cancel/refresh.
Use disposable test data for create/read/write/move/delete, backup/restore and
cache cleanup. Compare saved/restored bytes and actual measured/deleted files.
Exercise Reset Access Cache and restart recovery only on the test installation.
Record failed checks as failures; empty lists or successful token creation alone
do not demonstrate access. Keep production app data out of mutation tests.

The historical omission/audit documents describe the base revision. This file
describes the implemented branch; it does not replace runtime evidence.
