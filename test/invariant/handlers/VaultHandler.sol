// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/* solhint-disable custom-errors */
/* solhint-disable no-global-import */

import "../Base.sol";

import {hevm} from "../../../lib/properties/contracts/util/Hevm.sol";

import {IHexOneVault} from "../../../src/interfaces/IHexOneVault.sol";

contract VaultHandler is Base {
    // amounts
    uint256 internal constant HEX_AMOUNT = 1_000_000_000e8;
    uint256 internal constant DAI_AMOUNT = 1_000_000e18;
    uint256 internal constant WPLS_AMOUNT = 200_000_000_000e18;
    uint256 internal constant USDT_AMOUNT = 500_000e6;
    uint256 internal constant USDC_AMOUNT = 500_000e6;

    // helpers
    mapping(User => uint256[]) internal stakes;
    mapping(User => mapping(uint256 => bool)) internal status;
    uint256 internal ids;

    // ---------------------- Initial State --------------------------

    constructor() {
        for (uint256 i; i < NUMBER_OF_USERS; ++i) {
            // deal tokens to user
            HEX_TOKEN.mint(address(users[i]), HEX_AMOUNT);
            DAI_TOKEN.mint(address(users[i]), DAI_AMOUNT);
            WPLS_TOKEN.mint(address(users[i]), WPLS_AMOUNT);
            USDT_TOKEN.mint(address(users[i]), USDT_AMOUNT);
            USDC_TOKEN.mint(address(users[i]), USDC_AMOUNT);

            // user approves vault to spend tokens
            users[i].approve(address(HEX_TOKEN), address(VAULT));

            // user approves router to spend tokens
            users[i].approve(address(HEX_TOKEN), address(ROUTER));
            users[i].approve(address(WPLS_TOKEN), address(ROUTER));
            users[i].approve(address(DAI_TOKEN), address(ROUTER));
            users[i].approve(address(USDT_TOKEN), address(ROUTER));
            users[i].approve(address(USDC_TOKEN), address(ROUTER));
        }
    }

    // ---------------------- Utilities ------------------------------

    function setHexDaiPrice(uint256 _newPrice) public {
        _newPrice = clampBetween(_newPrice, HEX_DAI_INIT_PRICE / 5, HEX_DAI_INIT_PRICE * 5);
        FEED.setPrice(address(HEX_TOKEN), address(DAI_TOKEN), _newPrice);
    }

    function setHexUsdcPrice(uint256 _newPrice) public {
        _newPrice = clampBetween(_newPrice, HEX_USDC_INIT_PRICE / 5, HEX_USDC_INIT_PRICE * 5);
        FEED.setPrice(address(HEX_TOKEN), address(USDC_TOKEN), _newPrice);
    }

    function setHexUsdtPrice(uint256 _newPrice) public {
        _newPrice = clampBetween(_newPrice, HEX_USDT_INIT_PRICE / 5, HEX_USDT_INIT_PRICE * 5);
        FEED.setPrice(address(HEX_TOKEN), address(USDT_TOKEN), _newPrice);
    }

    // ---------------------- Handlers -------------------------------

    function enableBuyback() public {
        hevm.prank(address(BOOTSTRAP));
        VAULT.enableBuyback();
    }

    function deposit(uint256 _user, uint256 _amount) public {
        User user = users[_user % users.length];
        _amount = clampBetween(_amount, HEX_AMOUNT / 100, HEX_AMOUNT / 10);

        uint256 balanceBefore = HEX_TOKEN.balanceOf(address(user));

        (bool success, bytes memory data) =
            user.proxy(address(VAULT), abi.encodeWithSelector(HexOneVaultHarness.deposit.selector, _amount));
        require(success, "deposit failed");

        uint256 id = abi.decode(data, (uint256));
        stakes[user].push(id);
        status[user][id] = true;
        ids++;

        uint256 balanceAfter = HEX_TOKEN.balanceOf(address(user));

        assertEq(balanceAfter, balanceBefore - _amount, "deposit amount error");
    }

    function withdraw(uint256 _user, uint256 _id) public {
        User user = users[_user % users.length];

        _id = stakes[user][_id % stakes[user].length];
        require(status[user][_id], "id already burned");

        (,,,,, uint16 end) = VAULT.stakes(_id);
        require(VAULT.currentDay() >= end, "stake mature");

        uint256 hexBalanceBefore = HEX_TOKEN.balanceOf(address(user));
        uint256 hdrnBalanceBefore = HDRN_TOKEN.balanceOf(address(user));

        (bool success, bytes memory data) =
            user.proxy(address(VAULT), abi.encodeWithSelector(HexOneVaultHarness.withdraw.selector, _id));
        require(success, "withdraw failed");

        (uint256 hexAmountClaimed, uint256 hdrnAmountClaimed) = abi.decode(data, (uint256, uint256));

        status[user][_id] = false;

        uint256 hexBalanceAfter = HEX_TOKEN.balanceOf(address(user));
        uint256 hdrnBalanceAfter = HDRN_TOKEN.balanceOf(address(user));

        assertEq(hexBalanceAfter, hexBalanceBefore + hexAmountClaimed, "withdraw hex error");
        assertEq(hdrnBalanceAfter, hdrnBalanceBefore + hdrnAmountClaimed, "withdraw hdrn error");
    }

    function liquidate(uint256 _user, uint256 _id) public {
        User user = users[_user % users.length];

        _id = _id % ids;
        require(status[user][_id], "id already burned");

        uint256 hexBalanceBefore = IERC20(HEX_TOKEN).balanceOf(address(user));
        uint256 hdrnBalanceBefore = IERC20(HDRN_TOKEN).balanceOf(address(user));

        (bool success, bytes memory data) =
            user.proxy(address(VAULT), abi.encodeWithSelector(HexOneVaultHarness.liquidate.selector, _id));
        require(success, "liquidate failed");

        (uint256 hexAmountClaimed, uint256 hdrnAmountClaimed) = abi.decode(data, (uint256, uint256));

        status[user][_id] = false;

        uint256 hexBalanceAfter = IERC20(HEX_TOKEN).balanceOf(address(user));
        uint256 hdrnBalanceAfter = IERC20(HDRN_TOKEN).balanceOf(address(user));

        assertEq(hexBalanceAfter, hexBalanceBefore + hexAmountClaimed, "liquidate hex error");
        assertEq(hdrnBalanceAfter, hdrnBalanceBefore + hdrnAmountClaimed, "liquidate hdrn error");
    }

    function repay(uint256 _user, uint256 _id) public {
        User user = users[_user % users.length];

        _id = stakes[user][_id % stakes[user].length];
        require(status[user][_id], "id already burned");

        (uint256 debt,,,,,) = VAULT.stakes(_id);
        require(debt > 0, "no debt to repay");

        uint256 balanceBefore = HEX1.balanceOf(address(user));

        (bool success,) =
            user.proxy(address(VAULT), abi.encodeWithSelector(HexOneVaultHarness.repay.selector, _id, debt));
        require(success, "repay failed");

        uint256 balanceAfter = HEX1.balanceOf(address(user));

        assertEq(balanceAfter, balanceBefore - debt, "repay amount error");
    }

    function borrow(uint256 _user, uint256 _id) public {
        User user = users[_user % users.length];

        _id = stakes[user][_id % stakes[user].length];
        require(status[user][_id], "id already burned");

        uint256 maxBorrowable = VAULT.maxBorrowable(_id);
        require(maxBorrowable > 0, "zero amount can not be borrowed");

        uint256 balanceBefore = HEX1.balanceOf(address(user));

        (bool success,) =
            user.proxy(address(VAULT), abi.encodeWithSelector(HexOneVaultHarness.borrow.selector, _id, maxBorrowable));
        require(success, "borrow failed");

        uint256 balanceAfter = HEX1.balanceOf(address(user));

        assertEq(balanceAfter, balanceBefore + maxBorrowable, "borrow amount error");
    }

    function take(uint256 _user, uint256 _id, uint256 _amount) public {
        User user = users[_user % users.length];

        _id = _id % ids;
        require(status[user][_id], "id already burned");

        require(VAULT.healthRatio(_id) < VAULT.MIN_HEALTH_RATIO(), "stake is healthy");

        (uint256 debt,,,,,) = VAULT.stakes(_id);
        require(debt != 0);

        _amount = clampBetween(_amount, debt / 2, debt);

        uint256 balanceBefore = HEX1.balanceOf(address(user));

        (bool success,) =
            user.proxy(address(VAULT), abi.encodeWithSelector(HexOneVaultHarness.take.selector, _id, _amount));
        require(success, "take failed");

        uint256 balanceAfter = HEX1.balanceOf(address(user));

        assertEq(balanceAfter, balanceBefore - _amount, "take amount error");
    }

    // ---------------------- Invariants ----------------------—------

    /// @dev The sum off each HDT stake.debt must always be equal to HEX1 total supply.
    function invariant_1() public {
        uint256 debtSum;
        for (uint256 i; i < ids; ++i) {
            (uint256 debt,,,,,) = VAULT.stakes(i);
            debtSum += debt;
        }
        assertEq(debtSum, HEX1.totalSupply(), "invariant 1 broke");
    }

    /// @dev If an HDT has stake.debt == 0 it can not be took.
    function invariant_2(uint256 _user, uint256 _id, uint256 _amount) public {
        User user = users[_user % users.length];
        _id = _id % ids;
        require(status[user][_id], "id already burned");

        (uint256 debt,,,,,) = VAULT.stakes(_id);
        require(debt == 0, "debt is not zero");

        (bool success,) =
            user.proxy(address(VAULT), abi.encodeWithSelector(HexOneVaultHarness.take.selector, _id, _amount));
        assert(!success);
    }

    /// @dev HDT can only be took if at least 50% of the stake.debt is repaid and the healthRatio is less than MIN_HEALTH_RATIO.
    function invariant_3(uint256 _user, uint256 _id, uint256 _amount) public {
        User user = users[_user % users.length];

        _id = _id % ids;
        require(status[user][_id], "id already burned");

        require(VAULT.healthRatio(_id) < VAULT.MIN_HEALTH_RATIO(), "stake is healthy");

        (uint256 debt,,,,,) = VAULT.stakes(_id);
        require(debt != 0);

        _amount = clampBetween(_amount, debt / 2, debt);

        (bool success,) =
            user.proxy(address(VAULT), abi.encodeWithSelector(HexOneVaultHarness.take.selector, _id, _amount));
        assert(success);
    }

    /*

    /// @dev Users must only be able to mint more HEX1 with the same HEX collateral if the HEX price in USD increases.
    function invariant_4() public {}

    /// @dev The number of stake days accrued + stake days estimated must be equal to 5555.
    function invariant_5() public {}

    */

    /// @dev If buybackEnabled == true, the depositing fee must always equal 1%.
    function invariant_6(uint256 _user, uint256 _amount) public {
        User user = users[_user % users.length];
        _amount = clampBetween(_amount, 1, IERC20(HEX_TOKEN).balanceOf(address(user)));

        require(VAULT.buybackEnabled(), "buyback not enabled");

        (bool success, bytes memory data) =
            user.proxy(address(VAULT), abi.encodeWithSelector(HexOneVaultHarness.deposit.selector, _amount));
        require(success, "deposit failed");

        uint256 id = abi.decode(data, (uint256));

        (, uint72 realAmount,,,,) = VAULT.stakes(id);
        uint256 expectedAmount = _amount - (_amount * 100) / 10_000;

        ids++;
        stakes[user].push(id);
        status[user][id] = true;

        assert(realAmount == expectedAmount);
    }

    /// @dev Withdraw must never be possible if HDT has not reached stake.end.
    function invariant_7(uint256 _user, uint256 _id) public {
        User user = users[_user % users.length];

        _id = stakes[user][_id % stakes[user].length];
        require(status[user][_id], "id already burned");

        (,,,,, uint16 end) = VAULT.stakes(_id);
        require(VAULT.currentDay() < end, "stake not mature");

        (bool success,) = user.proxy(address(VAULT), abi.encodeWithSelector(HexOneVaultHarness.withdraw.selector, _id));
        assert(!success);

        status[user][_id] = false;
    }

    /// @dev Liquidation must never be possible if HDT has not reached stake.end + GRACE_PERIOD.
    function invariant_8(uint256 _user, uint256 _id) public {
        User user = users[_user % users.length];

        _id = _id % ids;
        require(status[user][_id], "id already burned");

        (,,,,, uint16 end) = VAULT.stakes(_id);
        require(VAULT.currentDay() < end + VAULT.GRACE_PERIOD(), "stake not liquidatable");

        (bool success,) = user.proxy(address(VAULT), abi.encodeWithSelector(HexOneVaultHarness.liquidate.selector, _id));
        assert(!success);

        status[user][_id] = false;
    }

    /// @dev Borrowing must never be possible if HDT has reached stake.end.
    function invariant_9(uint256 _user, uint256 _id) public {
        User user = users[_user % users.length];

        _id = stakes[user][_id % stakes[user].length];
        require(status[user][_id], "id already burned");

        (,,,,, uint16 end) = VAULT.stakes(_id);
        require(VAULT.currentDay() >= end, "stake mature");

        (bool success,) = user.proxy(
            address(VAULT), abi.encodeWithSelector(HexOneVaultHarness.borrow.selector, _id, VAULT.maxBorrowable(_id))
        );
        assert(!success);
    }

    /// @dev Borrowing must never be possible if amount exceeds maxBorrowable().
    function invariant_10(uint256 _user, uint256 _id, uint256 _amount) public {
        User user = users[_user % users.length];

        _id = stakes[user][_id % stakes[user].length];
        require(status[user][_id], "id already burned");

        require(_amount > VAULT.maxBorrowable(_id), "amount > max borrowable");

        (bool success,) =
            user.proxy(address(VAULT), abi.encodeWithSelector(HexOneVaultHarness.borrow.selector, _id, _amount));
        assert(!success);
    }

    /// @dev Borrowing must never be possible if the resulting healthRatio is less than MIN_HEALTH_RATIO.
    function invariant_11(uint256 _user, uint256 _id, uint256 _amount) public {
        User user = users[_user % users.length];

        _id = stakes[user][_id % stakes[user].length];
        require(status[user][_id], "id already burned");

        require(VAULT.healthRatio(_id) > VAULT.MIN_HEALTH_RATIO(), "health ratio < min health ratio");

        _amount = clampBetween(_amount, 1, VAULT.maxBorrowable(_id));

        (bool success, bytes memory data) =
            user.proxy(address(VAULT), abi.encodeWithSelector(HexOneVaultHarness.borrow.selector, _id, _amount));
        if (!success) {
            bytes4 err = abi.decode(data, (bytes4));
            assert(err == IHexOneVault.HealthRatioTooLow.selector);
        }
    }

    /// @dev Take must never be possible if HDT has not reached stake.end + GRACE_PERIOD.
    function invariant_12(uint256 _user, uint256 _id, uint256 _amount) public {
        User user = users[_user % users.length];

        _id = _id % ids;
        require(status[user][_id], "id already burned");

        (,,,,, uint16 end) = VAULT.stakes(_id);
        require(VAULT.currentDay() >= end + VAULT.GRACE_PERIOD(), "stake not liquidatable");

        (bool success,) =
            user.proxy(address(VAULT), abi.encodeWithSelector(HexOneVaultHarness.take.selector, _id, _amount));
        assert(!success);
    }
}
