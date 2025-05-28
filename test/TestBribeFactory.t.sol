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
import {TestPairFactory} from "test/TestPairFactory.t.sol";
import {IPair} from "src/interfaces/IPair.sol";

interface ICLFactoryExtended is ICLFactory {
    function setVoter(address _voter) external;
}

contract TestBribeFactory is TestCLFactory, TestPairFactory {
    mapping(address poolAddress => address) internalBribe;
    mapping(address poolAddress => address) externalBribe;

    function testBribeFactory__setUp() public {
        testCLFactory__setUp();
        testPairFactory__setUp();

        vm.startPrank(address(voter));

        for (uint i; i < poolList.length; i++) {
            address pool = poolList[i];

            address[] memory internalRewardList = new address[](2);
            internalRewardList[0] = ICLPool(pool).token0();
            internalRewardList[1] = ICLPool(pool).token1();

            address[] memory externalRewardList = new address[](3);
            externalRewardList[0] = address(kitten);
            externalRewardList[1] = ICLPool(pool).token0();
            externalRewardList[2] = ICLPool(pool).token1();

            internalBribe[pool] = bribeFactory.createInternalBribe(
                internalRewardList
            );
            externalBribe[pool] = bribeFactory.createExternalBribe(
                externalRewardList
            );

            console.log("pool bribes", pool);
            console.log("internal bribe", internalBribe[pool]);
            console.log("external bribe", externalBribe[pool]);
        }

        for (uint i; i < pairListVolatile.length; i++) {
            address pair = pairListVolatile[i];

            address[] memory internalRewardList = new address[](2);
            (internalRewardList[0], internalRewardList[1]) = IPair(pair)
                .tokens();

            address[] memory externalRewardList = new address[](3);
            externalRewardList[0] = address(kitten);
            externalRewardList[1] = internalRewardList[0];
            externalRewardList[2] = internalRewardList[1];

            internalBribe[pair] = bribeFactory.createInternalBribe(
                internalRewardList
            );
            externalBribe[pair] = bribeFactory.createExternalBribe(
                externalRewardList
            );

            console.log("pair bribes", pair);
            console.log("internal bribe", internalBribe[pair]);
            console.log("external bribe", externalBribe[pair]);
        }

        vm.stopPrank();
    }
}
