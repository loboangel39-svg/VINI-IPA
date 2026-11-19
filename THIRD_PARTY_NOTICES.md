# Third-party notices and credits

3105 is developed and designed by [YangJiii](https://x.com/duongduong0908). It also incorporates ideas, formats, research, or implementation foundations from the following community work.

| Project/person | Contribution acknowledged by 3105 | Upstream |
| --- | --- | --- |
| 0xjohnnydev and FilzaSlop contributors | MHA-C2 app-data discovery and sandbox-escape foundation | [FilzaSlop](https://github.com/0xjohnnydev/FilzaSlop) |
| CrazyMind90 | FilzaSlop sandbox-escape foundation | [GitHub profile](https://github.com/CrazyMind90) |
| LeminLimez and contributors | Pocket Poster, Nugget, and the `.tendies` package format | [Pocket-Poster](https://github.com/leminlimez/Pocket-Poster) |
| forcequitOS | `bad_query` research | [GitHub profile](https://github.com/forcequitOS) |
| Taj C (forcequitOS) | Isolated `worse_query` provider implementation and GPLv3 notice | [worse_query](https://github.com/forcequitOS/worse_query) |
| opa334 and Dopamine contributors | Kernel-exploit research foundation | [Dopamine](https://github.com/opa334/Dopamine) |

Original portions of 3105 are distributed under GPL-3.0. Pocket-Poster also publishes a GPL-3.0 license in its upstream repository. FilzaSlop did not expose a repository license through GitHub when this notice was prepared. Review each upstream project and its current terms before redistributing derived code.

The 3105 license applies only to material for which the project owner has the right to grant that license. This file provides attribution; it does not replace upstream copyright or license notices and does not relicense third-party material.

## WQFiles LaunchServices Phase 1

`ThreeOneOSFive/exploit/WQLaunchServicesPhase1.m` and its header are adapted from
`kolbicz/WQFiles` (`WQLaunchServices.m` and `WQLaunchServices.h`), licensed under
GPL-3.0-or-later. The original copyright and license header is retained. This
adaptation is limited to the LaunchServices/CSStore2 parser and uses Foundation
file reads only; it does not include WQAccess, WQCache, or other WQFiles modules.

## WQFiles complete integration

All WQFiles modules and transitive source dependencies are included under
`Vendor/WQFiles`, from kolbicz/WQFiles commit
`bb81069401875a470a032830b8e6bc934fbd9146` (0.9.8).
Copyright notices are retained in each file; GPL-3.0-or-later.
The upstream license is included at `Vendor/WQFiles/LICENSE`.
The worse_query technique is attributed upstream to Taj C (forcequit).
`UPSTREAM.json` records original file hashes. Host adaptations are visible in git.
