// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {EnumerableSet} from "../../../lib/openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

contract HexTokenMock is ERC20 {
    using EnumerableSet for EnumerableSet.UintSet;

    struct GlobalsStore {
        uint72 lockedHeartsTotal;
        uint72 nextStakeSharesTotal;
        uint40 shareRate;
        uint72 stakePenaltyTotal;
        uint16 dailyDataCount;
        uint72 stakeSharesTotal;
        uint40 latestStakeId;
        uint128 claimStats;
    }

    struct StakeStore {
        uint40 stakeId;
        uint72 stakedHearts;
        uint72 stakeShares;
        uint16 lockedDay;
        uint16 stakedDays;
        uint16 unlockedDay;
        bool isAutoStake;
    }

    uint256 internal constant HEART_UINT_SIZE = 72;

    uint256 public launchedTime;
    uint256 public stakeId;

    GlobalsStore private globals;
    mapping(address => EnumerableSet.UintSet) private stakedIds;
    mapping(uint256 => StakeStore) private stakeInfo;

    uint72 private payout = 6500000000000000;
    uint72 private shares = 9500000000000000000;

    constructor() ERC20("Hex Token", "HEX") {
        launchedTime = block.timestamp;
        stakeId = 1;
        globals.shareRate = 250000;
    }

    function decimals() public view virtual override returns (uint8) {
        return 8;
    }

    // ---------------------- Utilities -------------------------------

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function increaseShareRate(uint40 rate) external {
        globals.shareRate += rate;
    }

    // ---------------------- Hex Functions ---------------------------

    function currentDay() public view returns (uint256) {
        return ((block.timestamp - launchedTime) / 1 days) + 1;
    }

    function stakeStart(uint256 newStakedHearts, uint256 newStakedDays) external {
        address sender = msg.sender;
        uint256 curStakeId = stakeId;

        stakedIds[sender].add(curStakeId);

        uint256 curDay = currentDay();

        stakeInfo[curStakeId] = StakeStore(
            uint40(curStakeId),
            uint72(newStakedHearts),
            _calcShareRate(newStakedHearts),
            uint16(curDay),
            uint16(newStakedDays),
            uint16(curDay) + uint16(newStakedDays),
            false
        );

        _burn(sender, newStakedHearts);

        stakeId++;
    }

    function stakeEnd(uint256 stakeIndex, uint40 stakeIdParam) external {
        address sender = msg.sender;
        uint256 userStakeId = stakedIds[sender].at(stakeIndex);
        require(userStakeId == stakeIdParam, "wrong stakeIndex");

        StakeStore memory data = stakeInfo[stakeIdParam];
        uint256 rewardsAmount = (uint256(data.stakeShares) * uint256(payout)) / 1e15;
        _mint(sender, rewardsAmount + data.stakedHearts);

        delete stakeInfo[stakeIdParam];
    }

    function stakeCount(address stakerAddr) external view returns (uint256) {
        return stakedIds[stakerAddr].length();
    }

    function stakeLists(address stakerAddr, uint256 stakeIndex) external view returns (StakeStore memory) {
        require(stakeIndex < stakedIds[stakerAddr].length(), "invalid stakeIndex");
        uint256 stakeId_ = stakedIds[stakerAddr].at(stakeIndex);
        return stakeInfo[stakeId_];
    }

    function dailyData(uint256) external view returns (uint72, uint72, uint56) {
        return _dailyData();
    }

    function _dailyData() internal view returns (uint72, uint72, uint56) {
        return (payout, shares, 0);
    }

    function dailyDataRange(uint256 beginDay, uint256 endDay) external view returns (uint256[] memory list) {
        require(beginDay < endDay && endDay <= currentDay(), "range invalid");

        list = new uint256[](endDay - beginDay);

        (uint72 totalPayout, uint72 totalShares, uint56 unclaimedSatoshis) = _dailyData();

        uint256 src = beginDay;
        uint256 dst = 0;
        uint256 v;
        do {
            v = uint256(unclaimedSatoshis) << (HEART_UINT_SIZE * 2);
            v |= uint256(totalShares) << HEART_UINT_SIZE;
            v |= uint256(totalPayout);

            list[dst++] = v;
        } while (++src < endDay);

        return list;
    }

    function globalInfo() external view returns (uint256[13] memory) {
        return [0, 0, 0, 0, currentDay(), 0, 0, 0, 0, 0, 0, 0, 0];
    }

    function _calcShareRate(uint256 stakedHearts) internal view returns (uint72) {
        return uint72((stakedHearts * 10e5) / globals.shareRate);
    }
}
