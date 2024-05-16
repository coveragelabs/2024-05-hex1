// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/* solhint-disable custom-errors */
/* solhint-disable no-global-import */

import "../Base.sol";

contract VaultHandler is Base {
    uint256 internal constant HEX_AMOUNT = 100_000_000e8;
    address internal constant HEX_WHALE = 0x5280aa3cF5D6246B8a17dFA3D75Db26617B73937;

    uint256 internal ids;
    mapping(User => uint256[]) internal userIds;

    // ---------------------- Initial State --------------------------

    constructor() {
        for (uint256 i; i < NUMBER_OF_USERS; ++i) {
            // deal hex to users
            hevm.prank(HEX_WHALE);
            IERC20(HEX_TOKEN).transfer(address(users[i]), HEX_AMOUNT);

            // approve vault to spend users hex
            users[i].approve(HEX_TOKEN, address(vault));
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

    function increaseHexPrice() public {
        // TODO
        // aim for a price impact of 10% upwards
    }

    function decreaseHexPrice() public {
        // TODO
        // aim for a price impact of 10% downwards
    }

    // ---------------------- Handlers ------------------------------

    function enableBuyback() public {
        hevm.prank(address(bootstrap));
        vault.enableBuyback();
    }

    function deposit(uint256 _user, uint256 _amount) public {
        User user = users[_user % users.length];
        _amount = clampBetween(_amount, 1, HEX_AMOUNT);

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

    /// @dev the sum off each HDT stake.debt must always be equal to HEX1 total supply.
    function invariant_1() public view {
        uint256 debtSum;
        for (uint256 i; i < ids; ++i) {
            (uint256 debt,,,,,) = vault.stakes(i);
            debtSum += debt;
        }

        assert(debtSum == hex1.totalSupply());
    }

    /// @dev if an HDT stake.debt == 0 it can not be took.
    function invariant_2(uint256 _user, uint256 _id, uint256 _amount) public {
        User user = users[_user % users.length];
        _id = _id % ids;

        (uint256 debt,,,,,) = vault.stakes(_id);
        if (debt == 0) {
            (bool success,) =
                user.proxy(address(vault), abi.encodeWithSelector(HexOneVault.take.selector, _id, _amount));
            assert(!success);
        }
    }

    /// @dev when an HDT is liquidated it must always be burned.
    function invariant_3(uint256 _user, uint256 _id) public {
        User user = users[_user % users.length];
        _id = _id % ids;

        uint256 hdtBalanceBefore = vault.balanceOf(address(user));

        (bool success,) = user.proxy(address(vault), abi.encodeWithSelector(HexOneVault.liquidate.selector, _id));
        require(success, "liquidate failed");

        uint256 hdtBalanceAfter = vault.balanceOf(address(user));

        assert(hdtBalanceBefore - hdtBalanceAfter == 1);
    }

    /// @dev when an HDT is withdrawn it must always be burned.
    function invariant_4(uint256 _user, uint256 _id) public {
        User user = users[_user % users.length];
        _id = userIds[user][_id % userIds[user].length];

        uint256 hdtBalanceBefore = vault.balanceOf(address(user));

        (bool success,) = user.proxy(address(vault), abi.encodeWithSelector(HexOneVault.withdraw.selector, _id));
        require(success, "withdraw failed");

        uint256 hdtBalanceAfter = vault.balanceOf(address(user));

        assert(hdtBalanceBefore - hdtBalanceAfter == 1);
    }

    /// @dev HDT can only be took if at least 50% of the stake.debt is repaid and the resulting health ratio >= 250%.
    function invariant_5() public {}

    /// @dev users must only be able to mint more HEX1 with the same HEX collateral if the HEX price in USD decreases.
    function invariant_6() public {}

    /// @dev the number of stake days accrued + stake days estimated must be equal to 5555.
    function invariant_7() public {}
}
