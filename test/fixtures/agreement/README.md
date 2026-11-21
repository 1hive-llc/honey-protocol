# Agreement fixture rebuild

The artifacts in `artifacts/` are built from Agreement commit `faf3df6d23845deeab515a02c7517743c620bbed` using pinned legacy compiler and dependency versions. Run from the honey-v2 repository. Source/dependency preparation requires network access; compilation and tests run locally:

```sh
agreement_repo="$PWD"
agreement_tmp="$(mktemp -d /tmp/honey-agreement-proof.XXXXXX)"
curl -fsSL https://codeload.github.com/1Hive/agreement-app/tar.gz/faf3df6d23845deeab515a02c7517743c620bbed \
  -o "$agreement_tmp/source.tar.gz"
tar -xzf "$agreement_tmp/source.tar.gz" -C "$agreement_tmp"
cd "$agreement_tmp"
npm --ignore-scripts --save-exact install solc@0.4.24 solc05@npm:solc@0.5.17 @aragon/os@5.0.0-rc.0 @aragon/staking@0.3.2 openzeppelin-solidity@1.12.0
cd "$agreement_repo"
node scripts/build-agreement-fixtures.cjs \
  "$agreement_tmp/agreement-app-faf3df6d23845deeab515a02c7517743c620bbed" \
  "$agreement_tmp/node_modules" \
  test/fixtures/agreement/artifacts
HONEY_AGREEMENT_ARTIFACTS=test/fixtures/agreement/artifacts forge test --match-contract AgreementIntegrationTest
```

The script validates the pinned Agreement source hash and dependency versions, and records source, fixture, and compiler-input hashes in `artifacts/source-manifest.json`.

Without `HONEY_AGREEMENT_ARTIFACTS`, Foundry skips this suite. This is a local integration fixture, not a reproducible production release manifest or proof of deployed contracts.
