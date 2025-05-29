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

contract TestCLFactory is Base {
    address[] poolList;

    int24[] tickSpacings;

    bool CLFactory__setUp;
    function testCLFactory__setUp() public {
        _setUp();

        if (CLFactory__setUp) return;
        CLFactory__setUp = true;

        vm.startPrank(deployer);

        tickSpacings = clFactory.tickSpacings();

        for (uint i; i < tokenList.length; i++) {
            for (uint j; j < i; j++) {
                for (uint k; k < tickSpacings.length; k++) {
                    address pool = clFactory.getPool(
                        tokenList[i],
                        tokenList[j],
                        tickSpacings[k]
                    );

                    if (pool != address(0)) {
                        poolList.push(pool);
                    }
                }
            }
        }

        vm.stopPrank();

        console.log("tickSpacings");
        for (uint i; i < tickSpacings.length; i++) {
            console.log("i", tickSpacings[i]);
        }

        console.log("poolList");
        for (uint i; i < poolList.length; i++) {
            console.log("i", poolList[i]);
        }
    }
}
