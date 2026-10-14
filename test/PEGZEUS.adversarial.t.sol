// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {PEGZEUS} from "src/PEGZEUS.sol";

/// @dev A real intermediate caller to distinguish msg.sender from tx.origin.
contract PEGZEUSForwarder {
    function transfer(PEGZEUS token, address to, uint256 amount) external returns (bool) {
        return token.transfer(to, amount);
    }

    function approve(PEGZEUS token, address spender, uint256 amount) external returns (bool) {
        return token.approve(spender, amount);
    }

    function transferFrom(PEGZEUS token, address from, address to, uint256 amount) external returns (bool) {
        return token.transferFrom(from, to, amount);
    }
}

/// @dev Complements the original unit suite with approval transitions, caller
///      aliasing, rollback properties, and equivalent ways of moving value.
/// forge-config: default.fuzz.runs = 1000
contract PEGZEUSAdversarialTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    PEGZEUS internal token;
    address internal alice;
    address internal bob;
    address internal spender;

    function setUp() public {
        token = new PEGZEUS();
        alice = makeAddr("adversarial alice");
        bob = makeAddr("adversarial bob");
        spender = makeAddr("adversarial spender");
    }

    function test_maximumFiniteAllowanceIsConsumed() public {
        uint256 approved = type(uint256).max - 1;
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), approved - 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY - 1));
        assertEq(token.allowance(address(this), spender), approved - SUPPLY);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_unlimitedApprovalCanBeDowngradedAndRevoked() public {
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max);

        token.approve(spender, 2);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 2));
        assertEq(token.allowance(address(this), spender), 0);
        _expectNoAllowance(address(this), alice, 1);

        token.approve(spender, type(uint256).max);
        token.approve(spender, 0);
        _expectNoAllowance(address(this), alice, 1);
        assertEq(token.balanceOf(alice), 3);
        assertEq(token.balanceOf(address(this)), SUPPLY - 3);
    }

    function test_allowanceStaysWithOwnerWhenTokensMoveAndIsUsableAfterRefill() public {
        token.transfer(alice, 10);
        vm.prank(alice);
        token.approve(spender, 10);
        vm.prank(alice);
        token.transfer(bob, 10);

        // Receiving approved tokens does not delegate control over the new holder.
        _expectNoAllowance(bob, spender, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, spender, 1);
        assertEq(token.allowance(alice, spender), 10);
        assertEq(token.balanceOf(bob), 10);

        vm.prank(bob);
        token.transfer(alice, 10);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, spender, 10));
        assertEq(token.balanceOf(spender), 10);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_selfDelegationNeedsAndConsumesItsOwnAllowance() public {
        token.transfer(alice, 10);
        vm.prank(alice);
        token.approve(alice, 7);
        vm.prank(alice);
        assertTrue(token.transferFrom(alice, alice, 7));
        assertEq(token.balanceOf(alice), 10);
        assertEq(token.allowance(alice, alice), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transferFrom(alice, bob, 1);
        assertEq(token.balanceOf(alice), 10);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_zeroApprovalToZeroSpenderIsStillInvalid() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_zeroDelegatedTransferToZeroIsStillInvalid() public {
        token.approve(spender, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 0);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maximumDelegatedAmountCannotOverflowOrBypassBalance() public {
        testFuzz_unlimitedAllowanceCannotBypassBalance(SUPPLY, type(uint256).max - SUPPLY);
    }

    function testFuzz_approvalReplacementIsIdempotentAndIsolated(uint256 oldAmount, uint256 newAmount) public {
        token.transfer(alice, SUPPLY / 2);
        token.approve(spender, 17);
        vm.prank(alice);
        token.approve(bob, 23);
        vm.prank(alice);
        token.approve(spender, oldAmount);
        assertEq(token.allowance(alice, spender), oldAmount);

        for (uint256 i; i < 2; ++i) {
            vm.prank(alice);
            assertTrue(token.approve(spender, newAmount));
            assertEq(token.allowance(alice, spender), newAmount);
            assertEq(token.allowance(address(this), spender), 17);
            assertEq(token.allowance(alice, bob), 23);
            assertEq(token.allowance(spender, alice), 0);
            assertEq(token.balanceOf(alice), SUPPLY / 2);
            assertEq(token.balanceOf(address(this)), SUPPLY / 2);
            assertEq(token.balanceOf(spender), 0);
            assertEq(token.balanceOf(bob), 0);
            assertEq(token.totalSupply(), SUPPLY);
        }
    }

    function testFuzz_failedDelegatedTransferRestoresFiniteAllowance(uint256 balance, uint256 excess, uint256 approved)
        public
    {
        balance = bound(balance, 0, SUPPLY);
        // Keep the approval strictly below the unlimited sentinel.
        excess = bound(excess, 1, type(uint256).max - 1 - balance);
        uint256 amount = balance + excess;
        approved = bound(approved, amount, type(uint256).max - 1);
        token.transfer(alice, balance);
        vm.prank(alice);
        token.approve(spender, approved);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, amount));
        vm.prank(spender);
        token.transferFrom(alice, bob, amount);
        assertEq(token.allowance(alice, spender), approved);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.totalSupply(), SUPPLY);

        // A failed attempt must not prevent the entire valid balance being spent next.
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, balance));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), balance);
        assertEq(token.allowance(alice, spender), approved - balance);
    }

    function testFuzz_unlimitedAllowanceCannotBypassBalance(uint256 balance, uint256 excess) public {
        balance = bound(balance, 0, SUPPLY);
        uint256 amount = balance + bound(excess, 1, type(uint256).max - balance);
        token.transfer(alice, balance);
        vm.prank(alice);
        token.approve(spender, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, amount));
        vm.prank(spender);
        token.transferFrom(alice, bob, amount);
        assertEq(token.allowance(alice, spender), type(uint256).max);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_failedTransferToZeroPreservesAuthorization(uint256 approved, uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        approved = bound(approved, amount, type(uint256).max);
        token.approve(spender, approved);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), amount);
        assertEq(token.allowance(address(this), spender), approved);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.allowance(address(this), spender), approved == type(uint256).max ? approved : approved - amount);
    }

    function testFuzz_transferRoundTripRestoresPreexistingBalances(uint256 funding, uint256 amount) public {
        funding = bound(funding, 0, SUPPLY);
        amount = bound(amount, 0, funding);
        token.transfer(alice, funding);
        token.transfer(bob, SUPPLY - funding);
        vm.prank(alice);
        token.approve(spender, 123);
        vm.prank(alice);
        assertTrue(token.transfer(bob, amount));
        assertEq(token.balanceOf(alice), funding - amount);
        assertEq(token.balanceOf(bob), SUPPLY - funding + amount);
        vm.prank(bob);
        assertTrue(token.transfer(alice, amount));
        assertEq(token.balanceOf(alice), funding);
        assertEq(token.balanceOf(bob), SUPPLY - funding);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.allowance(alice, spender), 123);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_splitDelegatedSpendingMatchesSingleSpend(
        uint256 total,
        uint256 first,
        uint256 approved,
        bool unlimited
    ) public {
        total = bound(total, 0, SUPPLY);
        first = bound(first, 0, total);
        approved = unlimited ? type(uint256).max : bound(approved, total, type(uint256).max - 1);
        PEGZEUS splitToken = new PEGZEUS();
        token.approve(spender, approved);
        splitToken.approve(spender, approved);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, total));
        vm.prank(spender);
        assertTrue(splitToken.transferFrom(address(this), alice, first));
        vm.prank(spender);
        assertTrue(splitToken.transferFrom(address(this), alice, total - first));

        assertEq(token.balanceOf(alice), total);
        assertEq(splitToken.balanceOf(alice), token.balanceOf(alice));
        assertEq(token.balanceOf(address(this)), SUPPLY - total);
        assertEq(splitToken.balanceOf(address(this)), token.balanceOf(address(this)));
        assertEq(token.allowance(address(this), spender), unlimited ? approved : approved - total);
        assertEq(splitToken.allowance(address(this), spender), token.allowance(address(this), spender));
        assertEq(token.balanceOf(spender), 0);
        assertEq(splitToken.balanceOf(spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(splitToken.totalSupply(), SUPPLY);
    }

    function testFuzz_forwarderCannotUseTransactionOriginAuthority(uint256 amount) public {
        amount = bound(amount, 1, SUPPLY);
        token.transfer(alice, SUPPLY);
        PEGZEUSForwarder forwarder = new PEGZEUSForwarder();

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(forwarder), 0, amount)
        );
        vm.prank(alice, alice);
        forwarder.transfer(token, bob, amount);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(forwarder), 0, amount)
        );
        vm.prank(alice, alice);
        forwarder.transferFrom(token, alice, bob, amount);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(bob), 0);

        vm.prank(alice, alice);
        assertTrue(forwarder.approve(token, spender, amount));
        assertEq(token.allowance(address(forwarder), spender), amount);
        assertEq(token.allowance(alice, spender), 0);

        vm.prank(alice);
        token.approve(address(forwarder), amount);
        vm.prank(bob, bob);
        assertTrue(forwarder.transferFrom(token, alice, bob, amount));
        assertEq(token.balanceOf(alice), SUPPLY - amount);
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.balanceOf(address(forwarder)), 0);
        assertEq(token.allowance(alice, address(forwarder)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_valueAttachedToTokenCallsRevertsAtomically(uint256 value) public {
        value = bound(value, 1, 1 ether);
        vm.deal(address(this), value);
        token.approve(address(this), 1);
        bytes[3] memory calls = [
            abi.encodeCall(token.transfer, (alice, 1)),
            abi.encodeCall(token.approve, (spender, 1)),
            abi.encodeCall(token.transferFrom, (address(this), alice, 1))
        ];
        for (uint256 i; i < calls.length; ++i) {
            (bool success,) = address(token).call{value: value}(calls[i]);
            assertFalse(success);
            assertEq(address(this).balance, value);
            assertEq(address(token).balance, 0);
            assertEq(token.balanceOf(address(this)), SUPPLY);
            assertEq(token.balanceOf(alice), 0);
            assertEq(token.allowance(address(this), spender), 0);
            assertEq(token.allowance(address(this), address(this)), 1);
            assertEq(token.totalSupply(), SUPPLY);
        }
    }

    function _expectNoAllowance(address owner, address recipient, uint256 amount) internal {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, amount));
        vm.prank(spender);
        token.transferFrom(owner, recipient, amount);
    }
}
