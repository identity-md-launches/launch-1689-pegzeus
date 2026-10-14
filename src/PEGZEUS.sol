// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title PEGZEUS (PEGZ)
/// @notice A fixed-supply ERC-20 with 18 decimals and no administrative powers.
/// @dev The immediate deployer receives the entire supply. For an IdentityMD launch,
///      that deployer is the factory, which handles all subsequent allocations.
contract PEGZEUS is ERC20 {
    /// @notice One billion PEGZ, expressed in the token's smallest units.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    constructor() ERC20("PEGZEUS", "PEGZ") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
