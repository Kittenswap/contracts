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

contract TestCLGauge is TestCLFactory, TestBribeFactory {
    address[] clGaugeList;

    function testCLGauge__setUp() public {
        testBribeFactory__setUp();

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
                internalBribe[poolAddress], // _internal_bribe
                address(kitten), // _kitten
                true // _isPool
            );

            clGaugeList.push(gaugeAddress);

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

    function testDeposit() public returns (uint256 nfpTokenId) {
        testCreateCLGauge();

        CLGauge clGauge = CLGauge(clGaugeList[0]);

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
        clGauge.deposit(nfpTokenId, 0);

        // ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter
        //     .ExactInputSingleParams({
        //         tokenIn: token0,
        //         tokenOut: token1,
        //         tickSpacing: tickSpacing,
        //         recipient: user1,
        //         deadline: block.timestamp + 60 * 20,
        //         amountIn: IERC20(token0).balanceOf(user1) / 2,
        //         amountOutMinimum: 0,
        //         sqrtPriceLimitX96: 0
        //     });
        // swapRouter.exactInputSingle(swapParams);

        vm.assertEq(nfp.ownerOf(nfpTokenId), address(clGauge));

        uint256[] memory stakedNFPs = clGauge.getUserStakedNFPs(user1);
        bool containsNfpTokenId;
        for (uint i; i < stakedNFPs.length; i++) {
            if (stakedNFPs[i] == nfpTokenId) {
                containsNfpTokenId = true;
                break;
            }
        }
        vm.assertTrue(containsNfpTokenId);

        vm.stopPrank();
    }

    /* Get reward tests */
    // function testFuzz_GetRewardForNfpTokenId(uint256 emissionAmount) public {
    function testGetRewardForNfpTokenId() public {
        uint256 nfpTokenId = testDeposit();

        CLGauge clGauge = CLGauge(clGaugeList[0]);

        // vm.assume(emissionAmount <= kitten.balanceOf(deployer));
        // vm.assume(emissionAmount >= 1 ether);

        uint256 emissionAmount = kitten.balanceOf(deployer) / 10;

        vm.startPrank(deployer);

        kitten.approve(address(clGauge), emissionAmount);
        clGauge.notifyRewardAmount(clGauge.kitten(), emissionAmount);

        vm.stopPrank();

        vm.warp((block.timestamp / 1 weeks) * 1 weeks + 7 days);

        vm.startPrank(user1);

        uint256 kittenBalBefore = kitten.balanceOf(user1);
        clGauge.getReward(nfpTokenId);
        uint256 kittenBalAfter = kitten.balanceOf(user1);

        vm.assertApproxEqAbs(
            kittenBalAfter - kittenBalBefore,
            emissionAmount,
            10 ** 6
        );

        vm.stopPrank();
    }

    function testGetRewardForAccount() public {
        testDeposit();

        CLGauge clGauge = CLGauge(clGaugeList[0]);

        uint256 emissionAmount = kitten.balanceOf(deployer) / 10;

        vm.startPrank(deployer);

        kitten.approve(address(clGauge), emissionAmount);
        clGauge.notifyRewardAmount(clGauge.kitten(), emissionAmount);

        vm.stopPrank();

        vm.warp((block.timestamp / 1 weeks) * 1 weeks + 7 days);

        vm.startPrank(user1);

        address[] memory emptyList;

        uint256 kittenBalBefore = kitten.balanceOf(user1);
        clGauge.getReward(user1, emptyList);
        uint256 kittenBalAfter = kitten.balanceOf(user1);

        vm.assertApproxEqAbs(
            kittenBalAfter - kittenBalBefore,
            emissionAmount,
            10 ** 6
        );

        vm.stopPrank();
    }

    function testRevertNotOwnerGetReward() public {
        uint256 nfpTokenId = testDeposit();

        CLGauge clGauge = CLGauge(clGaugeList[0]);

        uint256 emissionAmount = kitten.balanceOf(deployer) / 10;

        vm.startPrank(deployer);

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
        uint256 nfpTokenId = testDeposit();

        CLGauge clGauge = CLGauge(clGaugeList[0]);

        uint256 emissionAmount = kitten.balanceOf(deployer) / 10;

        vm.startPrank(deployer);

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
        uint256 nfpTokenId = testDeposit();

        CLGauge clGauge = CLGauge(clGaugeList[0]);

        uint256 emissionAmount = kitten.balanceOf(deployer) / 10;

        vm.startPrank(deployer);

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

        CLGauge clGauge = CLGauge(clGaugeList[0]);

        vm.startPrank(deployer);
        clGauge.claimFees();

        console.log("fees0", clGauge.fees0());
        console.log("fees1", clGauge.fees1());

        vm.stopPrank();
    }

    /* Issue due to the flawed clPool.collectFees() logic */
    function testNoPhantomClaimFees() public {
        // claim to reset the clPool.gaugeFees()to (1,1)
        testClaimFees();

        CLGauge clGauge = CLGauge(clGaugeList[0]);

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
}
