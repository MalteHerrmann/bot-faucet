// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";

import {FundsDispenserHarness} from "./FundsDispenserHarness.sol";
import {IFundsDispenser} from "../src/IFundsDispenser.sol";

/**
 * @notice The handler for invariant tests. It calls the dispenser and records ghost state.
 */
contract RequesterHandler is Test {
    FundsDispenserHarness public immutable dispenser;

    address[] internal requesters;

    /// The sum of all native tokens paid out by the dispenser.
    uint256 public ghost_totalPaid;

    /// The amount paid per requester and epoch.
    mapping(address => mapping(uint256 => uint256)) public ghost_paidInEpoch;

    /// The timestamp of the last payout per requester.
    mapping(address => uint256) public ghost_lastPayout;

    /// Set to true when a payout happens inside the cooldown.
    bool public ghost_cooldownViolated;

    /// The epochs with at least one payout per requester.
    mapping(address => uint256[]) internal ghost_epochsSeen;

    constructor(FundsDispenserHarness dispenser_, address[] memory requesters_) {
        dispenser = dispenser_;
        requesters = requesters_;
    }

    /**
     * @notice Requests funds for a random requester and records the payout.
     */
    function requestFunds(uint256 seed) external {
        address requester = requesters[seed % requesters.length];

        uint256 registeredAt = dispenser.getRegistrationUpdatedAt(requester);
        IFundsDispenser.FundsRequestConfig memory config = dispenser.getFundsRequestConfig(requester);
        uint256 balanceBefore = requester.balance;

        try dispenser.requestFunds(requester) {
            uint256 paid = requester.balance - balanceBefore;
            uint256 epoch = (block.timestamp - registeredAt) / config.epochDuration;

            // A first payout in an epoch has no recorded amount yet.
            if (ghost_paidInEpoch[requester][epoch] == 0) ghost_epochsSeen[requester].push(epoch);
            ghost_paidInEpoch[requester][epoch] += paid;
            ghost_totalPaid += paid;

            uint256 last = ghost_lastPayout[requester];
            if (last != 0 && block.timestamp - last < config.cooldown) ghost_cooldownViolated = true;
            ghost_lastPayout[requester] = block.timestamp;
        } catch {}
    }

    /**
     * @notice Sets the balance of a random requester to zero. This simulates a bot that uses its gas.
     */
    function spend(uint256 seed) external {
        vm.deal(requesters[seed % requesters.length], 0);
    }

    /**
     * @notice Moves time forward by 1 second up to 3 days.
     */
    function warp(uint256 secs) external {
        secs = bound(secs, 1, 3 days);
        vm.warp(block.timestamp + secs);
    }

    /**
     * @notice Returns the epochs with at least one payout for a requester.
     */
    function getEpochsSeen(address requester) external view returns (uint256[] memory) {
        return ghost_epochsSeen[requester];
    }
}

/**
 * @notice The invariant tests for `FundsDispenser`.
 */
contract FundsDispenserInvariants is Test {
    FundsDispenserHarness public dispenser;
    RequesterHandler public handler;

    address public immutable ADMIN = makeAddr("ADMIN");

    address[] internal requesters;
    uint256 internal initialBalance;

    function setUp() public {
        dispenser = new FundsDispenserHarness(ADMIN);
        vm.deal(address(dispenser), 1_000_000 ether);
        initialBalance = address(dispenser).balance;

        requesters.push(makeAddr("REQUESTER_A"));
        requesters.push(makeAddr("REQUESTER_B"));
        requesters.push(makeAddr("REQUESTER_C"));

        // ARRANGE: register three requesters with different configs.
        vm.startPrank(ADMIN);
        // A: one payout per day, many payouts per epoch.
        dispenser.registerConfig(requesters[0], IFundsDispenser.FundsRequestConfig(2e15, 1 days, 3e17, 28 days, 1e15));
        // B: no cooldown, two payouts per epoch.
        dispenser.registerConfig(requesters[1], IFundsDispenser.FundsRequestConfig(1e17, 0, 25e16, 7 days, 5e16));
        // C: one payout per epoch.
        dispenser.registerConfig(requesters[2], IFundsDispenser.FundsRequestConfig(1e18, 6 hours, 1e18, 1 days, 1e17));
        vm.stopPrank();

        handler = new RequesterHandler(dispenser, requesters);
        targetContract(address(handler));
    }

    /// @notice The paid amount in any epoch never exceeds the granted funds per epoch.
    function invariant_EpochLimitNeverExceeded() public view {
        for (uint256 i; i < requesters.length; ++i) {
            address requester = requesters[i];
            uint256 limit = dispenser.getFundsRequestConfig(requester).grantedFundsPerEpoch;
            uint256[] memory epochs = handler.getEpochsSeen(requester);

            for (uint256 j; j < epochs.length; ++j) {
                assertLe(handler.ghost_paidInEpoch(requester, epochs[j]), limit);
            }
        }
    }

    /// @notice Two payouts to one requester are never closer than the cooldown.
    function invariant_CooldownRespected() public view {
        assertFalse(handler.ghost_cooldownViolated());
    }

    /// @notice The dispenser balance equals the initial balance minus all payouts.
    function invariant_BalanceMatchesLedger() public view {
        assertEq(address(dispenser).balance, initialBalance - handler.ghost_totalPaid());
    }
}
