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
import {IMinter} from "src/interfaces/IMinter.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import {ProtocolTimeLibrary} from "src/clAMM/libraries/ProtocolTimeLibrary.sol";

/* tests */
import {Base} from "test/base/Base.t.sol";

interface ICLFactoryExtended is ICLFactory {
    function setVoter(address _voter) external;
}

contract TestMinter is Base {
    function testMinter__setUp() public {
        _setUp();
    }

    /* setTreasury tests */
    function test_SetTreasury() public {
        testMinter__setUp();
        vm.prank(deployer);
        minter.setTreasury(deployer);
        assertEq(minter.treasury(), deployer);
    }

    function test_RevertIf_NotOwner_SetTreasury() public {
        testMinter__setUp();
        address randomUser = vm.randomAddress();
        vm.prank(randomUser);
        vm.expectRevert();
        minter.setTreasury(randomUser);
    }

    /* setTreasuryRate tests */
    function test_SetTreasuryRate() public {
        testMinter__setUp();
        uint256 rate = (minter.MAX_TREASURY_RATE() * 50) / 100;
        vm.prank(deployer);
        minter.setTreasuryRate(rate);
        assertEq(minter.treasuryRate(), rate);
    }

    function test_RevertIf_NotOwner_SetTreasuryRate() public {
        testMinter__setUp();
        address randomUser = vm.randomAddress();
        uint256 rate = 100;
        vm.prank(randomUser);
        vm.expectRevert();
        minter.setTreasuryRate(rate);
    }

    function test_RevertIf_TreasuryRateTooHigh_SetTreasuryRate() public {
        testMinter__setUp();
        uint256 maxRate = minter.MAX_TREASURY_RATE();
        uint256 tooHighRate = maxRate + 1;
        vm.prank(deployer);
        vm.expectRevert();
        minter.setTreasuryRate(tooHighRate);
    }

    /* setRebaseRate tests */
    function test_SetRebaseRate() public {
        testMinter__setUp();
        uint256 rate = (minter.MAX_REBASE_RATE() * 50) / 100;
        vm.prank(deployer);
        minter.setRebaseRate(rate);
        assertEq(minter.rebaseRate(), rate);
    }

    function test_RevertIf_NotOwner_SetRebaseRate() public {
        testMinter__setUp();
        address randomUser = vm.randomAddress();
        uint256 rate = 1000;
        vm.prank(randomUser);
        vm.expectRevert();
        minter.setRebaseRate(rate);
    }

    function test_RevertIf_RebaseRateTooHigh_SetRebaseRate() public {
        testMinter__setUp();
        uint256 maxRate = minter.MAX_REBASE_RATE();
        uint256 tooHighRate = maxRate + 1;
        vm.prank(deployer);
        vm.expectRevert();
        minter.setRebaseRate(tooHighRate);
    }

    /* start tests */
    function test_Start() public {
        testMinter__setUp();

        vm.startPrank(address(voter));
        minter.start();
        vm.stopPrank();
    }

    function test_RevertIf_NotVoter_Start() public {
        testMinter__setUp();
        address randomUser = vm.randomAddress();
        vm.prank(randomUser);
        vm.expectRevert();
        minter.start();
    }
}
