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

These entries are transcribed facts from the developer inventory, outside
the manifest's pinned on-chain checks. The historical Celeste Voting entry
is omitted because the source does not give a full 20-byte address. The
inventory also lists a Polygon deployment, outside the scope of this guide.

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
| Celeste Treasury module | `0xeac1dc5ccf09e2b816f9544878cd513728fa6af7` |
| Celeste Subscriptions module | `0x4e4ea6845d7656d569dc4ccc7b68bb3023720837` |

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
