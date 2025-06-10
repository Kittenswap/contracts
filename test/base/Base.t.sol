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
    RebaseReward rebaseReward;
    Minter minter;

    /* gauges & bribes */
    GaugeFactory gaugeFactory;
    VotingRewardFactory votingRewardFactory;
    CLGaugeFactory clGaugeFactory;

    /* tokens */
    address[] tokenList = [
        0x5555555555555555555555555555555555555555, // WHYPE
        // 0x94e8396e0869c9F2200760aF0621aFd240E1CF38, // wstHYPE
        // 0xdAbB040c428436d41CECd0Fb06bCFDBAaD3a9AA8, // mHYPE
        0x9FDBdA0A5e284c32744D2f17Ee5c74B284993463, // UBTC
        // 0x068f321Fa8Fb9f0D135f290Ef6a3e2813e1c8A29, // USOL
        // 0x00fDBc53719604D924226215bc871D55e40a1009, // LOOP
        // 0x502EE789B448aA692901FE27Ab03174c90F07dD1, // stLOOP
        // 0x3B4575E689DEd21CAAD31d64C4df1f10F3B2CedF, // UFART
        // 0x1Ecd15865D7F8019D546f76d095d9c93cc34eDFa, // LIQD
        0xBe6727B535545C67d5cAa73dEa54865B92CF7907, // UETH
        // 0x5d3a1Ff2b6BAb83b63cd9AD0787074081a52ef34, // USDe
        // 0x0aD339d66BF4AeD5ce31c64Bc37B3244b6394A77, // USDR
        // 0xca79db4B49f608eF54a5CB813FbEd3a6387bC645, // USDXL
        // 0x9b498C3c8A0b8CD8BA1D9851d40D186F1872b44E, // PURR
        // 0x02c6a2fA58cC01A18B8D9E00eA48d65E4dF26c70, // feUSD
        0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb, // USDT0
        // 0x5748ae796AE46A4F1348a1693de4b50560485562, // LHYPE
        // 0xB5fE77d323d69eB352A02006eA8ecC38D882620C, // KEI
        0xe3C80b7A1A8631E8cFd59c61E2a74Eb497dB28F6 // PAWS
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
            0x94e8396e0869c9F2200760aF0621aFd240E1CF38
        ] = 0x0Ab8AAE3335Ed4B373A33D9023b6A6585b149D33; // wstHYPE
        whale[
            0xdAbB040c428436d41CECd0Fb06bCFDBAaD3a9AA8
        ] = 0xE4847Cb23dAd9311b9907497EF8B39d00AC1DE14; // mHYPE
        whale[
            0x9FDBdA0A5e284c32744D2f17Ee5c74B284993463
        ] = 0x20000000000000000000000000000000000000c5; // UBTC
        whale[
            0x068f321Fa8Fb9f0D135f290Ef6a3e2813e1c8A29
        ] = 0x20000000000000000000000000000000000000fE; // USOL
        whale[
            0x00fDBc53719604D924226215bc871D55e40a1009
        ] = 0x502EE789B448aA692901FE27Ab03174c90F07dD1; // LOOP
        whale[
            0x502EE789B448aA692901FE27Ab03174c90F07dD1
        ] = 0x6D7823CD5c3d9dcd63E6A8021b475e0c7C94b291; // stLOOP
        whale[
            0x3B4575E689DEd21CAAD31d64C4df1f10F3B2CedF
        ] = 0x200000000000000000000000000000000000010D; // UFART
        whale[
            0x1Ecd15865D7F8019D546f76d095d9c93cc34eDFa
        ] = 0x20000000000000000000000000000000000000B2; // LIQD
        whale[
            0xBe6727B535545C67d5cAa73dEa54865B92CF7907
        ] = 0x20000000000000000000000000000000000000dD; // UETH
        whale[
            0x5d3a1Ff2b6BAb83b63cd9AD0787074081a52ef34
        ] = 0x20000000000000000000000000000000000000eB; // USDe
        whale[
            0x0aD339d66BF4AeD5ce31c64Bc37B3244b6394A77
        ] = 0x1e772565d78761d67796643941597c9f452Da0D9; // USR
        whale[
            0xca79db4B49f608eF54a5CB813FbEd3a6387bC645
        ] = 0x9992eD1214EA2bC91B0587b37C3E03D5e2a242C1; // USDXL
        whale[
            0x9b498C3c8A0b8CD8BA1D9851d40D186F1872b44E
        ] = 0x2000000000000000000000000000000000000001; // PURR
        whale[
            0x02c6a2fA58cC01A18B8D9E00eA48d65E4dF26c70
        ] = 0x576c9c501473e01aE23748de28415a74425eFD6b; // feUSD
        whale[
            0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb
        ] = 0x200000000000000000000000000000000000010C; // USDT0
        whale[
            0x5748ae796AE46A4F1348a1693de4b50560485562
        ] = 0xAeedD5B6d42e0F077ccF3E7A78ff70b8cB217329; // LHYPE
        whale[
            0xB5fE77d323d69eB352A02006eA8ecC38D882620C
        ] = 0xb22f7B5d5724B1a454d6811456C85491C1BB249b; // KEI
        whale[
            0xe3C80b7A1A8631E8cFd59c61E2a74Eb497dB28F6
        ] = 0x606b48D6b2F4B168f99e1Bd47B382c8e403f15bA; // PAWS

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
        console.log("kitten", address(kitten));
        artProxy = new VeArtProxy();
        console.log("artProxy", address(artProxy));
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
        console.log("veKitten", address(veKitten));
        voter = Voter(
            Upgrades.deployUUPSProxy(
                "Voter.sol",
                abi.encodeCall(
                    Voter.initialize,
                    (address(veKitten), address(factoryRegistry), deployer)
                ),
                opts
            )
        );
        console.log("voter", address(voter));
        rebaseReward = RebaseReward(
            Upgrades.deployUUPSProxy(
                "RebaseReward.sol",
                abi.encodeCall(
                    RebaseReward.initialize,
                    (address(voter), address(veKitten), deployer)
                ),
                opts
            )
        );
        console.log("rebaseReward", address(rebaseReward));
        minter = Minter(
            Upgrades.deployUUPSProxy(
                "Minter.sol",
                abi.encodeCall(
                    Minter.initialize,
                    (
                        address(voter),
                        address(veKitten),
                        address(rebaseReward),
                        multisig
                    )
                ),
                opts
            )
        );
        console.log("minter", address(minter));

        /* deploy gauge */
        gaugeFactory = GaugeFactory(
            Upgrades.deployUUPSProxy(
                "GaugeFactory.sol",
                abi.encodeCall(
                    GaugeFactory.initialize,
                    (address(kitten), address(voter), deployer)
                ),
                opts
            )
        );
        console.log("gaugeFactory", address(gaugeFactory));
        votingRewardFactory = VotingRewardFactory(
            Upgrades.deployUUPSProxy(
                "VotingRewardFactory.sol",
                abi.encodeCall(
                    VotingRewardFactory.initialize,
                    (address(veKitten), address(voter), deployer)
                ),
                opts
            )
        );
        console.log("votingRewardFactory", address(votingRewardFactory));
        clGaugeFactory = CLGaugeFactory(
            Upgrades.deployUUPSProxy(
                "CLGaugeFactory.sol",
                abi.encodeCall(
                    CLGaugeFactory.initialize,
                    (
                        address(veKitten),
                        address(voter),
                        address(nfp),
                        address(kitten)
                    )
                ),
                opts
            )
        );
        console.log("clGaugeFactory", address(clGaugeFactory));

        /* init */
        kitten.setMinter(address(minter));

        veKitten.setVoter(address(voter));

        voter.grantRole(voter.AUTHORIZED_ROLE(), multisig);
        voter.setRebaseReward(address(rebaseReward));

        for (uint256 i; i < tokenList.length; i++) {
            voter.whitelist(tokenList[i], true);
        }

        rebaseReward.grantNotifyRole(address(minter));

        address[] memory tokens = new address[](1);
        tokens[0] = address(kitten);
        voter.init(tokens, address(minter));

        clFactory.setVoter(address(voter));

        vm.stopPrank();

        vm.startPrank(multisig);
        factoryRegistry.approve(
            address(pairFactory),
            address(votingRewardFactory),
            address(gaugeFactory)
        );
        factoryRegistry.approve(
            address(clFactory),
            address(votingRewardFactory),
            address(clGaugeFactory)
        );

        vm.stopPrank();
    }
}
