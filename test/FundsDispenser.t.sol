// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { Test } from "forge-std/Test.sol";

import {FundsDispenser} from "../src/FundsDispenser.sol";
import {IFundsDispenser} from "../src/IFundsDispenser.sol";

contract FundsDispenserTest is Test {
  FundsDispenser public dispenser;

  address public immutable ADMIN = makeAddr("ADMIN");
  address public immutable ALICE = makeAddr("ALICE");

  function setUp() public {
    dispenser = new FundsDispenser(ADMIN);
    vm.deal(address(dispenser), 1e18);
  }

  function test_RequestFunds_Invalid() public {
    // ASSERT: unregistered account should revert
    vm.expectRevert(
      abi.encodeWithSelector(IFundsDispenser.NotRegistered.selector, ALICE)
    );
    vm.prank(ALICE);
    dispenser.requestFunds();
  }

  function test_RequestFunds_Success() public {
    // ACT: register ALICE
    IFundsDispenser.FundsRequestConfig memory aliceConfig = IFundsDispenser.FundsRequestConfig(
      2e15,
      2e17,
      3e15
    );

    // ASSERT: non-admin cannot register.
    vm.expectRevert(IFundsDispenser.Unauthorized.selector);
    vm.prank(ALICE);
    dispenser.registerConfig(ALICE, aliceConfig);

    // ASSERT: admin can register.
    vm.expectEmit();
    emit IFundsDispenser.RegistrationUpdated(ALICE);
    vm.prank(ADMIN);
    dispenser.registerConfig(ALICE, aliceConfig);

    // ASSERT: registered accounts can request funds
    uint256 balancePre = ALICE.balance;

    vm.expectEmit();
    emit IFundsDispenser.FundsDistributed(ALICE, aliceConfig.amount);

    vm.prank(ALICE);
    dispenser.requestFunds();

    // ASSERT: balance has changed
    assert(ALICE.balance == balancePre + aliceConfig.amount);
  }
}
