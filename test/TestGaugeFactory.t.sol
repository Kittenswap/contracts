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

contract TestGaugeFactory is TestPairFactory {
    bool GaugeFactory__setUp;
    function testGaugeFactory__setUp() public {
        testPairFactory__setUp();

        if (GaugeFactory__setUp) return;
        GaugeFactory__setUp = true;

        vm.stopPrank();
    }

    function test_CreateGauge() public {
        testGaugeFactory__setUp();

        address _lpToken = vm.randomAddress();
        address votingReward = vm.randomAddress();

        vm.startPrank(address(voter));
        Gauge gauge = Gauge(gaugeFactory.createGauge(_lpToken, votingReward));

        vm.assertEq(address(gauge.lpToken()), _lpToken);
        vm.assertEq(address(gauge.kitten()), address(kitten));
        vm.assertEq(address(gauge.voter()), address(voter));
        vm.assertEq(address(gauge.owner()), deployer);
        vm.assertEq(address(gauge.votingReward()), votingReward);
        vm.stopPrank();
    }

    function test_RevertIf_NotVoter_CreateGauge() public {
        testGaugeFactory__setUp();

        address _lpToken = vm.randomAddress();
        address randomUser = vm.randomAddress();

        address votingReward = vm.randomAddress();

        vm.startPrank(randomUser);
        vm.expectRevert();
        gaugeFactory.createGauge(_lpToken, votingReward);
        vm.stopPrank();
    }
}
