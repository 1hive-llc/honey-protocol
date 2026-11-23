# Honey Kleros migration: local source review candidate

Selected protocol source for review, not deployed or audited production software.
This repository contains a source-only snapshot, not a deployment or migration instruction.
It contains the Kleros-derived court, Honey stake weighting and identity eligibility,
optimistic/execution and Agreement adapters, related local tests, and supporting
Foundry libraries. It omits deploy/broadcast scripts, historical rehearsals, UI,
private Git history, the GPL Celeste vendor tree and root Celeste prototype tests.

For legacy on-chain addresses, see the [Honey v1 Gnosis deployment manifest](docs/gnosis-honey-v1.md).

## Reproduce locally

Install Foundry and allow it to fetch Solidity 0.8.30 once, then run:

```sh
npm ci --prefix vendor/kleros-v2 --ignore-scripts --no-audit
forge test
```

No wallet, RPC, account or private key is needed. The optional historical Agreement
integration suite is skipped without locally generated artifacts. See
[test fixture notes](test/fixtures/agreement/README.md); don't distribute the
artefacts without independent provenance and license review.

## Licenses and provenance

Honey-authored code is licensed under [MIT](LICENSE), copyright 1Hive LLC.
Third-party and upstream code remains under the notices supplied with it:
Kleros v2 base 6365842177e8972f751aa0f6ba4ec6febf14a791 (MIT; preserved in
vendor/kleros-v2/LICENSE); Forge Std (MIT and Apache 2.0 notices in lib/forge-std);
and OpenZeppelin Contracts 5.5.0 (MIT; separately installed from the lockfile).
The top-level license does not replace the upstream notices.

Exclude local caches, out/, node_modules/, and generated fixtures from any export.
No claim is made about correspondence to deployed bytecode or a production migration.
