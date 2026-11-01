// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Script, console} from "forge-std/Script.sol";

import {FundsDispenser} from "../src/FundsDispenser.sol";

/**
 * @notice Deploys `FundsDispenser`.
 * @dev Set the env var `ADMIN` to the engineering multisig address. The signer comes from the
 *      `forge script` command line.
 */
contract DeployFundsDispenser is Script {
    function run() external returns (FundsDispenser dispenser) {
        address admin = vm.envAddress("ADMIN");

        vm.startBroadcast();
        dispenser = new FundsDispenser(admin);
        vm.stopBroadcast();

        // Check the deployed state before reporting success.
        require(dispenser.defaultAdmin() == admin, "admin mismatch");
        require(dispenser.hasRole(dispenser.PAUSER_ROLE(), admin), "pauser role missing");

        console.log("FundsDispenser deployed at", address(dispenser));
    }
}
