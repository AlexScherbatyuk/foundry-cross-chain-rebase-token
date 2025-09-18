// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {MockContract} from "./Mocks/MockContract.sol";

contract RebaseTokenTest is Test {
    RebaseToken private rebaseToken;
    Vault private vault;

    address public owner = makeAddr("onwer");
    address public user = makeAddr("user");

    function setUp() public {
        //vm.deal(owner, 100 ether);
        vm.startPrank(owner);
        rebaseToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(rebaseToken)));
        rebaseToken.grantMintAndBurnRole(address(vault));
        // (bool success,) = payable(address(vault)).call{value: 1e18}("");
        // assertTrue(success);
        vm.stopPrank();
    }
    /*//////////////////////////////////////////////////////////////
                                REWARDS
    //////////////////////////////////////////////////////////////*/

    function addRewardsToVault(uint256 amount) public {
        // send some rewards to the vault using the receive function
        (bool success,) = payable(address(vault)).call{value: amount}("");
        if (!success) {
            revert();
        }
    }

    /*//////////////////////////////////////////////////////////////
                                DEPOSIT
    //////////////////////////////////////////////////////////////*/

    function testFuzzDepositLinear(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);
        // 1. Deposit
        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();
        // 2. check our rebase token balance
        uint256 startBalance = rebaseToken.balanceOf(user);
        console.log("balance: ", startBalance);
        assertEq(startBalance, amount);
        // 3. warp the time and check the balance again
        vm.warp(block.timestamp + 1 hours);
        uint256 middleBalance = rebaseToken.balanceOf(user);
        assertGt(middleBalance, startBalance);
        // 4. warp the time again by same the same amount and check the balancce
        vm.warp(block.timestamp + 1 hours);
        uint256 endBalance = rebaseToken.balanceOf(user);
        assertGt(endBalance, middleBalance);
        assertApproxEqAbs(endBalance - middleBalance, middleBalance - startBalance, 1);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                                 REDEEM
    //////////////////////////////////////////////////////////////*/

    function testFuzzRedeemFails(uint256 amount) public {
        amount = 1;
        address mockContract = address(new MockContract());

        // 1. deposit
        vm.startPrank(mockContract);
        vm.deal(mockContract, amount);
        vault.deposit{value: amount}();
        assertEq(rebaseToken.balanceOf(mockContract), amount);
        // 2. redeem
        vm.expectRevert(Vault.Vault__RedeemFailed.selector);
        vault.redeem(type(uint256).max);
        vm.stopPrank();
    }

    function testFuzzRedeemStraightAway(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);
        // 1. deposit
        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();
        assertEq(rebaseToken.balanceOf(user), amount);
        // 2. redeem
        vault.redeem(type(uint256).max);
        assertEq(rebaseToken.balanceOf(user), 0);
        assertEq(address(user).balance, amount);
        vm.stopPrank();
    }

    function testFuzzRedeemAfterTimePassed(uint256 depositAmount, uint256 time) public {
        time = bound(time, 1000, type(uint96).max);
        depositAmount = bound(depositAmount, 1e5, type(uint96).max);
        // 1. deposit
        vm.deal(user, depositAmount);
        vm.prank(user);
        vault.deposit{value: depositAmount}();
        // 2. warp the time
        vm.warp(block.timestamp + time);
        uint256 balanceAfterSomeTime = rebaseToken.balanceOf(user);
        // (b) Add rewards to the walt
        vm.deal(owner, balanceAfterSomeTime - depositAmount);
        vm.prank(owner);
        addRewardsToVault(balanceAfterSomeTime - depositAmount);
        // 3. redeem
        vm.prank(user);
        vault.redeem(type(uint256).max);

        uint256 ethBalance = address(user).balance;
        assertEq(ethBalance, balanceAfterSomeTime);
        assertGt(ethBalance, depositAmount);
    }

    /*//////////////////////////////////////////////////////////////
                                TRANSFER
    //////////////////////////////////////////////////////////////*/

    function testFuzzTransfer(uint256 amount, uint256 amountToSend) public {
        amount = bound(amount, 2e5, type(uint96).max);
        amountToSend = bound(amountToSend, 1e5, amount - 1e5);

        // 1. deposit
        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();

        address user2 = makeAddr("user2");
        uint256 userBalance = rebaseToken.balanceOf(user);
        uint256 user2Balance = rebaseToken.balanceOf(user2);
        assertEq(userBalance, amount);
        assertEq(user2Balance, 0);

        // 2. owner reduces the interest rate
        vm.prank(owner);
        rebaseToken.setInterestRate(4e10);

        // 3. transfer
        vm.prank(user);
        rebaseToken.transfer(user2, amountToSend);
        uint256 userBalanceAfterTransfer = rebaseToken.balanceOf(user);
        uint256 user2BalanceAfterTransfer = rebaseToken.balanceOf(user2);
        assertEq(userBalanceAfterTransfer, userBalance - amountToSend);
        assertEq(user2BalanceAfterTransfer, user2Balance + amountToSend);

        // check user interast rate has been inherited (5e10 not 4e10)
        assertEq(rebaseToken.getUserInterestRate(user), 5e10);
        assertEq(rebaseToken.getUserInterestRate(user2), 5e10);
    }

    function testFuzzTransferAllTokens(uint256 amount) public {
        amount = bound(amount, 2e5, type(uint96).max);
        uint256 amountToSend = type(uint256).max;

        // 1. deposit
        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();

        address user2 = makeAddr("user2");
        uint256 userBalance = rebaseToken.balanceOf(user);
        uint256 user2Balance = rebaseToken.balanceOf(user2);
        assertEq(userBalance, amount);
        assertEq(user2Balance, 0);

        // 2. owner reduces the interest rate
        vm.prank(owner);
        rebaseToken.setInterestRate(4e10);

        // 3. transfer
        vm.prank(user);
        rebaseToken.transfer(user2, amountToSend);
        // uint256 userBalanceAfterTransfer = rebaseToken.balanceOf(user);
        uint256 user2BalanceAfterTransfer = rebaseToken.balanceOf(user2);
        assertEq(userBalance + user2Balance, user2BalanceAfterTransfer);

        // check user interast rate has been inherited (5e10 not 4e10)
        assertEq(rebaseToken.getUserInterestRate(user), 5e10);
        assertEq(rebaseToken.getUserInterestRate(user2), 5e10);
    }
    /*//////////////////////////////////////////////////////////////
                             TRANSFER FROM
    //////////////////////////////////////////////////////////////*/

    function testFuzzTransferFrom(uint256 amount, uint256 amountToSend) public {
        amount = bound(amount, 2e5, type(uint96).max);
        amountToSend = bound(amountToSend, 1e5, amount - 1e5);
        address spender = makeAddr("spender");
        // 1. deposit
        vm.deal(user, amount);
        vm.startPrank(user);
        vault.deposit{value: amount}();
        rebaseToken.approve(spender, amountToSend);
        vm.stopPrank();

        address user2 = makeAddr("user2");
        uint256 userBalance = rebaseToken.balanceOf(user);
        uint256 user2Balance = rebaseToken.balanceOf(user2);
        assertEq(userBalance, amount);
        assertEq(user2Balance, 0);

        // 2. owner reduces the interest rate
        vm.prank(owner);
        rebaseToken.setInterestRate(4e10);

        // 3. transfer
        vm.prank(spender);
        rebaseToken.transferFrom(user, user2, amountToSend);
        uint256 userBalanceAfterTransfer = rebaseToken.balanceOf(user);
        uint256 user2BalanceAfterTransfer = rebaseToken.balanceOf(user2);
        assertEq(userBalanceAfterTransfer, userBalance - amountToSend);
        assertEq(user2BalanceAfterTransfer, user2Balance + amountToSend);

        // check user interast rate has been inherited (5e10 not 4e10)
        assertEq(rebaseToken.getUserInterestRate(user), 5e10);
        assertEq(rebaseToken.getUserInterestRate(user2), 5e10);
    }

    function testFuzzTransferFromAllTokens(uint256 amount) public {
        amount = bound(amount, 2e5, type(uint96).max);
        uint256 amountToSend = type(uint256).max;
        address spender = makeAddr("spender");
        // 1. deposit
        vm.deal(user, amount);
        vm.startPrank(user);
        vault.deposit{value: amount}();
        rebaseToken.approve(spender, amountToSend);
        vm.stopPrank();

        address user2 = makeAddr("user2");
        uint256 userBalance = rebaseToken.balanceOf(user);
        uint256 user2Balance = rebaseToken.balanceOf(user2);
        assertEq(userBalance, amount);
        assertEq(user2Balance, 0);

        // 2. owner reduces the interest rate
        vm.prank(owner);
        rebaseToken.setInterestRate(4e10);

        // 3. transfer
        vm.prank(spender);
        rebaseToken.transferFrom(user, user2, amountToSend);
        // uint256 userBalanceAfterTransfer = rebaseToken.balanceOf(user);
        uint256 user2BalanceAfterTransfer = rebaseToken.balanceOf(user2);
        assertEq(userBalance + user2Balance, user2BalanceAfterTransfer);
        // assertEq(user2BalanceAfterTransfer, user2Balance + amountToSend);

        // check user interast rate has been inherited (5e10 not 4e10)
        assertEq(rebaseToken.getUserInterestRate(user), 5e10);
        assertEq(rebaseToken.getUserInterestRate(user2), 5e10);
    }

    /*//////////////////////////////////////////////////////////////
                         TRANSFER INTERESTRATE
    //////////////////////////////////////////////////////////////*/

    function testFuzzCannotSetInterestRate(uint256 newInterestRate) public {
        vm.prank(user);
        vm.expectPartialRevert(Ownable.OwnableUnauthorizedAccount.selector);
        rebaseToken.setInterestRate(newInterestRate);
    }

    function testGetInterestRateDoNotRevert() public view {
        uint256 interestRate = rebaseToken.getInterestRate();
        assertGt(interestRate, 0);
    }

    function testFuzzInterestRateCanOnlyDecrease(uint256 newInterestRate) public {
        uint256 initialInterestRate = rebaseToken.getInterestRate();
        newInterestRate = bound(newInterestRate, initialInterestRate, type(uint96).max);
        vm.prank(owner);
        vm.expectPartialRevert(RebaseToken.RebaseToken__InterestRateCanOnlyDecrease.selector);
        rebaseToken.setInterestRate(newInterestRate);
        assertEq(rebaseToken.getInterestRate(), initialInterestRate);
    }

    /*//////////////////////////////////////////////////////////////
                             MINT AND BURN
    //////////////////////////////////////////////////////////////*/

    function testCannotCallMintAndBurn() public {
        vm.startPrank(user);
        uint256 interestRate = rebaseToken.getInterestRate();
        console.log("interest rate: ", interestRate);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        rebaseToken.mint(user, 100, interestRate);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        rebaseToken.burn(user, type(uint256).max);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                             PRINCIPAL BALANCE
    //////////////////////////////////////////////////////////////*/

    function testFuzzGetPrincipalAmount(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);

        // 1. deposit
        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();
        assertEq(rebaseToken.principalBalanceOf(user), amount);
    }

    /*//////////////////////////////////////////////////////////////
                             REBASE TOKEN ADDRESS
    //////////////////////////////////////////////////////////////*/

    function testGetRebaseTokenAddress() public view {
        assertEq(vault.getRebaseTokenAddress(), address(rebaseToken));
    }
}
