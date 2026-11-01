// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";

import {
    IAccessControlDefaultAdminRules
} from "@openzeppelin/contracts/access/extensions/IAccessControlDefaultAdminRules.sol";

import {DeployFundsDispenser} from "../script/Deploy.s.sol";
import {FundsDispenser} from "../src/FundsDispenser.sol";

contract DeployTest is Test {
    // `vm.setEnv` changes the env of the whole process. Tests run in parallel,
    // so two tests that set `ADMIN` race. Keep all cases in one test.
    function test_Run() public {
        // The deployment of the script is a call too. Deploy it before `vm.expectRevert`.
        DeployFundsDispenser script = new DeployFundsDispenser();

        // ACT: run the deploy script with a valid admin.
        address admin = makeAddr("multisig");
        vm.setEnv("ADMIN", vm.toString(admin));
        FundsDispenser dispenser = script.run();

        // ASSERT: the admin holds both roles and the initial delay is set.
        assertEq(dispenser.defaultAdmin(), admin);
        assertTrue(dispenser.hasRole(dispenser.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(dispenser.hasRole(dispenser.PAUSER_ROLE(), admin));
        assertEq(dispenser.defaultAdminDelay(), dispenser.INITIAL_ADMIN_DELAY());

        // ASSERT: zero admin is rejected. Keep this case last. The revert leaves the broadcast active.
        vm.setEnv("ADMIN", vm.toString(address(0)));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControlDefaultAdminRules.AccessControlInvalidDefaultAdmin.selector, address(0)
            )
        );
        script.run();
    }
}
