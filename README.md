# PEGZEUS (PEGZ)

PEGZEUS is a fixed-supply ERC-20. Its constructor mints **1,000,000,000 PEGZ**
with **18 decimals** to the immediate deployer. Every transfer moves the exact
requested amount. There are no transfer taxes, administrative roles, subsequent
minting, burning, pausing, blacklisting, upgrade mechanisms, or external calls.

## Design and assumptions

The implementation is `src/PEGZEUS.sol:PEGZEUS`, built on the vendored
OpenZeppelin Contracts v5.0.2 ERC-20. The only customization is the constructor
and the named `INITIAL_SUPPLY` constant, equal to `1000000000000000000000000000`
minor units (`10^27`). Metadata and supply cannot be changed after deployment.

The brief's progression from moving value to running programs to producing work
is treated as project context. It specifies no work-validation, execution,
reward, or settlement protocol, so this token exposes the ERC-20 interface;
`execute()` and `produce()` are not token functions. No application contracts
are needed for the requested token. The name does not introduce a price peg,
collateral, oracle, or redemption mechanism.

ERC-20 behavior:

- `transfer`, `approve`, and `transferFrom` return `true` on success and revert
  with the inherited ERC-6093 custom errors on failure.
- Zero-amount transfers to valid addresses succeed and emit `Transfer`.
  Self-transfers preserve balances, but still require sufficient funds.
- Zero recipients and zero approval spenders are rejected.
- `approve` replaces the caller's allowance for that spender. A zero approval
  revokes it. Finite allowances decrease when spent; `type(uint256).max` is
  treated as an unlimited allowance and is not decreased.
- `transferFrom` requires allowance even when the caller is the holder.
  Failed transfers restore all balances and allowances atomically.
- Construction and transfers emit `Transfer`; explicit approvals emit
  `Approval`. This OpenZeppelin version does not emit `Approval` on allowance
  consumption in `transferFrom`; read `allowance()` for current authorization.
- Token transfers do not invoke recipient callbacks. Recipients must be able
  to manage ERC-20 balances themselves. Tokens sent to the token contract or
  another contract without a withdrawal path cannot be recovered by an admin.
- Direct native-currency payments revert. There is no native-currency handling
  or recovery function, including for ETH forcibly credited by the EVM.

## Build and check

Requirements: Foundry and Solidity **0.8.26** available in its compiler cache.
`foundry.toml` pins that compiler, the Cancun EVM, optimization at 200 runs, and
`bytecode_hash = "none"`. No FFI or filesystem permissions are enabled.

All Solidity dependencies and their licenses are ordinary files under `lib/`.
No package installation, git submodules, RPC, wallet, environment-specific
configuration, or network access is needed to build or test once the pinned
compiler is available. `dependencies.lock.json` records release URLs, archive
SHA-256 hashes, and the hash of every vendored file. OpenZeppelin includes only
the ERC-20 dependency closure; forge-std v1.9.7 supplies test utilities.

```sh
forge build
FOUNDRY_FUZZ_SEED=0xc60eb4d6badda03cf0faa9d3def1b7d19bebf8316dd3cae2136e88b36102b943 forge test
forge fmt --check
```

Tests do not read or change environment variables, require RPC forks, or share
state between cases. The shell seed above controls Foundry's fuzzer. The
configuration sets 1,000 runs per fuzz test and 256 invariant sequences at depth
64, with unexpected handler reverts treated as failures.

| Test file | Coverage |
| --- | --- |
| `test/PEGZEUS.t.sol` | Metadata, mint and transfer events, exact transfers, approvals and revocation, finite/unlimited allowances, self/zero/full-balance transfers, contract recipients, atomic failures, privilege and opcode checks, fuzzed success and failure cases |
| `test/LaunchFlow.t.sol` | CREATE2 deployment to a factory, entire supply held by the immediate deployer, exact launch allocations and claims, token-side pool transfers in both directions, arbitrary deployers |
| `test/PEGZEUS.invariant.t.sol` | Randomized transfers, approvals, delegated spending and invalid operations, with independent balance and allowance accounting across four actors |

The launch fixture checks token movements; it does not implement the production
factory, a Merkle distributor, pricing, or Uniswap. The supplied protected
launch checks run in the network's separate harness with its platform contracts
and resolved launch configuration. They are not standalone tests in this project.

## Deployment parameters

| Parameter | Value |
| --- | --- |
| Launch chain | Ethereum, chain ID 1 |
| Solidity artifact | `src/PEGZEUS.sol:PEGZEUS` |
| Contract identifier | `PEGZEUS` |
| Name / symbol / decimals | `PEGZEUS` / `PEGZ` / `18` |
| Total supply in minor units | `1000000000000000000000000000` |
| Constructor arguments | None (`[]`); constructor argument bytes are empty |
| Native value on deployment | 0 |
| Initial holder | Immediate constructor caller (`msg.sender`), the launch factory |
| Initialization / linked libraries | None |
| Application contracts / owners | None |

The launch system deploys the creation bytecode from
`out/PEGZEUS.sol/PEGZEUS.json`. The constructor does not contact outside
contracts or rely on any existing chain state. It works under CREATE or CREATE2
and does not use `tx.origin`. Deploying through any other helper gives that
helper the whole supply, so the launch must use its intended factory directly.

The factory, rather than the token constructor, handles the supplied economics:

| Launch setting | Supplied value / responsibility |
| --- | --- |
| Swarm allocation | 10%: 100,000,000 PEGZ to the launch's Merkle distributor |
| Pool allocation | `poolBps = 8800`: 88%, or 880,000,000 PEGZ |
| Remainder | 2%: 20,000,000 PEGZ to `0xded42160d0642ba91c6c976c7ba8b6e24ea90590` |
| Paired currency | IMD at `0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7` (18 decimals) |
| Pool fee / tick spacing | `12500` (1.25%) / `60`, applied by the launch system |
| Opening capitalization | `initialMarketCapWei = "2500000000000000000000"` in IMD minor units |
| Initial price provenance | `"79228162514264337593543950336"`; the deployer derives the actual opening price from capitalization, supply, and token ordering |

These are launch settings, not token constructor parameters or on-chain token
configuration. No launch allocation is reserved, transferred, or minted by
another project contract. The manifest step supplies `launch.json` later; this
repository intentionally contains no manifest, signer, or broadcasting script.

## After launch

There are no owner-settable settings, keepers, minting permissions, or service
accounts to configure. The launch operator is responsible for deploying the
reviewed artifact, verifying its source and metadata, distributing the supply,
and checking pool and distributor initialization under the launch policy.

Holders control transfers and allowances. Integrators should check transaction
success and use the actual token address, 18-decimal units, and current
allowances. Approve only the needed amount where possible. To replace an
existing nonzero allowance, first revoke it and wait for confirmation; a spender
can still spend an existing allowance before revocation is confirmed.

The token has no admin recovery or upgrade path. Future work-production services
would require a separately specified application and cannot alter this token's
supply. See `docs/SECURITY.md` for the review scope and release responsibilities.
