// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { FundsDispenser } from "../src/FundsDispenser.sol";

/**
 * @notice The test harness providing some internal data access for ease of use.
 */
contract FundsDispenserHarness is FundsDispenser {
    constructor(address _admin) FundsDispenser(_admin) {}

    /**
     * @notice Returns the registered funds request configuration for a given address.
     * @dev Check whether the address is registered or now by validating the returned config.
     */
    function getFundsRequestConfig(address requester) external view returns (FundsRequestConfig memory) {
        return _approvedRequestConfigs[requester];
    }

    /**
     * @notice Exposes the registration time query for tests.
     */
    function getRegistrationUpdatedAt(address requester) external view returns (uint256) {
        return _registrationUpdatedAt[requester];
    }

    /**
     * @notice Exposes the payout info query for tests.
     */
    function getPayoutInfo(address requester) external view returns (PayoutInfo memory) {
        return _payoutInfo[requester];
    }

    /**
     * @notice Just a utility to create a new FundsRequestConfig.
     */
    function newFundsRequestConfig(
        uint256 amount,
        uint256 cooldown,
        uint256 grantedFundsPerEpoch,
        uint256 epochDuration,
        uint256 thresholdBalance
    ) external pure returns (FundsRequestConfig memory) {
        FundsRequestConfig memory config = FundsRequestConfig(
            amount,
            cooldown,
            grantedFundsPerEpoch,
            epochDuration,
            thresholdBalance
        );
        if(!_validateConfig(config)) revert InvalidConfig();
        return config;
    }

    /**
     * @notice Sets the payout info in storage for testing different scenarios.
     */
    function setPayoutInfo(address requester, PayoutInfo memory payoutInfo) external {
        _payoutInfo[requester] = payoutInfo;
    }

    /**
     * @notice Exposes the config validation for tests.
     */
    function validateConfig(FundsRequestConfig calldata config) external pure returns (bool) {
        return _validateConfig(config);
    }
}
