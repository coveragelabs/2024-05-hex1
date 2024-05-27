// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../Base.sol";

contract PoolHandler is Base {
    uint256 internal constant INITIAL_MINT = 1_000_000e18;
    HexOnePool internal immutable POOL;
    mapping(address => uint256) internal rewardsOf;

    // ---------------------- Initial State --------------------------

    constructor() {
        POOL = HexOnePool(MANAGER.pools(1));

        for (uint256 i; i < NUMBER_OF_USERS; ++i) {
            User user = users[i];

            hevm.prank(address(BOOTSTRAP));
            HEXIT.mintAdmin(address(user), INITIAL_MINT);

            user.approve(address(HEXIT), address(POOL));
        }
    }

    // ---------------------- Handlers -------------------------------

    function stake(uint256 _user, uint256 _amount) public {
        User user = users[_user % users.length];
        IERC20 poolToken = IERC20(POOL.token());
        uint256 amount = clampBetween(_amount, 1, poolToken.balanceOf(address(user)));

        _stake(user, amount);
    }

    function _stake(User _user, uint256 _amount) internal {
        (bool success,) = _user.proxy(address(POOL), abi.encodeWithSelector(HexOnePool.stake.selector, _amount));
        require(success, "stake failed");
    }

    function unstake(uint256 _user, uint256 _amount) public {
        User user = users[_user % users.length];
        uint256 stakedAmount = POOL.stakeOf(address(user));
        require(stakedAmount != 0, "zero staked amount");

        uint256 amount = clampBetween(_amount, 1, stakedAmount);

        (bool success,) = user.proxy(address(POOL), abi.encodeWithSelector(HexOnePool.unstake.selector, amount));

        require(success, "unstake failed");
    }

    function claim(uint256 _user) public {
        User user = users[_user % users.length];
        _claim(user);
    }

    function _claim(User _user) internal {
        (bool success, bytes memory data) =
            _user.proxy(address(POOL), abi.encodeWithSelector(HexOnePool.claim.selector));
        require(success, "claim failed");

        uint256 rewards = abi.decode(data, (uint256));
        rewardsOf[address(_user)] += rewards;
    }

    function exit(uint256 _user) public {
        User user = users[_user % users.length];
        _exit(user);
    }

    function _exit(User _user) internal {
        require(POOL.stakeOf(address(_user)) != 0, "zero stake amount");

        (bool success, bytes memory data) = _user.proxy(address(POOL), abi.encodeWithSelector(HexOnePool.exit.selector));
        require(success, "exit failed");

        uint256 rewards = abi.decode(data, (uint256));
        rewardsOf[address(_user)] += rewards;
    }

    // ---------------------- Invariants -----------------------------

    /// @dev The total HEXIT rewards per second must always be equal to rewardPerToken * totalStaked.
    function invariant_1(uint256 _skipDays) public {
        for (uint256 i; i < NUMBER_OF_USERS; ++i) {
            _claim(users[i]);
        }

        uint256 skipDays = clampBetween(_skipDays, 1 days, 365 days);
        uint256 lastTimestamp = block.timestamp;
        hevm.warp(lastTimestamp + skipDays);

        uint256 totalHexitRewards;
        for (uint256 i; i < NUMBER_OF_USERS; ++i) {
            totalHexitRewards += POOL.calculateRewardsEarned(address(users[i]));
        }

        uint256 expectedHexitRewards =
            (POOL.totalStaked() * (block.timestamp - lastTimestamp) * POOL.rewardPerToken()) / POOL.MULTIPLIER();

        assertEq(totalHexitRewards, expectedHexitRewards, "invariant 1 broke");
    }

    /// @dev User can never unstake more than what he staked, excluding rewards.
    function invariant_2() public {
        for (uint256 i; i < NUMBER_OF_USERS; ++i) {
            User user = users[i];
            uint256 userBalance = IERC20(POOL.token()).balanceOf(address(user));
            uint256 userRewards = rewardsOf[address(user)];

            assertLte(userBalance - userRewards, INITIAL_MINT, "invariant 2 broke");
        }
    }

    /// @dev The total rewards to be distributed to Alice with N deposits of X value must always be equal to Bob with p * N deposits of X / p.
    function invariant_3(uint256 _user, uint256 _amount, uint256 _n, uint256 _p, uint256 _skipDays) public {
        User alice = users[_user % users.length];
        User bob = users[(_user + 1) % users.length];
        uint256 aliceBalance = IERC20(POOL.token()).balanceOf(address(alice));
        uint256 bobBalance = IERC20(POOL.token()).balanceOf(address(bob));
        uint256 lowestBalance = aliceBalance < bobBalance ? aliceBalance : bobBalance;
        require(lowestBalance > 100, "no balance");

        uint256 n = clampBetween(_n, 1, 10);
        uint256 p = clampBetween(_p, 1, 10);
        uint256 amount = clampBetween(_amount, 1, lowestBalance / (n * p));

        _exit(alice);
        _exit(bob);

        for (uint256 i; i < n; ++i) {
            _stake(alice, amount * p);
        }

        for (uint256 i; i < n * p; ++i) {
            _stake(bob, amount);
        }

        uint256 skipDays = clampBetween(_skipDays, 1 days, 365 days);
        hevm.warp(block.timestamp + skipDays);

        uint256 aliceRewards = POOL.calculateRewardsEarned(address(alice));
        uint256 bobRewards = POOL.calculateRewardsEarned(address(bob));
        assertEq(aliceRewards, bobRewards, "invariant 3 broke");
    }

    /// @dev The totalStaked amount must always equal the sum of each user's stakeOf amount.
    function invariant_4() public {
        uint256 stakeOfSum;

        for (uint256 i; i < NUMBER_OF_USERS; ++i) {
            stakeOfSum += POOL.stakeOf(address(users[i]));
        }

        assertEq(POOL.totalStaked(), stakeOfSum, "invariant 4");
    }
}
