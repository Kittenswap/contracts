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

interface ICLFactoryExtended is ICLFactory {
    function setVoter(address _voter) external;
}

/* This will test everything */
// - Voter contracts
// - Emissions
// - Gauge contracts
// - CL Gauge contracts

contract TestAll is Test {
    address deployer = 0xb6Ff1afa18d22ab746B72122032d42E12f62d01C;
    address multisig = 0x907438e82802C48d754EA87910feaCCbe7ecd063;

    /* volatile contracts */
    PairFactory pairFactory =
        PairFactory(0xDa12F450580A4cc485C3b501BAB7b0B3cbc3B31B);
    Router router = Router(payable(0xD6EeFfbDAF6503Ad6539CF8f337D79BEbbd40802));

    /* cl contracts */
    FactoryRegistry factoryRegistry =
        FactoryRegistry(0x8C142521ebB1aC1cC1F0958037702A69b6f608e4);
    ICLFactoryExtended clFactory =
        ICLFactoryExtended(0x2E08F5Ff603E4343864B14599CAeDb19918BDCaF);
    ICustomFeeModule swapFeeModule =
        ICustomFeeModule(0x24c95c78771a16c455eA859EbB8B7052F49E58C6);
    ICustomFeeModule unstakedFeeModule =
        ICustomFeeModule(0x5dAF501156447aC2A851DB972871F56673204d09);
    ISwapRouter swapRouter =
        ISwapRouter(0x8fFDB06039B1b8188c2C721Dc3C435B5773D7346);
    INonfungiblePositionManager nfp =
        INonfungiblePositionManager(0xB9201e89f94a01FF13AD4CAeCF43a2e232513754);
    IQuoterV2 quoterV2 = IQuoterV2(0xd9949cB0655E8D5167373005Bd85f814c8E0C9BF);

    /* voter contracts */
    Kitten kitten;
    VeArtProxy artProxy;
    VotingEscrow veKitten;
    Voter voter;
    RewardsDistributor rewardsDistributor;
    Minter minter;

    /* gauges & bribes */
    GaugeFactory gaugeFactory;
    BribeFactory bribeFactory;
    CLGaugeFactory clGaugeFactory;

    /* misc */
    IWHYPE9 WHYPE =
        IWHYPE9(payable(0x5555555555555555555555555555555555555555));
    IERC20 UBTC = IERC20(0x9FDBdA0A5e284c32744D2f17Ee5c74B284993463); // UBTC at the moment
    bool stable = false;

    /* users */
    address user1 =
        address(uint160(uint256(keccak256(abi.encodePacked("user1")))));
    address user2 =
        address(uint160(uint256(keccak256(abi.encodePacked("user2")))));
    address swapper =
        address(uint160(uint256(keccak256(abi.encodePacked("swapper")))));

    function _setUp() internal {
        vm.startPrank(deployer);

        Options memory opts;
        // opts.unsafeSkipAllChecks = true;

        /* deploy voter  */
        kitten = Kitten(
            Upgrades.deployUUPSProxy(
                "Kitten.sol",
                abi.encodeCall(Kitten.initialize, ()),
                opts
            )
        );
        artProxy = new VeArtProxy();
        veKitten = VotingEscrow(
            Upgrades.deployUUPSProxy(
                "VotingEscrow.sol",
                abi.encodeCall(
                    VotingEscrow.initialize,
                    (address(kitten), address(artProxy))
                ),
                opts
            )
        );
        voter = Voter(
            Upgrades.deployUUPSProxy(
                "Voter.sol",
                abi.encodeCall(
                    Voter.initialize,
                    (address(veKitten), address(factoryRegistry))
                ),
                opts
            )
        );
        rewardsDistributor = RewardsDistributor(
            Upgrades.deployUUPSProxy(
                "RewardsDistributor.sol",
                abi.encodeCall(
                    RewardsDistributor.initialize,
                    (address(veKitten))
                ),
                opts
            )
        );
        minter = Minter(
            Upgrades.deployUUPSProxy(
                "Minter.sol",
                abi.encodeCall(
                    Minter.initialize,
                    (
                        address(voter),
                        address(veKitten),
                        address(rewardsDistributor)
                    )
                ),
                opts
            )
        );

        /* deploy gauge */
        gaugeFactory = new GaugeFactory();
        bribeFactory = new BribeFactory();
        clGaugeFactory = CLGaugeFactory(
            Upgrades.deployUUPSProxy(
                "CLGaugeFactory.sol",
                abi.encodeCall(
                    CLGaugeFactory.initialize,
                    (address(veKitten), address(voter), address(nfp))
                ),
                opts
            )
        );

        /* init */
        kitten.initialMint(deployer, 1_000_000_000 ether);
        kitten.setMinter(address(minter));

        veKitten.setVoter(address(voter));
        veKitten.setTeam(multisig);

        voter.setGovernor(deployer);
        voter.setEmergencyCouncil(multisig);

        rewardsDistributor.setDepositor(address(minter));

        minter.setTeam(multisig);

        address[] memory tokens = new address[](3);
        tokens[0] = address(kitten);
        tokens[1] = address(WHYPE);
        tokens[2] = address(UBTC);
        voter.init(tokens, address(minter));

        minter.init();

        console.log("clFactory owner", clFactory.owner());
        clFactory.setVoter(address(voter));

        vm.stopPrank();

        vm.startPrank(multisig);
        factoryRegistry.approve(
            address(pairFactory),
            address(bribeFactory),
            address(gaugeFactory)
        );
        factoryRegistry.approve(
            address(clFactory),
            address(bribeFactory),
            address(clGaugeFactory)
        );

        vm.stopPrank();
    }

    function testDistributeVeKitten() public {
        _setUp();

        vm.startPrank(deployer);

        kitten.approve(address(veKitten), type(uint256).max);
        veKitten.create_lock_for(100_000_000 ether, 52 weeks * 2, user1);
        veKitten.create_lock_for(150_000_000 ether, 52 weeks * 2, user2);

        vm.stopPrank();
    }

    function testCreateGauge() public returns (address pair, address pool) {
        testDistributeVeKitten();

        vm.startPrank(deployer);

        pair = pairFactory.getPair(address(WHYPE), address(UBTC), stable);
        console.log("pair address", pair);
        voter.createGauge(address(pairFactory), pair);

        pool = clFactory.getPool(address(WHYPE), address(UBTC), 200);
        voter.createCLGauge(address(clFactory), pool);

        vm.stopPrank();
    }

    function testStakeInGauge() public returns (address pair, address pool) {
        (pair, pool) = testCreateGauge();

        vm.startPrank(deployer);

        (Gauge pairGauge, CLGauge poolGauge) = (
            Gauge(voter.gauges(pair)),
            CLGauge(voter.gauges(pool))
        );

        IERC20(pairGauge.stake()).approve(
            address(pairGauge),
            type(uint256).max
        );
        console.log("block.number depositAll", block.number);
        pairGauge.depositAll(0);
        console.log("block.number depositAll", block.number);

        nfp.setApprovalForAll(address(poolGauge), true);
        poolGauge.deposit(21401, 0);

        vm.stopPrank();
    }

    function testSwapVolume() public returns (address pair, address pool) {
        (pair, pool) = testStakeInGauge();

        vm.deal(swapper, 1_000 ether);
        vm.startPrank(swapper);

        Router.route[] memory routes = new Router.route[](1);
        routes[0].from = address(WHYPE);
        routes[0].to = address(UBTC);
        routes[0].stable = false;

        uint amount = (((swapper).balance / 2) * (block.timestamp % 10_000)) /
            10_000;

        router.swapExactETHForTokens{value: amount}(
            0,
            routes,
            swapper,
            block.timestamp + 60 * 20
        );

        (routes[0].from, routes[0].to) = (routes[0].to, routes[0].from);

        amount =
            (UBTC.balanceOf(swapper) *
                ((block.timestamp * block.timestamp) % 10_000)) /
            10_000;

        UBTC.approve(address(router), amount);
        router.swapExactTokensForETH(
            amount,
            0,
            routes,
            swapper,
            block.timestamp + 60 * 20
        );

        /* CL */
        amount =
            (((swapper).balance / 2) * (block.timestamp % 10_000)) /
            10_000;
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams(
                address(WHYPE),
                address(UBTC),
                200,
                swapper,
                block.timestamp + 60 * 20,
                amount,
                0,
                0
            );
        swapRouter.exactInputSingle{value: amount}(params);

        amount =
            (UBTC.balanceOf(swapper) *
                ((block.timestamp * block.timestamp) % 10_000)) /
            10_000;

        UBTC.approve(address(swapRouter), type(uint256).max);
        params = ISwapRouter.ExactInputSingleParams(
            address(UBTC),
            address(WHYPE),
            200,
            swapper,
            block.timestamp + 60 * 20,
            amount,
            0,
            0
        );
        swapRouter.exactInputSingle(params);

        vm.stopPrank();
    }

    function testVote() public returns (address pairGauge, address poolGauge) {
        (address pair, address pool) = testSwapVolume();

        (pairGauge, poolGauge) = (voter.gauges(pair), voter.gauges(pool));

        console.log("pair gauge", pairGauge);
        console.log("pool gauge", poolGauge);
        (uint128 gaugeFees0, uint128 gaugeFees1) = ICLPool(pool).gaugeFees();
        console.log("pool gauge fees", gaugeFees0, gaugeFees1);

        {
            vm.startPrank(user1);

            // uint256 bal = veKitten.balanceOf(user1);
            uint256 veKittenId = veKitten.tokenOfOwnerByIndex(user1, 0);

            address[] memory voteList = new address[](2);
            voteList[0] = pair;
            voteList[1] = pool;
            uint256[] memory weightList = new uint256[](2);
            weightList[0] = block.timestamp % 10_000;
            weightList[1] = 10_000 - (block.timestamp % 10_000);
            voter.vote(veKittenId, voteList, weightList);

            vm.stopPrank();
        }

        {
            vm.startPrank(user2);

            // uint256 bal = veKitten.balanceOf(user1);
            uint256 veKittenId = veKitten.tokenOfOwnerByIndex(user2, 0);

            address[] memory voteList = new address[](2);
            voteList[0] = pair;
            voteList[1] = pool;
            uint256[] memory weightList = new uint256[](2);
            weightList[0] = (block.timestamp * 3) % 10_000;
            weightList[1] = 10_000 - ((block.timestamp * 3) % 10_000);
            voter.vote(veKittenId, voteList, weightList);

            vm.stopPrank();
        }
    }

    function testDistributeEmissionsAndFees()
        public
        returns (address pairGauge, address poolGauge)
    {
        (pairGauge, poolGauge) = testVote();

        uint256 active_period = minter.active_period();
        require(active_period == (block.timestamp / 1 weeks) * 1 weeks);

        vm.startPrank(deployer);

        console.log("current epoch", veKitten.epoch());
        vm.warp(active_period + 1 weeks);

        address[] memory _gauges = new address[](2);
        _gauges[0] = pairGauge;
        _gauges[1] = poolGauge;
        voter.distributeFees(_gauges);
        voter.distro();
        console.log("current epoch", veKitten.epoch());

        vm.stopPrank();
    }

    function testClaimVotingFees()
        public
        returns (address pairGauge, address poolGauge)
    {
        (pairGauge, poolGauge) = testDistributeEmissionsAndFees();

        vm.warp(block.timestamp + 3 days);

        vm.startPrank(user1);

        address[] memory _internalBribes = new address[](2);
        _internalBribes[0] = Gauge(pairGauge).internal_bribe();
        _internalBribes[1] = Gauge(poolGauge).internal_bribe();

        address[][] memory _tokens = new address[][](_internalBribes.length);

        for (uint i; i < _internalBribes.length; i++) {
            uint len = InternalBribe(_internalBribes[i]).rewardsListLength();
            _tokens[i] = new address[](len);

            for (uint j; j < len; j++) {
                _tokens[i][j] = InternalBribe(_internalBribes[i]).rewards(j);

                console.log(
                    "token bal",
                    IERC20(_tokens[i][j]).balanceOf(_internalBribes[i])
                );
            }
        }

        uint256 veKittenId = veKitten.tokenOfOwnerByIndex(user1, 0);
        voter.claimFees(_internalBribes, _tokens, veKittenId);

        vm.stopPrank();
    }

    function testClaimEmissions()
        public
        returns (address pairGauge, address poolGauge)
    {
        (pairGauge, poolGauge) = testClaimVotingFees();

        vm.startPrank(deployer);

        address[] memory _gauges = new address[](2);
        _gauges[0] = pairGauge;
        _gauges[1] = poolGauge;

        address[][] memory _tokens = new address[][](_gauges.length);

        uint len = Gauge(pairGauge).rewardsListLength();
        _tokens[0] = new address[](len);

        for (uint i; i < len; i++) {
            _tokens[0][i] = Gauge(pairGauge).rewards(i);
        }

        _tokens[1] = new address[](1);
        _tokens[1][0] = CLGauge(poolGauge).kitten();

        voter.claimRewards(_gauges, _tokens);

        console.log("kitten bal", kitten.balanceOf(deployer));
        require(kitten.balanceOf(deployer) > 0);

        vm.stopPrank();
    }

    function testUnstakeFromGauge() public {
        (address pairGauge, address poolGauge) = testClaimEmissions();
        (Gauge gauge, CLGauge clGauge) = (Gauge(pairGauge), CLGauge(poolGauge));

        vm.startPrank(deployer);

        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);

        console.log("block.number withdrawAll", block.number);
        gauge.withdrawAll();
        console.log("block.number withdrawAll", block.number);

        uint256 len = clGauge.getUserStakedNFPsLength(deployer);

        uint256[] memory nfpTokenIdList = new uint256[](len);

        nfpTokenIdList = clGauge.getUserStakedNFPs(deployer);

        for (uint i; i < len; i++) {
            clGauge.withdraw(nfpTokenIdList[i]);
        }

        vm.stopPrank();
    }

    function testClaimRebaseRewards() public {
        testUnstakeFromGauge();

        uint256 active_period = minter.active_period();
        vm.warp(active_period + 1 weeks);
        vm.roll(block.number + 1);

        voter.distro();

        vm.startPrank(user1);

        uint256 veKittenId = veKitten.tokenOfOwnerByIndex(user1, 0);
        rewardsDistributor.claim(veKittenId);

        vm.stopPrank();
    }

    // expect this test to fail
    function testGaugeActionLock() public returns (address pair, address pool) {
        (pair, pool) = testCreateGauge();

        vm.startPrank(deployer);

        IERC20(Gauge(voter.gauges(pair)).stake()).approve(
            address(voter.gauges(pair)),
            type(uint256).max
        );

        uint blockNumber = block.number;
        vm.roll(blockNumber);
        Gauge(voter.gauges(pair)).depositAll(0);

        vm.roll(blockNumber);
        // vm.expectRevert("Action Locked");
        Gauge(voter.gauges(pair)).withdrawAll();

        vm.stopPrank();
    }

    // expect this test to fail
    function testCLGaugeActionLock()
        public
        returns (address pair, address pool)
    {
        (pair, pool) = testCreateGauge();

        vm.startPrank(deployer);

        nfp.setApprovalForAll(voter.gauges(pool), true);

        uint blockNumber = block.number;
        vm.roll(blockNumber);
        CLGauge(voter.gauges(pool)).deposit(21401, 0);

        vm.roll(blockNumber);
        // vm.expectRevert("Action Locked");
        CLGauge(voter.gauges(pool)).withdraw(21401);

        vm.stopPrank();
    }

    function testExternalBribeExploitFixed()
        public
        returns (address pairGauge, address poolGauge)
    {
        (pairGauge, poolGauge) = testVote();

        vm.deal(deployer, 1_000 ether);
        vm.startPrank(deployer);

        uint256 veKittenId = veKitten.tokenOfOwnerByIndex(user1, 0);

        address[] memory tokens = new address[](2);
        tokens[0] = address(kitten);
        tokens[1] = address(WHYPE);

        ExternalBribe xBribe = ExternalBribe(Gauge(pairGauge).external_bribe());

        WHYPE.deposit{value: 100 ether}();
        kitten.approve(address(xBribe), type(uint256).max);
        WHYPE.approve(address(xBribe), type(uint256).max);
        xBribe.notifyRewardAmount(address(kitten), 1_000_000 ether);
        xBribe.notifyRewardAmount(address(WHYPE), WHYPE.balanceOf(deployer));

        vm.stopPrank();

        vm.startPrank(address(voter));

        vm.warp(block.timestamp + 1 weeks);
        xBribe.getRewardForOwner(veKittenId, tokens);
        xBribe.getRewardForOwner(veKittenId, tokens);

        vm.stopPrank();
    }

    function testSplitVeKitten() public {
        testDistributeVeKitten();

        vm.startPrank(user1);

        uint veKittenId = veKitten.tokenOfOwnerByIndex(user1, 0);
        (int128 lockedAmount, uint endTime) = veKitten.locked(veKittenId);

        veKitten.split(veKittenId, uint256(uint128(lockedAmount)) / 3);

        vm.stopPrank();
    }

    // expect this test to fail
    function testSplitVeKittenNotZero() public {
        testDistributeVeKitten();

        vm.startPrank(user1);

        uint veKittenId = veKitten.tokenOfOwnerByIndex(user1, 0);
        (int128 lockedAmount, uint endTime) = veKitten.locked(veKittenId);

        veKitten.split(veKittenId, 0);

        vm.stopPrank();
    }
}
