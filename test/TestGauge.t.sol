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
import {TestVoter} from "test/TestVoter.t.sol";

interface ICLFactoryExtended is ICLFactory {
    function setVoter(address _voter) external;
}

contract TestGauge is TestVoter {
    using EnumerableMap for EnumerableMap.AddressToAddressMap;

    bool Gauge__setUp;
    function testGauge__setUp() public {
        test_Vote();

        if (Gauge__setUp) return;
        Gauge__setUp = true;

        vm.startPrank(deployer);

        vm.stopPrank();
    }

    // function testTransferStuckERC20() public {
    //     test_CreateGauge();

    //     Gauge gauge = Gauge(gauge.get(pairListVolatile[0]));

    //     vm.prank(kitten.minter());
    //     kitten.mint(address(voter), 1 ether);

    //     uint256 emissionAmount = kitten.balanceOf(address(voter));

    //     vm.startPrank(address(voter));

    //     kitten.approve(address(gauge), emissionAmount);
    //     gauge.notifyRewardAmount(address(kitten), emissionAmount);

    //     vm.stopPrank();

    //     vm.startPrank(veKitten.team());

    //     uint256 gaugeBalBefore = IERC20(address(kitten)).balanceOf(
    //         address(gauge)
    //     );
    //     uint256 teamBalBefore = IERC20(address(kitten)).balanceOf(
    //         veKitten.team()
    //     );
    //     gauge.transferERC20(address(kitten));

    //     uint256 gaugeBalAfter = IERC20(address(kitten)).balanceOf(
    //         address(gauge)
    //     );
    //     uint256 teamBalAfter = IERC20(address(kitten)).balanceOf(
    //         veKitten.team()
    //     );

    //     vm.assertEq(
    //         teamBalAfter - teamBalBefore,
    //         gaugeBalBefore - gaugeBalAfter
    //     );
    //     vm.assertEq(gaugeBalAfter, 0);

    //     vm.stopPrank();
    // }

    // function testRevertNotTeamTransferStuckERC20() public {
    //     test_CreateGauge();

    //     Gauge gauge = Gauge(gauge[pairListVolatile[0]]);

    //     address randomUser = vm.randomAddress();
    //     vm.startPrank(randomUser);

    //     vm.expectRevert();
    //     gauge.transferERC20(address(kitten));

    //     vm.stopPrank();
    // }

    function testNotifyRewardAmount() public {
        test_CreateGauge();

        for (uint i; i < pairListVolatile.length; i++) {
            Gauge _gauge = Gauge(gauge.get(pairListVolatile[i]));

            vm.prank(kitten.minter());
            kitten.mint(address(voter), 1 ether);

            uint256 gaugeBalBefore = kitten.balanceOf(address(_gauge));
            vm.prank(address(voter));
            _gauge.notifyRewardAmount(1 ether);
            uint256 gaugeBalAfter = kitten.balanceOf(address(_gauge));

            vm.assertEq(1 ether, gaugeBalAfter - gaugeBalBefore);
        }
    }

    function testNotifyRewardAmount_AUTHORIZED_ROLE() public {
        test_CreateGauge();

        for (uint i; i < pairListVolatile.length; i++) {
            Gauge _gauge = Gauge(gauge.get(pairListVolatile[i]));

            bytes32 role = _gauge.AUTHORIZED_ROLE();
            address randomUser = vm.randomAddress();
            vm.prank(deployer);
            _gauge.grantRole(role, randomUser);

            vm.prank(kitten.minter());
            kitten.mint(randomUser, 1 ether);

            uint256 gaugeBalBefore = kitten.balanceOf(address(_gauge));
            vm.startPrank(randomUser);
            kitten.approve(address(_gauge), 1 ether);
            _gauge.notifyRewardAmount(1 ether);
            vm.stopPrank();
            uint256 gaugeBalAfter = kitten.balanceOf(address(_gauge));

            vm.assertEq(1 ether, gaugeBalAfter - gaugeBalBefore);
        }
    }

    function testRevertNotVoterNotifyRewardAmount() public {
        test_CreateGauge();

        for (uint i; i < pairListVolatile.length; i++) {
            Gauge _gauge = Gauge(gauge.get(pairListVolatile[i]));

            address randomUser = vm.randomAddress();
            vm.prank(randomUser);
            vm.expectRevert();
            _gauge.notifyRewardAmount(1 ether);
        }
    }

    function testGrantRole_AUTHORIZED_ROLE() public {
        test_CreateGauge();

        Gauge _gauge = Gauge(gauge.get(pairListVolatile[0]));
        bytes32 role = _gauge.AUTHORIZED_ROLE();
        address randomUser = vm.randomAddress();
        vm.prank(deployer);
        _gauge.grantRole(role, randomUser);
    }

    function testGetReward() public {
        test_CreateGauge();

        address pool = pairListVolatile[0];
        Gauge _gauge = Gauge(gauge.get(pool));

        address token0 = ICLPool(pool).token0();
        address token1 = ICLPool(pool).token1();

        address user1 = userList[0];

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
        IERC20(token0).approve(address(router), type(uint256).max);
        IERC20(token1).approve(address(router), type(uint256).max);
        router.addLiquidity(
            token0,
            token1,
            false,
            IERC20(token0).balanceOf(user1),
            IERC20(token1).balanceOf(user1),
            0,
            0,
            user1,
            block.timestamp + 60 * 20
        );
        vm.stopPrank();

        vm.prank(address(minter));
        kitten.mint(address(voter), 1 ether);
        vm.prank(address(voter));
        _gauge.notifyRewardAmount(1 ether);

        vm.startPrank(user1);
        IERC20(pool).approve(address(_gauge), type(uint256).max);
        _gauge.deposit(IERC20(pool).balanceOf(user1));

        vm.warp(block.timestamp + 1 weeks);

        _gauge.getReward(user1);
        vm.stopPrank();
    }

    function test_Deposit() public {
        test_CreateGauge();

        address pool = pairListVolatile[0];
        Gauge _gauge = Gauge(gauge.get(pool));

        address user1 = userList[0];

        deal(pool, user1, 1 ether);
        vm.startPrank(user1);

        IERC20(pool).approve(address(_gauge), type(uint256).max);
        _gauge.deposit(IERC20(pool).balanceOf(user1));

        vm.stopPrank();
    }

    function test_RevertIf_NotGaugeOrNotAlive_Deposit() public {
        test_CreateGauge();

        address pool = pairListVolatile[0];
        Gauge _gauge = Gauge(gauge.get(pool));

        address user1 = userList[0];

        vm.prank(deployer);
        voter.killGauge(address(_gauge));

        deal(pool, user1, 1 ether);
        vm.startPrank(user1);

        IERC20(pool).approve(address(_gauge), type(uint256).max);
        uint256 balance = IERC20(pool).balanceOf(user1);
        vm.expectRevert();
        _gauge.deposit(balance);

        vm.stopPrank();
    }

    function test_ZeroSupplyRewards_TransferRemainingKitten() public {
        // setup
        test_CreateGauge();
        Gauge _gauge = Gauge(gauge.get(pairListVolatile[0]));
        address user1 = userList[0];
        address lpToken = address(_gauge.lpToken());
        vm.prank(kitten.minter());
        kitten.mint(address(voter), 2 ether);
        deal(lpToken, user1, 1 ether);

        // voter distributes 1e18 KITTEN to the gauge
        vm.prank(address(voter));
        _gauge.notifyRewardAmount(1 ether);

        // after 1 week, user1 deposits LP tokens into the gauge
        vm.warp(block.timestamp + 1 weeks);
        vm.startPrank(user1);
        IERC20(lpToken).approve(address(_gauge), 1 ether);
        _gauge.deposit(1 ether);
        vm.stopPrank();

        // voter distributes another 1e18 KITTEN to the gauge
        vm.prank(address(voter));
        _gauge.notifyRewardAmount(1 ether);

        // after another week, user1 claims rewards
        vm.warp(block.timestamp + 1 weeks);
        vm.prank(user1);
        _gauge.getReward(user1);

        // gauge has 1e18 KITTEN balance, but no rewards left
        assertGe(kitten.balanceOf(address(_gauge)), 1 ether);
        assertEq(_gauge.left(), 0);

        uint256 zeroSupplyRewards = _gauge.zeroSupplyRewards();
        vm.assertGt(zeroSupplyRewards, 0);

        // transfer remaining kitten out of gauge
        vm.startPrank(deployer);
        uint256 balBefore = kitten.balanceOf(deployer);
        _gauge.transferRemainingKitten();
        uint256 balAfter = kitten.balanceOf(deployer);
        vm.stopPrank();

        assertEq(balAfter - balBefore, zeroSupplyRewards);
    }
}
