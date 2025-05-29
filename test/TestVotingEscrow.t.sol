pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {Options} from "openzeppelin-foundry-upgrades/Options.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {IWHYPE9} from "src/interfaces/IWHYPE9.sol";
import {PairFactory} from "src/factories/PairFactory.sol";
import {Router} from "src/Router.sol";
import {FactoryRegistry} from "src/clAMM/core/FactoryRegistry.sol";
import {ICLFactory} from "src/clAMM/core/interfaces/ICLFactory.sol";
import {ICustomFeeModule} from "src/clAMM/core/interfaces/fees/ICustomFeeModule.sol";
import {ISwapRouter} from "src/clAMM/periphery/interfaces/ISwapRouter.sol";
import {INonfungiblePositionManager} from "src/clAMM/periphery/interfaces/INonfungiblePositionManager.flatten.sol";
import {IQuoterV2} from "src/clAMM/periphery/interfaces/IQuoterV2.sol";
import {Kitten} from "src/Kitten.sol";
import {VeArtProxy} from "src/VeArtProxy.sol";
import {VotingEscrow} from "src/VotingEscrow.sol";
import {Voter} from "src/Voter.sol";
import {RewardsDistributor} from "src/RewardsDistributor.sol";
import {Minter} from "src/Minter.sol";
import {GaugeFactory} from "src/factories/GaugeFactory.sol";
import {BribeFactory} from "src/factories/BribeFactory.sol";
import {CLGaugeFactory} from "src/clAMM/gauge/CLGaugeFactory.sol";
import {ICLPool} from "src/clAMM/core/interfaces/ICLPool.sol";
import {Gauge} from "src/Gauge.sol";
import {InternalBribe} from "src/InternalBribe.sol";
import {CLGauge} from "src/clAMM/gauge/CLGauge.sol";
import {ExternalBribe} from "src/ExternalBribe.sol";

import {IERC20} from "src/interfaces/IERC20.sol";

import {Base} from "test/base/Base.t.sol";

interface ICLFactoryExtended is ICLFactory {
    function setVoter(address _voter) external;
}

