// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC721, IERC721Metadata} from "openzeppelin-contracts/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {IERC721Receiver} from "openzeppelin-contracts/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {IVeArtProxy} from "./interfaces/IVeArtProxy.sol";
import {IVotingEscrow} from "./interfaces/IVotingEscrow.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {ERC721EnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {ProtocolTimeLibrary} from "./clAMM/libraries/ProtocolTimeLibrary.sol";

contract VotingEscrow is
    IVotingEscrow,
    UUPSUpgradeable,
    Ownable2StepUpgradeable,
    ERC721EnumerableUpgradeable,
    ReentrancyGuardUpgradeable
{
    uint256 public constant WEEK = ProtocolTimeLibrary.WEEK;
    uint256 public constant MAXTIME = 2 * 365 days;
    int128 public constant iMAXTIME = 2 * 365 days;
    uint256 public constant MULTIPLIER = 1 ether;

    address public kitten;
    address public voter;
    address public artProxy;

    mapping(uint256 => Point) public point_history; // epoch -> unsigned point

    uint256 public tokenId; // current tokenId

    mapping(uint256 => uint256) public user_point_epoch;
    mapping(uint256 => Point[1000000000]) public user_point_history; // user -> Point[user_epoch]
    mapping(uint256 => LockedBalance) public locked;
    uint256 public epoch;
    mapping(uint256 => int128) public slope_changes; // time -> signed slope change
    uint256 public supply;

    mapping(uint256 => bool) public voted;

    mapping(uint256 => uint256) public ownership_change;

    modifier notVoted(uint256 _tokenId) {
        if (voted[_tokenId] == true) revert Voted();
        _;
    }

    modifier onlyAuthorized(uint256 _tokenId) {
        address _owner = ownerOf(_tokenId);
        _checkAuthorized(_owner, msg.sender, _tokenId);
        _;
    }

    modifier onlyVoter() {
        if (msg.sender != voter || voter == address(0)) revert NotVoter();
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _kitten,
        address art_proxy
    ) external initializer {
        __UUPSUpgradeable_init();
        __ERC721Enumerable_init();
        __ERC721_init("veKITTEN", "veKITTEN");
        __Ownable2Step_init();
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();

        kitten = _kitten;
        artProxy = art_proxy;

        point_history[0].blk = block.number;
        point_history[0].ts = block.timestamp;

        // mint-ish
        emit Transfer(address(0), address(this), tokenId);
        // burn-ish
        emit Transfer(address(this), address(0), tokenId);
    }

    /* public functions */
    function merge(
        uint256 _from,
        uint256 _to
    )
        external
        nonReentrant
        onlyAuthorized(_from)
        onlyAuthorized(_to)
        notVoted(_from)
    {
        if (_from == _to) revert Invalid();

        LockedBalance memory _locked0 = locked[_from];
        LockedBalance memory _locked1 = locked[_to];
        uint256 value0 = uint256(int256(_locked0.amount));
        uint256 end = _locked0.end >= _locked1.end
            ? _locked0.end
            : _locked1.end;

        locked[_from] = LockedBalance(0, 0);
        _checkpoint(_from, _locked0, LockedBalance(0, 0));
        supply -= value0;
        _deposit_for(_to, value0, end, _locked1, DepositType.MERGE_TYPE);
    }

    function split(
        uint256 _from,
        uint256 _amount
    )
        external
        nonReentrant
        onlyAuthorized(_from)
        notVoted(_from)
        returns (uint256 _tokenId1, uint256 _tokenId2)
    {
        address tokenIdOwner = ownerOf(_from);

        LockedBalance memory _locked = locked[_from];
        int128 value = _locked.amount;

        if (_amount == 0 || _amount >= uint256(uint128(value)))
            revert ZeroSplit();

        locked[_from] = LockedBalance(0, 0);
        _checkpoint(_from, _locked, LockedBalance(0, 0));

        // set max lock on new NFTs
        _locked.end = ((block.timestamp + MAXTIME) / WEEK) * WEEK;

        // split and mint new NFTs
        int128 _splitAmount = int128(uint128(_amount));
        _locked.amount = value - _splitAmount;
        _tokenId1 = _createSplitNFT(tokenIdOwner, _locked);

        _locked.amount = _splitAmount;
        _tokenId2 = _createSplitNFT(tokenIdOwner, _locked);

        emit Split(
            _from,
            _tokenId1,
            _tokenId2,
            msg.sender,
            uint256(uint128(locked[_tokenId1].amount)),
            uint256(uint128(_splitAmount)),
            _locked.end,
            block.timestamp
        );
    }

    function checkpoint() external {
        _checkpoint(0, LockedBalance(0, 0), LockedBalance(0, 0));
    }

    function deposit_for(
        uint256 _tokenId,
        uint256 _value
    ) external nonReentrant {
        LockedBalance memory _locked = locked[_tokenId];

        if (_value == 0) revert Invalid();
        if (_locked.amount == 0) revert LockNotExist();
        if (block.timestamp >= _locked.end) revert LockExpired();
        _deposit_for(
            _tokenId,
            _value,
            0,
            _locked,
            DepositType.DEPOSIT_FOR_TYPE
        );
    }

    function create_lock(
        uint256 _value,
        uint256 _lock_duration
    ) external nonReentrant returns (uint256) {
        return _create_lock(_value, _lock_duration, msg.sender);
    }

    function create_lock_for(
        uint256 _value,
        uint256 _lock_duration,
        address _to
    ) external nonReentrant returns (uint256) {
        return _create_lock(_value, _lock_duration, _to);
    }

    function increase_amount(
        uint256 _tokenId,
        uint256 _value
    ) external nonReentrant onlyAuthorized(_tokenId) {
        LockedBalance memory _locked = locked[_tokenId];

        if (_value == 0) revert Invalid();
        if (_locked.amount == 0) revert LockNotExist();
        if (block.timestamp >= _locked.end) revert LockExpired();
        _deposit_for(
            _tokenId,
            _value,
            0,
            _locked,
            DepositType.INCREASE_LOCK_AMOUNT
        );
    }

    function increase_unlock_time(
        uint256 _tokenId,
        uint256 _lock_duration
    ) external nonReentrant onlyAuthorized(_tokenId) {
        LockedBalance memory _locked = locked[_tokenId];
        uint256 unlock_time = ((block.timestamp + _lock_duration) / WEEK) *
            WEEK; // Locktime is rounded down to weeks

        if (block.timestamp >= _locked.end) revert LockExpired();
        if (_locked.amount == 0) revert LockNotExist();
        if (unlock_time <= _locked.end) revert Invalid();
        if (unlock_time > block.timestamp + MAXTIME) revert OverMaxLockTime();

        _deposit_for(
            _tokenId,
            0,
            unlock_time,
            _locked,
            DepositType.INCREASE_UNLOCK_TIME
        );
    }

    function withdraw(
        uint256 _tokenId
    ) external nonReentrant onlyAuthorized(_tokenId) notVoted(_tokenId) {
        LockedBalance memory _locked = locked[_tokenId];
        if (block.timestamp < _locked.end) revert NotExpired();
        uint256 value = uint256(int256(_locked.amount));

        locked[_tokenId] = LockedBalance(0, 0);
        uint256 supply_before = supply;
        supply = supply_before - value;

        // old_locked can have either expired <= timestamp or zero end
        // _locked has only 0 end
        // Both can have >= 0 amount
        _checkpoint(_tokenId, _locked, LockedBalance(0, 0));

        assert(IERC20(kitten).transfer(msg.sender, value));

        emit Withdraw(msg.sender, _tokenId, value, block.timestamp);
        emit Supply(supply_before, supply_before - value);
    }

    /* view functions */
    function tokenURI(
        uint256 _tokenId
    ) public view override returns (string memory) {
        _requireOwned(_tokenId);
        LockedBalance memory _locked = locked[_tokenId];
        return
            IVeArtProxy(artProxy)._tokenURI(
                _tokenId,
                _balanceOfNFT(_tokenId, block.timestamp),
                _locked.end,
                uint256(int256(_locked.amount))
            );
    }

    function isApprovedOrOwner(
        address _spender,
        uint256 _tokenId
    ) external view returns (bool) {
        address _owner = ownerOf(_tokenId);
        return _isAuthorized(_owner, _spender, _tokenId);
    }

    function get_last_user_slope(
        uint256 _tokenId
    ) external view returns (int128) {
        uint256 uepoch = user_point_epoch[_tokenId];
        return user_point_history[_tokenId][uepoch].slope;
    }

    function userPointHistory(
        uint256 _tokenId,
        uint256 _idx
    ) external view returns (Point memory) {
        return user_point_history[_tokenId][_idx];
    }

    function balanceOfNFT(uint256 _tokenId) external view returns (uint256) {
        if (ownership_change[_tokenId] == block.number) return 0;
        return _balanceOfNFT(_tokenId, block.timestamp);
    }

    function totalVotingPower() public view returns (uint256) {
        return _supply_at(point_history[epoch], block.timestamp);
    }

    /* only owner functions */
    function setVoter(address _voter) external onlyOwner {
        voter = _voter;
    }

    function setArtProxy(address _proxy) external onlyOwner {
        artProxy = _proxy;
    }

    /* only voter functions */

    function voting(uint256 _tokenId) external onlyVoter {
        voted[_tokenId] = true;
    }

    function abstain(uint256 _tokenId) external onlyVoter {
        voted[_tokenId] = false;
    }

    /* internal functions */
    function _createSplitNFT(
        address _to,
        LockedBalance memory _newLocked
    ) internal returns (uint256 _tokenId) {
        _tokenId = ++tokenId;
        _mint(_to, _tokenId);
        locked[_tokenId] = _newLocked;
        _checkpoint(_tokenId, LockedBalance(0, 0), _newLocked);
    }

    function _update(
        address _to,
        uint256 _tokenId,
        address _auth
    ) internal override notVoted(_tokenId) returns (address) {
        return ERC721EnumerableUpgradeable._update(_to, _tokenId, _auth);
    }

    function _checkpoint(
        uint256 _tokenId,
        LockedBalance memory old_locked,
        LockedBalance memory new_locked
    ) internal {
        Point memory u_old;
        Point memory u_new;
        int128 old_dslope = 0;
        int128 new_dslope = 0;
        uint256 _epoch = epoch;

        if (_tokenId != 0) {
            // Calculate slopes and biases
            // Kept at zero when they have to
            if (old_locked.end > block.timestamp && old_locked.amount > 0) {
                u_old.slope = old_locked.amount / iMAXTIME;
                u_old.bias =
                    u_old.slope *
                    int128(int256(old_locked.end - block.timestamp));
            }
            if (new_locked.end > block.timestamp && new_locked.amount > 0) {
                u_new.slope = new_locked.amount / iMAXTIME;
                u_new.bias =
                    u_new.slope *
                    int128(int256(new_locked.end - block.timestamp));
            }

            // Read values of scheduled changes in the slope
            // old_locked.end can be in the past and in the future
            // new_locked.end can ONLY by in the FUTURE unless everything expired: than zeros
            old_dslope = slope_changes[old_locked.end];
            if (new_locked.end != 0) {
                if (new_locked.end == old_locked.end) {
                    new_dslope = old_dslope;
                } else {
                    new_dslope = slope_changes[new_locked.end];
                }
            }
        }

        Point memory last_point = Point({
            bias: 0,
            slope: 0,
            ts: block.timestamp,
            blk: block.number
        });
        if (_epoch > 0) {
            last_point = point_history[_epoch];
        }
        uint256 last_checkpoint = last_point.ts;
        // initial_last_point is used for extrapolation to calculate block number
        // (approximately, for *At methods) and save them
        // as we cannot figure that out exactly from inside the contract
        Point memory initial_last_point = Point({
            bias: last_point.bias,
            slope: last_point.slope,
            ts: last_point.ts,
            blk: last_point.blk
        });
        uint256 block_slope = 0; // dblock/dt
        if (block.timestamp > last_point.ts) {
            block_slope =
                (MULTIPLIER * (block.number - last_point.blk)) /
                (block.timestamp - last_point.ts);
        }
        // If last point is already recorded in this block, slope=0
        // But that's ok b/c we know the block in such case

        // Go over weeks to fill history and calculate what the current point is
        {
            uint256 t_i = (last_checkpoint / WEEK) * WEEK;
            for (uint256 i = 0; i < 255; ++i) {
                // Hopefully it won't happen that this won't get used in 5 years!
                // If it does, users will be able to withdraw but vote weight will be broken
                t_i += WEEK;
                int128 d_slope = 0;
                if (t_i > block.timestamp) {
                    t_i = block.timestamp;
                } else {
                    d_slope = slope_changes[t_i];
                }
                last_point.bias -=
                    last_point.slope *
                    int128(int256(t_i - last_checkpoint));
                last_point.slope += d_slope;
                if (last_point.bias < 0) {
                    // This can happen
                    last_point.bias = 0;
                }
                if (last_point.slope < 0) {
                    // This cannot happen - just in case
                    last_point.slope = 0;
                }
                last_checkpoint = t_i;
                last_point.ts = t_i;
                last_point.blk =
                    initial_last_point.blk +
                    (block_slope * (t_i - initial_last_point.ts)) /
                    MULTIPLIER;
                _epoch += 1;
                if (t_i == block.timestamp) {
                    last_point.blk = block.number;
                    break;
                } else {
                    point_history[_epoch] = last_point;
                }
            }
        }

        epoch = _epoch;
        // Now point_history is filled until t=now

        if (_tokenId != 0) {
            // If last point was in this block, the slope change has been applied already
            // But in such case we have 0 slope(s)
            last_point.slope += (u_new.slope - u_old.slope);
            last_point.bias += (u_new.bias - u_old.bias);
            if (last_point.slope < 0) {
                last_point.slope = 0;
            }
            if (last_point.bias < 0) {
                last_point.bias = 0;
            }
        }

        // Record the changed point into history
        point_history[_epoch] = last_point;

        if (_tokenId != 0) {
            // Schedule the slope changes (slope is going down)
            // We subtract new_user_slope from [new_locked.end]
            // and add old_user_slope to [old_locked.end]
            if (old_locked.end > block.timestamp) {
                // old_dslope was <something> - u_old.slope, so we cancel that
                old_dslope += u_old.slope;
                if (new_locked.end == old_locked.end) {
                    old_dslope -= u_new.slope; // It was a new deposit, not extension
                }
                slope_changes[old_locked.end] = old_dslope;
            }

            if (new_locked.end > block.timestamp) {
                if (new_locked.end > old_locked.end) {
                    new_dslope -= u_new.slope; // old slope disappeared at this point
                    slope_changes[new_locked.end] = new_dslope;
                }
                // else: we recorded it already in old_dslope
            }
            // Now handle user history
            uint256 user_epoch = user_point_epoch[_tokenId] + 1;

            user_point_epoch[_tokenId] = user_epoch;
            u_new.ts = block.timestamp;
            u_new.blk = block.number;
            user_point_history[_tokenId][user_epoch] = u_new;
        }
    }

    function _deposit_for(
        uint256 _tokenId,
        uint256 _value,
        uint256 unlock_time,
        LockedBalance memory locked_balance,
        DepositType deposit_type
    ) internal {
        LockedBalance memory _locked = locked_balance;
        uint256 supply_before = supply;

        supply = supply_before + _value;
        LockedBalance memory old_locked;
        (old_locked.amount, old_locked.end) = (_locked.amount, _locked.end);
        // Adding to existing lock, or if a lock is expired - creating a new one
        _locked.amount += int128(int256(_value));
        if (unlock_time != 0) {
            _locked.end = unlock_time;
        }
        locked[_tokenId] = _locked;

        // Possibilities:
        // Both old_locked.end could be current or expired (>/< block.timestamp)
        // value == 0 (extend lock) or value > 0 (add to lock or extend lock)
        // _locked.end > block.timestamp (always)
        _checkpoint(_tokenId, old_locked, _locked);

        address from = msg.sender;
        if (_value != 0 && deposit_type != DepositType.MERGE_TYPE) {
            assert(IERC20(kitten).transferFrom(from, address(this), _value));
        }

        emit Deposit(
            from,
            _tokenId,
            _value,
            _locked.end,
            deposit_type,
            block.timestamp
        );
        emit Supply(supply_before, supply_before + _value);
    }

    function _create_lock(
        uint256 _value,
        uint256 _lock_duration,
        address _to
    ) internal returns (uint256) {
        uint256 unlock_time = ((block.timestamp + _lock_duration) / WEEK) *
            WEEK; // Locktime is rounded down to weeks

        if (_value == 0) revert Invalid();
        if (block.timestamp >= unlock_time) revert Invalid();
        if (unlock_time > block.timestamp + MAXTIME) revert OverMaxLockTime();

        ++tokenId;
        uint256 _tokenId = tokenId;
        _mint(_to, _tokenId);

        _deposit_for(
            _tokenId,
            _value,
            unlock_time,
            locked[_tokenId],
            DepositType.CREATE_LOCK_TYPE
        );
        return _tokenId;
    }

    function _balanceOfNFT(
        uint256 _tokenId,
        uint256 _t
    ) internal view returns (uint256) {
        uint256 _epoch = user_point_epoch[_tokenId];
        if (_epoch == 0) {
            return 0;
        } else {
            Point memory last_point = user_point_history[_tokenId][_epoch];
            last_point.bias -=
                last_point.slope *
                int128(int256(_t) - int256(last_point.ts));
            if (last_point.bias < 0) {
                last_point.bias = 0;
            }
            return uint256(int256(last_point.bias));
        }
    }

    function _supply_at(
        Point memory point,
        uint256 t
    ) internal view returns (uint256) {
        Point memory last_point = point;
        uint256 t_i = (last_point.ts / WEEK) * WEEK;
        for (uint256 i = 0; i < 255; ++i) {
            t_i += WEEK;
            int128 d_slope = 0;
            if (t_i > t) {
                t_i = t;
            } else {
                d_slope = slope_changes[t_i];
            }
            last_point.bias -=
                last_point.slope *
                int128(int256(t_i - last_point.ts));
            if (t_i == t) {
                break;
            }
            last_point.slope += d_slope;
            last_point.ts = t_i;
        }

        if (last_point.bias < 0) {
            last_point.bias = 0;
        }
        return uint256(uint128(last_point.bias));
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
}
