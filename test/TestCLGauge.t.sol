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

interface ICLFactoryExtended is ICLFactory {
    function setVoter(address _voter) external;
}

contract TestCLGauge is TestCLFactory {
    address[] clGaugeList;

    function testCLGauge__setUp() public {
        testCLFactory__setUp();

        vm.startPrank(deployer);

        vm.stopPrank();
    }

    function testCreateCLGauge() public {
        testCLGauge__setUp();

        vm.startPrank(address(voter));

        for (uint i; i < poolList.length; i++) {
            address poolAddress = poolList[i];
            address gaugeAddress = clGaugeFactory.createGauge(
                poolAddress,
                vm.randomAddress(), // _internal_bribe
                vm.randomAddress(), // _kitten
                true // _isPool
            );

            CLGauge gauge = CLGauge(gaugeAddress);

            vm.assertEq(ICLPool(poolAddress).gauge(), gaugeAddress);

            vm.stopPrank();

            vm.startPrank(deployer);
            gauge.acceptOwnership();
            vm.stopPrank();

            vm.startPrank(address(voter));
            vm.assertEq(gauge.owner(), deployer);
        }

        vm.stopPrank();
    }

    // require(msg.sender == voter, "Only voter can create gauge");
    function testCreateCLGaugeUnauthorized() public {
        testCLGauge__setUp();

        address caller = vm.randomAddress();
        vm.startPrank(caller);

        for (uint i; i < poolList.length; i++) {
            vm.expectRevert();
            clGaugeFactory.createGauge(
                poolList[i],
                vm.randomAddress(),
                vm.randomAddress(),
                true
            );
        }

        vm.stopPrank();
    }
}
