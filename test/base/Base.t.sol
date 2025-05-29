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

contract Base is Test {
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

    /* tokens */
    address[] tokenList = [
        0x5555555555555555555555555555555555555555, // WHYPE
        0x9FDBdA0A5e284c32744D2f17Ee5c74B284993463, // UBTC
        0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb // USDT0
    ];

    mapping(address _token => address) whale;

    IWHYPE9 WHYPE =
        IWHYPE9(payable(0x5555555555555555555555555555555555555555));

    /* users */
    uint256 numberOfUsers = 3;
    address[] userList;

    bool Base__setUp;

    function _setUp() internal {
        if (Base__setUp) return;
        Base__setUp = true;

        /* generate users */
        console.log("users");
        for (uint i; i < numberOfUsers; i++) {
            address _user = vm.randomAddress();
            userList.push(_user);
            vm.deal(_user, 1_000 ether);
            console.log(i, userList[i]);
        }

        /* set whale list for tests */
        whale[
            0x5555555555555555555555555555555555555555
        ] = 0x0000000000000000000000000000000000000000; // WHYPE
        whale[
            0x9FDBdA0A5e284c32744D2f17Ee5c74B284993463
        ] = 0x20000000000000000000000000000000000000c5; // UBTC
        whale[
            0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb
        ] = 0x200000000000000000000000000000000000010C; // USDT0

        vm.startPrank(deployer);

        Options memory opts;
        opts.unsafeSkipAllChecks = true;

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

        address[] memory tokens = new address[](1);
        tokens[0] = address(kitten);
        voter.init(tokens, address(minter));

        minter.init();

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
}
