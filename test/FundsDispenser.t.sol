// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {console} from "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {
    IAccessControlDefaultAdminRules
} from "@openzeppelin/contracts/access/extensions/IAccessControlDefaultAdminRules.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {FundsDispenserHarness} from "./FundsDispenserHarness.sol";
import {ReentrantRequester} from "./mocks/ReentrantRequester.sol";
import {RejectingReceiver} from "./mocks/RejectingReceiver.sol";
import {IFundsDispenser} from "../src/IFundsDispenser.sol";

contract FundsDispenserTest is Test {
    FundsDispenserHarness public dispenser;

    address public immutable ADMIN = makeAddr("ADMIN");
    address public immutable REGISTERED_USER = makeAddr("REGISTERED_USER");
    address public immutable NOT_REGISTERED_USER = makeAddr("NOT_REGISTERED_USER");

    uint256 public constant DAYS_1 = 1 days;
    uint256 public constant WEEKS_4 = 28 days;

    function setUp() public {
        dispenser = new FundsDispenserHarness(ADMIN);
        vm.deal(address(dispenser), 1e18);

        // ACT: register user
        IFundsDispenser.FundsRequestConfig memory registeredConfig =
            dispenser.newFundsRequestConfig(2e15, DAYS_1, 3e17, WEEKS_4, 1e15);

        vm.prank(ADMIN);
        dispenser.registerConfig(REGISTERED_USER, registeredConfig);
    }

    function test_Constructor_RevertsOnZeroAdmin() public {
        // ASSERT: zero admin is rejected.
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControlDefaultAdminRules.AccessControlInvalidDefaultAdmin.selector, address(0)
            )
        );
        new FundsDispenserHarness(address(0));
    }

    function test_AdminTransfer_TwoStep() public {
        address newAdmin = makeAddr("newAdmin");

        // ACT: begin the transfer.
        vm.prank(ADMIN);
        dispenser.beginDefaultAdminTransfer(newAdmin);

        // ASSERT: the new admin cannot accept in the same block as the begin call.
        vm.expectPartialRevert(IAccessControlDefaultAdminRules.AccessControlEnforcedDefaultAdminDelay.selector);
        vm.prank(newAdmin);
        dispenser.acceptDefaultAdminTransfer();

        // ACT: accept the transfer in a later block.
        vm.warp(vm.getBlockTimestamp() + dispenser.INITIAL_ADMIN_DELAY() + 1);
        vm.prank(newAdmin);
        dispenser.acceptDefaultAdminTransfer();

        // ASSERT: the admin role has moved to the new admin.
        assertEq(dispenser.defaultAdmin(), newAdmin);
        assertTrue(dispenser.hasRole(dispenser.DEFAULT_ADMIN_ROLE(), newAdmin));
        assertFalse(dispenser.hasRole(dispenser.DEFAULT_ADMIN_ROLE(), ADMIN));

        // ASSERT: the old admin cannot register anymore.
        IFundsDispenser.FundsRequestConfig memory config =
            dispenser.newFundsRequestConfig(2e15, DAYS_1, 3e17, WEEKS_4, 1e15);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, ADMIN, dispenser.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(ADMIN);
        dispenser.registerConfig(REGISTERED_USER, config);
    }

    function test_RegisterUser_FailsForNonAdmin() public {
        IFundsDispenser.FundsRequestConfig memory bobConfig =
            dispenser.newFundsRequestConfig(2e15, DAYS_1, 3e17, WEEKS_4, 1e15);

        // ASSERT: non-admin cannot register.
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                REGISTERED_USER,
                dispenser.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(REGISTERED_USER);
        dispenser.registerConfig(REGISTERED_USER, bobConfig);
    }

    function test_RegisterUser_InvalidConfig() public {
        IFundsDispenser.FundsRequestConfig memory invalidConfig = IFundsDispenser.FundsRequestConfig(0, 0, 0, 0, 0);

        // ASSERT: the configuration should be invalid.
        assert(!dispenser.validateConfig(invalidConfig));

        // ASSERT: registration fails
        vm.expectRevert(IFundsDispenser.InvalidConfig.selector);

        vm.prank(ADMIN);
        dispenser.registerConfig(REGISTERED_USER, invalidConfig);
    }

    function test_RegisterUser_Success() public {
        address newUser = makeAddr("newUser");
        IFundsDispenser.FundsRequestConfig memory newConfig =
            dispenser.newFundsRequestConfig(2e15, DAYS_1, 3e17, WEEKS_4, 1e15);

        // ASSERT: account is not registered yet.
        IFundsDispenser.FundsRequestConfig memory config = dispenser.getFundsRequestConfig(newUser);
        assert(!dispenser.validateConfig(config));
        assert(dispenser.getRegistrationUpdatedAt(newUser) == 0);

        // ASSERT: admin can register.
        vm.expectEmit();
        emit IFundsDispenser.RegistrationUpdated(newUser, newConfig);
        vm.prank(ADMIN);
        dispenser.registerConfig(newUser, newConfig);

        // ASSERT: new config is registered and is stored correctly.
        IFundsDispenser.FundsRequestConfig memory retrievedConfig = dispenser.getFundsRequestConfig(newUser);
        assertEq32(keccak256(abi.encode(retrievedConfig)), keccak256(abi.encode(newConfig)));
        assertEq(dispenser.getRegistrationUpdatedAt(newUser), block.timestamp);
    }

    function test_RegisterUser_RevertsOnZeroAddress() public {
        IFundsDispenser.FundsRequestConfig memory config =
            dispenser.newFundsRequestConfig(2e15, DAYS_1, 3e17, WEEKS_4, 1e15);

        // ASSERT: zero address is rejected.
        vm.expectRevert(IFundsDispenser.EmptyAddress.selector);
        vm.prank(ADMIN);
        dispenser.registerConfig(address(0), config);
    }

    function test_RegisterUser_InvalidConfig_ZeroAmount() public {
        IFundsDispenser.FundsRequestConfig memory config =
            IFundsDispenser.FundsRequestConfig(0, DAYS_1, 3e17, WEEKS_4, 1e15);

        // ASSERT: the configuration is invalid and registration fails.
        assertFalse(dispenser.validateConfig(config));

        vm.expectRevert(IFundsDispenser.InvalidConfig.selector);
        vm.prank(ADMIN);
        dispenser.registerConfig(REGISTERED_USER, config);
    }

    function test_RegisterUser_InvalidConfig_AmountAboveEpochLimit() public {
        IFundsDispenser.FundsRequestConfig memory config =
            IFundsDispenser.FundsRequestConfig(3e17 + 1, DAYS_1, 3e17, WEEKS_4, 1e15);

        // ASSERT: the configuration is invalid and registration fails.
        assertFalse(dispenser.validateConfig(config));

        vm.expectRevert(IFundsDispenser.InvalidConfig.selector);
        vm.prank(ADMIN);
        dispenser.registerConfig(REGISTERED_USER, config);
    }

    function test_RegisterUser_InvalidConfig_ZeroEpochDuration() public {
        IFundsDispenser.FundsRequestConfig memory config = IFundsDispenser.FundsRequestConfig(2e15, 0, 3e17, 0, 1e15);

        // ASSERT: the configuration is invalid and registration fails.
        assertFalse(dispenser.validateConfig(config));

        vm.expectRevert(IFundsDispenser.InvalidConfig.selector);
        vm.prank(ADMIN);
        dispenser.registerConfig(REGISTERED_USER, config);
    }

    function test_RegisterUser_InvalidConfig_CooldownNotBelowEpoch() public {
        IFundsDispenser.FundsRequestConfig memory config =
            IFundsDispenser.FundsRequestConfig(2e15, WEEKS_4, 3e17, WEEKS_4, 1e15);

        // ASSERT: the configuration is invalid and registration fails.
        assertFalse(dispenser.validateConfig(config));

        vm.expectRevert(IFundsDispenser.InvalidConfig.selector);
        vm.prank(ADMIN);
        dispenser.registerConfig(REGISTERED_USER, config);
    }

    function test_RegisterUser_InvalidConfig_ZeroThreshold() public {
        IFundsDispenser.FundsRequestConfig memory config =
            IFundsDispenser.FundsRequestConfig(2e15, DAYS_1, 3e17, WEEKS_4, 0);

        // ASSERT: the configuration is invalid and registration fails.
        assertFalse(dispenser.validateConfig(config));

        vm.expectRevert(IFundsDispenser.InvalidConfig.selector);
        vm.prank(ADMIN);
        dispenser.registerConfig(REGISTERED_USER, config);
    }

    function test_RegisterUser_ResetsPayoutInfo() public {
        _requestFunds(REGISTERED_USER);
        assertEq(dispenser.getPayoutInfo(REGISTERED_USER).amount, 2e15);

        IFundsDispenser.FundsRequestConfig memory config =
            dispenser.newFundsRequestConfig(2e15, DAYS_1, 3e17, WEEKS_4, 1e15);

        // ACT: admin registers the same account again, one hour later.
        vm.warp(vm.getBlockTimestamp() + 1 hours);
        vm.prank(ADMIN);
        dispenser.registerConfig(REGISTERED_USER, config);

        // ASSERT: payout info is reset and the registration time is updated.
        IFundsDispenser.PayoutInfo memory payoutInfo = dispenser.getPayoutInfo(REGISTERED_USER);
        assertEq(payoutInfo.amount, 0);
        assertEq(payoutInfo.epoch, 0);
        assertEq(payoutInfo.lastPayout, 0);
        assertEq(dispenser.getRegistrationUpdatedAt(REGISTERED_USER), vm.getBlockTimestamp());
    }

    function test_RemoveRequester_FailsForNonAdmin() public {
        // ASSERT: non-admin cannot remove.
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                REGISTERED_USER,
                dispenser.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(REGISTERED_USER);
        dispenser.removeRequester(REGISTERED_USER);
    }

    function test_RemoveRequester_NotRegistered() public {
        // ASSERT: removing an unregistered account reverts.
        vm.expectRevert(abi.encodeWithSelector(IFundsDispenser.NotRegistered.selector, NOT_REGISTERED_USER));
        vm.prank(ADMIN);
        dispenser.removeRequester(NOT_REGISTERED_USER);
    }

    function test_RemoveRequester_Success() public {
        // ASSERT: admin can remove.
        vm.expectEmit();
        emit IFundsDispenser.RegistrationRemoved(REGISTERED_USER);
        vm.prank(ADMIN);
        dispenser.removeRequester(REGISTERED_USER);

        // ASSERT: all registration state is cleared.
        assertEq(dispenser.getRegistrationUpdatedAt(REGISTERED_USER), 0);

        IFundsDispenser.PayoutInfo memory payoutInfo = dispenser.getPayoutInfo(REGISTERED_USER);
        assertEq(payoutInfo.amount, 0);
        assertEq(payoutInfo.epoch, 0);
        assertEq(payoutInfo.lastPayout, 0);

        assertFalse(dispenser.validateConfig(dispenser.getFundsRequestConfig(REGISTERED_USER)));
    }

    function test_RequestFunds_Fail_NotRegistered() public {
        // ASSERT: unregistered account should revert
        vm.expectRevert(abi.encodeWithSelector(IFundsDispenser.NotRegistered.selector, NOT_REGISTERED_USER));
        vm.prank(NOT_REGISTERED_USER);
        dispenser.requestFunds(NOT_REGISTERED_USER);
    }

    function test_RequestFunds_Fail_AfterRemoval() public {
        vm.prank(ADMIN);
        dispenser.removeRequester(REGISTERED_USER);

        // ASSERT: removed account should revert with NotRegistered.
        vm.expectRevert(abi.encodeWithSelector(IFundsDispenser.NotRegistered.selector, REGISTERED_USER));
        vm.prank(REGISTERED_USER);
        dispenser.requestFunds(REGISTERED_USER);
    }

    function test_RequestFunds_Success() public {
        // ASSERT: registered accounts can request funds
        _requestFunds(REGISTERED_USER);
    }

    function test_RequestFunds_ByThirdParty() public {
        uint256 requesterBalancePre = REGISTERED_USER.balance;
        uint256 callerBalancePre = NOT_REGISTERED_USER.balance;

        IFundsDispenser.FundsRequestConfig memory config = dispenser.getFundsRequestConfig(REGISTERED_USER);

        // ACT: a third party requests funds for the registered account.
        vm.expectEmit();
        emit IFundsDispenser.FundsDistributed(REGISTERED_USER, config.amount);
        vm.prank(NOT_REGISTERED_USER);
        dispenser.requestFunds(REGISTERED_USER);

        // ASSERT: funds go to the requester, not to the caller.
        assertEq(REGISTERED_USER.balance, requesterBalancePre + config.amount);
        assertEq(NOT_REGISTERED_USER.balance, callerBalancePre);
        assertEq(dispenser.getPayoutInfo(REGISTERED_USER).lastPayout, block.timestamp);
    }

    function test_RequestFunds_ResetsAfterInterval() public {
        IFundsDispenser.FundsRequestConfig memory config = dispenser.getFundsRequestConfig(REGISTERED_USER);

        uint256 timestampAfterCooldown = vm.getBlockTimestamp() + config.cooldown;
        vm.warp(timestampAfterCooldown);

        // ACT: set the paid out amount close to the limit, but outside of cooldown window to limit on amount, not time.
        IFundsDispenser.PayoutInfo memory closeToLimit = IFundsDispenser.PayoutInfo(
            config.grantedFundsPerEpoch - config.amount + 1, // this will tip the amount 1 wei over the limit
            0,
            vm.getBlockTimestamp() - config.cooldown // this will allow claiming based on cooldown
        );

        dispenser.setPayoutInfo(REGISTERED_USER, closeToLimit);

        vm.expectRevert(
            abi.encodeWithSelector(IFundsDispenser.LimitReached.selector, REGISTERED_USER, config.grantedFundsPerEpoch)
        );
        vm.prank(REGISTERED_USER);
        dispenser.requestFunds(REGISTERED_USER);

        // ASSERT: after epoch end it should be possible to request funds again. We're testing multiple epochs passing here.
        uint256 timestampAfterInterval = vm.getBlockTimestamp() + 2 * config.epochDuration;
        vm.warp(timestampAfterInterval);

        _requestFunds(REGISTERED_USER);

        // ASSERT: payout info has been updated accordingly
        IFundsDispenser.PayoutInfo memory payoutInfoPostEpoch = dispenser.getPayoutInfo(REGISTERED_USER);
        assertEq(payoutInfoPostEpoch.amount, config.amount); // after the epoch the amount should be reset to zero and then only show the one requested amount.
        assertEq(payoutInfoPostEpoch.lastPayout, block.timestamp);
        assertEq(payoutInfoPostEpoch.epoch, 2); // check that the epoch was bumped and not only incremented.
    }

    function test_RequestFunds_RevertsOnReentrancy() public {
        address sink = makeAddr("sink");
        ReentrantRequester attacker = new ReentrantRequester(dispenser, sink);

        // ACT: register the mock as a requester.
        IFundsDispenser.FundsRequestConfig memory attackerConfig =
            dispenser.newFundsRequestConfig(2e15, DAYS_1, 3e17, WEEKS_4, 1e15);

        vm.prank(ADMIN);
        dispenser.registerConfig(address(attacker), attackerConfig);

        uint256 dispenserBalancePre = address(dispenser).balance;

        // ASSERT: the inner request reverts, so the outer payout fails.
        vm.expectRevert(abi.encodeWithSelector(IFundsDispenser.FailedToSend.selector, address(attacker), 2e15));
        attacker.attack();

        // ASSERT: no funds have left the dispenser.
        assertEq(address(dispenser).balance, dispenserBalancePre);
        assertEq(sink.balance, 0);
    }

    function test_Receive_AcceptsFunds() public {
        address funder = makeAddr("funder");
        vm.deal(funder, 1 ether);

        uint256 balancePre = address(dispenser).balance;

        // ASSERT: plain transfers emit the event.
        vm.expectEmit();
        emit IFundsDispenser.Funded(funder, 1 ether);

        vm.prank(funder);
        (bool ok,) = address(dispenser).call{value: 1 ether}("");

        // ASSERT: transfer succeeds and balance increases.
        assertTrue(ok);
        assertEq(address(dispenser).balance, balancePre + 1 ether);
    }

    function test_Fallback_Reverts() public {
        address funder = makeAddr("funder");
        vm.deal(funder, 1 ether);

        uint256 balancePre = address(dispenser).balance;

        // ASSERT: calls with data revert, as there is no fallback.
        vm.prank(funder);
        (bool ok,) = address(dispenser).call{value: 1 ether}(hex"deadbeef");

        assertFalse(ok);
        assertEq(address(dispenser).balance, balancePre);
    }

    function test_Withdraw_Success() public {
        address to = makeAddr("treasury");

        uint256 dispenserBalancePre = address(dispenser).balance;
        uint256 toBalancePre = to.balance;

        // ACT: admin withdraws.
        vm.expectEmit();
        emit IFundsDispenser.Withdrawn(to, 5e17);
        vm.prank(ADMIN);
        dispenser.withdraw(to, 5e17);

        // ASSERT: balances moved by exactly the amount.
        assertEq(address(dispenser).balance, dispenserBalancePre - 5e17);
        assertEq(to.balance, toBalancePre + 5e17);
    }

    function test_Withdraw_FailsForNonAdmin() public {
        // ASSERT: non-admin cannot withdraw.
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                REGISTERED_USER,
                dispenser.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(REGISTERED_USER);
        dispenser.withdraw(REGISTERED_USER, 1);
    }

    function test_Withdraw_RevertsOnZeroAddress() public {
        // ASSERT: zero address is rejected.
        vm.expectRevert(IFundsDispenser.EmptyAddress.selector);
        vm.prank(ADMIN);
        dispenser.withdraw(address(0), 1);
    }

    function test_Withdraw_RevertsOnInsufficientBalance() public {
        address to = makeAddr("treasury");
        uint256 amount = address(dispenser).balance + 1;

        // ASSERT: withdrawing more than the balance reverts.
        vm.expectRevert(abi.encodeWithSelector(IFundsDispenser.FailedToSend.selector, to, amount));
        vm.prank(ADMIN);
        dispenser.withdraw(to, amount);
    }

    function test_Withdraw_RevertsOnRejectingReceiver() public {
        RejectingReceiver receiver = new RejectingReceiver();

        // ASSERT: a receiver that rejects native tokens reverts the withdrawal.
        vm.expectRevert(abi.encodeWithSelector(IFundsDispenser.FailedToSend.selector, address(receiver), 1));
        vm.prank(ADMIN);
        dispenser.withdraw(address(receiver), 1);
    }

    function test_Pause_BlocksRequestFunds() public {
        // ACT: admin pauses.
        vm.expectEmit();
        emit Pausable.Paused(ADMIN);
        vm.prank(ADMIN);
        dispenser.pause();

        // ASSERT: funds requests revert while paused.
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(REGISTERED_USER);
        dispenser.requestFunds(REGISTERED_USER);
    }

    function test_Pause_FailsWithoutRole() public {
        // ASSERT: an account without `PAUSER_ROLE` cannot pause.
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, REGISTERED_USER, dispenser.PAUSER_ROLE()
            )
        );
        vm.prank(REGISTERED_USER);
        dispenser.pause();
    }

    function test_Unpause_FailsForPauser() public {
        address pauser = makeAddr("pauser");
        bytes32 pauserRole = dispenser.PAUSER_ROLE();

        // ACT: admin grants `PAUSER_ROLE` and the pauser pauses.
        vm.prank(ADMIN);
        dispenser.grantRole(pauserRole, pauser);

        vm.prank(pauser);
        dispenser.pause();

        // ASSERT: the pauser cannot unpause.
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, pauser, dispenser.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(pauser);
        dispenser.unpause();
    }

    function test_Unpause_RestoresRequestFunds() public {
        vm.prank(ADMIN);
        dispenser.pause();

        // ACT: admin unpauses.
        vm.expectEmit();
        emit Pausable.Unpaused(ADMIN);
        vm.prank(ADMIN);
        dispenser.unpause();

        // ASSERT: funds requests work again.
        _requestFunds(REGISTERED_USER);
    }

    function test_Withdraw_WorksWhilePaused() public {
        address to = makeAddr("treasury");

        vm.prank(ADMIN);
        dispenser.pause();

        // ACT: admin withdraws while paused.
        vm.prank(ADMIN);
        dispenser.withdraw(to, 1e17);

        // ASSERT: the funds arrived.
        assertEq(to.balance, 1e17);
    }

    function test_RequestFunds_Fail_BalanceTooHigh() public {
        vm.deal(REGISTERED_USER, 1e15 + 1);

        // ASSERT: a balance above the threshold is rejected.
        vm.expectRevert(abi.encodeWithSelector(IFundsDispenser.BalanceTooHigh.selector, REGISTERED_USER, 1e15 + 1));
        vm.prank(REGISTERED_USER);
        dispenser.requestFunds(REGISTERED_USER);
    }

    function test_RequestFunds_Fail_CooldownNotElapsed() public {
        _requestFunds(REGISTERED_USER);

        // ACT: the bot spends its funds, then one second remains in the cooldown.
        vm.deal(REGISTERED_USER, 0);
        vm.warp(vm.getBlockTimestamp() + DAYS_1 - 1);

        // ASSERT: a request inside the cooldown is rejected.
        vm.expectRevert(
            abi.encodeWithSelector(IFundsDispenser.CooldownNotElapsed.selector, REGISTERED_USER, DAYS_1, DAYS_1 - 1)
        );
        vm.prank(REGISTERED_USER);
        dispenser.requestFunds(REGISTERED_USER);
    }

    function test_RequestFunds_SucceedsAtCooldownBoundary() public {
        _requestFunds(REGISTERED_USER);

        // ACT: the bot spends its funds, then the cooldown ends exactly now.
        vm.deal(REGISTERED_USER, 0);
        vm.warp(vm.getBlockTimestamp() + DAYS_1);

        // ASSERT: a request at the cooldown boundary succeeds.
        _requestFunds(REGISTERED_USER);
    }

    function testFuzz_RegisterConfig_StoresValidConfig(
        uint256 amount,
        uint256 cooldown,
        uint256 granted,
        uint256 epochDuration,
        uint256 threshold
    ) public {
        // ARRANGE: bound the inputs to a valid config.
        epochDuration = bound(epochDuration, 2, 365 days);
        cooldown = bound(cooldown, 0, epochDuration - 1);
        granted = bound(granted, 1, 1e24);
        amount = bound(amount, 1, granted);
        threshold = bound(threshold, 1, 1e24);

        IFundsDispenser.FundsRequestConfig memory config =
            IFundsDispenser.FundsRequestConfig(amount, cooldown, granted, epochDuration, threshold);
        assertTrue(dispenser.validateConfig(config));

        // ACT: admin registers the config.
        address user = makeAddr("fuzzUser");
        vm.prank(ADMIN);
        dispenser.registerConfig(user, config);

        // ASSERT: the stored config equals the input.
        IFundsDispenser.FundsRequestConfig memory stored = dispenser.getFundsRequestConfig(user);
        assertEq(stored.amount, amount);
        assertEq(stored.cooldown, cooldown);
        assertEq(stored.grantedFundsPerEpoch, granted);
        assertEq(stored.epochDuration, epochDuration);
        assertEq(stored.thresholdBalance, threshold);
    }

    function testFuzz_RequestFunds_Cooldown(uint256 elapsed) public {
        _requestFunds(REGISTERED_USER);

        // ACT: the bot spends its funds, then time passes inside the first epoch.
        vm.deal(REGISTERED_USER, 0);
        elapsed = bound(elapsed, 0, WEEKS_4 - DAYS_1 - 1);
        vm.warp(vm.getBlockTimestamp() + elapsed);

        if (elapsed < DAYS_1) {
            // ASSERT: a request inside the cooldown is rejected.
            vm.expectRevert(
                abi.encodeWithSelector(IFundsDispenser.CooldownNotElapsed.selector, REGISTERED_USER, DAYS_1, elapsed)
            );
            vm.prank(REGISTERED_USER);
            dispenser.requestFunds(REGISTERED_USER);
        } else {
            // ASSERT: a request after the cooldown succeeds.
            _requestFunds(REGISTERED_USER);
        }
    }

    // -------------------------------------------------------
    //                        HELPERS
    // -------------------------------------------------------

    function _requestFunds(address sender) internal {
        uint256 balancePre = sender.balance;

        IFundsDispenser.FundsRequestConfig memory senderConfig = dispenser.getFundsRequestConfig(sender);

        vm.expectEmit();
        emit IFundsDispenser.FundsDistributed(sender, senderConfig.amount);

        vm.prank(sender);
        dispenser.requestFunds(sender);

        // ASSERT: balance has changed
        assert(sender.balance == balancePre + senderConfig.amount);

        // ASSERT: payout info should be updated with last claim (other values depend on external factors so we're not asserting them here).
        assertEq(dispenser.getPayoutInfo(sender).lastPayout, vm.getBlockTimestamp());
    }
}
