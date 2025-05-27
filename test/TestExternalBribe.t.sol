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

import {TestCLFactory} from "test/TestCLFactory.t.sol";
import {TestBribeFactory} from "test/TestBribeFactory.t.sol";

interface ICLFactoryExtended is ICLFactory {
    function setVoter(address _voter) external;
}

contract TestExternalBribe is TestBribeFactory {
    function testExternalBribe__setUp() public {
        testBribeFactory__setUp();

        vm.startPrank(deployer);

        vm.stopPrank();
    }

    function testEarned() public {
        testExternalBribe__setUp();

        ExternalBribe _externalBribe = ExternalBribe(
            externalBribe[poolList[0]]
        );

        uint256 EPOCH = 1 weeks;
        uint256 epochStartTime = (block.timestamp / 1 weeks) * 1 weeks + 1;
        uint256 tokenId = 1;
        uint256 votingPower = 1 ether;

        vm.prank(address(deployer));
        kitten.approve(address(_externalBribe), type(uint256).max);

        // epoch 0
        vm.warp(epochStartTime);
        vm.prank(address(voter));
        _externalBribe._deposit(votingPower, tokenId);
        uint256 epoch0Rewards = 1 ether;

        vm.prank(address(deployer));
        _externalBribe.notifyRewardAmount(address(kitten), epoch0Rewards);

        // epoch 1
        vm.warp(epochStartTime + 1 * EPOCH);
        vm.assertEq(
            _externalBribe.earned(address(kitten), tokenId),
            epoch0Rewards
        );

        vm.startPrank(address(voter));
        _externalBribe._withdraw(votingPower, tokenId);
        _externalBribe._deposit(votingPower, tokenId);
        vm.stopPrank();
        uint256 epoch1Rewards = 1 ether;

        vm.prank(address(deployer));
        _externalBribe.notifyRewardAmount(address(kitten), epoch1Rewards);

        // epoch 2
        vm.warp(epochStartTime + 2 * EPOCH);
        vm.assertEq(
            _externalBribe.earned(address(kitten), tokenId),
            epoch0Rewards + epoch1Rewards
        );

        vm.startPrank(address(voter));
        _externalBribe._withdraw(votingPower, tokenId);
        _externalBribe._deposit(votingPower, tokenId);
        vm.stopPrank();
        uint256 epoch2Rewards = 1 ether;

        vm.prank(address(deployer));
        _externalBribe.notifyRewardAmount(address(kitten), epoch2Rewards);

        // epoch 2
        vm.warp(epochStartTime + 3 * EPOCH);
        vm.assertEq(
            _externalBribe.earned(address(kitten), tokenId),
            epoch0Rewards + epoch1Rewards + epoch2Rewards
        );

        vm.stopPrank();
    }

    function testNoVotePreviousEarned() public {
        testExternalBribe__setUp();

        ExternalBribe _externalBribe = ExternalBribe(
            externalBribe[poolList[0]]
        );

        uint256 EPOCH = 1 weeks;
        uint256 epochStartTime = (block.timestamp / 1 weeks) * 1 weeks + 1;
        uint256 tokenId = 1;
        uint256 votingPower = 1 ether;

        vm.prank(address(deployer));
        kitten.approve(address(_externalBribe), type(uint256).max);

        // epoch 0
        vm.warp(epochStartTime);
        vm.prank(address(voter));
        _externalBribe._deposit(votingPower, tokenId);
        uint256 epoch0Rewards = 1 ether;

        vm.prank(address(deployer));
        _externalBribe.notifyRewardAmount(address(kitten), epoch0Rewards);

        // epoch 1
        vm.warp(epochStartTime + 1 * EPOCH);
        vm.assertEq(
            _externalBribe.earned(address(kitten), tokenId),
            epoch0Rewards
        );

        vm.startPrank(address(voter));
        _externalBribe._withdraw(votingPower, tokenId);
        vm.stopPrank();
        uint256 epoch1Rewards = 1 ether;

        vm.prank(address(deployer));
        _externalBribe.notifyRewardAmount(address(kitten), epoch1Rewards);

        // epoch 2
        vm.warp(epochStartTime + 2 * EPOCH);
        vm.assertEq(
            _externalBribe.earned(address(kitten), tokenId),
            epoch0Rewards
        );

        vm.stopPrank();
    }

    function testSupplyCheckpoints() public {
        testExternalBribe__setUp();

        ExternalBribe _externalBribe = ExternalBribe(
            externalBribe[poolList[0]]
        );

        uint256 EPOCH = 1 weeks;
        uint256 epochStartTime = (block.timestamp / 1 weeks) * 1 weeks;
        uint256 tokenId = 1;
        uint256 votingPower = 1 ether;

        vm.prank(address(deployer));
        kitten.approve(address(_externalBribe), type(uint256).max);

        // epoch 0
        vm.warp(epochStartTime + 1 * EPOCH);
        vm.prank(address(voter));
        _externalBribe._deposit(votingPower, tokenId);

        (, uint _currentSupply) = _externalBribe.supplyCheckpoints(
            _externalBribe.supplyNumCheckpoints() - 1
        );

        vm.assertEq(_currentSupply, votingPower);

        // epoch 1
        vm.warp(epochStartTime + 2 * EPOCH);
        vm.startPrank(address(voter));
        _externalBribe._withdraw(votingPower, tokenId);
        _externalBribe._deposit(votingPower * 2, tokenId);
        vm.stopPrank();

        (, uint _prevSupply) = _externalBribe.supplyCheckpoints(
            _externalBribe.supplyNumCheckpoints() - 2
        );
        (, _currentSupply) = _externalBribe.supplyCheckpoints(
            _externalBribe.supplyNumCheckpoints() - 1
        );

        vm.assertEq(_prevSupply, votingPower);
        vm.assertEq(_currentSupply, votingPower * 2);

        vm.stopPrank();
    }
}
