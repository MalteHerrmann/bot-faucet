// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { IFundsDispenser } from "./IFundsDispenser.sol";

/**
 * @title FundsDispenser
 * @author M0 Engineering Team
 * @notice This contract is intended to provide known bot accounts with recurring funding
 *         for them to operate normally without having to hold large quantities of funds,
 *         while keeping operational burdens low for the Engineering team.
 * @dev TODO: move behind proxy?
 */
contract FundsDispenser is IFundsDispenser {
  // ---------------------------------------------------------------------------
  //                                 STATE
  // ---------------------------------------------------------------------------

  /// The contract's admin.
  address private _admin;

  /// The duration of an epoch before the faucet counter is reset.
  uint256 public epochDuration;

  /// The map of approved funds request configs.
  mapping(address => FundsRequestConfig) internal _approvedRequestConfigs;

  /// The map of summed payout amounts per bot address.
  mapping(address => uint256) internal _fundsRequestThisInterval;

  // ---------------------------------------------------------------------------
  //                               CONSTRUCTOR
  // ---------------------------------------------------------------------------

  /**
   * @notice Constructs a new instance of the contract.
   * @param admin The address of the admin authority, able to register,
                  and de-register funds requesters.
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
   * @inheritdoc IFundsDispenser
   */
  function requestFunds() external {
    address requester = msg.sender;
    FundsRequestConfig memory config = _approvedRequestConfigs[requester];
    if (!_validateBotConfig(config)) {
      revert NotRegistered(requester);
    }

    _validateRequest(requester, config);

    (bool sent, ) = requester.call{value: config.amount}("");
    if (!sent) {
      revert FailedToSend(requester, config.amount);
    }

    emit FundsDistributed(requester, config.amount);
  }

  /**
   * @inheritdoc IFundsDispenser
   */
  function registerConfig(address requester, FundsRequestConfig calldata config) external onlyAdmin {
    if (requester == address(0)) {
      revert EmptyAddress();
    }

    if (!_validateBotConfig(config)) {
      revert InvalidConfig();
    }

    _approvedRequestConfigs[requester] = config;

    emit RegistrationUpdated(requester);
  }

  /**
   * @inheritdoc IFundsDispenser
   */
  function removeRequester(address requester) external onlyAdmin {
    if (!_validateBotConfig(_approvedRequestConfigs[requester])) {
      revert NotRegistered(requester);
    }

    delete _approvedRequestConfigs[requester];

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
  function _validateBotConfig(FundsRequestConfig memory config) internal pure returns (bool) {
    if (config.grantedFundsPerDuration == 0) {
      return false;
    }

    if (config.amount == 0) {
      return false;
    }

    if (config.thresholdBalance == 0) {
      return false;
    }

    return true;
  }

  /**
   * @notice Validates the funds request and reverts the transaction if e.g. the
   *         funds limit per epoch is reached.
   * @param receiver The address receiving the gas tokens.
   * @param config The configuration to validate the request against.
   */
  function _validateRequest(address receiver, FundsRequestConfig memory config) internal view {
    uint256 bal = receiver.balance;
    if (bal > config.thresholdBalance) {
      revert BalanceTooHigh(receiver, bal);
    }

    if (_fundsRequestThisInterval[receiver] + config.amount > config.grantedFundsPerDuration) {
      revert LimitReached(receiver, config.grantedFundsPerDuration);
    }
  }
}
