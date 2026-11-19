#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

required=(
  "ThreeOneOSFive/exploit/worse_query.m"
  "ThreeOneOSFive/exploit/worse_query_adapter.m"
  "ThreeOneOSFive/exploit/bad_query.c"
  "ThreeOneOSFive/exploit/mcm_bridge.m"
  "ThreeOneOSFive/helpers/ContainerAccessCoordinator.swift"
  "ThreeOneOSFive/helpers/ContainerStore.swift"
  "ThreeOneOSFive/helpers/WQFilesIdentityResolver.swift"
  "ThreeOneOSFive/exploit/WQLaunchServicesPhase1.m"
  "ThreeOneOSFive/helpers/WQIdentityHealth.swift"
  "WQFILES_SANDBOX_OMISSIONS.md"
  "WQFILES_ACCESS_DEPENDENCIES.md"
  "WQFILES_3105_FUNCTION_PARITY.md"
  "WQFILES_ACCESS_FAILURE_ANALYSIS.md"
  "WQFILES_NEXT_INTEGRATION_PLAN.md"
)

for file in "${required[@]}"; do
  test -f "$file" || { echo "missing audit input: $file" >&2; exit 1; }
done

grep -q 'group.pigtjing.top' ThreeOneOSFive/3105-Experimental.entitlements
grep -q 'com.apple.mobile.MobileHouseArrest' ThreeOneOSFive.xcodeproj/project.pbxproj
grep -q 'MHA-C2' ThreeOneOSFive/helpers/ContainerAccessCoordinator.swift
grep -q 'bad_query' ThreeOneOSFive/helpers/ContainerAccessCoordinator.swift
grep -q 'worse_query' ThreeOneOSFive/helpers/ContainerAccessCoordinator.swift
grep -q 'wq_phase1_identity_report' ThreeOneOSFive/exploit/WQLaunchServicesPhase1.m
grep -q 'WQIdentityHealth.run' ThreeOneOSFive/helpers/WQBundleIdentityCoordinator.swift

# The audit must not silently turn the reference's privileged module into a
# copied source file. Its absence is recorded in the parity/omissions reports.
test ! -e ThreeOneOSFive/exploit/WQAccess.m
test ! -e ThreeOneOSFive/exploit/WQAccess.h
! grep -R '#import[[:space:]]*["<]WQAccess' ThreeOneOSFive

echo 'WQFiles sandbox audit static checks: PASS'
echo 'Runtime authorization and device access: NOT CLAIMED by this script'
