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
import {TestPairFactory} from "test/TestPairFactory.t.sol";
import {TestVotingEscrow} from "test/TestVotingEscrow.t.sol";
import {TestCLGauge} from "test/TestCLGauge.t.sol";
import {ProtocolTimeLibrary} from "src/clAMM/libraries/ProtocolTimeLibrary.sol";

interface ICLFactoryExtended is ICLFactory {
    function setVoter(address _voter) external;
}

contract TestVoter is TestPairFactory, TestVotingEscrow, TestCLGauge {
    function testCreateGauge() public {
        testPairFactory__setUp();
        testCLGauge__setUp();
        testDistributeVeKitten();

        vm.startPrank(deployer);

        for (uint i; i < pairListVolatile.length; i++) {
            address _gauge = voter.createGauge(
                address(pairFactory),
                pairListVolatile[i]
            );

            address _gaugeFetched = voter.gauges(pairListVolatile[i]);
            vm.assertTrue(_gaugeFetched != address(0));
            vm.assertTrue(_gaugeFetched == _gauge);
            vm.assertTrue(voter.isGauge(_gauge));
            vm.assertTrue(voter.isAlive(_gauge));

            clGaugeList.push(_gauge);
        }

        for (uint i; i < pairListStable.length; i++) {
            address _gauge = voter.createGauge(
                address(pairFactory),
                pairListStable[i]
            );

            address _gaugeFetched = voter.gauges(pairListStable[i]);
            vm.assertTrue(_gaugeFetched != address(0));
            vm.assertTrue(_gaugeFetched == _gauge);
            vm.assertTrue(voter.isGauge(_gauge));
            vm.assertTrue(voter.isAlive(_gauge));

            clGaugeList.push(_gauge);
        }

        for (uint i; i < poolList.length; i++) {
            address _gauge = voter.createCLGauge(
                address(clFactory),
                poolList[i]
            );

            address _gaugeFetched = voter.gauges(poolList[i]);
            vm.assertTrue(_gaugeFetched != address(0));
            vm.assertTrue(_gaugeFetched == _gauge);
            vm.assertTrue(voter.isGauge(_gauge));
            vm.assertTrue(voter.isAlive(_gauge));

            clGaugeList.push(_gauge);
        }

        vm.stopPrank();
    }

    /* Vote tests */
    function testVote() public returns (uint256 tokenId) {
        testCreateGauge();

        vm.startPrank(user1);

        uint256 len = poolList.length;

        address[] memory voteList = new address[](len);
        uint256[] memory weightList = new uint256[](len);
        uint256 totalWeight;

        uint256[] memory weightsListBefore = new uint256[](len);
        uint256[] memory votesListBefore = new uint256[](len);

        tokenId = veKitten.tokenOfOwnerByIndex(user1, 0);

        for (uint256 i; i < len; i++) {
            weightsListBefore[i] = voter.weights(poolList[i]);
            votesListBefore[i] = voter.votes(tokenId, poolList[i]);

            voteList[i] = poolList[i];
            weightList[i] = vm.randomUint(100, 1000);

            totalWeight += weightList[i];
        }

        uint256 voteTime = ProtocolTimeLibrary.epochVoteStart(block.timestamp) +
            vm.randomUint(1, 1 weeks - 2 hours);
        vm.warp(voteTime);

        voter.vote(tokenId, voteList, weightList);

        for (uint256 i; i < len; i++) {
            vm.assertEq(voter.poolVote(tokenId, i), voteList[i]);

            uint256 _poolWeight = (weightList[i] *
                veKitten.balanceOfNFT(tokenId)) / totalWeight;
            vm.assertEq(
                voter.weights(voteList[i]),
                weightsListBefore[i] + _poolWeight
            );
            vm.assertEq(
                voter.votes(tokenId, voteList[i]),
                votesListBefore[i] + _poolWeight
            );
        }

        vm.stopPrank();
    }

    function testZeroTotalWeightVote() public returns (uint256 tokenId) {
        testCreateGauge();

        vm.startPrank(user1);

        uint256 len = poolList.length;

        address[] memory voteList = new address[](len);
        uint256[] memory weightList = new uint256[](len);
        uint256 totalWeight;

        uint256[] memory weightsListBefore = new uint256[](len);
        uint256[] memory votesListBefore = new uint256[](len);

        tokenId = veKitten.tokenOfOwnerByIndex(user1, 0);

        for (uint256 i; i < len; i++) {
            weightsListBefore[i] = voter.weights(poolList[i]);
            votesListBefore[i] = voter.votes(tokenId, poolList[i]);

            voteList[i] = poolList[i];
            weightList[i] = 0;

            totalWeight += weightList[i];
        }

        vm.expectRevert();
        voter.vote(tokenId, voteList, weightList);

        vm.stopPrank();
    }

    function testRevertVoteOnStartEpochOneHour() public {
        testCreateGauge();

        vm.startPrank(user1);

        uint256 len = poolList.length;

        address[] memory voteList = new address[](len);
        uint256[] memory weightList = new uint256[](len);
        uint256 totalWeight;

        uint256[] memory weightsListBefore = new uint256[](len);
        uint256[] memory votesListBefore = new uint256[](len);

        uint256 tokenId = veKitten.tokenOfOwnerByIndex(user1, 0);

        for (uint256 i; i < len; i++) {
            weightsListBefore[i] = voter.weights(poolList[i]);
            votesListBefore[i] = voter.votes(tokenId, poolList[i]);

            voteList[i] = poolList[i];
            weightList[i] = vm.randomUint(100, 1000);

            totalWeight += weightList[i];
        }

        uint256 voteTime = ProtocolTimeLibrary.epochStart(block.timestamp) +
            vm.randomUint(1, 1 hours - 1);
        vm.warp(voteTime);

        vm.expectRevert();
        voter.vote(tokenId, voteList, weightList);

        vm.stopPrank();
    }

    function testRevertVoteOnEndEpochOneHour() public {
        testCreateGauge();

        vm.startPrank(user1);

        uint256 len = poolList.length;

        address[] memory voteList = new address[](len);
        uint256[] memory weightList = new uint256[](len);
        uint256 totalWeight;

        uint256[] memory weightsListBefore = new uint256[](len);
        uint256[] memory votesListBefore = new uint256[](len);

        uint256 tokenId = veKitten.tokenOfOwnerByIndex(user1, 0);

        for (uint256 i; i < len; i++) {
            weightsListBefore[i] = voter.weights(poolList[i]);
            votesListBefore[i] = voter.votes(tokenId, poolList[i]);

            voteList[i] = poolList[i];
            weightList[i] = vm.randomUint(100, 1000);

            totalWeight += weightList[i];
        }

        uint256 voteTime = ProtocolTimeLibrary.epochVoteEnd(block.timestamp) +
            vm.randomUint(1, 1 hours - 1);
        vm.warp(voteTime);

        vm.expectRevert();
        voter.vote(tokenId, voteList, weightList);

        vm.stopPrank();
    }

    function testWhitelistedVoteOnEndEpochOneHour() public {
        testCreateGauge();

        vm.startPrank(user1);

        uint256 len = poolList.length;

        address[] memory voteList = new address[](len);
        uint256[] memory weightList = new uint256[](len);
        uint256 totalWeight;

        uint256[] memory weightsListBefore = new uint256[](len);
        uint256[] memory votesListBefore = new uint256[](len);

        uint256 tokenId = veKitten.tokenOfOwnerByIndex(user1, 0);

        for (uint256 i; i < len; i++) {
            weightsListBefore[i] = voter.weights(poolList[i]);
            votesListBefore[i] = voter.votes(tokenId, poolList[i]);

            voteList[i] = poolList[i];
            weightList[i] = vm.randomUint(100, 1000);

            totalWeight += weightList[i];
        }

        vm.stopPrank();
        vm.startPrank(deployer);
        voter.setWhitelistTokenId(tokenId, true);
        vm.stopPrank();
        vm.startPrank(user1);

        uint256 voteTime = ProtocolTimeLibrary.epochVoteEnd(block.timestamp) +
            vm.randomUint(1, 1 hours - 1);
        vm.warp(voteTime);

        voter.vote(tokenId, voteList, weightList);

        vm.stopPrank();
    }

    /* Poke tests */
    function testPoke() public {
        uint256 tokenId = testVote();

        vm.warp(block.timestamp + 1 weeks);

        // allow anyone to poke
        voter.poke(tokenId);
    }

    function testNotRevertOnPokeVotesForDustWeight() public {
        testCreateGauge();

        vm.startPrank(deployer);

        uint256 tokenId = veKitten.create_lock_for(
            1 ether,
            2 * 52 weeks,
            user1
        );

        vm.stopPrank();

        vm.startPrank(user1);

        uint256 len = poolList.length;

        address[] memory voteList = new address[](len);
        uint256[] memory weightList = new uint256[](len);

        uint256 balanceWeight = veKitten.balanceOfNFT(tokenId);

        for (uint256 i; i < len; i++) {
            voteList[i] = poolList[i];
            weightList[i] =
                (balanceWeight * vm.randomUint(1_000, 100_000)) /
                1_000;
        }

        voteList[0] = poolList[0];
        weightList[0] = 1;

        voter.vote(tokenId, voteList, weightList);

        vm.stopPrank();

        vm.warp(block.timestamp + 1 weeks);

        voter.poke(tokenId);
    }

    /* Set governor tests  */
    function testSetGovernor() public {
        _setUp();

        vm.startPrank(deployer);

        voter.setGovernor(multisig);

        vm.stopPrank();

        address newGovernor = vm.randomAddress();

        vm.startPrank(multisig);

        voter.setGovernor(newGovernor);

        vm.stopPrank();
    }

    function testOwnerSetGovernor() public {
        _setUp();

        vm.startPrank(deployer);

        voter.setGovernor(multisig);

        vm.stopPrank();
    }

    function testRevertSetGovernor() public {
        _setUp();

        address notGovernorOrOwner = vm.randomAddress();
        vm.startPrank(notGovernorOrOwner);

        address newGovernor = vm.randomAddress();
        vm.expectRevert();
        voter.setGovernor(newGovernor);

        vm.stopPrank();
    }

    /* Set whitelist tokenId tests  */
    function testSetWhitelistTokenId() public {
        _setUp();

        uint256 tokenId = vm.randomUint(1, 10_000);

        vm.startPrank(deployer);

        address newGovernor = multisig;
        voter.setGovernor(newGovernor);

        // owner set whitelist tokenId
        voter.setWhitelistTokenId(tokenId, true);
        voter.setWhitelistTokenId(tokenId, false);

        vm.stopPrank();

        vm.startPrank(newGovernor);

        // governor set whitelist tokenId
        voter.setWhitelistTokenId(tokenId, true);
        voter.setWhitelistTokenId(tokenId, false);

        vm.stopPrank();
    }

    function testRevertSetWhitelistTokenId() public {
        _setUp();

        address notGovernorOrOwner = vm.randomAddress();
        vm.startPrank(notGovernorOrOwner);

        uint256 tokenId = vm.randomUint(1, 10_000);
        vm.expectRevert();
        voter.setWhitelistTokenId(tokenId, true);

        vm.stopPrank();
    }
}
