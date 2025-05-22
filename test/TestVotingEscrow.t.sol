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
        veKitten.create_lock_for(100_000_000 ether, 52 weeks * 2, user1);
        veKitten.create_lock_for(150_000_000 ether, 52 weeks * 2, user2);

        vm.stopPrank();
    }

    /* Split tests */
    function testSplitVeKitten()
        public
        returns (uint tokenIdFrom, uint tokenId1, uint tokenId2)
    {
        testDistributeVeKitten();

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

    function testSplitVeKittenGreaterThanLocked() public {
        testDistributeVeKitten();

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

        vm.startPrank(user1);

        uint veKittenId = veKitten.tokenOfOwnerByIndex(user1, 0);
        (int128 lockedAmount, uint endTime) = veKitten.locked(veKittenId);

        vm.expectRevert();
        veKitten.split(veKittenId, uint256(uint128(lockedAmount)));

        vm.stopPrank();
    }

    function testSplitVeKittenZeroTokenId2() public {
        testDistributeVeKitten();

        vm.startPrank(user1);

        uint veKittenId = veKitten.tokenOfOwnerByIndex(user1, 0);
        (int128 lockedAmount, uint endTime) = veKitten.locked(veKittenId);

        vm.expectRevert();
        veKitten.split(veKittenId, 0);

        vm.stopPrank();
    }

    function testLockTimeRounding() public {
        (uint tokenIdFrom, uint tokenId1, uint tokenId2) = testSplitVeKitten();

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
}
