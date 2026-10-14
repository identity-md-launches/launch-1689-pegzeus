// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {PEGZEUS} from "../src/PEGZEUS.sol";

/// @dev Test fixture only; the actual IdentityMD factory is external to this project.
contract DeploymentHarness {
    function deploy(bytes32 salt) external returns (PEGZEUS) {
        return new PEGZEUS{salt: salt}();
    }

    function move(PEGZEUS token, address recipient, uint256 amount) external returns (bool) {
        return token.transfer(recipient, amount);
    }
}

contract LaunchFlowTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    DeploymentHarness internal factory;
    PEGZEUS internal token;
    address internal distributor;
    address internal poolManager;
    address internal remainderRecipient;
    address internal claimant;
    address internal trader;

    function setUp() public {
        factory = new DeploymentHarness();
        token = factory.deploy(keccak256("PEGZEUS launch fixture"));
        distributor = makeAddr("distributor fixture");
        poolManager = makeAddr("pool manager fixture");
        remainderRecipient = makeAddr("remainder recipient fixture");
        claimant = makeAddr("claimant fixture");
        trader = makeAddr("trader fixture");
    }

    function test_factoryReceivesWholeSupplyWithoutInitialization() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(factory)), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(tx.origin), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.allowance(address(factory), address(this)), 0);
    }

    function test_launchAllocationsAndClaimArriveExactly() public {
        _distribute();
        uint256 swarm = SUPPLY / 10;
        vm.prank(distributor);
        assertTrue(token.transfer(claimant, swarm));
        assertEq(token.balanceOf(distributor), 0);
        assertEq(token.balanceOf(claimant), swarm);
        assertEq(token.balanceOf(poolManager), SUPPLY * 88 / 100);
        assertEq(token.balanceOf(remainderRecipient), SUPPLY * 2 / 100);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// @dev Exercises only the token-side movements; this is not a Uniswap swap simulation.
    function test_poolTransfersInBothDirectionsHaveNoTaxOrRestrictions() public {
        _distribute();
        uint256 poolBefore = token.balanceOf(poolManager);
        uint256 bought = 25_000 ether;
        vm.prank(poolManager);
        assertTrue(token.transfer(trader, bought));
        assertEq(token.balanceOf(trader), bought);
        assertEq(token.balanceOf(poolManager), poolBefore - bought);
        vm.prank(trader);
        assertTrue(token.transfer(poolManager, bought));
        assertEq(token.balanceOf(trader), 0);
        assertEq(token.balanceOf(poolManager), poolBefore);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_anyImmediateDeployerReceivesEntireSupply(address deployer) public {
        vm.assume(deployer != address(0));
        vm.prank(deployer);
        PEGZEUS another = new PEGZEUS();
        assertEq(another.balanceOf(deployer), SUPPLY);
        assertEq(another.totalSupply(), SUPPLY);
    }

    function _distribute() private {
        assertTrue(factory.move(token, distributor, SUPPLY / 10));
        assertTrue(factory.move(token, poolManager, SUPPLY * 88 / 100));
        assertTrue(factory.move(token, remainderRecipient, SUPPLY * 2 / 100));
        assertEq(token.balanceOf(address(factory)), 0);
        assertEq(token.balanceOf(distributor), SUPPLY / 10);
        assertEq(token.balanceOf(poolManager), SUPPLY * 88 / 100);
        assertEq(token.balanceOf(remainderRecipient), SUPPLY * 2 / 100);
    }
}
