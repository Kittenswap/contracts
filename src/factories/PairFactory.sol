// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../interfaces/IPairFactory.sol";
import "../Pair.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

contract PairFactory is IPairFactory, UUPSUpgradeable, Ownable2StepUpgradeable {
    bool public isPaused;
    address public pauser;
    address public pendingPauser;

    uint256 public stableFee;
    uint256 public volatileFee;
    uint256 public constant MAX_FEE = 500; // 0.05%
    address public feeManager;
    address public pendingFeeManager;
    mapping(address => uint256) public customFee;

    mapping(address => mapping(address => mapping(bool => address)))
        public getPair;
    address[] public allPairs;
    mapping(address => bool) public isPair; // simplified check if its a pair, given that `stable` flag might not be available in peripherals

    address internal _temp0;
    address internal _temp1;
    bool internal _temp;

    event PairCreated(
        address indexed token0,
        address indexed token1,
        bool stable,
        address pair,
        uint
    );

    event SetCustomFee(address indexed pair, uint256 fee);

    function initialize() public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();

        pauser = msg.sender;
        isPaused = false;
        feeManager = msg.sender;
        stableFee = 2; // 0.02%
        volatileFee = 200;
    }

    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }

    function setPauser(address _pauser) external {
        require(msg.sender == pauser);
        pendingPauser = _pauser;
    }

    function acceptPauser() external {
        require(msg.sender == pendingPauser);
        pauser = pendingPauser;
    }

    function setPause(bool _state) external {
        require(msg.sender == pauser);
        isPaused = _state;
    }

    function setFeeManager(address _feeManager) external {
        require(msg.sender == feeManager, "not fee manager");
        pendingFeeManager = _feeManager;
    }

    function acceptFeeManager() external {
        require(msg.sender == pendingFeeManager, "not pending fee manager");
        feeManager = pendingFeeManager;
    }

    function setFee(bool _stable, uint256 _fee) external {
        require(msg.sender == feeManager, "not fee manager");
        require(_fee <= MAX_FEE, "fee too high");
        require(_fee != 0, "fee must be nonzero");
        if (_stable) {
            stableFee = _fee;
        } else {
            volatileFee = _fee;
        }
    }

    function setCustomFee(address _pair, uint256 _fee) external {
        require(msg.sender == feeManager, "not fee manager");
        require(_fee <= MAX_FEE, "fee too high");
        require(isPair[_pair], "invalid pair");

        customFee[_pair] = _fee;
        emit SetCustomFee(_pair, _fee);
    }

    function getFee(address _pair, bool _stable) public view returns (uint256) {
        if (customFee[_pair] != 0) {
            return customFee[_pair];
        }
        return _stable ? stableFee : volatileFee;
    }

    function pairCodeHash() external pure returns (bytes32) {
        return keccak256(type(Pair).creationCode);
    }

    function getInitializable() external view returns (address, address, bool) {
        return (_temp0, _temp1, _temp);
    }

    function createPair(
        address tokenA,
        address tokenB,
        bool stable
    ) external returns (address pair) {
        require(tokenA != tokenB, "IA"); // Pair: IDENTICAL_ADDRESSES
        (address token0, address token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
        require(token0 != address(0), "ZA"); // Pair: ZERO_ADDRESS
        require(getPair[token0][token1][stable] == address(0), "PE"); // Pair: PAIR_EXISTS - single check is sufficient
        bytes32 salt = keccak256(abi.encodePacked(token0, token1, stable)); // notice salt includes stable as well, 3 parameters
        (_temp0, _temp1, _temp) = (token0, token1, stable);
        pair = address(new Pair{salt: salt}());
        getPair[token0][token1][stable] = pair;
        getPair[token1][token0][stable] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);
        isPair[pair] = true;
        emit PairCreated(token0, token1, stable, pair, allPairs.length);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
}
