# Honey v1 protocol background

This historical reference explains the components in the [Gnosis deployment
manifest](gnosis-honey-v1.md#core-deployment). Use the manifest for addresses
checked against chain state and contract source evidence. References below
are not deployment checks, operating instructions, or claims about today's
contract configuration or service availability.

## Honey, the Common Pool, and governance

HNY is the 1Hive community token. In Gardens v1, funding proposals request
an allocation from the DAO treasury (the Common Pool); signaling proposals
do not request HNY. Conviction Voting lets participants allocate support
across concurrently open proposals, without counting the same support twice.
Support strengthens over time rather than counting in full immediately.
A funding request that represents a larger share of the pool requires more
accumulated support.

The Aragon DAO Kernel provides the base for the DAO's apps; its ACL defines
permissions. The Agent/Vault is the treasury address identified as the
Common Pool for this deployment. Decision Voting is the separate app for
yes-or-no decisions such as changing a protocol parameter or approving an
upgrade. Agreement links the governance dispute process
to an arbitrator; the manifest records the specific Celeste pointer read on
Gnosis. The Hooked Token Manager is another app in the same DAO. These
roles do not imply that every app or dispute uses the same settings.

The older FAQ gives a different Common Pool address. This reference does
not use that entry as evidence of custody: the manifest identifies its
Agent/Vault using the developer address list, the pinned Gardens inventory,
and the deployment evidence shown there.

## Other addresses in the historical Gnosis developer inventory

These entries are from the historical developer inventory except where
noted. Only the Voting and Subscriptions entries in this table were also
checked against the court at the manifest block. The inventory also lists
a Polygon deployment, outside the scope of this guide.

| Historical component | Documented Gnosis address |
| --- | --- |
| BrightID Register | `0x7714eb44754cb9db6d65b61f3352df12600dc593` |
| Staking Factory | `0xe71331aef803baec606423b105e4d1c85f012c00` |
| Honey Staking | `0x0e25b918c9fb2fea5d42011d1f4b9f8c61b453e7` |
| Honey price oracle | `0x6f38d112b13eda1e3abafc61e296be2e27f15071` |
| Celeste Fees Updater | `0xeb24f7001437188baf2d5ef0b0fcfadad4564517` |
| Collateral Requirement Updater | `0xc08fbc829a879470c15916aad14e85905e6ab901` |
| Celeste Dispute module | `0xec7904e20b69f60966d6c6b9dc534355614dd922` |
| Celeste Registry module | `0x8c9968a2b16bc1cd0ead74f5eef25e899e795501` |
| Celeste Voting module (deployment output and pinned court read) | `0x1a0d15f1f6d90c2b71eba3859a1f30c91e5af9b8` |
| Celeste Treasury module | `0xeac1dc5ccf09e2b816f9544878cd513728fa6af7` |
| Celeste Subscriptions module (developer inventory and pinned court read) | `0x4e4ea6845d7656d569dc4ccc7b68bb3023720837` |

At block **49,432,749**, the Celeste court listed in the manifest returned the
table values from `getVoting()` and `getSubscriptions()`. This records the
configured addresses at that block, not whether either service was usable.
The wiki's Voting entry was truncated; the full address matches the
[Voting v1.0 creation receipt](https://gnosisscan.io/tx/0xe9fc244f72c7d433315be68cc9280a5cff3ee2c112ca86f10a3f8c2bf370c20a).
The [pinned Celeste deployment output](https://github.com/metrodao/celeste-deploy/blob/ba0c1a2e4727f4d04bf6f56112fb3e54ed30205e/data/output/court.xdai.json)
also records a separate [Subscriptions v1.0 creation receipt](https://gnosisscan.io/tx/0x3ac3ef47d76b72312a451c617407dac38e87886748fae3fa89ddb6c88d0bf0de)
at `0x41ab49872ed459c840d0caecd47fcdc201c48307`, which differs from the
Subscriptions address returned by the court at the manifest block.

The developer inventory describes the oracle as an HNY price reference
for certain funding payouts and Celeste fees. It lists separate contracts
for updating court fees and proposal collateral requirements. The names
above identify those historical components; they do not establish active
dependencies or current settings.

## Historical sources

The paths below are from the same pinned `1Hive/wiki` revision.

- 1Hive, *1Hive Protocol*, sections “1Hive Aragon DAO addresses,”
  “External contract addresses,” and “Celeste and modules addresses”:
  repository `1Hive/wiki`, commit `36bd2a64f0d7ae85b4ea725957917a016ca19417`,
  file `developers/1hive-protocol.md`, blob `fd00a5cb7f4f499c82de808096278d6c4be47768`.
- 1Hive, *Distribution*, `getting-started/honey/distribution.md`, for
  historical Common Pool and Conviction Voting behavior.
- 1Hive, *Decisions*, `getting-started/honey/decisions.md`, for the historical
  role of Decision Voting.
- 1Hive, *1Hive FAQ*, `guides/faq.md`, Tokenomics section, for historical
  HNY identification and the differing treasury reference.
