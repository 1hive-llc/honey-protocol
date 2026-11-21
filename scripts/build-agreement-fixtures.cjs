// Compile the pinned external Agreement and Aragon contracts without modifying their source.
// Usage: node scripts/build-agreement-fixtures.cjs SOURCE_DIR DEPENDENCIES_DIR OUTPUT_DIR
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const args = process.argv.slice(2);
if (args.length !== 3) {
  console.error('Usage: node scripts/build-agreement-fixtures.cjs SOURCE_DIR DEPENDENCIES_DIR OUTPUT_DIR');
  process.exit(1);
}
const [source, dependencies, output] = args.map(p => path.resolve(p));
const expectedSourceCommit = 'faf3df6d23845deeab515a02c7517743c620bbed';
const expectedAgreementHash = 'f85c6ec195b0e1b6a0303ed6f641aeebd2a3ab469bdb67db81f84894f26052cf';
const expectedDependencies = {
  solc: '0.4.24',
  solc05: '0.5.17',
  '@aragon/os': '5.0.0-rc.0',
  '@aragon/staking': '0.3.2',
  'openzeppelin-solidity': '1.12.0'
};
const hash = contents => crypto.createHash('sha256').update(contents).digest('hex');
const shortError = error => String(error && error.message || error).slice(0, 2000);
function dependencyVersion(name) {
  try { return require(path.join(dependencies, name, 'package.json')).version; }
  catch (error) { console.error(`Missing dependency ${name}: ${shortError(error)}`); process.exit(1); }
}
for (const [name, expected] of Object.entries(expectedDependencies)) {
  const actual = dependencyVersion(name);
  if (actual !== expected) { console.error(`Expected ${name}@${expected}, found ${actual}`); process.exit(1); }
}
try {
const solc04 = require(path.join(dependencies, 'solc'));
const solc05 = require(path.join(dependencies, 'solc05'));
if (!solc04.version().startsWith('0.4.24+') || !solc05.version().startsWith('0.5.17+')) {
  console.error(`Incorrect compiler versions: ${solc04.version()}, ${solc05.version()}`);
  process.exit(1);
}
let agreement;
try { agreement = fs.readFileSync(path.join(source, 'contracts/Agreement.sol'), 'utf8'); }
catch (error) { console.error(`Cannot read contracts/Agreement.sol: ${shortError(error)}`); process.exit(1); }
if (hash(agreement) !== expectedAgreementHash) {
  console.error('Agreement.sol hash does not match the pinned source commit');
  process.exit(1);
}
const manifest = {
  sourceCommit: expectedSourceCommit,
  dependencies: expectedDependencies,
  compilers: [solc04.version(), solc05.version()],
  compilerInputs: {},
  fixtures: {},
  sources: {}
};
function read(name) {
  const file = name.startsWith('@') || name.startsWith('openzeppelin-solidity/') ? path.join(dependencies, name) : path.join(source, name);
  const contents = fs.readFileSync(file, 'utf8');
  manifest.sources[name] = hash(contents);
  return { contents };
}
fs.mkdirSync(output, { recursive: true });
function compile(label, compiler, sources) {
  const input = { language: 'Solidity', sources, settings: { optimizer: { enabled: true, runs: 200 }, outputSelection: { '*': { '*': ['abi', 'evm.bytecode.object'] } } } };
  manifest.compilerInputs[label] = hash(JSON.stringify(input));
  let result;
  try {
    result = JSON.parse(compiler.compileStandardWrapper(JSON.stringify(input), name => {
      try { return read(name); } catch (e) { return { error: shortError(e) }; }
    }));
  } catch (error) {
    console.error(`${label} compiler failed: ${shortError(error)}`);
    process.exit(1);
  }
  if (!result || typeof result !== 'object') {
    console.error(`${label} compiler returned invalid output`);
    process.exit(1);
  }
  const errors = (result.errors || []).filter(e => e.severity === 'error');
  if (errors.length) {
    console.error(`${label} compiler reported ${errors.length} error(s):`);
    console.error(errors.slice(0, 3).map(e => shortError(e.formattedMessage || e.message)).join('\n'));
    process.exit(1);
  }
  for (const contracts of Object.values(result.contracts || {})) for (const [name, artifact] of Object.entries(contracts)) {
    if (artifact.evm.bytecode.object) fs.writeFileSync(path.join(output, `${name}.json`), JSON.stringify({ abi: artifact.abi, bytecode: { object: '0x' + artifact.evm.bytecode.object } }));
  }
}
const fixture = fs.readFileSync(path.join(__dirname, '../test/fixtures/agreement/DisputableFixture.sol.txt'), 'utf8');
manifest.fixtures['DisputableFixture.sol.txt'] = hash(fixture);
manifest.sources['DisputableFixture.sol'] = hash(fixture);
compile('solc04', solc04, {
  'contracts/Agreement.sol': { content: read('contracts/Agreement.sol').contents },
  'Imports.sol': { content: 'pragma solidity 0.4.24; import "@aragon/os/contracts/kernel/Kernel.sol"; import "@aragon/os/contracts/acl/ACL.sol";' },
  'DisputableFixture.sol': { content: fixture }
});
compile('solc05', solc05, { 'Imports.sol': { content: 'pragma solidity 0.5.17; import "@aragon/staking/contracts/StakingFactory.sol";' } });
fs.writeFileSync(path.join(output, 'source-manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
console.log('Compiled Agreement, Kernel, ACL, staking and disputable fixture.');

} catch (error) {
  console.error(`Fixture build failed: ${shortError(error)}`);
  process.exit(1);
}
