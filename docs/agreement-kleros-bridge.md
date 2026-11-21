# Agreement / Honey-Kleros bridge

Local fresh-deployment source candidate: `src/optimistic/KlerosAgreementAdapter.sol`. This implements the selected Honey fee flow for the existing Agreement arbitrator interface; it does not replace the separate optimistic-executor adapter.

## Fixed boundaries

The adapter binds one Agreement, one Core, one Honey token and one court/dispute-kit extraData configuration at construction. There are no owner setters, withdrawal powers or shared pre-funded fee pool. Construction requires deployed contract addresses and Core's staking token to match Honey; dispute creation rechecks that token binding before taking funds.

`getDisputeFees()` returns this adapter as spender/recipient, Honey and the Core's current ERC20 arbitration quote. Agreement obtains its own participant allowance, escrows the challenger fee separately, and approves the adapter for the submitter arbitration fee. Only Agreement may create a dispute; the adapter pulls that fee and pays Core. It must not consume Agreement's challenger escrow. Token and Core are trusted contract dependencies; a binding check does not attest their implementation or proxy upgrades.

`getSubscriptionFees(address)` returns a zero cashier, Honey, and zero fees. The planned Agreement setting disables its optional app-fees cashier. This bridge does not provide a subscription service.

## IDs, evidence and finality

Agreement indexes challenges by arbitrator dispute ID alone. The adapter uses `keccak256(abi.encode(adapterAddress,coreDisputeId))` as a uint256 namespace-qualified ID, with explicit existence state and reverse mapping. This avoids restarting a small integer sequence next to historical Celeste IDs; collision resistance is cryptographic, not a mathematical guarantee. IDs must stay decimal strings/bigints in CLI/indexer code.

Evidence can only be forwarded by the immutable Agreement, for a known unfinished dispute. The adapter emits evidence associated with its namespaced ID and records the corresponding Core ID in the creation event. Juror-facing evidence indexing still needs integration proof.

`closeEvidencePeriod` explicitly reverts as unsupported. Kleros retains its configured period; Agreement's automatic low-level early-close attempt ignores failure in the inspected source. A direct user early-close command must show this limitation, not report successful shortening.

Core's authenticated `rule(coreId,choice)` callback is the only finality input. Unknown IDs, duplicate callbacks and choices above 2 revert. Rulings map as follows:

| Kleros choice | Agreement outcome |
| --- | --- |
| 0, refuse/tie | 2, void |
| 1, challenger | 3, reject action |
| 2, submitter | 4, accept action |

Agreement pulls `(address subject,uint256 ruling)` using `rule(adapterDisputeId)` only after that callback. The adapter does not execute Agreement or the proposal. Callback delivery, Agreement resolution, proposal execution and deployment remain separate actions.

## Source authority and proof limits

Agreement and its IArbitrator interface were read at public commit `faf3df6d23845deeab515a02c7517743c620bbed` from `1Hive/agreement-app`. This pins source, not deployed proxy/ACL state. The interface returns an address, not a boolean, alongside the ruling.

Unit tests cover exact fees, IDs, callback authorization/finality, ruling mapping, evidence restrictions and failed funding. `test/HoneyAppeals.t.sol` additionally uses real Core, classic dispute kit, Honey fees and a full appeal before the bridge receives a ruling. Its Agreement harness reproduces the fee/approval/evidence/resolve call sequence; it is not the Aragon app and does not prove its collateral accounting, ACL, setting change or indexed evidence UI.

Before a switch: verify deployed Agreement implementation/ACL and Honey collateral bindings; verify actual Gardens application callbacks and proposal execution; prepare ABI/bytecode-bound CLI transaction policy; verify evidence discovery and document exact choice labels; perform the bounded outstanding-obligation check. No contract deployment, signer activation or live transaction was performed.


## Real Agreement integration proof

`test/AgreementIntegration.t.sol` deploys the unmodified pinned Agreement with real Aragon Kernel/ACL proxies and StakingFactory/Staking, connected to the local Core/Classic and Honey adapter. It checks challenge escrow, submitter fee transfer, collateral lock/slash/unlock and payouts for all three final outcomes. It also checks unauthorized setting changes and the requirement to sign the new setting before submitting. The disputable application is a minimal callback fixture; actual Gardens proposal execution is not covered.

See [fixture build instructions](../test/fixtures/agreement/README.md). Legacy Solidity artifacts are generated locally and ignored by Git. The suite is explicitly opt-in via `HONEY_AGREEMENT_ARTIFACTS`; a default run without it skips this proof. With artifacts configured, the full root suite passed 115 tests with no skips. This local proof does not establish deployed proxy state, ownership/ACL, evidence discovery or WalletConnect device behavior.
