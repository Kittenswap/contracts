pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {Options} from "openzeppelin-foundry-upgrades/Options.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

/* volatile contracts */
import {PairFactory} from "src/factories/PairFactory.sol";
import {Router} from "src/Router.sol";

/* cl contracts */
import {FactoryRegistry} from "src/clAMM/core/FactoryRegistry.sol";
import {ICustomFeeModule} from "src/clAMM/core/interfaces/fees/ICustomFeeModule.sol";
import {ISwapRouter} from "src/clAMM/periphery/interfaces/ISwapRouter.sol";
import {INonfungiblePositionManager} from "src/clAMM/periphery/interfaces/INonfungiblePositionManager.flatten.sol";
import {IQuoterV2} from "src/clAMM/periphery/interfaces/IQuoterV2.sol";
import {ICLFactory} from "src/clAMM/core/interfaces/ICLFactory.sol";
import {ICLPool} from "src/clAMM/core/interfaces/ICLPool.sol";

/* voter contracts */
import {Kitten} from "src/Kitten.sol";
import {VeArtProxy} from "src/VeArtProxy.sol";
import {VotingEscrow} from "src/VotingEscrow.sol";
import {Voter} from "src/Voter.sol";
import {RebaseReward} from "src/reward/RebaseReward.sol";
import {Minter} from "src/Minter.sol";
import {VotingReward} from "src/reward/VotingReward.sol";

/* gauges and voting rewards */
import {GaugeFactory} from "src/gauge/GaugeFactory.sol";
import {CLGaugeFactory} from "src/clAMM/gauge/CLGaugeFactory.sol";
import {VotingRewardFactory} from "src/reward/VotingRewardFactory.sol";
import {Gauge} from "src/gauge/Gauge.sol";
import {CLGauge} from "src/clAMM/gauge/CLGauge.sol";

/* others */
import {IWHYPE9} from "src/interfaces/IWHYPE9.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import {ProtocolTimeLibrary} from "src/clAMM/libraries/ProtocolTimeLibrary.sol";

/* tests */
import {TestPairFactory} from "test/TestPairFactory.t.sol";
import {TestCLFactory} from "test/TestCLFactory.t.sol";
import {TestVotingEscrow} from "test/TestVotingEscrow.t.sol";

interface ICLFactoryExtended is ICLFactory {
    function setVoter(address _voter) external;
}

