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
import {TestVoter} from "test/TestVoter.t.sol";
import {ProtocolTimeLibrary} from "src/clAMM/libraries/ProtocolTimeLibrary.sol";

interface ICLFactoryExtended is ICLFactory {
    function setVoter(address _voter) external;
}

contract TestCLGauge is TestVoter {
    bool CLGauge__setUp;
    function testCLGauge__setUp() public {
        testVote();

        if (CLGauge__setUp) return;
        CLGauge__setUp = true;

        vm.startPrank(deployer);

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

    function testDeposit() public {
        testCLGauge__setUp();

        for (uint k; k < userList.length; k++) {
            address user1 = userList[k];

            console.log("user", user1);
            for (uint i; i < poolList.length; i++) {
                ICLPool pool = ICLPool(poolList[i]);

                CLGauge clGauge = CLGauge(gauge[address(pool)]);

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

                int24 tickSpacing = 200;

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
                clGauge.deposit(nfpTokenId, 0);

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
    }

    function testRevertKilledGaugeDeposit()
        public
        returns (uint256 nfpTokenId)
    {
        testCLGauge__setUp();

        address user1 = userList[0];

        CLGauge clGauge = CLGauge(gauge[address(poolList[0])]);

        vm.prank(voter.emergencyCouncil());
        voter.killGauge(address(clGauge));

        address token0 = ICLPool(poolList[0]).token0();
        address token1 = ICLPool(poolList[0]).token1();

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
                IERC20(token0).balanceOf(whale[token0])
            );
            vm.stopPrank();
        }

        if (token1 != address(WHYPE)) {
            vm.startPrank(whale[token1]);
            IERC20(token1).transfer(
                user1,
                IERC20(token1).balanceOf(whale[token1])
            );
            vm.stopPrank();
        }

        vm.startPrank(user1);

        int24 tickSpacing = 200;

        IERC20(token0).approve(address(nfp), IERC20(token0).balanceOf(user1));
        IERC20(token1).approve(address(nfp), IERC20(token1).balanceOf(user1));
        INonfungiblePositionManager.MintParams
            memory params = INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                tickSpacing: tickSpacing,
                tickLower: (-887272 / tickSpacing) * tickSpacing + tickSpacing,
                tickUpper: (887272 / tickSpacing) * tickSpacing,
                amount0Desired: IERC20(token0).balanceOf(user1) / 2,
                amount1Desired: IERC20(token1).balanceOf(user1) / 2,
                amount0Min: 0,
                amount1Min: 0,
                recipient: user1,
                deadline: block.timestamp + 60 * 20,
                sqrtPriceX96: 0
            });
        (nfpTokenId, , , ) = nfp.mint(params);

        IERC20(token0).approve(
            address(swapRouter),
            IERC20(token0).balanceOf(user1)
        );

        nfp.setApprovalForAll(address(clGauge), true);

        vm.expectRevert();
        clGauge.deposit(nfpTokenId, 0);

        vm.stopPrank();
    }

    /* Get reward tests */
    // function testFuzz_GetRewardForNfpTokenId(uint256 emissionAmount) public {
    function testGetRewardForNfpTokenId() public {
        testDeposit();

        address user1 = userList[0];

        CLGauge clGauge = CLGauge(gauge[address(poolList[0])]);
        uint256 nfpTokenId = clGauge.getUserStakedNFPs(user1)[0];

        // vm.assume(emissionAmount <= kitten.balanceOf(deployer));
        // vm.assume(emissionAmount >= 1 ether);

        uint256 emissionAmount = kitten.balanceOf(deployer) / 10;

        vm.prank(deployer);
        kitten.transfer(address(voter), emissionAmount);

        vm.startPrank(address(voter));

        kitten.approve(address(clGauge), emissionAmount);
        clGauge.notifyRewardAmount(clGauge.kitten(), emissionAmount);

        vm.stopPrank();

        vm.warp((block.timestamp / 1 weeks) * 1 weeks + 7 days);

        vm.startPrank(user1);

        uint256 kittenBalBefore = kitten.balanceOf(user1);
        clGauge.getReward(nfpTokenId);
        uint256 kittenBalAfter = kitten.balanceOf(user1);

        (, , , , , , , uint128 _liquidity, , , , ) = nfp.positions(nfpTokenId);

        vm.assertApproxEqAbs(
            kittenBalAfter - kittenBalBefore,
            (emissionAmount * _liquidity) /
                ICLPool(poolList[0]).stakedLiquidity(),
            10 ** 6
        );

        vm.stopPrank();
    }

    function testGetRewardForAccount() public {
        testDeposit();

        address user1 = userList[0];

        CLGauge clGauge = CLGauge(gauge[address(poolList[0])]);
        uint256 nfpTokenId = clGauge.getUserStakedNFPs(user1)[0];

        uint256 emissionAmount = kitten.balanceOf(deployer) / 10;

        vm.prank(deployer);
        kitten.transfer(address(voter), emissionAmount);

        vm.startPrank(address(voter));
        kitten.approve(address(clGauge), emissionAmount);
        clGauge.notifyRewardAmount(clGauge.kitten(), emissionAmount);

        vm.stopPrank();

        vm.warp((block.timestamp / 1 weeks) * 1 weeks + 7 days);

        vm.startPrank(user1);

        address[] memory emptyList;

        uint256 kittenBalBefore = kitten.balanceOf(user1);
        clGauge.getReward(user1, emptyList);
        uint256 kittenBalAfter = kitten.balanceOf(user1);

        (, , , , , , , uint128 _liquidity, , , , ) = nfp.positions(nfpTokenId);

        vm.assertApproxEqAbs(
            kittenBalAfter - kittenBalBefore,
            (emissionAmount * _liquidity) /
                ICLPool(poolList[0]).stakedLiquidity(),
            10 ** 6
        );

        vm.stopPrank();
    }

    function testGetRewardAsVoterForAccount() public {
        testDeposit();

        address user1 = userList[0];

        CLGauge clGauge = CLGauge(gauge[address(poolList[0])]);
        uint256 nfpTokenId = clGauge.getUserStakedNFPs(user1)[0];

        uint256 emissionAmount = kitten.balanceOf(deployer) / 10;

        vm.prank(deployer);
        kitten.transfer(address(voter), emissionAmount);

        vm.startPrank(address(voter));
        kitten.approve(address(clGauge), emissionAmount);
        clGauge.notifyRewardAmount(clGauge.kitten(), emissionAmount);

        vm.stopPrank();

        vm.warp((block.timestamp / 1 weeks) * 1 weeks + 7 days);

        vm.startPrank(address(voter));

        address[] memory emptyList;

        uint256 kittenBalBefore = kitten.balanceOf(user1);
        clGauge.getReward(user1, emptyList);
        uint256 kittenBalAfter = kitten.balanceOf(user1);

        (, , , , , , , uint128 _liquidity, , , , ) = nfp.positions(nfpTokenId);

        vm.assertApproxEqAbs(
            kittenBalAfter - kittenBalBefore,
            (emissionAmount * _liquidity) /
                ICLPool(poolList[0]).stakedLiquidity(),
            10 ** 6
        );

        vm.stopPrank();
    }

    function testRevertNotOwnerGetReward() public {
        testDeposit();

        CLGauge clGauge = CLGauge(gauge[address(poolList[0])]);
        uint256 nfpTokenId = clGauge.getUserStakedNFPs(userList[0])[0];

        uint256 emissionAmount = kitten.balanceOf(deployer) / 10;

        vm.prank(deployer);
        kitten.transfer(address(voter), emissionAmount);

        vm.startPrank(address(voter));

        kitten.approve(address(clGauge), emissionAmount);
        clGauge.notifyRewardAmount(clGauge.kitten(), emissionAmount);

        vm.stopPrank();

        vm.warp((block.timestamp / 1 weeks) * 1 weeks + 7 days);

        address randomUser = vm.randomAddress();
        vm.startPrank(randomUser);

        vm.expectRevert();
        clGauge.getReward(nfpTokenId);

        vm.stopPrank();
    }

    function testRevertNotOwnerGetRewardForAccount() public {
        testDeposit();

        CLGauge clGauge = CLGauge(gauge[address(poolList[0])]);
        uint256 nfpTokenId = clGauge.getUserStakedNFPs(userList[0])[0];

        uint256 emissionAmount = kitten.balanceOf(deployer) / 10;

        vm.prank(deployer);
        kitten.transfer(address(voter), emissionAmount);

        vm.startPrank(address(voter));

        kitten.approve(address(clGauge), emissionAmount);
        clGauge.notifyRewardAmount(clGauge.kitten(), emissionAmount);

        vm.stopPrank();

        vm.warp((block.timestamp / 1 weeks) * 1 weeks + 7 days);

        address randomUser = vm.randomAddress();
        vm.startPrank(randomUser);

        address[] memory emptyList;

        vm.expectRevert();
        clGauge.getReward(nfpTokenId);

        vm.stopPrank();
    }

    function testRevertNotOwnerOrVoterGetRewardForAccount() public {
        testDeposit();

        CLGauge clGauge = CLGauge(gauge[address(poolList[0])]);
        uint256 nfpTokenId = clGauge.getUserStakedNFPs(userList[0])[0];

        uint256 emissionAmount = kitten.balanceOf(deployer) / 10;

        vm.prank(deployer);
        kitten.transfer(address(voter), emissionAmount);

        vm.startPrank(address(voter));

        kitten.approve(address(clGauge), emissionAmount);
        clGauge.notifyRewardAmount(clGauge.kitten(), emissionAmount);

        vm.stopPrank();

        vm.warp((block.timestamp / 1 weeks) * 1 weeks + 7 days);

        address randomUser = vm.randomAddress();
        vm.startPrank(randomUser);

        address[] memory emptyList;

        vm.expectRevert();
        clGauge.getReward(nfpTokenId);

        vm.stopPrank();
    }

    function testClaimFees() public {
        testDeposit();

        CLGauge clGauge = CLGauge(gauge[address(poolList[0])]);

        vm.startPrank(deployer);
        clGauge.claimFees();

        console.log("fees0", clGauge.fees0());
        console.log("fees1", clGauge.fees1());

        vm.stopPrank();
    }

    /* Issue due to the flawed clPool.collectFees() logic */
    function testNoPhantomClaimFees() public {
        // claim to reset the clPool.gaugeFees() to (1,1)
        testClaimFees();

        CLGauge clGauge = CLGauge(gauge[address(poolList[0])]);
        address user1 = userList[0];

        vm.startPrank(user1);

        (uint128 _gaugefees0, uint128 _gaugefees1) = ICLPool(poolList[0])
            .gaugeFees();

        console.log("gaugeFees0", _gaugefees0);
        console.log("gaugeFees1", _gaugefees1);
        vm.assertEq(_gaugefees0, 1);
        vm.assertEq(_gaugefees1, 1);

        clGauge.claimFees();

        console.log("fees0", clGauge.fees0());
        console.log("fees1", clGauge.fees1());
        vm.assertEq(clGauge.fees0(), 0);
        vm.assertEq(clGauge.fees1(), 0);

        (_gaugefees0, _gaugefees1) = ICLPool(poolList[0]).gaugeFees();

        console.log("gaugeFees0", _gaugefees0);
        console.log("gaugeFees1", _gaugefees1);
        vm.assertEq(_gaugefees0, 1);
        vm.assertEq(_gaugefees1, 1);

        clGauge.claimFees();

        console.log("fees0", clGauge.fees0());
        console.log("fees1", clGauge.fees1());
        vm.assertEq(clGauge.fees0(), 0);
        vm.assertEq(clGauge.fees1(), 0);

        (_gaugefees0, _gaugefees1) = ICLPool(poolList[0]).gaugeFees();

        console.log("gaugeFees0", _gaugefees0);
        console.log("gaugeFees1", _gaugefees1);
        vm.assertEq(_gaugefees0, 1);
        vm.assertEq(_gaugefees1, 1);

        clGauge.claimFees();

        console.log("fees0", clGauge.fees0());
        console.log("fees1", clGauge.fees1());
        vm.assertEq(clGauge.fees0(), 0);
        vm.assertEq(clGauge.fees1(), 0);

        address token0 = ICLPool(poolList[0]).token0();
        address token1 = ICLPool(poolList[0]).token1();

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
                IERC20(token0).balanceOf(whale[token0])
            );
            vm.stopPrank();
        }

        if (token1 != address(WHYPE)) {
            vm.startPrank(whale[token1]);
            IERC20(token1).transfer(
                user1,
                IERC20(token1).balanceOf(whale[token1])
            );
            vm.stopPrank();
        }

        vm.startPrank(user1);

        int24 tickSpacing = 200;

        /* swap to test phantom fees1 */
        ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: token0,
                tokenOut: token1,
                tickSpacing: tickSpacing,
                recipient: user1,
                deadline: block.timestamp + 60 * 20,
                amountIn: IERC20(token0).balanceOf(user1) / 2,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });
        IERC20(token0).approve(
            address(swapRouter),
            IERC20(token0).balanceOf(user1)
        );
        swapRouter.exactInputSingle(swapParams);

        vm.stopPrank();

        (_gaugefees0, _gaugefees1) = ICLPool(poolList[0]).gaugeFees();

        console.log("gaugeFees0", _gaugefees0);
        console.log("gaugeFees1", _gaugefees1);
        vm.assertEq(_gaugefees1, 1);

        console.log("fees0 before", clGauge.fees0());
        console.log("fees1 before", clGauge.fees1());
        console.log(
            "left0",
            InternalBribe(clGauge.internal_bribe()).left(token0)
        );

        clGauge.claimFees();

        console.log("fees0 after", clGauge.fees0());
        console.log("fees1 after", clGauge.fees1());
        vm.assertEq(clGauge.fees1(), 0);

        /* swap to test phantom fees0 */
        vm.startPrank(user1);

        swapParams = ISwapRouter.ExactInputSingleParams({
            tokenIn: token1,
            tokenOut: token0,
            tickSpacing: tickSpacing,
            recipient: user1,
            deadline: block.timestamp + 60 * 20,
            amountIn: IERC20(token1).balanceOf(user1) / 2,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });
        IERC20(token1).approve(
            address(swapRouter),
            IERC20(token1).balanceOf(user1)
        );
        swapRouter.exactInputSingle(swapParams);

        vm.stopPrank();

        (_gaugefees0, _gaugefees1) = ICLPool(poolList[0]).gaugeFees();

        console.log("gaugeFees0", _gaugefees0);
        console.log("gaugeFees1", _gaugefees1);
        vm.assertEq(_gaugefees0, 1);

        console.log("fees0 before", clGauge.fees0());
        console.log("fees1 before", clGauge.fees1());

        clGauge.claimFees();

        console.log("fees0 after", clGauge.fees0());
        console.log("fees1 after", clGauge.fees1());
    }

    function testTransferStuckERC20() public {
        testDeposit();

        CLGauge clGauge = CLGauge(gauge[address(poolList[0])]);

        uint256 emissionAmount = kitten.balanceOf(deployer) / 10;

        vm.prank(deployer);
        kitten.transfer(address(voter), emissionAmount);

        vm.startPrank(address(voter));

        kitten.approve(address(clGauge), emissionAmount);
        clGauge.notifyRewardAmount(clGauge.kitten(), emissionAmount);

        vm.stopPrank();

        vm.startPrank(clGauge.owner());

        uint256 clGaugeBalBefore = IERC20(address(kitten)).balanceOf(
            address(clGauge)
        );
        uint256 ownerBalBefore = IERC20(address(kitten)).balanceOf(
            clGauge.owner()
        );
        clGauge.transferERC20(address(kitten));

        uint256 clGaugeBalAfter = IERC20(address(kitten)).balanceOf(
            address(clGauge)
        );
        uint256 ownerBalAfter = IERC20(address(kitten)).balanceOf(
            clGauge.owner()
        );

        vm.assertEq(
            ownerBalAfter - ownerBalBefore,
            clGaugeBalBefore - clGaugeBalAfter
        );
        vm.assertEq(clGaugeBalAfter, 0);

        vm.stopPrank();
    }

    function testRevertNotOwnerTransferStuckERC20() public {
        testDeposit();

        CLGauge clGauge = CLGauge(gauge[address(poolList[0])]);

        address randomUser = vm.randomAddress();
        vm.startPrank(randomUser);

        vm.expectRevert();
        clGauge.transferERC20(address(kitten));

        vm.stopPrank();
    }

    function testEarned() public {
        testDeposit();

        vm.warp(ProtocolTimeLibrary.epochNext(block.timestamp));
        voter.distro();

        vm.warp(ProtocolTimeLibrary.epochNext(block.timestamp));

        uint256 totalEmissions;
        for (uint i; i < userList.length; i++) {
            address user1 = userList[i];

            console.log("user", user1);
            for (uint j; j < poolList.length; j++) {
                address pool = poolList[j];

                console.log(
                    "pool",
                    pool,
                    IERC20(ICLPool(pool).token0()).symbol(),
                    IERC20(ICLPool(pool).token1()).symbol()
                );

                CLGauge clGauge = CLGauge(gauge[address(pool)]);

                uint256 nfpTokenId = clGauge.getUserStakedNFPs(user1)[0];

                uint256 amount = clGauge.earned(nfpTokenId);
                console.log("amount", amount);

                totalEmissions += amount;
            }
        }

        console.log("totalEmissions", totalEmissions);
    }

    function testRevertNotVoterNotifyRewardAmount() public {
        testCLGauge__setUp();

        address randomUser = vm.randomAddress();
        vm.prank(randomUser);

        // only voter can notify rewards once per epoch
        vm.expectRevert();
        CLGauge(gauge[address(poolList[0])]).notifyRewardAmount(
            address(kitten),
            1 ether
        );
    }
}
