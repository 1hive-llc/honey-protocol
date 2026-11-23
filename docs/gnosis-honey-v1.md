# Honey v1 on Gnosis Chain

This is a public inventory of legacy deployment addresses, not an execution
guide. Gnosis Chain (formerly xDai) is chain ID **100**. Contract presence was
checked with read-only RPC at block **49,432,749**
([block](https://gnosisscan.io/block/49432749), hash
`0x58a8ae288199f1cd9dd223a4eff4885e38d0655f475d895c1961001125c11a15`). Nonempty code establishes that
an address is a contract at that block, not that a feature is operational or
that its current configuration or permissions are safe. The public 1Hive docs
identify [Gardens v1 as the Common Pool governance
interface](https://1hive.org/Curating-community-contributions).

For how these components fit together, see the [local protocol background][background].

## Core deployment

| Component | Gnosis address | Address provenance |
| --- | --- | --- |
| Honey token (HNY) | `0x71850b7e9ee3f13ab46d67167341e4bdc905eef9` | [Developer inventory and historical FAQ][sources] |
| Common Pool (Aragon Agent/Vault) | `0x4ba7362f9189572cbb1216819a45aba0d0b2d1cb` | [Developer inventory: Agent/Vault][sources], [public Gardens v1 address list][addresses] |
| DAO Kernel | `0x8ccbeab14b5ac4a431fffc39f4bec4089020a155` | [Developer inventory: DAO/Kernel][sources] |
| Aragon ACL | `0xbc4fb635636b81e60a4e356c4dceb53cac507d03` | [Developer inventory: ACL][sources] |
| Conviction Voting | `0x0b21081c6f8b1990f53fc76279cc41ba22d7afe2` | [Developer inventory: ConvictionVoting][sources] |
| Decision Voting (Disputable Voting) | `0xfbd0b2726070a9d6aff6d7216c9e9340eae68b2a` | [Developer inventory: DisputableVoting][sources] |
| Agreement | `0x59a15718992a42082ab2306bc6cbd662958a178c` | [Developer inventory: Agreement][sources] |
| Hooked Token Manager | `0xed062e26c8f41a9088d060156edc7fc6c17d5825` | [Developer inventory: HookedTokenManager][sources] |
| Celeste court | `0x44e4fcfed14e1285c9e0f6eae77d5fdd0f196f85` | [Developer inventory: Celeste and modules (xDai)][sources] |

Celeste is the documented legacy court. This inventory does not establish which
Agreement setting governs a particular proposal or dispute, whether there are
unresolved cases, or whether any service needed to use these contracts is
available.

## Deployment evidence and source verification

The proxy implementation addresses below were read on Gnosis at the manifest
block. Links under “Creation evidence” refer to the listed deployment address
(the proxy itself for proxy rows), not to creation of its implementation.
A proxy source match is distinct from a source match for its implementation.
The last column links Sourcify records for implementations read at the pinned
block. Sourcify runtime matches are not described as exact unless noted.

| Component | Creation evidence | Implementation at the manifest block |
| --- | --- | --- |
| HNY | [Creation transaction](https://gnosisscan.io/tx/0x8b6fe398d91c528510379d1391ae315362a24f93e12a65dcbd9ef4ba0077b179), [source match](https://sourcify.dev/server/v2/contract/100/0x71850b7e9ee3f13ab46d67167341e4bdc905eef9?fields=deployment%2Ccompilation) | Not recorded |
| Common Pool | [Shared creation transaction][shared], [proxy source match](https://sourcify.dev/server/v2/contract/100/0x4ba7362f9189572cbb1216819a45aba0d0b2d1cb?fields=deployment%2Ccompilation) | [`0xa6ad366bfd2f43615bbec56f50cf606036fc11fe`](https://sourcify.dev/server/v2/contract/100/0xa6ad366bfd2f43615bbec56f50cf606036fc11fe?fields=deployment%2Ccompilation) |
| DAO Kernel | [Shared creation transaction][shared] (internal CREATE); proxy source match not established | [`0x336ebb4def4da4fad6936874b8c952e800024653`](https://sourcify.dev/server/v2/contract/100/0x336ebb4def4da4fad6936874b8c952e800024653?fields=deployment%2Ccompilation) |
| Aragon ACL | [Shared creation transaction][shared], [proxy source match](https://sourcify.dev/server/v2/contract/100/0xbc4fb635636b81e60a4e356c4dceb53cac507d03?fields=deployment%2Ccompilation) | [`0x4499948d089330df05795b08aa23a964027b9cd8`](https://sourcify.dev/server/v2/contract/100/0x4499948d089330df05795b08aa23a964027b9cd8?fields=deployment%2Ccompilation) |
| Conviction Voting | [Creation transaction](https://gnosisscan.io/tx/0xdd5c0203a2ca07e8d5f8895889733844aba8888d50df36c09fb8c11a847ea40a), [proxy source match](https://sourcify.dev/server/v2/contract/100/0x0b21081c6f8b1990f53fc76279cc41ba22d7afe2?fields=deployment%2Ccompilation) | [`0x4e18915179a846f90b0342f16e0b274090733ac7`](https://sourcify.dev/server/v2/contract/100/0x4e18915179a846f90b0342f16e0b274090733ac7?fields=deployment%2Ccompilation) |
| Decision Voting | [Shared creation transaction][shared], [proxy source match](https://sourcify.dev/server/v2/contract/100/0xfbd0b2726070a9d6aff6d7216c9e9340eae68b2a?fields=deployment%2Ccompilation) | [`0x4fdc6f0684128f1234c4c053e7fe998324c1839a`](https://sourcify.dev/server/v2/contract/100/0x4fdc6f0684128f1234c4c053e7fe998324c1839a?fields=deployment%2Ccompilation) |
| Agreement | [Creation transaction](https://gnosisscan.io/tx/0x1b53c2411d413c23f77d631e3ca4676c5e77ac25149b8b1a9204c894f8fc11fd), [proxy source match](https://sourcify.dev/server/v2/contract/100/0x59a15718992a42082ab2306bc6cbd662958a178c?fields=deployment%2Ccompilation) | [`0xe2b44f206f4ce313c6d3b85496a7f85194ec10fb`](https://sourcify.dev/server/v2/contract/100/0xe2b44f206f4ce313c6d3b85496a7f85194ec10fb?fields=deployment%2Ccompilation) |
| Hooked Token Manager | [Shared creation transaction][shared], [proxy source match](https://sourcify.dev/server/v2/contract/100/0xed062e26c8f41a9088d060156edc7fc6c17d5825?fields=deployment%2Ccompilation) | [`0xbba6f5611202b2e1a24c8cfcbb4278754ebcbe99`](https://sourcify.dev/server/v2/contract/100/0xbba6f5611202b2e1a24c8cfcbb4278754ebcbe99?fields=deployment%2Ccompilation) |
| Celeste court | [Creation transaction](https://gnosisscan.io/tx/0xdad0be7662e50123a06881d04e51b7ffbd96c7fdd7fb4f9678be0e56228e7505), [source match](https://sourcify.dev/server/v2/contract/100/0x44e4fcfed14e1285c9e0f6eae77d5fdd0f196f85?fields=deployment%2Ccompilation) | Not recorded |

The shared creation transaction is recorded at block **14,861,344**. The HNY
and Celeste source records are for their listed addresses directly; no separate
implementation is recorded for either.

At the manifest block, Agreement’s `getCurrentSettingId()` returned `1`; its
`getSetting(1)` returned the listed Celeste address as arbitrator. This verifies
the configured pointer at that block only, not which setting governs any
particular dispute or whether the court is operational.

For source history, see the upstream [Gardens v1 tree](https://github.com/1Hive/gardens/tree/739042716f0f19f23e6baf193621d0590188b46d)
and [Celeste contracts tree](https://github.com/1Hive/celeste-contracts/tree/927d780dbf5cbf6a52074db19293fd3162135087).
These are repository snapshots, not assertions that those commits built the
listed deployments.

## Separate from the Honey v1 governance deployment

- **Fluid Proposals streaming pilot.** This is listed separately from the
  core governance contracts above. The Gnosis proxy
  [`0x856d17d5323794a7db0ba17f59d4b88fd402d321`](https://gnosisscan.io/address/0x856d17d5323794a7db0ba17f59d4b88fd402d321)
  first has code at block 31,113,810; the previous block returns empty code.
  The [creation transaction](https://gnosisscan.io/tx/0xc17ed965bd1f08f11acbd2b8d16eb723ce6ec1b7d371a93fd7db2904165ebdd2)
  was identified by its internal CREATE trace. A proxy source match is not
  established here. The [published source for its implementation](https://sourcify.dev/server/v2/contract/100/0xbf2f2337337508ed26855ef0482dd221c9752216?fields=deployment%2Ccompilation)
  reports an exact runtime match and is separate from the proxy address.
  Code presence does not establish current funding, authority, streaming
  status, or removal of any role.
- **Legacy streaming token wrapper.** The separate Gnosis proxy
  [`0x602a48a53a425521c9923708d277dc7430e3c749`](https://gnosisscan.io/address/0x602a48a53a425521c9923708d277dc7430e3c749)
  has a [creation transaction](https://gnosisscan.io/tx/0x3796254904bc710a55367a70ef37b6cf801e8bce8507381a9f6fabfda374b0f8)
  and a [published proxy source record](https://sourcify.dev/server/v2/contract/100/0x602a48a53a425521c9923708d277dc7430e3c749?fields=deployment%2Ccompilation).
  Its [implementation](https://sourcify.dev/server/v2/contract/100/0xb1c83cdece395e1cd8883e05648f9aa1e37b9a98?fields=deployment%2Ccompilation),
  `0xb1c83cdece395e1cd8883e05648f9aa1e37b9a98`, was read at the manifest block
  and has a Sourcify exact runtime match. The wrapper is not the HNY token or
  part of the Common Pool governance deployment.
- **Kleros migration candidate.** The source in [this repository](../README.md)
  is for review. No activated Gnosis migration or production address is
  asserted by this manifest. Do not treat it as the court listed above.

[addresses]: https://github.com/lkngtn/gardens-v1-deprecation/blob/1e219193a562b37563491dde42497230a8b31df4/src/addresses.ts#L7-L16
[shared]: https://gnosisscan.io/tx/0x9bf0055eca264a8de18612a3e1f0eccb89e59a8c511b97a4d4aefd60cc4fde63

[background]: gnosis-honey-v1-background.md
[sources]: gnosis-honey-v1-background.md#historical-sources
