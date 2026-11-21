# Contributing

Open an issue to discuss larger changes. For a pull request, explain the behavior
change, add or update focused tests, and mark any change to governance, court,
staking, or token-flow assumptions. Keep upstream changes separate where practical
and preserve provenance and license notices.

Run the source-preview checks with Foundry and Node.js:

```sh
npm ci --prefix vendor/kleros-v2 --ignore-scripts --no-audit --no-fund
forge test
```

The fixture-backed Agreement integration is optional; see
[fixture instructions](test/fixtures/agreement/README.md). Do not commit credentials,
private keys, deployment outputs, or generated fixtures. See the
[security policy](SECURITY.md) for suspected vulnerabilities.
