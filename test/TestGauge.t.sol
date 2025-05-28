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
import {Pair} from "src/Pair.sol";

interface ICLFactoryExtended is ICLFactory {
    function setVoter(address _voter) external;
}

contract TestGauge is TestBribeFactory {
    address[] gaugeList;

    function testGauge__setUp() public {
        testBribeFactory__setUp();

        vm.startPrank(deployer);

        vm.stopPrank();
    }

    function testCreateGauge() public {
        testGauge__setUp();

        vm.startPrank(address(voter));

        console.log("pair volatile");
        for (uint i; i < pairListVolatile.length; i++) {
            address pairAddress = pairListVolatile[i];

            address[] memory allowedRewards = new address[](1);
            allowedRewards[0] = address(kitten);

            address gaugeAddress = gaugeFactory.createGauge(
                pairAddress,
                internalBribe[pairAddress], // _internal_bribe
                externalBribe[pairAddress], // _external_bribe
                address(veKitten), // veKitten
                true, // _isPool
                allowedRewards
            );

            gaugeList.push(gaugeAddress);

            console.log("pair gauge", pairAddress, gaugeAddress);

            vm.stopPrank();
        }

        console.log("pair stable");
        for (uint i; i < pairListStable.length; i++) {
            address pairAddress = pairListStable[i];

            address[] memory allowedRewards = new address[](1);
            allowedRewards[0] = address(kitten);

            address gaugeAddress = gaugeFactory.createGauge(
                pairAddress,
                internalBribe[pairAddress], // _internal_bribe
                externalBribe[pairAddress], // _external_bribe
                address(veKitten), // veKitten
                true, // _isPool
                allowedRewards
            );

            gaugeList.push(gaugeAddress);

            console.log("pair gauge", pairAddress, gaugeAddress);
        }

        vm.stopPrank();
    }

    function testTransferStuckERC20() public {
        testCreateGauge();

        Gauge gauge = Gauge(gaugeList[0]);

        uint256 emissionAmount = kitten.balanceOf(deployer) / 10;

        vm.startPrank(deployer);

        kitten.approve(address(gauge), emissionAmount);
        gauge.notifyRewardAmount(address(kitten), emissionAmount);

        vm.stopPrank();

        vm.startPrank(veKitten.team());

        uint256 gaugeBalBefore = IERC20(address(kitten)).balanceOf(
            address(gauge)
        );
        uint256 teamBalBefore = IERC20(address(kitten)).balanceOf(
            veKitten.team()
        );
        gauge.transferERC20(address(kitten));

        uint256 gaugeBalAfter = IERC20(address(kitten)).balanceOf(
            address(gauge)
        );
        uint256 teamBalAfter = IERC20(address(kitten)).balanceOf(
            veKitten.team()
        );

        vm.assertEq(
            teamBalAfter - teamBalBefore,
            gaugeBalBefore - gaugeBalAfter
        );
        vm.assertEq(gaugeBalAfter, 0);

        vm.stopPrank();
    }

    function testRevertNotTeamTransferStuckERC20() public {
        testCreateGauge();

        Gauge gauge = Gauge(gaugeList[0]);

        address randomUser = vm.randomAddress();
        vm.startPrank(randomUser);

        vm.expectRevert();
        gauge.transferERC20(address(kitten));

        vm.stopPrank();
    }
}
