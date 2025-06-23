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

contract TestRebaseReward is TestVoter {
    using EnumerableMap for EnumerableMap.AddressToAddressMap;

    bool RebaseReward__setUp;
    function testRebaseReward__setUp() public {
        test_Vote();
    }

    function test_RevertWhen_InitializingAgain_Initialize() public {
        testRebaseReward__setUp();

        address _voter = vm.randomAddress();
        address _veKitten = vm.randomAddress();
        address _initialOwner = vm.randomAddress();
        vm.expectRevert();
        rebaseReward.initialize(_voter, _veKitten, _initialOwner);
    }

    /* grantNotifyRole tests */
    function test_GrantNotifyRole() public {
        testRebaseReward__setUp();

        address notifierAddress = vm.randomAddress();
        vm.startPrank(deployer);
        rebaseReward.grantNotifyRole(notifierAddress);
        vm.stopPrank();
    }

    function test_RevertIf_Not_DEFAULT_ADMIN_ROLE_GrantNotifyRole() public {
        testRebaseReward__setUp();

        address randomUser = vm.randomAddress();
        vm.startPrank(randomUser);
        vm.expectRevert();
        rebaseReward.grantNotifyRole(randomUser);
        vm.stopPrank();
    }

    /* notifyRewardAmount tests */
    function test_NotifyRewardAmount() public {
        testRebaseReward__setUp();

        vm.startPrank(address(minter));
        kitten.mint(address(minter), vm.randomUint(1 ether, 100 ether));
        uint256 amount = kitten.balanceOf(address(minter));
        kitten.approve(address(rebaseReward), amount);
        rebaseReward.notifyRewardAmount(amount);
        vm.stopPrank();
    }

    function test_RevertIf_Not_NOTIFY_ROLE_NotifyRewardAmount() public {
        testRebaseReward__setUp();

        address randomUser = vm.randomAddress();
        vm.startPrank(randomUser);
        vm.expectRevert();
        rebaseReward.notifyRewardAmount(vm.randomUint(1 ether, 100 ether));
        vm.stopPrank();
    }

    /* _getReward tests */
    function test_GetRewardForTokenId() public {
        test_CreateGauge();

        CLGauge _gauge = CLGauge(gauge.get(poolList[0]));
        RebaseReward _rebaseReward = RebaseReward(voter.rebaseReward());

        // vote
        vm.startPrank(address(voter));
        address user1 = userList[0];
        uint256 tokenId = veKitten.tokenOfOwnerByIndex(user1, 0);
        _rebaseReward._deposit(1 ether, tokenId);
        vm.stopPrank();

        // notify reward after epoch ends/star of next epoch
        vm.warp(ProtocolTimeLibrary.epochNext(block.timestamp));
        uint256 kittenAmount = vm.randomUint(1 ether, 10 ether);

        vm.prank(address(minter));
        kitten.mint(address(minter), kittenAmount);
        vm.stopPrank();

        vm.startPrank(address(minter));
        kitten.approve(address(_rebaseReward), kittenAmount);
        _rebaseReward.notifyRewardAmount(address(kitten), kittenAmount);

        vm.stopPrank();

        // vote
        vm.startPrank(address(voter));
        _rebaseReward._deposit(1 ether, tokenId);
        vm.stopPrank();

        // next epoch
        vm.warp(ProtocolTimeLibrary.epochNext(block.timestamp));
        uint256 kittenAmount2 = vm.randomUint(1 ether, 10 ether);

        vm.startPrank(address(minter));
        kitten.mint(address(minter), kittenAmount2);
        vm.stopPrank();

        vm.startPrank(address(minter));
        kitten.approve(address(_rebaseReward), kittenAmount2);
        _rebaseReward.notifyRewardAmount(address(kitten), kittenAmount2);
        vm.stopPrank();

        vm.startPrank(user1);
        (int128 veKittenBalBefore, ) = veKitten.locked(tokenId);
        _rebaseReward.getRewardForTokenId(tokenId);
        (int128 veKittenBalAfter, ) = veKitten.locked(tokenId);
        vm.stopPrank();

        vm.assertEq(
            uint256(uint128(veKittenBalAfter - veKittenBalBefore)),
            kittenAmount + kittenAmount2
        );
    }

    function test_WhenAmountIsZero_ShouldClaimRewardsInNewTokenId_GetRewardForTokenId()
        public
    {
        test_CreateGauge();

        CLGauge _gauge = CLGauge(gauge.get(poolList[0]));
        RebaseReward _rebaseReward = RebaseReward(voter.rebaseReward());

        // vote
        vm.startPrank(address(voter));
        address user1 = userList[0];
        uint256 tokenId = veKitten.tokenOfOwnerByIndex(user1, 0);
        _rebaseReward._deposit(1 ether, tokenId);
        vm.stopPrank();

        // notify reward after epoch ends/star of next epoch
        vm.warp(ProtocolTimeLibrary.epochNext(block.timestamp));
        uint256 kittenAmount = vm.randomUint(1 ether, 10 ether);

        vm.prank(address(minter));
        kitten.mint(address(minter), kittenAmount);
        vm.stopPrank();

        vm.startPrank(address(minter));
        kitten.approve(address(_rebaseReward), kittenAmount);
        _rebaseReward.notifyRewardAmount(address(kitten), kittenAmount);

        vm.stopPrank();

        // vote
        vm.startPrank(address(voter));
        _rebaseReward._deposit(1 ether, tokenId);
        vm.stopPrank();

        // next epoch
        vm.warp(ProtocolTimeLibrary.epochNext(block.timestamp));
        uint256 kittenAmount2 = vm.randomUint(1 ether, 10 ether);

        vm.startPrank(address(minter));
        kitten.mint(address(minter), kittenAmount2);
        vm.stopPrank();

        vm.startPrank(address(minter));
        kitten.approve(address(_rebaseReward), kittenAmount2);
        _rebaseReward.notifyRewardAmount(address(kitten), kittenAmount2);
        vm.stopPrank();

        vm.startPrank(user1);
        (int128 veKittenBalBefore, ) = veKitten.locked(tokenId);

        veKitten.split(tokenId, uint256(uint128(veKittenBalBefore)) / 2);
        uint256 balanceOfOwnerBefore = veKitten.balanceOf(user1);

        _rebaseReward.getRewardForTokenId(tokenId);
        uint256 balanceOfOwnerAfter = veKitten.balanceOf(user1);
        vm.stopPrank();

        vm.assertGt(balanceOfOwnerAfter, balanceOfOwnerBefore);
    }

    function test_WhenLockExpired_ShouldClaimRewardsInNewTokenId_GetRewardForTokenId()
        public
    {
        test_CreateGauge();

        CLGauge _gauge = CLGauge(gauge.get(poolList[0]));
        RebaseReward _rebaseReward = RebaseReward(voter.rebaseReward());

        // vote
        vm.startPrank(address(voter));
        address user1 = userList[0];
        uint256 tokenId = veKitten.tokenOfOwnerByIndex(user1, 0);
        _rebaseReward._deposit(1 ether, tokenId);
        vm.stopPrank();

        // notify reward after epoch ends/star of next epoch
        vm.warp(ProtocolTimeLibrary.epochNext(block.timestamp));
        uint256 kittenAmount = vm.randomUint(1 ether, 10 ether);

        vm.prank(address(minter));
        kitten.mint(address(minter), kittenAmount);
        vm.stopPrank();

        vm.startPrank(address(minter));
        kitten.approve(address(_rebaseReward), kittenAmount);
        _rebaseReward.notifyRewardAmount(address(kitten), kittenAmount);

        vm.stopPrank();

        // vote
        vm.startPrank(address(voter));
        _rebaseReward._deposit(1 ether, tokenId);
        vm.stopPrank();

        // next epoch
        vm.warp(ProtocolTimeLibrary.epochNext(block.timestamp));
        uint256 kittenAmount2 = vm.randomUint(1 ether, 10 ether);

        vm.startPrank(address(minter));
        kitten.mint(address(minter), kittenAmount2);
        vm.stopPrank();

        vm.startPrank(address(minter));
        kitten.approve(address(_rebaseReward), kittenAmount2);
        _rebaseReward.notifyRewardAmount(address(kitten), kittenAmount2);
        vm.stopPrank();

        vm.startPrank(user1);
        (int128 veKittenBalBefore, ) = veKitten.locked(tokenId);

        vm.warp(block.timestamp + veKitten.MAXTIME());
        uint256 balanceOfOwnerBefore = veKitten.balanceOf(user1);

        _rebaseReward.getRewardForTokenId(tokenId);
        uint256 balanceOfOwnerAfter = veKitten.balanceOf(user1);
        vm.stopPrank();

        vm.assertGt(balanceOfOwnerAfter, balanceOfOwnerBefore);
    }

    function test_RevertIf_RewardTokenNotKitten_Incentivize() public {
        test_CreateGauge();
        CLGauge _gauge = CLGauge(gauge.get(poolList[0]));
        RebaseReward _rebaseReward = RebaseReward(voter.rebaseReward());
        address user1 = userList[0];
        address user2 = userList[1];
        uint256 kittenAmount = 1 ether;

        vm.startPrank(address(voter));
        // user1 votes
        uint256 tokenId1 = veKitten.tokenOfOwnerByIndex(user1, 0);
        _rebaseReward._deposit(1 ether, tokenId1);

        // user2 votes
        uint256 tokenId2 = veKitten.tokenOfOwnerByIndex(user2, 0);
        _rebaseReward._deposit(1 ether, tokenId2);
        vm.stopPrank();

        // user1 (or anyone else) sends 1e18 token0 as reward to RebaseReward
        address notKittenToken = address(_gauge.token0());
        deal(notKittenToken, user1, 1 ether);
        vm.startPrank(address(user1));
        IERC20(notKittenToken).approve(address(_rebaseReward), 1 ether);
        vm.expectRevert();
        _rebaseReward.incentivize(notKittenToken, 1 ether);
        vm.stopPrank();
    }
}