contract TestVoter is TestPairFactory, TestCLFactory, TestVotingEscrow {
    using EnumerableMap for EnumerableMap.AddressToAddressMap;

    EnumerableMap.AddressToAddressMap gauge;
    address[] gaugeVotingList;

    bool Voter__setUp;
    function testVoter__setUp() public {
        testPairFactory__setUp();
        testCLFactory__setUp();
        testDistributeVeKitten();

        // ensure that all voting tests will initially be set at the beginning of the epoch (vote open)
        // vm.warp(ProtocolTimeLibrary.epochVoteStart(block.timestamp) + 1);
    }

    /* vote tests */
    function test_Vote() public {
        test_CreateGauge();

        vm.warp(ProtocolTimeLibrary.epochNext(block.timestamp) + 1);

        address[] memory gaugeVotingList = gauge.keys(); // list of all pools

        for (uint i; i < gaugeVotingList.length; i++) {
            console.log("voting gauge", gaugeVotingList[i]);
        }

        console.log("/* Voting */");
        for (uint i; i < userList.length; i++) {
            address user1 = userList[i];

            console.log("user", user1);

            vm.startPrank(user1);

            uint256 len = gaugeVotingList.length;

            address[] memory voteList = new address[](len);
            uint256[] memory weightList = new uint256[](len);
            uint256 totalWeight;

            uint256[] memory weightsListBefore = new uint256[](len);
            uint256[] memory votesListBefore = new uint256[](len);

            uint256 tokenId = veKitten.tokenOfOwnerByIndex(user1, 0);

            for (uint256 j; j < len; j++) {
                weightsListBefore[j] = voter.weights(gaugeVotingList[j]);
                votesListBefore[j] = voter.votes(tokenId, gaugeVotingList[j]);

                voteList[j] = gaugeVotingList[j];
                weightList[j] = vm.randomUint(100, 1000);

                console.log("vote", j, voteList[j], weightList[j]);

                totalWeight += weightList[j];
            }

            uint256 voteTime = ProtocolTimeLibrary.epochVoteStart(
                block.timestamp
            ) + vm.randomUint(1, 1 weeks - 2 hours);
            vm.warp(voteTime);

            uint256 lastVotedBefore = voter.lastVoted(tokenId);
            vm.startSnapshotGas("vote");
            voter.vote(tokenId, voteList, weightList);
            uint256 gasUsed = vm.stopSnapshotGas();
            console.log("vote() gasUsed", gasUsed);
            vm.assertGt(voter.lastVoted(tokenId), lastVotedBefore);

            for (uint256 j; j < len; j++) {
                vm.assertEq(voter.poolVote(tokenId, j), voteList[j]);

                uint256 _poolWeight = (weightList[j] *
                    veKitten.balanceOfNFT(tokenId)) / totalWeight;

                vm.assertEq(voter.votes(tokenId, voteList[j]), _poolWeight);
            }

            vm.stopPrank();
        }
    }

    function test_ZeroTotalWeight_Vote() public returns (uint256 tokenId) {
        test_CreateGauge();

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

    function test_RevertIf_NotNewEpoch_Vote() public {
        test_Vote();

        address user1 = userList[0];
        vm.startPrank(user1);
        uint256 tokenId = veKitten.tokenOfOwnerByIndex(user1, 0);
        address[] memory voteList;
        uint256[] memory weightList;
        vm.expectRevert();
        voter.vote(tokenId, voteList, weightList);
        vm.stopPrank();
    }

    function test_RevertWhen_VoteOnStartEpochOneHour_Vote() public {
        test_CreateGauge();

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
            vm.randomUint(0, 1 hours - 1);
        vm.warp(voteTime);

        vm.expectRevert();
        voter.vote(tokenId, voteList, weightList);

        vm.stopPrank();
    }

    function test_RevertIf_InvalidGauge_Vote()
        public
        returns (uint256 tokenId)
    {
        test_CreateGauge();

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

    function test_RevertIf_NotWhitelisted_VoteOnEndEpochOneHour_Vote() public {
        test_CreateGauge();

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

    function test_WhitelistedVoteOnEndEpochOneHour_Vote() public {
        test_CreateGauge();

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

    function test_RevertIf_NotApproved_Vote() public {
        test_CreateGauge();

        address user1 = userList[0];
        address randomUser = vm.randomAddress();
        address[] memory poolList;
        uint256[] memory weightList;
        uint256 tokenId = veKitten.tokenOfOwnerByIndex(user1, 0);

        vm.startPrank(randomUser);
        vm.expectRevert();
        voter.vote(tokenId, poolList, weightList);
        vm.stopPrank();
    }

    function test_RevertIf_InvalidParameters_Vote() public {
        test_CreateGauge();

        address user1 = userList[0];
        address[] memory poolList;
        uint256[] memory weightList = new uint256[](1);
        uint256 tokenId = veKitten.tokenOfOwnerByIndex(user1, 0);

        vm.startPrank(user1);
        vm.expectRevert();
        voter.vote(tokenId, poolList, weightList);
        vm.stopPrank();
    }

    function test_RevertIf_AlredyVotedForPool_Vote() public {
        test_CreateGauge();

        address[] memory gaugeVotingList = gauge.keys(); // list of all pools

        for (uint i; i < gaugeVotingList.length; i++) {
            console.log("voting gauge", gaugeVotingList[i]);
        }

        console.log("/* Voting */");
        for (uint i; i < userList.length; i++) {
            address user1 = userList[i];

            console.log("user", user1);

            vm.startPrank(user1);

            uint256 len = gaugeVotingList.length;

            address[] memory voteList = new address[](len);
            uint256[] memory weightList = new uint256[](len);
            uint256 totalWeight;

            uint256[] memory weightsListBefore = new uint256[](len);
            uint256[] memory votesListBefore = new uint256[](len);

            uint256 tokenId = veKitten.tokenOfOwnerByIndex(user1, 0);

            for (uint256 j; j < len; j++) {
                weightsListBefore[j] = voter.weights(gaugeVotingList[j]);
                votesListBefore[j] = voter.votes(tokenId, gaugeVotingList[j]);

                voteList[j] = gaugeVotingList[j];
                weightList[j] = vm.randomUint(100, 1000);

                console.log("vote", j, voteList[j], weightList[j]);

                totalWeight += weightList[j];
            }
            voteList[voteList.length - 1] = voteList[0];

            uint256 voteTime = ProtocolTimeLibrary.epochVoteStart(
                block.timestamp
            ) + vm.randomUint(1, 1 weeks - 2 hours);
            vm.warp(voteTime);

            vm.expectRevert();
            voter.vote(tokenId, voteList, weightList);
            vm.stopPrank();
        }
    }

    /* reset tests */
    function test_Reset() public {
        test_Vote();

        vm.warp(ProtocolTimeLibrary.epochNext(block.timestamp));

        address user1 = userList[0];
        vm.startPrank(user1);
        uint256 tokenId = veKitten.tokenOfOwnerByIndex(user1, 0);

        uint256 len = voter.poolVoteLength(tokenId);
        address[] memory poolVote = new address[](len);

        for (uint256 i; i < len; i++) {
            poolVote[i] = voter.poolVote(tokenId, i);
        }

        voter.reset(tokenId);
        vm.assertEq(voter.poolVoteLength(tokenId), 0);
        vm.assertEq(veKitten.voted(tokenId), false); // abstained
        vm.stopPrank();
    }

    function test_RevertIf_NotNewEpoch_Reset() public {
        test_Vote();

        address user1 = userList[0];
        vm.startPrank(user1);
        uint256 tokenId = veKitten.tokenOfOwnerByIndex(user1, 0);
        vm.expectRevert();
        voter.reset(tokenId);
        vm.stopPrank();
    }

    function test_RevertIf_NotApproved_Reset() public {
        test_Vote();

        vm.warp(ProtocolTimeLibrary.epochNext(block.timestamp));

        address user1 = userList[0];
        address randomUser = vm.randomAddress();
        vm.startPrank(randomUser);
        uint256 tokenId = veKitten.tokenOfOwnerByIndex(user1, 0);
        vm.expectRevert();
        voter.reset(tokenId);
        vm.stopPrank();
    }

    /* Poke tests */
    function test_Poke() public {
        test_Vote();

        vm.warp(block.timestamp + 1 weeks + 1);
        for (uint i; i < userList.length; i++) {
            uint256 tokenId = veKitten.tokenOfOwnerByIndex(userList[i], 0);
            uint256 len = voter.poolVoteLength(tokenId);
            address[] memory poolVoteBefore = new address[](len);
            uint256[] memory votesBefore = new uint256[](len);

            for (uint256 j; j < len; j++) {
                poolVoteBefore[j] = voter.poolVote(tokenId, j);
                votesBefore[j] = voter.votes(tokenId, poolVoteBefore[j]);
            }

            // allow anyone to poke
            voter.poke(tokenId);

            for (uint256 j; j < len; j++) {
                uint256 votesAfter = voter.votes(tokenId, poolVoteBefore[j]);
                vm.assertLt(votesAfter, votesBefore[j]);
            }
        }
    }

    function test_NotRevertOnPokeVotesForDustWeight_Vote() public {
        test_CreateGauge();

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

    function test_PokeNoEffectOnNewEpoch_Poke() public {
        test_Vote();

        vm.warp(block.timestamp + 1 weeks + 1);
        voter.distro();

        uint256 tokenId = veKitten.tokenOfOwnerByIndex(userList[0], 0);
        uint256 len = voter.poolVoteLength(tokenId);
        address[] memory poolVoteBefore = new address[](len);
        uint256[] memory votesBefore = new uint256[](len);

        for (uint256 j; j < len; j++) {
            poolVoteBefore[j] = voter.poolVote(tokenId, j);
            votesBefore[j] = voter.votes(tokenId, poolVoteBefore[j]);
        }

        // allow anyone to poke
        voter.poke(tokenId);

        for (uint256 j; j < len; j++) {
            uint256 votesAfter = voter.votes(tokenId, poolVoteBefore[j]);
            vm.assertLt(votesAfter, votesBefore[j]);
        }
    }

    function test_PokeDoesNotPreventVotingNewEpoch_Poke() public {
        test_PokeNoEffectOnNewEpoch_Poke();

        test_Vote();
    }

    /* notifyRewardAmount tests */
    function test_Voter_NotifyRewardAmount() public {
        test_Vote();

        vm.startPrank(deployer);
        uint256 amount = (kitten.balanceOf(deployer) *
            vm.randomUint(1 ether, 100 ether)) / 100 ether;
        kitten.approve(address(voter), amount);

        uint256 indexBefore = voter.index();
        vm.startSnapshotGas("notifyRewardAmount");
        voter.notifyRewardAmount(amount);
        uint256 gasUsed = vm.stopSnapshotGas("notifyRewardAmount");
        console.log("gasUsed:", gasUsed);
        uint256 indexAfter = voter.index();

        uint256 ratio = (amount * 1 ether) / voter.totalWeight();
        vm.assertEq(indexAfter - indexBefore, ratio);
    }

    /* updateAll tests */
    function test_UpdateAll() public {
        test_Voter_NotifyRewardAmount();

        voter.updateAll();
    }

    /* claimEmissionsBatch tests */
    function test_ClaimEmissionsBatch() public {
        test_Distro();

        // deposit cl pool
        for (uint k; k < userList.length; k++) {
            address user1 = userList[k];

            console.log("user", user1);
            for (uint i; i < poolList.length; i++) {
                ICLPool pool = ICLPool(poolList[i]);

                CLGauge clGauge = CLGauge(gauge.get(address(pool)));

                address token0 = ICLPool(pool).token0();
                address token1 = ICLPool(pool).token1();

                if (token0 == address(WHYPE) || token1 == address(WHYPE)) {
                    vm.startPrank(user1);
                    vm.deal(user1, 1_000 ether);
                    WHYPE.deposit{value: 1_000 ether}();
                    vm.stopPrank();
                }

                if (token0 != address(WHYPE)) {
                    vm.startPrank(whale[token0]);
                    IERC20(token0).transfer(
                        user1,
                        (IERC20(token0).balanceOf(whale[token0]) *
                            vm.randomUint(1, 5_000)) / 10_000
                    );
                    vm.stopPrank();
                }

                if (token1 != address(WHYPE)) {
                    vm.startPrank(whale[token1]);
                    IERC20(token1).transfer(
                        user1,
                        (IERC20(token1).balanceOf(whale[token1]) *
                            vm.randomUint(1, 5_000)) / 10_000
                    );
                    vm.stopPrank();
                }

                vm.startPrank(user1);

                int24 tickSpacing = ICLPool(pool).tickSpacing();

                IERC20(token0).approve(
                    address(nfp),
                    IERC20(token0).balanceOf(user1)
                );
                IERC20(token1).approve(
                    address(nfp),
                    IERC20(token1).balanceOf(user1)
                );
                INonfungiblePositionManager.MintParams
                    memory params = INonfungiblePositionManager.MintParams({
                        token0: token0,
                        token1: token1,
                        tickSpacing: tickSpacing,
                        tickLower: (-887272 / tickSpacing) *
                            tickSpacing +
                            tickSpacing,
                        tickUpper: (887272 / tickSpacing) * tickSpacing,
                        amount0Desired: IERC20(token0).balanceOf(user1) / 2,
                        amount1Desired: IERC20(token1).balanceOf(user1) / 2,
                        amount0Min: 0,
                        amount1Min: 0,
                        recipient: user1,
                        deadline: block.timestamp + 60 * 20,
                        sqrtPriceX96: 0
                    });
                (uint256 nfpTokenId, , , ) = nfp.mint(params);

                IERC20(token0).approve(
                    address(swapRouter),
                    IERC20(token0).balanceOf(user1)
                );

                nfp.setApprovalForAll(address(clGauge), true);
                clGauge.deposit(nfpTokenId);

                vm.assertEq(nfp.ownerOf(nfpTokenId), address(clGauge));

                uint256[] memory stakedNFPs = clGauge.getUserStakedNFPs(user1);
                bool containsNfpTokenId;
                for (uint j; j < stakedNFPs.length; j++) {
                    if (stakedNFPs[j] == nfpTokenId) {
                        containsNfpTokenId = true;
                        break;
                    }
                }
                vm.assertTrue(containsNfpTokenId);
                console.log("nfpTokenId", nfpTokenId);

                vm.stopPrank();
            }
        }

        vm.warp(ProtocolTimeLibrary.epochNext(block.timestamp) + 1 weeks);

        address[] memory gaugeList = new address[](poolList.length);

        for (uint256 i; i < poolList.length; i++) {
            gaugeList[i] = gauge.get(poolList[i]);
        }

        for (uint256 i; i < userList.length; i++) {
            address user1 = userList[i];

            vm.startPrank(user1);
            voter.claimEmissionsBatch(gaugeList);
        }
    }

    /* claimVotingRewardBatch tests */
    function test_ClaimVotingRewardBatch() public {
        test_Distro();

        uint256 len = gauge.length();
        address[] memory votingRewardList = new address[](len);

        for (uint256 i; i < len; i++) {
            (, address _gauge) = gauge.at(i);
            votingRewardList[i] = voter.votingReward(_gauge);
        }

        address user1 = userList[0];
        uint256 tokenId = veKitten.tokenOfOwnerByIndex(user1, 0);

        vm.startPrank(user1);
        voter.claimVotingRewardBatch(votingRewardList, tokenId);
    }

    function test_ApprovedClaimFor_ClaimVotingRewardBatch() public {
        test_Distro();

        uint256 len = gauge.length();
        address[] memory votingRewardList = new address[](len);

        for (uint256 i; i < len; i++) {
            (, address _gauge) = gauge.at(i);
            votingRewardList[i] = voter.votingReward(_gauge);
        }

        address user1 = userList[0];
        uint256 tokenId = veKitten.tokenOfOwnerByIndex(user1, 0);

        address randomUser = vm.randomAddress();
        vm.prank(user1);
        veKitten.approve(randomUser, tokenId);

        vm.startPrank(randomUser);
        voter.claimVotingRewardBatch(votingRewardList, tokenId);
    }

    function test_RevertIf_NotApproved_ClaimVotingRewardBatch() public {
        test_Distro();

        address randomUser = vm.randomAddress();
        address[] memory votingRewardList;
        address user1 = userList[0];
        uint256 tokenId = veKitten.tokenOfOwnerByIndex(user1, 0);

        vm.startPrank(randomUser);
        vm.expectRevert();
        voter.claimVotingRewardBatch(votingRewardList, tokenId);
    }

    function test_Distro() public {
        test_Vote();

        vm.warp(ProtocolTimeLibrary.epochStart(block.timestamp + 1 weeks));
        vm.startSnapshotGas("distro");
        voter.distro();
        uint256 gasUsed = vm.stopSnapshotGas();

        address[] memory gaugeVotingList = gauge.keys();
        for (uint i; i < gaugeVotingList.length; i++) {
            address _gauge = voter.gauges(gaugeVotingList[i]);
            console.log("");
            console.log("gauge data:", _gauge);
            console.log(
                "symbol",
                IERC20(ICLPool(gaugeVotingList[i]).token0()).symbol(),
                IERC20(ICLPool(gaugeVotingList[i]).token1()).symbol()
            );
            console.log("emissions ->", kitten.balanceOf(_gauge));
            VotingReward _votingReward = VotingReward(
                voter.votingReward(_gauge)
            );
            console.log("voting fees:", address(_votingReward));
            address[] memory rewardList = _votingReward.getRewardList();
            for (uint j; j < rewardList.length; j++) {
                console.log(
                    rewardList[j],
                    IERC20(rewardList[j]).balanceOf(address(_votingReward))
                );
            }
        }
    }

    function test_SameEpoch_Distro() public {
        test_Vote();

        vm.warp(
            vm.randomUint(
                ProtocolTimeLibrary.epochStart(block.timestamp),
                ProtocolTimeLibrary.epochStart(block.timestamp + 1 weeks)
            )
        );
        voter.distro();

        address[] memory gaugeVotingList = gauge.keys();
        for (uint i; i < gaugeVotingList.length; i++) {
            address _gauge = voter.gauges(gaugeVotingList[i]);
            console.log("");
            console.log("gauge data:", _gauge);
            console.log(
                "symbol",
                IERC20(ICLPool(gaugeVotingList[i]).token0()).symbol(),
                IERC20(ICLPool(gaugeVotingList[i]).token1()).symbol()
            );
            console.log("emissions ->", kitten.balanceOf(_gauge));
            VotingReward _votingReward = VotingReward(
                voter.votingReward(_gauge)
            );
            console.log("voting fees:", address(_votingReward));
            address[] memory rewardList = _votingReward.getRewardList();
            for (uint j; j < rewardList.length; j++) {
                console.log(
                    rewardList[j],
                    IERC20(rewardList[j]).balanceOf(address(_votingReward))
                );
            }
        }
    }

    /* init tests */
    function test_WithNewMinter_Init() public {
        testVoter__setUp();

        vm.startPrank(deployer);
        Options memory opts;
        opts.unsafeSkipAllChecks = true;
        Minter newMinter = Minter(
            Upgrades.deployUUPSProxy(
                "Minter.sol",
                abi.encodeCall(
                    Minter.initialize,
                    (
                        address(voter),
                        address(veKitten),
                        address(rebaseReward),
                        multisig
                    )
                ),
                opts
            )
        );

        address[] memory tokenList;
        voter.init(tokenList, address(newMinter));
        vm.stopPrank();

        vm.assertEq(
            newMinter.lastMintedPeriod(),
            block.timestamp / ProtocolTimeLibrary.WEEK
        );
    }

    function test_RevertIf_NotOwner_Init() public {
        testVoter__setUp();

        address randomUser = vm.randomAddress();
        address randomMinter = vm.randomAddress();
        vm.startPrank(randomUser);
        address[] memory tokenList;
        vm.expectRevert();
        voter.init(tokenList, randomMinter);
        vm.stopPrank();
    }

    /* setMinter function */
    function test_SetMinter() public {
        testVoter__setUp();

        address newMinter = vm.randomAddress();
        vm.startPrank(deployer);
        voter.setMinter(newMinter);
        vm.stopPrank();
    }

    function test_RevertIf_NotOwner_SetMinter() public {
        testVoter__setUp();

        address randomUser = vm.randomAddress();
        address newMinter = vm.randomAddress();
        vm.startPrank(randomUser);
        vm.expectRevert();
        voter.setMinter(newMinter);
        vm.stopPrank();
    }

    /* setRebaseReward function */
    function test_SetRebaseReward() public {
        testVoter__setUp();

        address newRebaseReward = vm.randomAddress();
        vm.startPrank(deployer);
        voter.setRebaseReward(newRebaseReward);
        vm.stopPrank();
    }

    function test_RevertIf_NotOwner_SetRebaseReward() public {
        testVoter__setUp();

        address randomUser = vm.randomAddress();
        address newRebaseReward = vm.randomAddress();
        vm.startPrank(randomUser);
        vm.expectRevert();
        voter.setRebaseReward(newRebaseReward);
        vm.stopPrank();
    }

    /* whitelist tests */
    function test_WhitelistToken_Whitelist() public {
        test_Vote();

        address randomToken = vm.randomAddress();
        vm.startPrank(deployer);

        voter.whitelist(randomToken, true);
        vm.assertEq(voter.isWhitelisted(randomToken), true);
        voter.whitelist(randomToken, false);
        vm.assertEq(voter.isWhitelisted(randomToken), false);

        vm.stopPrank();
    }

    function test_RevertIf_NotRole_AUTHORIZED_ROLE_Whitelist() public {
        test_Vote();

        address randomToken = vm.randomAddress();
        address randomUser = vm.randomAddress();
        vm.startPrank(randomUser);

        vm.expectRevert();
        voter.whitelist(randomToken, true);

        vm.expectRevert();
        voter.whitelist(randomToken, false);

        vm.stopPrank();
    }

    /* Set whitelist tokenId tests  */
    function test_SetWhitelistTokenId() public {
        _setUp();

        uint256 tokenId = vm.randomUint(1, 10_000);

        vm.startPrank(deployer);

        address authorizedAddress = multisig;
        voter.grantRole(voter.AUTHORIZED_ROLE(), authorizedAddress);

        // owner set whitelist tokenId
        voter.setWhitelistTokenId(tokenId, true);
        voter.setWhitelistTokenId(tokenId, false);

        vm.stopPrank();

        vm.startPrank(authorizedAddress);

        // authorized set whitelist tokenId
        voter.setWhitelistTokenId(tokenId, true);
        voter.setWhitelistTokenId(tokenId, false);

        vm.stopPrank();
    }

    function test_RevertIf_NotRole_AUTHORIZED_ROLE_SetWhitelistTokenId()
        public
    {
        _setUp();

        address notAuthorizedAddress = vm.randomAddress();
        vm.startPrank(notAuthorizedAddress);

        uint256 tokenId = vm.randomUint(1, 10_000);
        vm.expectRevert();
        voter.setWhitelistTokenId(tokenId, true);

        vm.stopPrank();
    }

    // for all gauges and cl gauges
    bool Voter__CreateGauge__setUp;
    function test_CreateGauge() public {
        if (Voter__CreateGauge__setUp) return;
        Voter__CreateGauge__setUp = true;

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
            vm.assertEq(
                voter.votingReward(_gauge),
                address(Gauge(_gauge).votingReward())
            );

            gauge.set(pairListVolatile[i], _gauge);
            console.log("gauge", pairListVolatile[i], _gauge);
            console.log("votingReward", voter.votingReward(_gauge));
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

            gauge.set(pairListStable[i], _gauge);
            console.log("gauge", pairListStable[i], _gauge);
            console.log("votingReward", voter.votingReward(_gauge));
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

            gauge.set(poolList[i], _gauge);
            console.log("gauge", poolList[i], _gauge);
            console.log("votingReward", voter.votingReward(_gauge));
        }

        vm.stopPrank();
    }

    /* Kill gauge tests */
    function test_KillGauge() public {
        test_Vote();

        vm.warp(block.timestamp + 1 weeks);

        minter.updatePeriod();
        voter.updateAll();

        vm.startPrank(deployer);
        for (uint i; i < poolList.length; i++) {
            address _gauge = gauge.get(poolList[i]);
            uint256 _claimable = voter.claimable(_gauge);
            uint256 minterBalBefore = kitten.balanceOf(address(minter));
            voter.killGauge(_gauge);
            uint256 minterBalAfter = kitten.balanceOf(address(minter));

            vm.assertEq(minterBalAfter - minterBalBefore, _claimable);
            vm.assertTrue(voter.isAlive(_gauge) == false);
        }
        vm.stopPrank();
    }

    function test_RevertIf_AlreadyDead_KillGauge() public {
        test_Vote();

        vm.warp(block.timestamp + 1 weeks);

        minter.updatePeriod();
        voter.updateAll();

        vm.startPrank(deployer);
        for (uint i; i < poolList.length; i++) {
            address _gauge = gauge.get(poolList[i]);
            voter.killGauge(_gauge);
        }

        for (uint i; i < poolList.length; i++) {
            address _gauge = gauge.get(poolList[i]);
            vm.expectRevert();
            voter.killGauge(_gauge);
        }
        vm.stopPrank();
    }

    function test_RevertIf_NotRole_AUTHORIZED_ROLE_KillGauge() public {
        test_Vote();

        vm.warp(block.timestamp + 1 weeks);

        minter.updatePeriod();
        voter.updateAll();

        vm.startPrank(vm.randomAddress());
        for (uint i; i < poolList.length; i++) {
            address _gauge = gauge.get(poolList[i]);
            vm.expectRevert();
            voter.killGauge(_gauge);
        }

        vm.stopPrank();
    }

    function test_ReviveGauge() public {
        test_Vote();

        address pool = poolList[0];
        address _gauge = gauge.get(pool);

        address user1 = vm.randomAddress();

        vm.startPrank(deployer);
        kitten.approve(address(veKitten), type(uint256).max);
        veKitten.create_lock_for(
            (kitten.balanceOf(deployer) * vm.randomUint(1, 100)) / 100,
            52 weeks,
            user1
        );
        vm.stopPrank();

        uint256 tokenId = veKitten.tokenOfOwnerByIndex(user1, 0);

        address[] memory voteList = new address[](1);
        uint256[] memory weightList = new uint256[](1);

        voteList[0] = pool;
        weightList[0] = 100;

        vm.prank(user1);
        voter.vote(tokenId, voteList, weightList);

        vm.warp(block.timestamp + 1 weeks);

        minter.updatePeriod();
        voter.updateAll();

        uint256 claimableEpoch1 = voter.claimable(_gauge);
        // vm.assertEq(claimableEpoch1, 0);

        vm.prank(deployer);
        voter.killGauge(_gauge);

        vm.warp(block.timestamp + 1 weeks);

        minter.updatePeriod();
        voter.updateAll();

        uint256 claimableEpoch2 = voter.claimable(_gauge);
        vm.assertEq(claimableEpoch2, 0);

        for (uint i; i < 10; i++) {
            vm.warp(block.timestamp + 1 weeks);

            minter.updatePeriod();
            voter.updateAll();
        }

        vm.prank(deployer);
        voter.reviveGauge(_gauge);

        vm.warp(block.timestamp + 1 weeks);

        uint256 voterBalBefore = kitten.balanceOf(address(voter));
        minter.updatePeriod();
        voter.updateAll();
        uint256 voterBalAfter = kitten.balanceOf(address(voter));

        uint256 emissions = voterBalAfter - voterBalBefore;

        uint256 poolWeight = voter.weights(pool);

        uint256 claimableEpoch3 = voter.claimable(_gauge);
        {
            console.log("emissions", emissions);
            console.log("weights", poolWeight, voter.totalWeight());
            console.log(
                "emitted to pool",
                (emissions * poolWeight) / voter.totalWeight(),
                emissions
            );
        }

        // percentage emissions should be same
        vm.assertEq(
            (((emissions * poolWeight) / voter.totalWeight()) * 1 ether) /
                emissions,
            (poolWeight * 1 ether) / voter.totalWeight()
        );
    }

    function test_RevertIf_NotRole_AUTHORIZED_ROLE_ReviveGauge() public {
        test_Vote();

        vm.prank(deployer);
        voter.killGauge(gauge.get(poolList[0]));

        address randomUser = vm.randomAddress();
        vm.prank(randomUser);
        vm.expectRevert();
        voter.reviveGauge(gauge.get(poolList[0]));
    }

    function test_NotUnlimitedMinting_Minter_UpdatePeriod() public {
        test_Vote();
        vm.warp(block.timestamp + 1 weeks);

        // should correctly minter for next epoch
        uint256 totalSupplyBefore = kitten.totalSupply();
        minter.updatePeriod();
        uint256 totalSupplyAfter = kitten.totalSupply();
        vm.assertGt(totalSupplyAfter, totalSupplyBefore);
        totalSupplyBefore = totalSupplyAfter;

        // should not mint for current epoch
        for (uint256 i; i < 10; i++) {
            minter.updatePeriod();
            uint256 totalSupplyAfter = kitten.totalSupply();
            vm.assertEq(totalSupplyAfter, totalSupplyBefore);
            totalSupplyBefore = totalSupplyAfter;
        }
    }
}
