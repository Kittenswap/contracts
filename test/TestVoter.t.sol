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
import {TestCLFactory} from "test/TestCLFactory.t.sol";
import {TestCLGaugeFactory} from "test/TestCLGaugeFactory.t.sol";

interface ICLFactoryExtended is ICLFactory {
    function setVoter(address _voter) external;
}

contract TestVoter is
    TestPairFactory,
    TestCLFactory,
    TestCLGaugeFactory,
    TestVotingEscrow
{
    mapping(address _pool => address) gauge;

    bool Voter__setUp;
    function testVoter__setUp() public {
        testPairFactory__setUp();
        testCLFactory__setUp();
        testDistributeVeKitten();

        // ensure that all voting tests will initially be set at the beginning of the epoch (vote open)
        // vm.warp(ProtocolTimeLibrary.epochVoteStart(block.timestamp) + 1);
    }

    function testCreateGauge() public {
        testVoter__setUp();

        vm.startPrank(deployer);

        console.log("pair volatile");
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

            gauge[pairListVolatile[i]] = _gauge;
            console.log("gauge", pairListVolatile[i], _gauge);
        }

        console.log("pair stable");
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

            gauge[pairListStable[i]] = _gauge;
            console.log("gauge", pairListStable[i], _gauge);
        }

        console.log("cl pool");
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

            gauge[poolList[i]] = _gauge;
            console.log("gauge", poolList[i], _gauge);
        }

        vm.stopPrank();
    }

    /* Vote tests */
    function testVote() public {
        testCreateGauge();

        console.log("/* Voting */");
        for (uint i; i < userList.length; i++) {
            address user1 = userList[i];

            console.log("user", user1);

            vm.startPrank(user1);

            uint256 len = poolList.length;

            address[] memory voteList = new address[](len);
            uint256[] memory weightList = new uint256[](len);
            uint256 totalWeight;

            uint256[] memory weightsListBefore = new uint256[](len);
            uint256[] memory votesListBefore = new uint256[](len);

            uint256 tokenId = veKitten.tokenOfOwnerByIndex(user1, 0);

            for (uint256 j; j < len; j++) {
                weightsListBefore[j] = voter.weights(poolList[j]);
                votesListBefore[j] = voter.votes(tokenId, poolList[j]);

                voteList[j] = poolList[j];
                weightList[j] = vm.randomUint(100, 1000);

                console.log("vote", voteList[j], weightList[j]);

                totalWeight += weightList[j];
            }

            uint256 voteTime = ProtocolTimeLibrary.epochVoteStart(
                block.timestamp
            ) + vm.randomUint(1, 1 weeks - 2 hours);
            vm.warp(voteTime);

            voter.vote(tokenId, voteList, weightList);

            for (uint256 j; j < len; j++) {
                vm.assertEq(voter.poolVote(tokenId, j), voteList[j]);

                uint256 _poolWeight = (weightList[j] *
                    veKitten.balanceOfNFT(tokenId)) / totalWeight;
                vm.assertEq(
                    voter.weights(voteList[j]),
                    weightsListBefore[j] + _poolWeight
                );
                vm.assertEq(
                    voter.votes(tokenId, voteList[j]),
                    votesListBefore[j] + _poolWeight
                );
            }

            vm.stopPrank();
        }
    }

    function testRevertInvalidGaugeVote() public returns (uint256 tokenId) {
        testCreateGauge();

        address user1 = userList[0];

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

        voteList[0] = vm.randomAddress();

        uint256 voteTime = ProtocolTimeLibrary.epochVoteStart(block.timestamp) +
            vm.randomUint(1, 1 weeks - 2 hours);
        vm.warp(voteTime);

        vm.expectRevert();
        voter.vote(tokenId, voteList, weightList);

        vm.stopPrank();
    }

    function testRevertKilledGaugeVote() public returns (uint256 tokenId) {
        testCreateGauge();

        address user1 = userList[0];

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

        vm.stopPrank();

        vm.startPrank(voter.emergencyCouncil());
        voter.killGauge(voter.gauges(voteList[0]));
        vm.stopPrank();

        uint256 voteTime = ProtocolTimeLibrary.epochVoteStart(block.timestamp) +
            vm.randomUint(1, 1 weeks - 2 hours);
        vm.startPrank(user1);
        vm.warp(voteTime);

        vm.expectRevert();
        voter.vote(tokenId, voteList, weightList);

        vm.stopPrank();
    }

    function testZeroTotalWeightVote() public returns (uint256 tokenId) {
        testCreateGauge();

        address user1 = userList[0];

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

        address user1 = userList[0];

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

        address user1 = userList[0];

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

        address user1 = userList[0];

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
        testVote();

        vm.warp(block.timestamp + 1 weeks + 1);
        for (uint i; i < userList.length; i++) {
            uint256 tokenId = veKitten.tokenOfOwnerByIndex(userList[i], 0);

            // allow anyone to poke
            voter.poke(tokenId);
        }
    }

    function testNotRevertOnPokeVotesForDustWeight() public {
        testCreateGauge();

        address user1 = userList[0];

        vm.prank(kitten.minter());
        kitten.mint(deployer, 1 ether);

        vm.startPrank(deployer);

        kitten.approve(address(veKitten), type(uint256).max);
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

    /* Set governor tests  */
    function testSetEmergencyCouncil() public {
        _setUp();

        vm.startPrank(voter.emergencyCouncil());

        address newEmergencyCouncil = vm.randomAddress();
        voter.setEmergencyCouncil(newEmergencyCouncil);

        vm.stopPrank();

        vm.assertEq(newEmergencyCouncil, voter.emergencyCouncil());
    }

    function testOwnerSetEmergencyCouncil() public {
        _setUp();

        vm.startPrank(deployer);

        address newEmergencyCouncil = vm.randomAddress();
        voter.setEmergencyCouncil(newEmergencyCouncil);

        vm.stopPrank();

        vm.assertEq(newEmergencyCouncil, voter.emergencyCouncil());
    }

    function testRevertSetEmergencyCouncil() public {
        _setUp();

        address notEmergencyCouncilOrOwner = vm.randomAddress();
        vm.startPrank(notEmergencyCouncilOrOwner);

        address newEmergencyCouncil = vm.randomAddress();
        vm.expectRevert();
        voter.setEmergencyCouncil(newEmergencyCouncil);

        vm.stopPrank();
    }

    /* Kill gauge tests */
    function testKillGauge() public {
        testVote();

        vm.warp(block.timestamp + 1 weeks);

        minter.update_period();
        voter.updateAll();

        vm.startPrank(voter.emergencyCouncil());
        for (uint i; i < poolList.length; i++) {
            address _gauge = gauge[poolList[i]];
            uint256 _claimable = voter.claimable(_gauge);
            uint256 minterBalBefore = kitten.balanceOf(address(minter));
            voter.killGauge(_gauge);
            uint256 minterBalAfter = kitten.balanceOf(address(minter));

            vm.assertEq(minterBalAfter - minterBalBefore, _claimable);
            vm.assertTrue(voter.isAlive(_gauge) == false);
        }
        vm.stopPrank();
    }

    function testRevertAlreadyDeadKillGauge() public {
        testVote();

        vm.warp(block.timestamp + 1 weeks);

        minter.update_period();
        voter.updateAll();

        vm.startPrank(voter.emergencyCouncil());
        for (uint i; i < poolList.length; i++) {
            address _gauge = gauge[poolList[i]];
            voter.killGauge(_gauge);
        }

        for (uint i; i < poolList.length; i++) {
            address _gauge = gauge[poolList[i]];
            vm.expectRevert();
            voter.killGauge(_gauge);
        }
        vm.stopPrank();
    }

    function testRevertNotEmergencyCouncilKillGauge() public {
        testVote();

        vm.warp(block.timestamp + 1 weeks);

        minter.update_period();
        voter.updateAll();

        vm.startPrank(vm.randomAddress());
        for (uint i; i < poolList.length; i++) {
            address _gauge = gauge[poolList[i]];
            vm.expectRevert();
            voter.killGauge(_gauge);
        }

        vm.stopPrank();
    }

    /* Whitelist tokens */
    function testWhitelistToken() public {
        testVote();

        address randomToken = vm.randomAddress();
        vm.startPrank(voter.governor());

        voter.whitelist(randomToken, true);
        vm.assertEq(voter.isWhitelisted(randomToken), true);
        voter.whitelist(randomToken, false);
        vm.assertEq(voter.isWhitelisted(randomToken), false);

        vm.stopPrank();
    }

    function testRevertWhitelistToken() public {
        testVote();

        address randomToken = vm.randomAddress();
        address randomUser = vm.randomAddress();
        vm.startPrank(randomUser);

        vm.expectRevert();
        voter.whitelist(randomToken, true);

        vm.expectRevert();
        voter.whitelist(randomToken, false);

        vm.stopPrank();
    }
}
