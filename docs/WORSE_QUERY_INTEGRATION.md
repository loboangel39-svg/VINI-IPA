# worse_query integration report

## Baseline

- Repository: `YangJiiii/3105`
- Base commit: `a72617ed4c764a65d8aac1e91aca95231e72a2cb`
- Reference implementation: `forcequitOS/worse_query` (`d1540e20cd82b974d891e0551ced6d6aeb570ac2`)

## Added files

- `ThreeOneOSFive/exploit/worse_query.m`
- `ThreeOneOSFive/exploit/worse_query.h`
- `ThreeOneOSFive/exploit/worse_query_adapter.m`
- `ThreeOneOSFive/exploit/worse_query_adapter.h`
- `ThreeOneOSFive/helpers/ContainerAccessCoordinator.swift`

The upstream GPLv3 attribution is retained in the source header and
`THIRD_PARTY_NOTICES.md`.

## Modified files

- `ThreeOneOSFive.xcodeproj/project.pbxproj`: registers the isolated provider and coordinator.
- `ThreeOneOSFive/ThreeOneOSFive-Bridging-Header.h`: exposes only the adapter API.
- `ThreeOneOSFive/helpers/DevicePatchService.swift`: acquires shared sessions around the existing transaction calls.
- `ThreeOneOSFive/views/FileBrowserView.swift`: uses the shared coordinator at the existing root-access point.
- `THIRD_PARTY_NOTICES.md`: upstream credit.

## Identity and entitlements comparison

Unchanged from baseline: bundle identifier `com.apple.mobile.MobileHouseArrest`, app name
`3105`, deployment target `16.0`, and empty `CODE_SIGN_ENTITLEMENTS`. No App Group was
present in the baseline signature configuration and none was added. The adapter reads the
signed `com.apple.security.application-groups` entitlement at runtime and fails closed when
there is no authorized group.

## Shared flow

```text
Files / DevicePatchService
          |
          v
ContainerAccessCoordinator
   | MHA-C2 -> bad_query -> worse_query (only signed App Group)
   |
   +-- validates bundle/path/existence and verifies the container root
   +-- returns a session with provider and diagnostic
   +-- releases sandbox extensions when the session leaves scope
          |
       FileManager / PatchTransaction
```

`PatchTransaction.apply`, `restore`, `inspectRestore`, and
`resetToAppliedState` were not changed. No authorization handle is persisted.

## Validation status

- Static diff and whitespace validation: passed (`git diff --check`).
- Xcode/iOS build: not runnable on this Windows host (`xcodebuild`/Apple SDK unavailable).
- On-device Files, MHA-C2, bad_query, `.3105` Apply/Restore, entitlement comparison, and
  release tests: not executed because no authorized iOS test device/container is available.

## Limitations

The checked-out project has no authorized App Group. Consequently `worse_query` is present
and integrated but reports `no authorized App Group in the signed entitlements` rather than
changing signing configuration. No claim is made about iOS 27.2.1 compatibility.

## GitHub Actions runner correction

Run `43644265758` was cancelled before a runner was assigned: its job had `runner_id: 0`,
no steps, and zero billable milliseconds. The workflow requested `macos-14`, which is no
longer listed among GitHub's supported standard macOS labels. The only CI change was to use
the supported `macos-15` arm64 label; source code, signing settings, and project settings
were not changed.

The first `macos-15` build reached Xcode but failed because ARC rejected explicit
`xpc_release` calls in the imported Objective-C implementation. The minimal correction was
to use the same `OS_OBJECT_USE_OBJC` conditional-release pattern already present in
`mcm_bridge.m`.
