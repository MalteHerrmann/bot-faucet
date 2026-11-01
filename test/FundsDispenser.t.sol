// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {console} from "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";

import {FundsDispenserHarness} from "./FundsDispenserHarness.sol";
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

    function test_RegisterUser_FailsForNonAdmin() public {
        IFundsDispenser.FundsRequestConfig memory bobConfig =
            dispenser.newFundsRequestConfig(2e15, DAYS_1, 3e17, WEEKS_4, 1e15);

        // ASSERT: non-admin cannot register.
        vm.expectRevert(IFundsDispenser.Unauthorized.selector);
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
        emit IFundsDispenser.RegistrationUpdated(newUser);
        vm.prank(ADMIN);
        dispenser.registerConfig(newUser, newConfig);

        // ASSERT: new config is registered and is stored correctly.
        IFundsDispenser.FundsRequestConfig memory retrievedConfig = dispenser.getFundsRequestConfig(newUser);
        assertEq32(keccak256(abi.encode(retrievedConfig)), keccak256(abi.encode(newConfig)));
        assertEq(dispenser.getRegistrationUpdatedAt(newUser), block.timestamp);
    }

    function test_RequestFunds_Fail_NotRegistered() public {
        // ASSERT: unregistered account should revert
        vm.expectRevert(abi.encodeWithSelector(IFundsDispenser.NotRegistered.selector, NOT_REGISTERED_USER));
        vm.prank(NOT_REGISTERED_USER);
        dispenser.requestFunds();
    }

    function test_RequestFunds_Success() public {
        // ASSERT: registered accounts can request funds
        _requestFunds(REGISTERED_USER);
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
        dispenser.requestFunds();

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

    // TODO: add cooldown test here.

    // -------------------------------------------------------
    //                        HELPERS
    // -------------------------------------------------------

    function _requestFunds(address sender) internal {
        uint256 balancePre = sender.balance;

        IFundsDispenser.FundsRequestConfig memory senderConfig = dispenser.getFundsRequestConfig(sender);

        vm.expectEmit();
        emit IFundsDispenser.FundsDistributed(sender, senderConfig.amount);

        vm.prank(sender);
        dispenser.requestFunds();

        // ASSERT: balance has changed
        assert(sender.balance == balancePre + senderConfig.amount);

        // ASSERT: payout info should be updated with last claim (other values depend on external factors so we're not asserting them here).
        assertEq(dispenser.getPayoutInfo(sender).lastPayout, block.timestamp);
    }
}
