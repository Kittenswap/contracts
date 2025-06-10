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

contract TestVotingReward is TestVoter {
    using EnumerableMap for EnumerableMap.AddressToAddressMap;

    bool VotingReward__setUp;
    function testVotingReward__setUp() public {
        test_Vote();
    }

    function test_GetRewardForPeriod() public {
        test_CreateGauge();

        CLGauge _gauge = CLGauge(gauge.get(poolList[0]));
        VotingReward _votingReward = VotingReward(
            address(_gauge.votingReward())
        );

        // vote
        vm.startPrank(address(voter));
        address user1 = userList[0];
        uint256 tokenId = veKitten.tokenOfOwnerByIndex(user1, 0);
        _votingReward._deposit(1 ether, tokenId);
        vm.stopPrank();

        // notify reward after epoch ends/start of next epoch
        vm.warp(ProtocolTimeLibrary.epochNext(block.timestamp));
        uint256 notifyAmount = 1 ether;
        vm.prank(address(minter));
        kitten.mint(address(_gauge), notifyAmount);
        vm.stopPrank();

        vm.startPrank(address(_gauge));
        kitten.approve(address(_votingReward), notifyAmount);
        _votingReward.notifyRewardAmount(address(kitten), notifyAmount);

        // claim rewards
        vm.startPrank(user1);
        uint256 kittenBalBefore = kitten.balanceOf(user1);
        _votingReward.getRewardForPeriod(
            _votingReward.getCurrentPeriod(),
            tokenId,
            address(kitten)
        );
        uint256 kittenBalAfter = kitten.balanceOf(user1);
        vm.stopPrank();

        vm.assertEq(notifyAmount, kittenBalAfter - kittenBalBefore);
    }

    function test_RevertIf_NotApproved_GetRewardForPeriod() public {
        test_CreateGauge();

        CLGauge _gauge = CLGauge(gauge.get(poolList[0]));
        VotingReward _votingReward = VotingReward(
            address(_gauge.votingReward())
        );

        // vote
        vm.startPrank(address(voter));
        address user1 = userList[0];
        uint256 tokenId = veKitten.tokenOfOwnerByIndex(user1, 0);
        _votingReward._deposit(1 ether, tokenId);
        vm.stopPrank();

        // notify reward after epoch ends/start of next epoch
        vm.warp(ProtocolTimeLibrary.epochNext(block.timestamp));
        uint256 notifyAmount = 1 ether;
        vm.prank(address(minter));
        kitten.mint(address(_gauge), notifyAmount);
        vm.stopPrank();

        vm.startPrank(address(_gauge));
        kitten.approve(address(_votingReward), notifyAmount);
        _votingReward.notifyRewardAmount(address(kitten), notifyAmount);

        address randomUser = vm.randomAddress();
        uint256 currentPeriod = _votingReward.getCurrentPeriod();
        vm.startPrank(randomUser);
        vm.expectRevert();
        _votingReward.getRewardForPeriod(
            currentPeriod,
            tokenId,
            address(kitten)
        );
        vm.stopPrank();
    }

    function test_GetRewardForTokenId() public {
        test_CreateGauge();

        CLGauge _gauge = CLGauge(gauge.get(poolList[0]));
        VotingReward _votingReward = VotingReward(
            address(_gauge.votingReward())
        );

        // vote
        vm.startPrank(address(voter));
        address user1 = userList[0];
        uint256 tokenId = veKitten.tokenOfOwnerByIndex(user1, 0);
        _votingReward._deposit(1 ether, tokenId);
        vm.stopPrank();

        // notify reward after epoch ends/star of next epoch
        vm.warp(ProtocolTimeLibrary.epochNext(block.timestamp));
        uint256 kittenAmount = 1 ether;
        uint256 whypeAmount = 2 ether;

        vm.prank(address(minter));
        kitten.mint(address(_gauge), kittenAmount);
        vm.stopPrank();

        vm.startPrank(address(_gauge));
        kitten.approve(address(_votingReward), kittenAmount);
        _votingReward.notifyRewardAmount(address(kitten), kittenAmount);

        vm.deal(address(_gauge), whypeAmount);
        WHYPE.deposit{value: whypeAmount}();
        WHYPE.approve(address(_votingReward), whypeAmount);
        _votingReward.notifyRewardAmount(address(WHYPE), whypeAmount);

        uint256[] memory rewardList = new uint256[](2);
        address[] memory tokenList = new address[](2);

        uint256[] memory amountList = new uint256[](2);
        amountList[0] = kittenAmount;
        amountList[1] = whypeAmount;

        vm.stopPrank();

        // vote
        vm.startPrank(address(voter));
        _votingReward._deposit(1 ether, tokenId);
        vm.stopPrank();

        // next epoch
        vm.warp(ProtocolTimeLibrary.epochNext(block.timestamp));
        uint256 kittenAmount2 = vm.randomUint(1 ether, 10 ether);
        uint256 whypeAmount2 = vm.randomUint(1 ether, 10 ether);

        amountList[0] += kittenAmount2;
        amountList[1] += whypeAmount2;

        vm.startPrank(address(minter));
        kitten.mint(address(_gauge), kittenAmount2);
        vm.stopPrank();

        vm.startPrank(address(_gauge));
        kitten.approve(address(_votingReward), kittenAmount2);
        _votingReward.notifyRewardAmount(address(kitten), kittenAmount2);

        vm.deal(address(_gauge), whypeAmount2);
        WHYPE.deposit{value: whypeAmount2}();
        WHYPE.approve(address(_votingReward), whypeAmount2);
        _votingReward.notifyRewardAmount(address(WHYPE), whypeAmount2);
        vm.stopPrank();

        vm.startPrank(user1);
        _votingReward.getRewardForTokenId(tokenId);
    }

    function test_RevertIf_NotApproved_GetRewardForTokenId() public {
        test_CreateGauge();

        CLGauge _gauge = CLGauge(gauge.get(poolList[0]));
        VotingReward _votingReward = VotingReward(
            address(_gauge.votingReward())
        );

        // vote
        vm.startPrank(address(voter));
        address user1 = userList[0];
        uint256 tokenId = veKitten.tokenOfOwnerByIndex(user1, 0);
        _votingReward._deposit(1 ether, tokenId);
        vm.stopPrank();

        // notify reward after epoch ends/star of next epoch
        vm.warp(ProtocolTimeLibrary.epochNext(block.timestamp));
        uint256 kittenAmount = 1 ether;
        uint256 whypeAmount = 2 ether;

        vm.prank(address(minter));
        kitten.mint(address(_gauge), kittenAmount);
        vm.stopPrank();

        vm.startPrank(address(_gauge));
        kitten.approve(address(_votingReward), kittenAmount);
        _votingReward.notifyRewardAmount(address(kitten), kittenAmount);

        vm.deal(address(_gauge), whypeAmount);
        WHYPE.deposit{value: whypeAmount}();
        WHYPE.approve(address(_votingReward), whypeAmount);
        _votingReward.notifyRewardAmount(address(WHYPE), whypeAmount);

        uint256[] memory rewardList = new uint256[](2);
        address[] memory tokenList = new address[](2);

        uint256[] memory amountList = new uint256[](2);
        amountList[0] = kittenAmount;
        amountList[1] = whypeAmount;

        vm.stopPrank();

        // vote
        vm.startPrank(address(voter));
        _votingReward._deposit(1 ether, tokenId);
        vm.stopPrank();

        // next epoch
        vm.warp(ProtocolTimeLibrary.epochNext(block.timestamp));
        uint256 kittenAmount2 = vm.randomUint(1 ether, 10 ether);
        uint256 whypeAmount2 = vm.randomUint(1 ether, 10 ether);

        amountList[0] += kittenAmount2;
        amountList[1] += whypeAmount2;

        vm.startPrank(address(minter));
        kitten.mint(address(_gauge), kittenAmount2);
        vm.stopPrank();

        vm.startPrank(address(_gauge));
        kitten.approve(address(_votingReward), kittenAmount2);
        _votingReward.notifyRewardAmount(address(kitten), kittenAmount2);

        vm.deal(address(_gauge), whypeAmount2);
        WHYPE.deposit{value: whypeAmount2}();
        WHYPE.approve(address(_votingReward), whypeAmount2);
        _votingReward.notifyRewardAmount(address(WHYPE), whypeAmount2);
        vm.stopPrank();

        address randomUser = vm.randomAddress();
        vm.startPrank(randomUser);
        vm.expectRevert();
        _votingReward.getRewardForTokenId(tokenId);
    }

    function test_GetRewardForOwner() public {
        test_CreateGauge();

        CLGauge _gauge = CLGauge(gauge.get(poolList[0]));
        VotingReward _votingReward = VotingReward(
            address(_gauge.votingReward())
        );

        // vote
        vm.startPrank(address(voter));
        address user1 = userList[0];
        uint256 tokenId = veKitten.tokenOfOwnerByIndex(user1, 0);
        _votingReward._deposit(1 ether, tokenId);
        vm.stopPrank();

        // notify reward after epoch ends/star of next epoch
        vm.warp(ProtocolTimeLibrary.epochNext(block.timestamp));
        uint256 kittenAmount = 1 ether;
        uint256 whypeAmount = 2 ether;

        vm.prank(address(minter));
        kitten.mint(address(_gauge), kittenAmount);
        vm.stopPrank();

        vm.startPrank(address(_gauge));
        kitten.approve(address(_votingReward), kittenAmount);
        _votingReward.notifyRewardAmount(address(kitten), kittenAmount);

        vm.deal(address(_gauge), whypeAmount);
        WHYPE.deposit{value: whypeAmount}();
        WHYPE.approve(address(_votingReward), whypeAmount);
        _votingReward.notifyRewardAmount(address(WHYPE), whypeAmount);

        uint256[] memory rewardList = new uint256[](2);
        address[] memory tokenList = new address[](2);

        uint256[] memory amountList = new uint256[](2);
        amountList[0] = kittenAmount;
        amountList[1] = whypeAmount;

        vm.stopPrank();

        // vote
        vm.startPrank(address(voter));
        _votingReward._deposit(1 ether, tokenId);
        vm.stopPrank();

        // next epoch
        vm.warp(ProtocolTimeLibrary.epochNext(block.timestamp));
        uint256 kittenAmount2 = vm.randomUint(1 ether, 10 ether);
        uint256 whypeAmount2 = vm.randomUint(1 ether, 10 ether);

        amountList[0] += kittenAmount2;
        amountList[1] += whypeAmount2;

        vm.startPrank(address(minter));
        kitten.mint(address(_gauge), kittenAmount2);
        vm.stopPrank();

        vm.startPrank(address(_gauge));
        kitten.approve(address(_votingReward), kittenAmount2);
        _votingReward.notifyRewardAmount(address(kitten), kittenAmount2);

        vm.deal(address(_gauge), whypeAmount2);
        WHYPE.deposit{value: whypeAmount2}();
        WHYPE.approve(address(_votingReward), whypeAmount2);
        _votingReward.notifyRewardAmount(address(WHYPE), whypeAmount2);
        vm.stopPrank();

        vm.startPrank(address(voter));
        _votingReward.getRewardForOwner(tokenId);
    }

    function test_RevertIf_NotVoter_GetRewardForOwner() public {
        test_CreateGauge();

        CLGauge _gauge = CLGauge(gauge.get(poolList[0]));
        VotingReward _votingReward = VotingReward(
            address(_gauge.votingReward())
        );

        // vote
        vm.startPrank(address(voter));
        address user1 = userList[0];
        uint256 tokenId = veKitten.tokenOfOwnerByIndex(user1, 0);
        _votingReward._deposit(1 ether, tokenId);
        vm.stopPrank();

        // notify reward after epoch ends/star of next epoch
        vm.warp(ProtocolTimeLibrary.epochNext(block.timestamp));
        uint256 kittenAmount = 1 ether;
        uint256 whypeAmount = 2 ether;

        vm.prank(address(minter));
        kitten.mint(address(_gauge), kittenAmount);
        vm.stopPrank();

        vm.startPrank(address(_gauge));
        kitten.approve(address(_votingReward), kittenAmount);
        _votingReward.notifyRewardAmount(address(kitten), kittenAmount);

        vm.deal(address(_gauge), whypeAmount);
        WHYPE.deposit{value: whypeAmount}();
        WHYPE.approve(address(_votingReward), whypeAmount);
        _votingReward.notifyRewardAmount(address(WHYPE), whypeAmount);

        uint256[] memory rewardList = new uint256[](2);
        address[] memory tokenList = new address[](2);

        uint256[] memory amountList = new uint256[](2);
        amountList[0] = kittenAmount;
        amountList[1] = whypeAmount;

        vm.stopPrank();

        // vote
        vm.startPrank(address(voter));
        _votingReward._deposit(1 ether, tokenId);
        vm.stopPrank();

        // next epoch
        vm.warp(ProtocolTimeLibrary.epochNext(block.timestamp));
        uint256 kittenAmount2 = vm.randomUint(1 ether, 10 ether);
        uint256 whypeAmount2 = vm.randomUint(1 ether, 10 ether);

        amountList[0] += kittenAmount2;
        amountList[1] += whypeAmount2;

        vm.startPrank(address(minter));
        kitten.mint(address(_gauge), kittenAmount2);
        vm.stopPrank();

        vm.startPrank(address(_gauge));
        kitten.approve(address(_votingReward), kittenAmount2);
        _votingReward.notifyRewardAmount(address(kitten), kittenAmount2);

        vm.deal(address(_gauge), whypeAmount2);
        WHYPE.deposit{value: whypeAmount2}();
        WHYPE.approve(address(_votingReward), whypeAmount2);
        _votingReward.notifyRewardAmount(address(WHYPE), whypeAmount2);
        vm.stopPrank();

        address randomUser = vm.randomAddress();
        vm.startPrank(randomUser);
        vm.expectRevert();
        _votingReward.getRewardForOwner(tokenId);
    }

    function test_EarnedForPeriod() public {
        test_CreateGauge();

        CLGauge _gauge = CLGauge(gauge.get(poolList[0]));
        VotingReward _votingReward = VotingReward(
            address(_gauge.votingReward())
        );

        // vote
        vm.startPrank(address(voter));
        address user1 = userList[0];
        uint256 tokenId = veKitten.tokenOfOwnerByIndex(user1, 0);
        _votingReward._deposit(1 ether, tokenId);
        vm.stopPrank();

        // notify reward after epoch ends/star of next epoch
        vm.warp(ProtocolTimeLibrary.epochNext(block.timestamp));
        uint256 notifyAmount = 1 ether;
        vm.prank(address(minter));
        kitten.mint(address(_gauge), notifyAmount);
        vm.stopPrank();

        vm.startPrank(address(_gauge));
        kitten.approve(address(_votingReward), notifyAmount);
        _votingReward.notifyRewardAmount(address(kitten), notifyAmount);

        uint256 earned = _votingReward.earnedForPeriod(
            _votingReward.getCurrentPeriod(),
            tokenId,
            address(kitten)
        );

        vm.assertEq(notifyAmount, earned);
    }

    function testEarnedForToken() public {
        test_CreateGauge();

        CLGauge _gauge = CLGauge(gauge.get(poolList[0]));
        VotingReward _votingReward = VotingReward(
            address(_gauge.votingReward())
        );

        // vote
        vm.startPrank(address(voter));
        address user1 = userList[0];
        uint256 tokenId = veKitten.tokenOfOwnerByIndex(user1, 0);
        _votingReward._deposit(1 ether, tokenId);
        vm.stopPrank();

        // notify reward after epoch ends/star of next epoch
        vm.warp(ProtocolTimeLibrary.epochNext(block.timestamp));
        uint256 kittenAmount = 1 ether;
        uint256 whypeAmount = 2 ether;

        vm.prank(address(minter));
        kitten.mint(address(_gauge), kittenAmount);
        vm.stopPrank();

        vm.startPrank(address(_gauge));
        kitten.approve(address(_votingReward), kittenAmount);
        _votingReward.notifyRewardAmount(address(kitten), kittenAmount);

        vm.deal(address(_gauge), whypeAmount);
        WHYPE.deposit{value: whypeAmount}();
        WHYPE.approve(address(_votingReward), whypeAmount);
        _votingReward.notifyRewardAmount(address(WHYPE), whypeAmount);

        uint256 earnedKitten = _votingReward.earnedForToken(
            tokenId,
            address(kitten)
        );
        vm.assertEq(kittenAmount, earnedKitten);

        uint256 earnedWhype = _votingReward.earnedForToken(
            tokenId,
            address(WHYPE)
        );

        vm.assertEq(whypeAmount, earnedWhype);
        vm.stopPrank();

        // vote
        vm.startPrank(address(voter));
        _votingReward._deposit(1 ether, tokenId);
        vm.stopPrank();

        // next epoch
        vm.warp(ProtocolTimeLibrary.epochNext(block.timestamp));
        uint256 kittenAmount2 = vm.randomUint(1 ether, 10 ether);
        uint256 whypeAmount2 = vm.randomUint(1 ether, 10 ether);

        vm.startPrank(address(minter));
        kitten.mint(address(_gauge), kittenAmount2);
        vm.stopPrank();

        vm.startPrank(address(_gauge));
        kitten.approve(address(_votingReward), kittenAmount2);
        _votingReward.notifyRewardAmount(address(kitten), kittenAmount2);

        vm.deal(address(_gauge), whypeAmount2);
        WHYPE.deposit{value: whypeAmount2}();
        WHYPE.approve(address(_votingReward), whypeAmount2);
        _votingReward.notifyRewardAmount(address(WHYPE), whypeAmount2);

        earnedKitten = _votingReward.earnedForToken(tokenId, address(kitten));
        vm.assertEq(kittenAmount + kittenAmount2, earnedKitten);

        earnedWhype = _votingReward.earnedForToken(tokenId, address(WHYPE));

        vm.assertEq(whypeAmount + whypeAmount2, earnedWhype);
    }

    function testEarnedTokenId() public {
        test_CreateGauge();

        CLGauge _gauge = CLGauge(gauge.get(poolList[0]));
        VotingReward _votingReward = VotingReward(
            address(_gauge.votingReward())
        );

        // vote
        vm.startPrank(address(voter));
        address user1 = userList[0];
        uint256 tokenId = veKitten.tokenOfOwnerByIndex(user1, 0);
        _votingReward._deposit(1 ether, tokenId);
        vm.stopPrank();

        // notify reward after epoch ends/star of next epoch
        vm.warp(ProtocolTimeLibrary.epochNext(block.timestamp));
        uint256 kittenAmount = 1 ether;
        uint256 whypeAmount = 2 ether;

        vm.prank(address(minter));
        kitten.mint(address(_gauge), kittenAmount);
        vm.stopPrank();

        vm.startPrank(address(_gauge));
        kitten.approve(address(_votingReward), kittenAmount);
        _votingReward.notifyRewardAmount(address(kitten), kittenAmount);

        vm.deal(address(_gauge), whypeAmount);
        WHYPE.deposit{value: whypeAmount}();
        WHYPE.approve(address(_votingReward), whypeAmount);
        _votingReward.notifyRewardAmount(address(WHYPE), whypeAmount);

        uint256[] memory rewardList = new uint256[](2);
        address[] memory tokenList = new address[](2);

        uint256[] memory amountList = new uint256[](2);
        amountList[0] = kittenAmount;
        amountList[1] = whypeAmount;

        (rewardList, tokenList) = _votingReward.earnedForTokenId(tokenId);

        for (uint256 i; i < tokenList.length; i++) {
            vm.assertEq(rewardList[i], amountList[i]);
        }

        vm.stopPrank();

        // vote
        vm.startPrank(address(voter));
        _votingReward._deposit(1 ether, tokenId);
        vm.stopPrank();

        // next epoch
        vm.warp(ProtocolTimeLibrary.epochNext(block.timestamp));
        uint256 kittenAmount2 = vm.randomUint(1 ether, 10 ether);
        uint256 whypeAmount2 = vm.randomUint(1 ether, 10 ether);

        amountList[0] += kittenAmount2;
        amountList[1] += whypeAmount2;

        vm.startPrank(address(minter));
        kitten.mint(address(_gauge), kittenAmount2);
        vm.stopPrank();

        vm.startPrank(address(_gauge));
        kitten.approve(address(_votingReward), kittenAmount2);
        _votingReward.notifyRewardAmount(address(kitten), kittenAmount2);

        vm.deal(address(_gauge), whypeAmount2);
        WHYPE.deposit{value: whypeAmount2}();
        WHYPE.approve(address(_votingReward), whypeAmount2);
        _votingReward.notifyRewardAmount(address(WHYPE), whypeAmount2);

        (rewardList, tokenList) = _votingReward.earnedForTokenId(tokenId);

        for (uint256 i; i < tokenList.length; i++) {
            vm.assertEq(rewardList[i], amountList[i]);
        }
    }

    /* _deposit tests */
    function test__deposit() public {
        test_CreateGauge();

        CLGauge _gauge = CLGauge(gauge.get(poolList[0]));
        VotingReward _votingReward = VotingReward(
            address(_gauge.votingReward())
        );

        // vote
        vm.startPrank(address(voter));
        address user1 = userList[0];
        uint256 tokenId = veKitten.tokenOfOwnerByIndex(user1, 0);

        uint256 amount = vm.randomUint(1 ether, 100 ether);
        _votingReward._deposit(amount, tokenId);
        vm.stopPrank();

        uint256 nextPeriod = _votingReward.getCurrentPeriod() + 1;
        vm.assertEq(
            _votingReward.tokenIdVotesInPeriod(nextPeriod, tokenId),
            amount
        );
        vm.assertEq(_votingReward.totalVotesInPeriod(nextPeriod), amount);
    }

    function test_RevertIf_NotVoter__deposit() public {
        test_CreateGauge();

        CLGauge _gauge = CLGauge(gauge.get(poolList[0]));
        VotingReward _votingReward = VotingReward(
            address(_gauge.votingReward())
        );

        address randomUser = vm.randomAddress();
        vm.startPrank(randomUser);
        address user1 = userList[0];
        uint256 tokenId = veKitten.tokenOfOwnerByIndex(user1, 0);

        uint256 amount = vm.randomUint(1 ether, 100 ether);
        vm.expectRevert();
        _votingReward._deposit(amount, tokenId);
        vm.stopPrank();
    }

    /* _withdraw tests */
    function test__withdraw() public {
        test__deposit();

        CLGauge _gauge = CLGauge(gauge.get(poolList[0]));
        VotingReward _votingReward = VotingReward(
            address(_gauge.votingReward())
        );

        vm.startPrank(address(voter));
        address user1 = userList[0];
        uint256 tokenId = veKitten.tokenOfOwnerByIndex(user1, 0);

        uint256 nextPeriod = _votingReward.getCurrentPeriod() + 1;
        uint256 amount = _votingReward.tokenIdVotesInPeriod(
            nextPeriod,
            tokenId
        );
        _votingReward._withdraw(amount, tokenId);
        vm.stopPrank();

        vm.assertEq(_votingReward.tokenIdVotesInPeriod(nextPeriod, tokenId), 0);
        vm.assertEq(_votingReward.totalVotesInPeriod(nextPeriod), 0);
    }

    function test_RevertIf_NotVoter__withdraw() public {
        test__deposit();

        CLGauge _gauge = CLGauge(gauge.get(poolList[0]));
        VotingReward _votingReward = VotingReward(
            address(_gauge.votingReward())
        );

        address randomUser = vm.randomAddress();
        vm.startPrank(randomUser);
        address user1 = userList[0];
        uint256 tokenId = veKitten.tokenOfOwnerByIndex(user1, 0);

        uint256 nextPeriod = _votingReward.getCurrentPeriod() + 1;
        uint256 amount = _votingReward.tokenIdVotesInPeriod(
            nextPeriod,
            tokenId
        );

        vm.expectRevert();
        _votingReward._withdraw(amount, tokenId);
        vm.stopPrank();
    }

    /* grantNotifyRole tests */
    function test_GrantNotifyRole() public {
        testVotingReward__setUp();

        CLGauge _gauge = CLGauge(gauge.get(poolList[0]));
        VotingReward _votingReward = VotingReward(
            address(_gauge.votingReward())
        );

        address randomUser = vm.randomAddress();

        vm.startPrank(address(voter));
        _votingReward.grantNotifyRole(randomUser);
        vm.stopPrank();
    }

    function test_RevertIf_NotVoter_GrantNotifyRole() public {
        testVotingReward__setUp();

        CLGauge _gauge = CLGauge(gauge.get(poolList[0]));
        VotingReward _votingReward = VotingReward(
            address(_gauge.votingReward())
        );

        address randomUser = vm.randomAddress();
        vm.startPrank(randomUser);
        vm.expectRevert();
        _votingReward.grantNotifyRole(randomUser);
        vm.stopPrank();
    }

    function test_NotifyRewardAmount() public {
        testVotingReward__setUp();

        CLGauge _gauge = CLGauge(gauge.get(poolList[0]));
        VotingReward _votingReward = VotingReward(
            address(_gauge.votingReward())
        );

        vm.startPrank(address(voter));
        _votingReward.grantNotifyRole(deployer);
        vm.stopPrank();

        vm.startPrank(deployer);
        uint256 amount = (kitten.balanceOf(deployer) * vm.randomUint(1, 100)) /
            100;
        kitten.approve(address(_votingReward), amount);
        _votingReward.notifyRewardAmount(address(kitten), amount);
        vm.stopPrank();

        vm.assertEq(kitten.balanceOf(address(_votingReward)), amount);
    }

    function test_RevertIf_NotRole_NOTIFY_ROLE_NotifyRewardAmount() public {
        testVotingReward__setUp();

        CLGauge _gauge = CLGauge(gauge.get(poolList[0]));
        VotingReward _votingReward = VotingReward(
            address(_gauge.votingReward())
        );

        vm.startPrank(address(voter));
        _votingReward.grantNotifyRole(deployer);
        vm.stopPrank();

        address randomUser = vm.randomAddress();
        vm.startPrank(randomUser);

        vm.expectRevert();
        _votingReward.notifyRewardAmount(address(kitten), 1_000_000_000 ether);
        vm.stopPrank();
    }

    function test_Incentivize() public {
        testVotingReward__setUp();

        CLGauge _gauge = CLGauge(gauge.get(poolList[0]));
        VotingReward _votingReward = VotingReward(
            address(_gauge.votingReward())
        );

        MockERC20 _token = new MockERC20("token", "token", 18);

        vm.startPrank(deployer);
        voter.whitelist(address(_token), true);
        vm.stopPrank();

        address randomUser = vm.randomAddress();
        vm.startPrank(address(randomUser));

        uint256 amount = vm.randomUint(1 ether, 1_000_000_000 ether);
        _token.mint(randomUser, amount);

        _token.approve(address(_votingReward), amount);
        _votingReward.incentivize(address(_token), amount);
        vm.stopPrank();

        vm.assertEq(_token.balanceOf(address(_votingReward)), amount);
        vm.assertEq(
            _votingReward.rewardForPeriod(
                _votingReward.getCurrentPeriod() + 1,
                address(_token)
            ),
            amount
        );
    }

    function test_RevertIf_NotWhitelisted_Incentivize() public {
        testVotingReward__setUp();

        CLGauge _gauge = CLGauge(gauge.get(poolList[0]));
        VotingReward _votingReward = VotingReward(
            address(_gauge.votingReward())
        );

        address randomToken = vm.randomAddress();
        address randomUser = vm.randomAddress();
        vm.startPrank(address(randomUser));
        uint256 amount = vm.randomUint(1 ether, 1_000_000_000 ether);

        vm.expectRevert();
        _votingReward.incentivize(randomToken, amount);
        vm.stopPrank();
    }
}
