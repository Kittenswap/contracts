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
import {Base} from "test/base/Base.t.sol";

interface ICLFactoryExtended is ICLFactory {
    function setVoter(address _voter) external;
}

contract TestPairFactory is Base {
    address[] pairListVolatile;
    address[] pairListStable;

    bool PairFactory__setUp;
    function testPairFactory__setUp() public {
        _setUp();

        if (PairFactory__setUp) return;
        PairFactory__setUp = true;

        vm.startPrank(deployer);

        for (uint i; i < tokenList.length; i++) {
            for (uint j; j < i; j++) {
                address pairVolatile = pairFactory.getPair(
                    tokenList[i],
                    tokenList[j],
                    false
                );
                address pairStable = pairFactory.getPair(
                    tokenList[i],
                    tokenList[j],
                    true
                );

                if (pairVolatile != address(0)) {
                    pairListVolatile.push(pairVolatile);
                }
                if (pairStable != address(0)) {
                    pairListStable.push(pairStable);
                }
            }
        }

        vm.stopPrank();

        console.log("tokenList");
        for (uint i; i < tokenList.length; i++) {
            console.log("i", i, tokenList[i]);
        }

        console.log("pairListVolatile");
        for (uint i; i < pairListVolatile.length; i++) {
            console.log("i", i, pairListVolatile[i]);
        }

        console.log("pairListStable");
        for (uint i; i < pairListStable.length; i++) {
            console.log("i", i, pairListStable[i]);
        }
    }
}
