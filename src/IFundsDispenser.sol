// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

interface IFundsDispenser {
    /**
     * @notice The configuration for a given requesting account.
     */
    // TODO:  move to ERC-7201 storage
    struct FundsRequestConfig {
        /// The maximum balance an account can have before requesting funds.
        uint256 thresholdBalance;
        /// The limit of requestable funds per duration (e.g. 0.2 ETH per month).
        uint256 grantedFundsPerDuration;
        /// The amount of native tokens sent upon a successful request.
        uint256 amount;
    }

    /**
     * @notice Thrown in case the requesting bot still has too many funds in the account to request new funding.
     * @param requester The address that requests funds.
     * @param balance The balance of the account.
     */
    error BalanceTooHigh(address requester, uint256 balance);

    /**
     * @notice Thrown when trying to register an empty address.
     */
    error EmptyAddress();

    /**
     * @notice Thrown when sending funds has failed.
     * @param requester The address requesting funds.
     * @param amount The amount attempted to be sent.
     */
    error FailedToSend(address requester, uint256 amount);

    /**
     * @notice Thrown if an invalid configuration is registered.
     */
    error InvalidConfig();

    /**
     * @notice Thrown in case the given address is not registered as a receiver or the configuration is invalid.
     * @param requester The address requesting funds.
     */
    error NotRegistered(address requester);

    /**
     * @notice Thrown in case the bot has reached its limit of requestable funds per duration.
     * @param requester The address who has reached their request limit.
     * @param limit The limit of paid out funds.
     */
    error LimitReached(address requester, uint256 limit);

    /// @notice Thrown if a gated function is called by an unauthorized account.
    error Unauthorized();

    /**
     * @notice Emitted when a funds request was served.
     * @param requester The account receiving the funds.
     * @param amount The amount of tokens distributed.
     */
    event FundsDistributed(address indexed requester, uint256 amount);

    /**
     * @notice Emitted when a funds request config is added or updated.
     * @param requester The address whose request config has been updated.
     */
    event RegistrationUpdated(address indexed requester);

    /**
     * @notice Emitted when a funds request config is removed.
     * @param requester The address whose request config has been removed.
     */
    event RegistrationRemoved(address indexed requester);

    /**
     * @notice Request funds from the contract. The sender has to be registered in the contract.
     */
    function requestFunds() external;

    /**
     * @notice Registers a new account that can request funds.
     * @param requester The address of the requesting account.
     * @param config The configuration for requests.
     */
    function registerConfig(address requester, FundsRequestConfig calldata config) external;

    /**
     * @notice Removes a requesting accounts' configuration.
     * @param requester The address of the account to be removed.
     */
    function removeRequester(address requester) external;
}