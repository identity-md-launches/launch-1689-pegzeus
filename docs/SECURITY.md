# Security review scope

The production customization is a constructor calling OpenZeppelin's internal
`_mint` once, with a fixed supply and the immediate caller as recipient. The
vendored ERC-20 implementation is unmodified. Test helpers are under `test/`
and are not launch contracts.

The supplied security reference was used to review applicable failure modes:

| Area | Design and evidence |
| --- | --- |
| Supply and decimals | One constructor mint of `10^27` minor units; default decimals are 18. No externally reachable mint or burn. Unit, fuzz, and stateful invariant checks cover conservation. |
| Holder authority | Only the holder can approve or directly transfer. Delegated transfers require that caller's allowance. The deployer has no bypass or admin role. Failed unauthorized and privileged calls are tested. |
| Arithmetic | OpenZeppelin validates balances and finite allowances before subtraction. Its unchecked additions rely on conservation of the fixed supply. Tests include full supply, one minor unit, maximum uint256 requests, self-transfers, and failure rollback. |
| External interaction | The constructor and token operations make no external contract calls. There are no receiver hooks, arbitrary call targets, oracle reads, randomness, or signature checks. A reverting receiver fixture verifies that a transfer needs no callback. |
| Approvals | Standard ERC-20 replacement semantics, including the transaction-ordering risk of changing existing allowances. Unlimited approvals are supported but not required by this project. Revocation, spender isolation, allowance exhaustion and rollback are tested. |
| Launch flows | Factory deployment holds the full supply. Transfers take no fee and require no exemptions or address registries. Local fixtures check exact 10/88/2 allocations, claims, and token movements into and out of a pool role. |
| Upgrade and destructive powers | No proxy, initializer, owner, pause, blacklist, seizure, or upgrade interface. The runtime opcode test skips PUSH data and rejects DELEGATECALL, CALLCODE, and SELFDESTRUCT. |
| Dependency reproducibility | Compiler version and settings are pinned. Vendored source and licenses have recorded hashes; there are no linked external libraries or install-time dependencies. |

Validation uses `forge build`, `forge test` with the assignment's fuzz seed,
and `forge fmt --check`. There are five fuzz tests, 35 ordinary tests, and two
invariant properties evaluated together over 256 sequences of 64 actions. The
invariant handler exercises both valid calls and expected reverts; its independent
accounting detects unexpected balance or allowance changes.

The local fixtures do not validate live Uniswap pricing or the platform factory
and distributor implementations. The protected inputs depend on that platform's
separate harness, which was not supplied as a runnable project. Admission and
live deployment checks remain the launch system's responsibility.

This is an implementation self-review, not an independent audit. Slither and
Mythril were not run. Independent adversarial review and source verification
remain release responsibilities; no deployment or funded-wallet action was
performed as part of this assignment.
