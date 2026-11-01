// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IFundsDispenser} from "./IFundsDispenser.sol";

/**
 * @title FundsDispenser
 * @author M0 Engineering Team
 * @notice This contract is intended to provide known bot accounts with recurring funding
 *         for them to operate normally without having to hold large quantities of funds,
 *         while keeping operational burdens low for the Engineering team.
 * @dev TODO: move behind proxy?
 * @dev TODO: create ERC-7201 storage pattern
 * @dev TODO: add lastClaimed and a cooldown period to avoid potential exploits
 */
contract FundsDispenser is IFundsDispenser, ReentrancyGuard {
    // ---------------------------------------------------------------------------
    //                                 STATE
    // ---------------------------------------------------------------------------

    /// The contract's admin.
    address private _admin;

    /// The map of approved funds request configs per address.
    mapping(address => FundsRequestConfig) internal _approvedRequestConfigs;

    /// The map of summed payout amounts per address.
    mapping(address => PayoutInfo) internal _payoutInfo;

    /// The map of timestamps of last registration update per address.
    mapping(address => uint256) internal _registrationUpdatedAt;

    // ---------------------------------------------------------------------------
    //                               CONSTRUCTOR
    // ---------------------------------------------------------------------------

    /**
     * @notice Constructs a new instance of the contract.
     * @param admin The address of the admin authority, able to register,
     *                 and de-register funds requesters.
     */
    constructor(address admin) {
        if (admin == address(0)) {
            revert EmptyAddress();
        }

        _admin = admin;
    }

    // ---------------------------------------------------------------------------
    //                                 MODIFIER
    // ---------------------------------------------------------------------------

    /**
     * @notice Ensures admin authority for safety related features.
     */
    modifier onlyAdmin() {
        if (msg.sender != _admin) {
            revert Unauthorized();
        }
        _;
    }

    // ---------------------------------------------------------------------------
    //                              EXTERNAL FUNCTIONS
    // ---------------------------------------------------------------------------

    /**
     * @notice Accepts native tokens to fund the dispenser.
     */
    receive() external payable {
        emit Funded(msg.sender, msg.value);
    }

    /**
     * @inheritdoc IFundsDispenser
     */
    function requestFunds() external nonReentrant {
        address requester = msg.sender;
        if (_registrationUpdatedAt[requester] == 0) {
            revert NotRegistered(requester);
        }

        FundsRequestConfig memory config = _approvedRequestConfigs[requester];
        PayoutInfo memory payoutInfo = _payoutInfo[requester];

        // TODO: use SafeMath here?
        // The epoch update has to happen first to reset the limits before validating the request.
        uint256 currentEpoch = (block.timestamp - _registrationUpdatedAt[requester]) / config.epochDuration;
        _updateEpoch(requester, currentEpoch - payoutInfo.epoch);

        _validateRequest(requester, config);

        _updateRequestsMade(requester, config.amount);

        emit FundsDistributed(requester, config.amount);

        (bool sent,) = requester.call{value: config.amount}("");
        if (!sent) {
            revert FailedToSend(requester, config.amount);
        }
    }

    /**
     * @inheritdoc IFundsDispenser
     */
    function registerConfig(address requester, FundsRequestConfig calldata config) external onlyAdmin {
        if (requester == address(0)) {
            revert EmptyAddress();
        }

        if (!_validateConfig(config)) {
            revert InvalidConfig();
        }

        _approvedRequestConfigs[requester] = config;
        _payoutInfo[requester] = PayoutInfo(0, 0, 0);
        _registrationUpdatedAt[requester] = block.timestamp;

        emit RegistrationUpdated(requester);
    }

    /**
     * @inheritdoc IFundsDispenser
     */
    function removeRequester(address requester) external onlyAdmin {
        if (_registrationUpdatedAt[requester] == 0) {
            revert NotRegistered(requester);
        }

        delete _approvedRequestConfigs[requester];
        delete _payoutInfo[requester];
        delete _registrationUpdatedAt[requester];

        emit RegistrationRemoved(requester);
    }

    // ---------------------------------------------------------------------------
    //                               INTERNAL FUNCTIONS
    // ---------------------------------------------------------------------------

    /**
     * @notice Validates if the provided configuration for a requesting Bot account is correct.
     * @param config The configuration to validate.
     * @return valid A boolean value whether the configuration is valid or not.
     */
    function _validateConfig(FundsRequestConfig memory config) internal pure returns (bool) {
        if (config.grantedFundsPerEpoch == 0) return false;

        // NOTE: the amount per payout must not be greater than the total granted funds per duration.
        if (config.amount == 0 || config.amount > config.grantedFundsPerEpoch) {
            return false;
        }

        if (config.epochDuration == 0) return false;

        // NOTE: we currently don't accept cooldown periods longer than the interval.
        if (config.cooldown >= config.epochDuration) return false;

        if (config.thresholdBalance == 0) return false;

        return true;
    }

    /**
     * @notice Validates the funds request and reverts the transaction if e.g. the
     *         funds limit per epoch is reached.
     * @param requester The address receiving the gas tokens.
     * @param config The configuration to validate the request against.
     */
    function _validateRequest(address requester, FundsRequestConfig memory config) internal view {
        uint256 bal = requester.balance;
        if (bal > config.thresholdBalance) {
            revert BalanceTooHigh(requester, bal);
        }

        // Only check for cooldown if there has already been a payout.
        PayoutInfo memory payoutInfo = _payoutInfo[requester];
        if (payoutInfo.lastPayout > 0) {
            uint256 elapsed = block.timestamp - payoutInfo.lastPayout;
            // Cooldown is time based by design.
            // forge-lint: disable-next-line(block-timestamp)
            if (elapsed < config.cooldown) {
                revert CooldownNotElapsed(requester, config.cooldown, elapsed);
            }
        }

        if (payoutInfo.amount + config.amount > config.grantedFundsPerEpoch) {
            revert LimitReached(requester, config.grantedFundsPerEpoch);
        }
    }

    /**
     * @notice Updates to a new epoch for a given address.
     * @dev No-ops in case no epoch has passed.
     * @param requester The address whose epoch is updated.
     * @param n The number of epochs to increase.
     */
    function _updateEpoch(address requester, uint256 n) internal {
        // no-op in case 0 is passed.
        if (n == 0) return;

        PayoutInfo storage updatedPayoutInfo = _payoutInfo[requester];
        updatedPayoutInfo.amount = 0;
        updatedPayoutInfo.epoch += n;

        // TODO: emit Epoch event?
    }

    /**
     * @notice Updates the storage to reflect successful funds requests.
     * @param requester The address that successfully requested funds.
     * @param amount The amount that was sent.
     */
    function _updateRequestsMade(address requester, uint256 amount) internal {
        PayoutInfo storage updatedPayoutInfo = _payoutInfo[requester];
        updatedPayoutInfo.lastPayout = block.timestamp;
        updatedPayoutInfo.amount += amount;
    }
}