contract TestVotingEscrow is Base {
    function testDistributeVeKitten() public {
        _setUp();

        vm.startPrank(deployer);

        kitten.approve(address(veKitten), type(uint256).max);

        for (uint i; i < userList.length; i++) {
            veKitten.create_lock_for(
                (kitten.balanceOf(deployer) * vm.randomUint(1, 10_000)) /
                    10_000,
                vm.randomUint(1 weeks, 2 * 365 days),
                userList[i]
            );
        }

        vm.stopPrank();
    }

    /* Split tests */
    function testSplitVeKitten()
        public
        returns (uint tokenIdFrom, uint tokenId1, uint tokenId2)
    {
        testDistributeVeKitten();

        address user1 = userList[0];

        vm.startPrank(user1);

        tokenIdFrom = veKitten.tokenOfOwnerByIndex(user1, 0);
        (int128 lockedAmountFromBefore, ) = veKitten.locked(tokenIdFrom);

        uint256 amount = uint256(uint128(lockedAmountFromBefore)) / 3;

        (tokenId1, tokenId2) = veKitten.split(tokenIdFrom, amount);

        (int128 lockedAmountFromAfter, ) = veKitten.locked(tokenIdFrom);
        vm.assertEq(uint256(uint128(lockedAmountFromAfter)), 0);

        (int128 lockedAmountTokenId1, ) = veKitten.locked(tokenId1);
        vm.assertEq(
            uint256(uint128(lockedAmountTokenId1)),
            uint256(uint128(lockedAmountFromBefore)) - amount
        );

        (int128 lockedAmountTokenId2, ) = veKitten.locked(tokenId2);
        vm.assertEq(uint256(uint128(lockedAmountTokenId2)), amount);

        vm.stopPrank();
    }

    function testSplitVeKittenFromNotBurned() public {
        (uint256 tokenIdFrom, , ) = testSplitVeKitten();

        address user1 = userList[0];

        vm.assertEq(user1, veKitten.ownerOf(tokenIdFrom));
    }

    function testSplitVeKittenGreaterThanLocked() public {
        testDistributeVeKitten();

        address user1 = userList[0];

        vm.startPrank(user1);

        uint veKittenId = veKitten.tokenOfOwnerByIndex(user1, 0);
        (int128 lockedAmount, uint endTime) = veKitten.locked(veKittenId);

        vm.expectRevert();
        (uint t1, uint t2) = veKitten.split(
            veKittenId,
            uint256(uint128(lockedAmount)) * vm.randomUint(2, 100)
        );

        vm.stopPrank();
    }

    function testSplitVeKittenZeroTokenId1() public {
        testDistributeVeKitten();

        address user1 = userList[0];

        vm.startPrank(user1);

        uint veKittenId = veKitten.tokenOfOwnerByIndex(user1, 0);
        (int128 lockedAmount, uint endTime) = veKitten.locked(veKittenId);

        vm.expectRevert();
        veKitten.split(veKittenId, uint256(uint128(lockedAmount)));

        vm.stopPrank();
    }

    function testSplitVeKittenZeroTokenId2() public {
        testDistributeVeKitten();

        address user1 = userList[0];

        vm.startPrank(user1);

        uint veKittenId = veKitten.tokenOfOwnerByIndex(user1, 0);
        (int128 lockedAmount, uint endTime) = veKitten.locked(veKittenId);

        vm.expectRevert();
        veKitten.split(veKittenId, 0);

        vm.stopPrank();
    }

    function testLockTimeRounding() public {
        (uint tokenIdFrom, uint tokenId1, uint tokenId2) = testSplitVeKitten();

        address user1 = userList[0];

        vm.startPrank(user1);

        uint256 roundedMaxTime = ((block.timestamp + 2 * 365 days) / 1 weeks) *
            1 weeks;

        (, uint endTimeFrom) = veKitten.locked(tokenIdFrom);
        vm.assertEq(endTimeFrom, 0);

        (, uint endTime1) = veKitten.locked(tokenId1);
        vm.assertEq(endTime1, roundedMaxTime);

        (, uint endTime2) = veKitten.locked(tokenId2);
        vm.assertEq(endTime2, roundedMaxTime);

        vm.stopPrank();
    }

    function testApprovedSplitVeKitten()
        public
        returns (uint tokenIdFrom, uint tokenId1, uint tokenId2)
    {
        testDistributeVeKitten();

        address user1 = userList[0];

        vm.startPrank(user1);

        tokenIdFrom = veKitten.tokenOfOwnerByIndex(user1, 0);
        (int128 lockedAmountFromBefore, ) = veKitten.locked(tokenIdFrom);

        uint256 amount = uint256(uint128(lockedAmountFromBefore)) / 3;

        address approvedUser = vm.randomAddress();
        veKitten.approve(approvedUser, tokenIdFrom);

        vm.stopPrank();

        vm.startPrank(approvedUser);

        (tokenId1, tokenId2) = veKitten.split(tokenIdFrom, amount);

        vm.assertEq(veKitten.ownerOf(tokenId1), veKitten.ownerOf(tokenIdFrom));
        vm.assertEq(veKitten.ownerOf(tokenId2), veKitten.ownerOf(tokenIdFrom));

        vm.stopPrank();
    }

    function testRevertNotApprovedSplitVeKitten()
        public
        returns (uint tokenIdFrom, uint tokenId1, uint tokenId2)
    {
        testDistributeVeKitten();

        address user1 = userList[0];

        vm.startPrank(user1);

        tokenIdFrom = veKitten.tokenOfOwnerByIndex(user1, 0);
        (int128 lockedAmountFromBefore, ) = veKitten.locked(tokenIdFrom);

        uint256 amount = uint256(uint128(lockedAmountFromBefore)) / 3;

        vm.stopPrank();

        address approvedUser = vm.randomAddress();

        vm.startPrank(approvedUser);

        vm.expectRevert();
        (tokenId1, tokenId2) = veKitten.split(tokenIdFrom, amount);

        vm.stopPrank();
    }

    /* Merge tests */
    struct TestMergeVeKittenVars {
        uint256 lockAmount1;
        uint256 lockTime1;
        uint256 tokenId1;
        uint256 lockAmount2;
        uint256 lockTime2;
        uint256 tokenId2;
    }
    function testMergeVeKitten() public {
        _setUp();

        address user1 = userList[0];

        TestMergeVeKittenVars memory v;

        vm.startPrank(deployer);

        kitten.approve(address(veKitten), type(uint256).max);

        v.lockAmount1 = (100_000_000 ether * vm.randomUint(1, 100)) / 100;
        v.lockTime1 = (52 weeks * 2 * vm.randomUint(1, 100)) / 100;
        v.tokenId1 = veKitten.create_lock_for(
            v.lockAmount1,
            v.lockTime1,
            user1
        );

        v.lockAmount2 = (100_000_000 ether * vm.randomUint(1, 100)) / 100;
        v.lockTime2 = (52 weeks * 2 * vm.randomUint(1, 100)) / 100;
        v.tokenId2 = veKitten.create_lock_for(
            v.lockAmount2,
            v.lockTime2,
            user1
        );

        vm.stopPrank();

        vm.startPrank(user1);

        veKitten.merge(v.tokenId1, v.tokenId2);

        // should have cleared out tokenId1 but not burned veKitten for potential rewards claiming
        (int128 amount1, uint end1) = veKitten.locked(v.tokenId1);
        uint256 balanceOfTokenId1 = veKitten.balanceOfNFT(v.tokenId1);

        vm.assertEq(amount1, 0);
        vm.assertEq(end1, 0);
        vm.assertEq(balanceOfTokenId1, 0);
        vm.assertEq(user1, veKitten.ownerOf(v.tokenId1));

        // should have added tokenId1 balances to tokenId2
        (int128 amount2, uint end2) = veKitten.locked(v.tokenId2);
        uint256 endTime = ((block.timestamp +
            (v.lockTime1 > v.lockTime2 ? v.lockTime1 : v.lockTime2)) /
            1 weeks) * 1 weeks;
        uint256 balanceOfTokenId2 = veKitten.balanceOfNFT(v.tokenId2);

        vm.assertEq(uint256(uint128(amount2)), v.lockAmount1 + v.lockAmount2);
        vm.assertEq(end2, endTime);

        vm.stopPrank();
    }

    function testSupplyNotChangeMergeVeKitten() public {
        _setUp();

        address user1 = userList[0];

        TestMergeVeKittenVars memory v;

        vm.startPrank(deployer);

        kitten.approve(address(veKitten), type(uint256).max);

        v.lockAmount1 = (100_000_000 ether * vm.randomUint(1, 100)) / 100;
        v.lockTime1 = (52 weeks * 2 * vm.randomUint(1, 100)) / 100;
        v.tokenId1 = veKitten.create_lock_for(
            v.lockAmount1,
            v.lockTime1,
            user1
        );

        v.lockAmount2 = (100_000_000 ether * vm.randomUint(1, 100)) / 100;
        v.lockTime2 = (52 weeks * 2 * vm.randomUint(1, 100)) / 100;
        v.tokenId2 = veKitten.create_lock_for(
            v.lockAmount2,
            v.lockTime2,
            user1
        );

        vm.stopPrank();

        vm.startPrank(user1);

        uint256 supplyBefore = veKitten.supply();
        veKitten.merge(v.tokenId1, v.tokenId2);
        uint256 supplyAfter = veKitten.supply();

        vm.assertEq(supplyBefore, supplyAfter);

        vm.stopPrank();
    }

    function testApprovedMergeVeKitten() public {
        _setUp();

        address user1 = userList[0];

        TestMergeVeKittenVars memory v;

        vm.startPrank(deployer);

        kitten.approve(address(veKitten), type(uint256).max);

        v.lockAmount1 = (100_000_000 ether * vm.randomUint(1, 100)) / 100;
        v.lockTime1 = (52 weeks * 2 * vm.randomUint(1, 100)) / 100;
        v.tokenId1 = veKitten.create_lock_for(
            v.lockAmount1,
            v.lockTime1,
            user1
        );

        v.lockAmount2 = (100_000_000 ether * vm.randomUint(1, 100)) / 100;
        v.lockTime2 = (52 weeks * 2 * vm.randomUint(1, 100)) / 100;
        v.tokenId2 = veKitten.create_lock_for(
            v.lockAmount2,
            v.lockTime2,
            user1
        );

        vm.stopPrank();

        address approvedUser = vm.randomAddress();

        vm.startPrank(user1);
        veKitten.approve(approvedUser, v.tokenId1);
        veKitten.approve(approvedUser, v.tokenId2);
        vm.stopPrank();

        vm.startPrank(approvedUser);

        veKitten.merge(v.tokenId1, v.tokenId2);

        // should have cleared out tokenId1 but not burned veKitten for potential rewards claiming
        (int128 amount1, uint end1) = veKitten.locked(v.tokenId1);
        uint256 balanceOfTokenId1 = veKitten.balanceOfNFT(v.tokenId1);

        vm.assertEq(amount1, 0);
        vm.assertEq(end1, 0);
        vm.assertEq(balanceOfTokenId1, 0);
        vm.assertEq(user1, veKitten.ownerOf(v.tokenId1));

        // should have added tokenId1 balances to tokenId2
        (int128 amount2, uint end2) = veKitten.locked(v.tokenId2);
        uint256 endTime = ((block.timestamp +
            (v.lockTime1 > v.lockTime2 ? v.lockTime1 : v.lockTime2)) /
            1 weeks) * 1 weeks;
        uint256 balanceOfTokenId2 = veKitten.balanceOfNFT(v.tokenId2);

        vm.assertEq(uint256(uint128(amount2)), v.lockAmount1 + v.lockAmount2);
        vm.assertEq(end2, endTime);

        vm.stopPrank();
    }

    function testNotApprovedMergeVeKittenToken1() public {
        _setUp();

        address user1 = userList[0];

        TestMergeVeKittenVars memory v;

        vm.startPrank(deployer);

        kitten.approve(address(veKitten), type(uint256).max);

        v.lockAmount1 = (100_000_000 ether * vm.randomUint(1, 100)) / 100;
        v.lockTime1 = (52 weeks * 2 * vm.randomUint(1, 100)) / 100;
        v.tokenId1 = veKitten.create_lock_for(
            v.lockAmount1,
            v.lockTime1,
            user1
        );

        v.lockAmount2 = (100_000_000 ether * vm.randomUint(1, 100)) / 100;
        v.lockTime2 = (52 weeks * 2 * vm.randomUint(1, 100)) / 100;
        v.tokenId2 = veKitten.create_lock_for(
            v.lockAmount2,
            v.lockTime2,
            user1
        );

        vm.stopPrank();

        address approvedUser = vm.randomAddress();

        vm.startPrank(user1);
        veKitten.approve(approvedUser, v.tokenId2);
        vm.stopPrank();

        vm.startPrank(approvedUser);

        vm.expectRevert();
        veKitten.merge(v.tokenId1, v.tokenId2);

        vm.stopPrank();
    }

    function testNotApprovedMergeVeKittenToken2() public {
        _setUp();

        address user1 = userList[0];

        TestMergeVeKittenVars memory v;

        vm.startPrank(deployer);

        kitten.approve(address(veKitten), type(uint256).max);

        v.lockAmount1 = (100_000_000 ether * vm.randomUint(1, 100)) / 100;
        v.lockTime1 = (52 weeks * 2 * vm.randomUint(1, 100)) / 100;
        v.tokenId1 = veKitten.create_lock_for(
            v.lockAmount1,
            v.lockTime1,
            user1
        );

        v.lockAmount2 = (100_000_000 ether * vm.randomUint(1, 100)) / 100;
        v.lockTime2 = (52 weeks * 2 * vm.randomUint(1, 100)) / 100;
        v.tokenId2 = veKitten.create_lock_for(
            v.lockAmount2,
            v.lockTime2,
            user1
        );

        vm.stopPrank();

        address approvedUser = vm.randomAddress();

        vm.startPrank(user1);
        veKitten.approve(approvedUser, v.tokenId1);
        vm.stopPrank();

        vm.startPrank(approvedUser);

        vm.expectRevert();
        veKitten.merge(v.tokenId1, v.tokenId2);

        vm.stopPrank();
    }

    /* Withdraw tests */
    function testWithdrawVeKitten() public {
        _setUp();

        address user1 = userList[0];

        vm.startPrank(deployer);

        kitten.approve(address(veKitten), type(uint256).max);

        uint256 lockAmount1 = (100_000_000 ether * vm.randomUint(1, 100)) / 100;
        uint256 lockTime1 = (52 weeks * 2 * vm.randomUint(1, 100)) / 100;
        uint256 tokenId1 = veKitten.create_lock_for(
            lockAmount1,
            lockTime1,
            user1
        );

        vm.stopPrank();

        vm.startPrank(user1);
        vm.warp(block.timestamp + lockTime1);

        uint256 kittenBalBefore = kitten.balanceOf(user1);
        veKitten.withdraw(tokenId1);
        uint256 kittenBalAfter = kitten.balanceOf(user1);

        // should clear out the tokenId1 but not burn veKitten
        (int128 amount1, uint end1) = veKitten.locked(tokenId1);

        vm.assertEq(
            veKitten.balanceOfNFT(tokenId1),
            0,
            "should have 0 voting power"
        );
        vm.assertEq(amount1, 0, "should have 0 locked amount");
        vm.assertGt(block.timestamp, end1, "should have expired");
        vm.assertEq(
            user1,
            veKitten.ownerOf(tokenId1),
            "should still be owner of veKitten"
        );
        vm.assertEq(
            lockAmount1,
            kittenBalAfter - kittenBalBefore,
            "should get unlocked kitten"
        );

        vm.stopPrank();
    }

    function testApprovedWithdrawVeKitten() public {
        _setUp();

        address user1 = userList[0];

        vm.startPrank(deployer);

        kitten.approve(address(veKitten), type(uint256).max);

        uint256 lockAmount1 = (100_000_000 ether * vm.randomUint(1, 100)) / 100;
        uint256 lockTime1 = (52 weeks * 2 * vm.randomUint(1, 100)) / 100;
        uint256 tokenId1 = veKitten.create_lock_for(
            lockAmount1,
            lockTime1,
            user1
        );

        vm.stopPrank();

        vm.startPrank(user1);

        address approvedUser = vm.randomAddress();
        veKitten.approve(approvedUser, tokenId1);

        vm.stopPrank();

        vm.startPrank(approvedUser);
        vm.warp(block.timestamp + lockTime1);

        uint256 kittenBalBefore = kitten.balanceOf(approvedUser);
        veKitten.withdraw(tokenId1);
        uint256 kittenBalAfter = kitten.balanceOf(approvedUser);

        vm.assertEq(
            user1,
            veKitten.ownerOf(tokenId1),
            "should still be owner of veKitten"
        );
        vm.assertEq(
            lockAmount1,
            kittenBalAfter - kittenBalBefore,
            "should get unlocked kitten"
        );

        vm.stopPrank();
    }

    function testRevertNotApprovedWithdrawVeKitten() public {
        _setUp();

        address user1 = userList[0];

        vm.startPrank(deployer);

        kitten.approve(address(veKitten), type(uint256).max);

        uint256 lockAmount1 = (100_000_000 ether * vm.randomUint(1, 100)) / 100;
        uint256 lockTime1 = (52 weeks * 2 * vm.randomUint(1, 100)) / 100;
        uint256 tokenId1 = veKitten.create_lock_for(
            lockAmount1,
            lockTime1,
            user1
        );

        vm.stopPrank();

        vm.startPrank(user1);

        address randomUser = vm.randomAddress();

        vm.stopPrank();

        vm.startPrank(randomUser);
        vm.warp(block.timestamp + lockTime1);

        vm.expectRevert();
        veKitten.withdraw(tokenId1);

        vm.stopPrank();
    }
}
