# Honey-funded appeals — local source candidate

The selected Honey configuration uses Honey for both staking and dispute fees. The core and classic dispute kit now support ERC20 appeals in the same token as the dispute's initial round, without converting user funds to native currency. Native gas is separate.

## Contract surface

- Core `getDisputeFeeToken(disputeId)` identifies the immutable-in-lifecycle fee currency from round zero.
- Core `appealCostInFeeToken(disputeId)` quotes the current appeal cost in that currency. Existing `appealCost` remains native-denominated for upstream callers.
- Classic `fundAppealWithToken(disputeId,choice,maxAmount)` pulls only the remaining required contribution, after the participant grants an allowance. Excess remains in the participant's wallet.
- Classic calls core `appealWithToken` once two choices are funded. The core accepts only the current dispute kit, pulls the fee, and stores the same currency on the new round, including a court jump.
- Existing `withdrawFeesAndRewards` returns the dispute's token. Core juror payouts use each round's stored fee token. Failed ERC20 transfers in the new funding/withdrawal paths revert rather than losing the claim.
- Payable native funding rejects ERC20 disputes. ERC20 funding rejects native disputes. No storage layout changes were introduced.

This adds an ERC20 path to the fork rather than removing upstream native APIs. Honey-only deployment must select Honey as staking and initial-dispute fee token and constrain allowed arbitrables/dispute kits accordingly. Presence of the new methods alone is not proof of a Honey-only deployed configuration.

## Limits and prerequisites

The existing converter still determines quotes from native-denominated court parameters. Quotes can change during partial funding; contributed balances remain token-denominated. There is no new fixed-rate or quote-snapshot policy. Honey is treated as a trusted standard ERC20; fee-on-transfer/rebasing or callback-bearing tokens are not an approved configuration.

Only the modified classic kit is covered here. Court jumps within that kit are tested through settlement; other dispute-kit jumps require separate compatibility proof before enabling them. Existing deployments with mixed historical round currencies are not supported by this fresh-deployment candidate. The modified source remains uncommitted; this is not a release or deployment authorization.

The Agreement-compatible arbitration adapter, complete Honey-only collateral/configuration verification, CLI transaction builders and WalletConnect/device UAT remain separate unfinished work.

## Evidence

`forge test` at the root: 105 tests passed, no failures/skips. Focused Honey suite covers partial funding, excess caps, successful appeals and refunds/rewards, court jump, juror payout, native/token mismatch, absent allowance, expiry and paused withdrawal. Existing identity-sortition suite still passes.

Upstream contracts directory: `forge test --match-contract 'KlerosCore_AppealsTest|KlerosCore_ExecutionTest|KlerosCore_DisputesTest'`: 42 tests passed. This preserves native appeal/dispute/execution regression evidence, not all upstream tests.

Root optimizer profile produces Core below the 24,576-byte runtime limit; the upstream Foundry 10,000-run test profile exceeds it and is not a deployable artifact. Any release must pin compiler/settings and recheck actual artifact size. No contract deployment or transactions were performed.
