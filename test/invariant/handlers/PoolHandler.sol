// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../Base.sol";

contract PoolHandler is Base {
    uint256 internal constant INITIAL_MINT = 1_000_000e18;
    HexOnePool internal immutable pool;

    // ---------------------- Initial State --------------------------

    constructor() {
        pool = HexOnePool(manager.pools(1));

        for (uint256 i; i < NUMBER_OF_USERS; ++i) {
            User user = users[i];

            // Mint hexit for the user
            hevm.prank(address(bootstrap));
            hexit.mint(address(user), INITIAL_MINT);

            // Approve hexit and hex1Dai LP
            user.approve(address(hexit), address(pool));
        }
    }

    // ---------------------- Handlers -------------------------------

    function stake(uint256 _user, uint256 _amount) public {
        User user = users[_user % users.length];
        IERC20 poolToken = IERC20(pool.token());
        uint256 amount = clampBetween(_amount, 1, poolToken.balanceOf(address(user)));

        (bool success,) = user.proxy(address(pool), abi.encodeWithSelector(HexOnePool.stake.selector, amount));

        require(success, "stake failed");
    }

    function unstake(uint256 _user, uint256 _amount) public {
        User user = users[_user % users.length];
        uint256 stakedAmount = pool.stakeOf(address(user));
        require(stakedAmount != 0, "zero staked amount");

        uint256 amount = clampBetween(_amount, 1, stakedAmount);

        (bool success,) = user.proxy(address(pool), abi.encodeWithSelector(HexOnePool.unstake.selector, amount));

        require(success, "unstake failed");
    }

    function claim(uint256 _user) public {
        User user = users[_user % users.length];

        (bool success,) = user.proxy(address(pool), abi.encodeWithSelector(HexOnePool.claim.selector));

        require(success, "claim failed");
    }

    function exit(uint256 _user) public {
        User user = users[_user % users.length];
        require(pool.stakeOf(address(user)) != 0, "zero stake amount");

        (bool success,) = user.proxy(address(pool), abi.encodeWithSelector(HexOnePool.exit.selector));

        require(success, "exit failed");
    }

    // ---------------------- Invariants -----------------------------

    /// @dev The total HEXIT rewards per second must always be equal to rewardPerToken * totalStaked.
    function invariant_1() public {}

    /// @dev User can never unstake more than what he staked, excluding rewards.
    function invariant_2() public {}

    /// @dev The total rewards to be distributed to Alice with N deposits of X value must always be equal to Bob with p * N deposits of X / p.
    function invariant_3() public {}

    /// @dev The totalStaked amount must always equal the sum of each user's stakeOf amount.
    function invariant_4() public {}
}
