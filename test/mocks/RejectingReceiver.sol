// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.38;

/**
 * @notice Mock account with no `receive` and no `fallback`. Native token transfers to it fail.
 */
contract RejectingReceiver {}
