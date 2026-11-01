// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {FundsDispenser} from "../../src/FundsDispenser.sol";

/**
 * @notice Mock requester that re-enters `requestFunds` and forwards each payout to a sink.
 */
contract ReentrantRequester {
    FundsDispenser public immutable dispenser;
    address public immutable sink;

    bool private _reentered;

    constructor(FundsDispenser dispenser_, address sink_) {
        dispenser = dispenser_;
        sink = sink_;
    }

    function attack() external {
        dispenser.requestFunds();
    }

    // Forward the payout to the sink, then re-enter once.
    // One re-entry only. Endless re-entry ends in a revert and hides a missing guard.
    receive() external payable {
        (bool sent,) = sink.call{value: msg.value}("");
        require(sent);

        if (_reentered) return;
        _reentered = true;
        dispenser.requestFunds();
    }
}
