// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/* solhint-disable custom-errors */
/* solhint-disable no-global-import */

import "../Base.sol";

contract VaultHandler is Base {
    uint256 internal constant HEX_AMOUNT = 100_000_000e8;
    uint256 internal constant DAI_AMOUNT = 1_000_000e18;
    uint256 internal constant WPLS_AMOUNT = 10_000_000_000e18;

    address internal constant HEX_WHALE = 0x5280aa3cF5D6246B8a17dFA3D75Db26617B73937;
    address internal constant DAI_WHALE = 0xE56043671df55dE5CDf8459710433C10324DE0aE;
    address internal constant WPLS_WHALE = 0x930409e3c77ba9e6d2F6C95Ac16b64E273bc95C6;

    address[] internal stables;

    uint256 internal ids;
    mapping(User => uint256[]) internal userIds;

    // ---------------------- Initial State --------------------------

    constructor() {
        for (uint256 i; i < NUMBER_OF_USERS; ++i) {
            // deal tokens to users to users
            hevm.prank(HEX_WHALE);
            IERC20(HEX_TOKEN).transfer(address(users[i]), HEX_AMOUNT);

            hevm.prank(DAI_WHALE);
            IERC20(DAI_TOKEN).transfer(address(users[i]), DAI_AMOUNT);

            hevm.prank(WPLS_WHALE);
            IERC20(WPLS_TOKEN).transfer(address(users[i]), WPLS_AMOUNT);

            // approve vault to spend tokens
            users[i].approve(HEX_TOKEN, address(vault));
            users[i].approve(DAI_TOKEN, address(vault));
            users[i].approve(WPLS_TOKEN, address(vault));
        }

        hevm.warp(block.timestamp + feed.period());

        feed.update();
    }

    // ---------------------- Utilities -----------------------------

    function increaseTimestamp(uint256 _days) public {
        _days = clampBetween(_days, 1, vault.DURATION());
        hevm.warp(block.timestamp + _days * 1 days);
    }

    function updateFeed() public {
        feed.update();
    }

    function increaseHexWplsPrice(uint256 _user) public {
        // TODO
        // aim for a price impact of 1% upwards
    }

    function decreaseHexWplsPrice(uint256 _user) public {
        // TODO
        // aim for a price impact of 1% downwards
    }

    function increaseWplsStables(uint256 _user) public {
        // TODO
        // aim for a price impact of 1% upwards
        // fuzz the token out used as token out.
    }

    function decreaseWplsStables(uint256 _user) public {
        // TODO
        // aim for a price impact of 1% downwards
        // fuzz the token out used as token out.
    }

    // ---------------------- Handlers ------------------------------

    function enableBuyback() public {
        hevm.prank(address(bootstrap));
        vault.enableBuyback();
    }

    function deposit(uint256 _user, uint256 _amount) public {
        User user = users[_user % users.length];
        _amount = clampBetween(_amount, 1, HEX_AMOUNT / 100);

        (bool success, bytes memory data) =
            user.proxy(address(vault), abi.encodeWithSelector(HexOneVault.deposit.selector, _amount));
        require(success, "deposit failed");

        uint256 id = abi.decode(data, (uint256));

        userIds[user].push(id);
        ids++;
    }

    function withdraw(uint256 _user, uint256 _id) public {
        User user = users[_user % users.length];
        _id = userIds[user][_id % userIds[user].length];

        (bool success,) = user.proxy(address(vault), abi.encodeWithSelector(HexOneVault.withdraw.selector, _id));
        require(success, "withdraw failed");
    }

    function liquidate(uint256 _user, uint256 _id) public {
        User user = users[_user % users.length];
        _id = _id % ids;

        (bool success,) = user.proxy(address(vault), abi.encodeWithSelector(HexOneVault.liquidate.selector, _id));
        require(success, "liquidate failed");
    }

    function repay(uint256 _user, uint256 _id, uint256 _amount) public {
        User user = users[_user % users.length];
        _id = userIds[user][_id % userIds[user].length];

        (uint256 debt,,,,,) = vault.stakes(_id);
        _amount = clampBetween(_amount, 1, debt);

        (bool success,) = user.proxy(address(vault), abi.encodeWithSelector(HexOneVault.repay.selector, _id, _amount));
        require(success, "repay failed");
    }

    function borrow(uint256 _user, uint256 _id, uint256 _amount) public {
        User user = users[_user % users.length];
        _id = userIds[user][_id % userIds[user].length];
        _amount = clampBetween(_amount, 1, vault.maxBorrowable(_id));

        (bool success,) = user.proxy(address(vault), abi.encodeWithSelector(HexOneVault.borrow.selector, _id, _amount));
        require(success, "borrow failed");
    }

    function take(uint256 _user, uint256 _id, uint256 _amount) public {
        User user = users[_user % users.length];
        _id = _id % ids;

        (uint256 debt,,,,,) = vault.stakes(_id);
        _amount = clampBetween(_amount, 1, debt);

        (bool success,) = user.proxy(address(vault), abi.encodeWithSelector(HexOneVault.take.selector, _id, _amount));
        require(success, "take failed");
    }

    // ---------------------- Invariants ----------------------—

    /// @dev The sum off each HDT stake.debt must always be equal to HEX1 total supply.
    function invariant_1() public {
        uint256 debtSum;
        for (uint256 i; i < ids; ++i) {
            (uint256 debt,,,,,) = vault.stakes(i);
            debtSum += debt;
        }

        assertEq(debtSum, hex1.totalSupply(), "invariant 1 broke");
    }

    /// @dev If an HDT has stake.debt == 0 it can not be took.
    function invariant_2(uint256 _user, uint256 _id, uint256 _amount) public {
        User user = users[_user % users.length];
        _id = _id % ids;

        (uint256 debt,,,,,) = vault.stakes(_id);
        require(debt == 0, "debt is not zero");

        (bool success,) = user.proxy(address(vault), abi.encodeWithSelector(HexOneVault.take.selector, _id, _amount));
        assert(!success);
    }

    /// @dev HDT can only be took if at least 50% of the stake.debt is repaid and the healthRatio is less than MIN_HEALTH_RATIO.
    function invariant_3() public {}

    /// @dev Users must only be able to mint more HEX1 with the same HEX collateral if the HEX price in USD decreases.
    function invariant_4() public {}

    /// @dev The number of stake days accrued + stake days estimated must be equal to 5555.
    function invariant_5() public {}

    /// @dev If buybackEnabled == true, the depositing fee must always equal 1%.
    function invariant_6(uint256 _user, uint256 _amount) public {
        User user = users[_user % users.length];
        _amount = clampBetween(_amount, 1, HEX_AMOUNT / 100);

        require(vault.buybackEnabled(), "buyback not enabled");

        (bool success, bytes memory data) =
            user.proxy(address(vault), abi.encodeWithSelector(HexOneVault.deposit.selector, _amount));
        require(success, "deposit failed");

        uint256 id = abi.decode(data, (uint256));

        (, uint72 realAmount,,,,) = vault.stakes(id);
        uint256 expectedAmount = _amount - (_amount * 100) / 10_000;

        userIds[user].push(id);
        ids++;

        assertEq(realAmount, expectedAmount, "invariant 6 broke");
    }

    /// @dev Withdraw must never be possible if HDT has not reached stake.end.
    function invariant_7(uint256 _user, uint256 _id) public {
        User user = users[_user % users.length];
        _id = userIds[user][_id % userIds[user].length];

        (,,,,, uint16 end) = vault.stakes(_id);
        require(vault.currentDay() < end, "stake not mature");

        (bool success,) = user.proxy(address(vault), abi.encodeWithSelector(HexOneVault.withdraw.selector, _id));
        assert(!success);
    }

    /// @dev Liquidation must never be possible if HDT has not reached stake.end + GRACE_PERIOD.
    function invariant_8(uint256 _user, uint256 _id) public {
        User user = users[_user % users.length];
        _id = _id % ids;

        (,,,,, uint16 end) = vault.stakes(_id);
        require(vault.currentDay() < end + vault.GRACE_PERIOD(), "stake not liquidatable");

        (bool success,) = user.proxy(address(vault), abi.encodeWithSelector(HexOneVault.liquidate.selector, _id));
        assert(!success);
    }

    /// @dev Borrowing must never be possible if HDT has reached stake.end.
    function invariant_9(uint256 _user, uint256 _id) public {
        User user = users[_user % users.length];
        _id = userIds[user][_id % userIds[user].length];

        (,,,,, uint16 end) = vault.stakes(_id);
        require(vault.currentDay() >= end, "stake mature");

        (bool success,) = user.proxy(
            address(vault), abi.encodeWithSelector(HexOneVault.borrow.selector, _id, vault.maxBorrowable(_id))
        );
        assert(!success);
    }

    /// @dev Borrowing must never be possible if amount exceeds maxBorrowable().
    function invariant_10() public {}

    /// @dev Borrowing must never be possible if the resulting healthRatio is less than MIN_HEALTH_RATIO.
    function invariant_11() public {}

    /// @dev Take must never be possible if HDT has not reached stake.end + GRACE_PERIOD.
    function invariant_12(uint256 _user, uint256 _id, uint256 _amount) public {
        User user = users[_user % users.length];
        _id = _id % ids;

        (,,,,, uint16 end) = vault.stakes(_id);
        require(vault.currentDay() >= end + vault.GRACE_PERIOD(), "stake not liquidatable");

        (bool success,) = user.proxy(address(vault), abi.encodeWithSelector(HexOneVault.take.selector, _id, _amount));
        assert(!success);
    }
}
