pragma solidity ^0.8.23;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IVotingEscrow is IERC721 {
    enum DepositType {
        DEPOSIT_FOR_TYPE,
        CREATE_LOCK_TYPE,
        INCREASE_LOCK_AMOUNT,
        INCREASE_UNLOCK_TIME,
        MERGE_TYPE
    }

    struct LockedBalance {
        int128 amount;
        uint256 end;
    }

    struct Point {
        int128 bias;
        int128 slope; // # -dweight / dt
        uint256 ts;
        uint256 blk; // block
    }

    event Deposit(
        address indexed provider,
        uint256 tokenId,
        uint256 value,
        uint256 indexed locktime,
        DepositType deposit_type,
        uint256 ts
    );
    event Withdraw(
        address indexed provider,
        uint256 tokenId,
        uint256 value,
        uint256 ts
    );
    event Supply(uint256 prevSupply, uint256 supply);
    event Split(
        uint256 indexed _from,
        uint256 indexed _tokenId1,
        uint256 indexed _tokenId2,
        address _sender,
        uint256 _splitAmount1,
        uint256 _splitAmount2,
        uint256 _locktime,
        uint256 _ts
    );

    error Voted();
    error Invalid();
    error ZeroSplit();
    error NotVoter();
    error LockNotExist();
    error LockExpired();
    error OverMaxLockTime();
    error NotExpired();

    function kitten() external view returns (address);
    function epoch() external view returns (uint256);
    function point_history(
        uint256 loc
    )
        external
        view
        returns (int128 bias, int128 slope, uint256 ts, uint256 blk);
    function user_point_history(
        uint256 tokenId,
        uint256 loc
    )
        external
        view
        returns (int128 bias, int128 slope, uint256 ts, uint256 blk);
    function user_point_epoch(uint256 tokenId) external view returns (uint256);

    function isApprovedOrOwner(address, uint256) external view returns (bool);

    function voting(uint256 tokenId) external;
    function abstain(uint256 tokenId) external;

    function checkpoint() external;
    function deposit_for(uint256 tokenId, uint256 value) external;
    function create_lock_for(
        uint256,
        uint256,
        address
    ) external returns (uint256);

    function balanceOfNFT(uint256) external view returns (uint256);
    // function totalVotingPower() external view returns (uint256);
}
