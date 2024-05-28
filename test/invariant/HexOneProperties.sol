// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../invariant/Base.sol";

import {hevm} from "../../lib/properties/contracts/util/Hevm.sol";

contract HexOneProperties is Base {
    // amounts
    uint256 internal constant HEX_AMOUNT = 1_000_000_000e8;
    uint256 internal constant DAI_AMOUNT = 1_000_000e18;
    uint256 internal constant WPLS_AMOUNT = 200_000_000_000e18;
    uint256 internal constant PLSX_AMOUNT = 200_000_000_000e18;
    uint256 internal constant USDT_AMOUNT = 500_000e6;
    uint256 internal constant USDC_AMOUNT = 500_000e6;
    uint256 internal constant TOKEN_AMOUNT = 1_000_000e18;

    // helpers
    mapping(User => uint256[]) internal stakes;
    mapping(uint256 => bool) internal status;
    uint256 internal ids;

    uint256 internal constant INITIAL_MINT = 1_000_000e18;
    HexOnePool internal immutable POOL;
    mapping(address => uint256) internal rewardsOf;

    // ---------------------- Initial State --------------------------

    constructor() {
        POOL = HexOnePool(MANAGER.pools(1));

        for (uint256 i; i < NUMBER_OF_USERS; ++i) {
            User user = users[i];

            // deal tokens to users
            HEX_TOKEN.mint(address(users[i]), HEX_AMOUNT);
            DAI_TOKEN.mint(address(users[i]), DAI_AMOUNT);
            WPLS_TOKEN.mint(address(users[i]), WPLS_AMOUNT);
            PLSX_TOKEN.mint(address(users[i]), PLSX_AMOUNT);
            USDT_TOKEN.mint(address(users[i]), USDT_AMOUNT);
            USDC_TOKEN.mint(address(users[i]), USDC_AMOUNT);

            // approve BOOTSTRAP to spend tokens
            users[i].approve(address(HEX_TOKEN), address(BOOTSTRAP));
            users[i].approve(address(DAI_TOKEN), address(BOOTSTRAP));
            users[i].approve(address(WPLS_TOKEN), address(BOOTSTRAP));
            users[i].approve(address(PLSX_TOKEN), address(BOOTSTRAP));

            // pool approves
            hevm.prank(address(BOOTSTRAP));
            HEXIT.mintAdmin(address(user), INITIAL_MINT);
            user.approve(address(HEXIT), address(POOL));

            // user approves vault to spend tokens
            users[i].approve(address(HEX_TOKEN), address(VAULT));
            users[i].approve(address(HEX1), address(VAULT));

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

        (bool success,) = address(FEED).call(
            abi.encodeWithSelector(FEED.setPrice.selector, address(HEX_TOKEN), address(DAI_TOKEN), _newPrice)
        );
        require(success);
    }

    function setWplsDaiPrice(uint256 _newPrice) public {
        _newPrice = clampBetween(_newPrice, WPLS_DAI_INIT_PRICE / 5, WPLS_DAI_INIT_PRICE * 5);

        (bool success,) = address(FEED).call(
            abi.encodeWithSelector(FEED.setPrice.selector, address(WPLS_TOKEN), address(DAI_TOKEN), _newPrice)
        );
        require(success);
    }

    function setPlsxDaiPrice(uint256 _newPrice) public {
        _newPrice = clampBetween(_newPrice, PLSX_DAI_INIT_PRICE / 5, PLSX_DAI_INIT_PRICE * 5);

        (bool success,) = address(FEED).call(
            abi.encodeWithSelector(FEED.setPrice.selector, address(PLSX_TOKEN), address(DAI_TOKEN), _newPrice)
        );
        require(success);
    }

    // ---------------------- Handlers -------------------------------

    function sacrifice(uint256 randUser, uint256 randToken, uint256 randAmount) public {
        User user = users[randUser % users.length];

        address token = sacrificeTokens[randToken % sacrificeTokens.length];
        uint256 amount = clampBetween(randAmount, 1, (token == address(HEX_TOKEN) ? HEX_AMOUNT : TOKEN_AMOUNT) / 100);
        require(IERC20(token).balanceOf(address(user)) >= amount);

        (bool success,) =
            user.proxy(address(BOOTSTRAP), abi.encodeWithSelector(BOOTSTRAP.sacrifice.selector, token, amount, 1));
        require(success);
    }

    function processSacrifice() public {
        (bool successProcess,) = address(BOOTSTRAP).call(abi.encodeWithSelector(BOOTSTRAP.processSacrifice.selector, 1));
        require(successProcess);
    }

    function claimSacrifice(uint256 randUser) public {
        User user = users[randUser % users.length];

        (bool success,) = user.proxy(address(BOOTSTRAP), abi.encodeWithSelector(BOOTSTRAP.claimSacrifice.selector));
        require(success);
    }

    function startAirdrop() public {
        (bool success,) =
            address(BOOTSTRAP).call(abi.encodeWithSelector(BOOTSTRAP.startAirdrop.selector, uint64(block.timestamp)));
        require(success);
    }

    function claimAirdrop(uint256 randUser) public {
        User user = users[randUser % users.length];

        (bool success,) = user.proxy(address(BOOTSTRAP), abi.encodeWithSelector(BOOTSTRAP.claimAirdrop.selector));
        require(success);
    }

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
        status[id] = true;
        ids++;

        uint256 balanceAfter = HEX_TOKEN.balanceOf(address(user));

        assertEq(balanceAfter, balanceBefore - _amount, "deposit amount error");
    }

    function withdraw(uint256 _user, uint256 _id) public {
        User user = users[_user % users.length];

        _id = stakes[user][_id % stakes[user].length];
        require(status[_id], "id already burned");

        (,,,,, uint16 end) = VAULT.stakes(_id);
        require(VAULT.currentDay() >= end, "stake mature");

        uint256 hexBalanceBefore = HEX_TOKEN.balanceOf(address(user));
        uint256 hdrnBalanceBefore = HDRN_TOKEN.balanceOf(address(user));

        (bool success, bytes memory data) =
            user.proxy(address(VAULT), abi.encodeWithSelector(HexOneVaultHarness.withdraw.selector, _id));
        require(success, "withdraw failed");

        (uint256 hexAmountClaimed, uint256 hdrnAmountClaimed) = abi.decode(data, (uint256, uint256));

        status[_id] = false;

        uint256 hexBalanceAfter = HEX_TOKEN.balanceOf(address(user));
        uint256 hdrnBalanceAfter = HDRN_TOKEN.balanceOf(address(user));

        assertEq(hexBalanceAfter, hexBalanceBefore + hexAmountClaimed, "withdraw hex error");
        assertEq(hdrnBalanceAfter, hdrnBalanceBefore + hdrnAmountClaimed, "withdraw hdrn error");
    }

    function liquidate(uint256 _user, uint256 _id) public {
        User user = users[_user % users.length];

        _id = _id % ids;
        require(status[_id], "id already burned");

        uint256 hexBalanceBefore = IERC20(HEX_TOKEN).balanceOf(address(user));
        uint256 hdrnBalanceBefore = IERC20(HDRN_TOKEN).balanceOf(address(user));

        (bool success, bytes memory data) =
            user.proxy(address(VAULT), abi.encodeWithSelector(HexOneVaultHarness.liquidate.selector, _id));
        require(success, "liquidate failed");

        (uint256 hexAmountClaimed, uint256 hdrnAmountClaimed) = abi.decode(data, (uint256, uint256));

        status[_id] = false;

        uint256 hexBalanceAfter = IERC20(HEX_TOKEN).balanceOf(address(user));
        uint256 hdrnBalanceAfter = IERC20(HDRN_TOKEN).balanceOf(address(user));

        assertEq(hexBalanceAfter, hexBalanceBefore + hexAmountClaimed, "liquidate hex error");
        assertEq(hdrnBalanceAfter, hdrnBalanceBefore + hdrnAmountClaimed, "liquidate hdrn error");
    }

    function repay(uint256 _user, uint256 _id) public {
        User user = users[_user % users.length];

        _id = stakes[user][_id % stakes[user].length];
        require(status[_id], "id already burned");

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
        require(status[_id], "id already burned");

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
        require(status[_id], "id already burned");

        (uint256 debt,,,,,) = VAULT.stakes(_id);
        require(debt != 0);

        require(VAULT.healthRatio(_id) < VAULT.MIN_HEALTH_RATIO(), "stake is healthy");

        _amount = clampBetween(_amount, debt / 2, debt);

        uint256 balanceBefore = HEX1.balanceOf(address(user));

        (bool success,) =
            user.proxy(address(VAULT), abi.encodeWithSelector(HexOneVaultHarness.take.selector, _id, _amount));
        require(success, "take failed");

        uint256 balanceAfter = HEX1.balanceOf(address(user));

        assertEq(balanceAfter, balanceBefore - _amount, "take amount error");
    }

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

    // ---------------------- Invariants ----------------------—------

    // ---------------------- Bootstrap ----------------------—------

    /// @custom:invariant - If two users sacrifice the same amount in USD on different days, the one who sacrificed first should always receive more HEXIT
    function sacrificePriorityDifferentDays(
        uint256 randUser,
        uint256 randNewUser,
        uint256 randToken,
        uint256 randAmount,
        uint64 _seconds
    ) public {
        User user = users[randUser % users.length];
        User newUser = users[randNewUser % users.length];
        require(address(user) != address(newUser));

        (uint64 sacrificeStart,,) = BOOTSTRAP.sacrificeSchedule();
        require(block.timestamp < sacrificeStart + BOOTSTRAP.SACRIFICE_DURATION());

        (uint256 sacrificedUsdUser,,,) = BOOTSTRAP.userInfos(address(user));
        (uint256 sacrificedUsdNewUser,,,) = BOOTSTRAP.userInfos(address(newUser));
        require(sacrificedUsdUser == 0 && sacrificedUsdNewUser == 0);

        address token = sacrificeTokens[randToken % sacrificeTokens.length];
        uint256 amount = clampBetween(randAmount, 1, (token == address(HEX_TOKEN) ? HEX_AMOUNT : TOKEN_AMOUNT) / 100);
        require(IERC20(token).balanceOf(address(user)) >= amount && IERC20(token).balanceOf(address(newUser)) >= amount);

        bool success;
        bytes memory data;

        (success,) =
            user.proxy(address(BOOTSTRAP), abi.encodeWithSelector(BOOTSTRAP.sacrifice.selector, token, amount, 1));
        require(success);

        hevm.warp(
            block.timestamp
                + clampBetween(_seconds, 86400, sacrificeStart + BOOTSTRAP.SACRIFICE_DURATION() - block.timestamp - 1)
        );

        (success,) =
            newUser.proxy(address(BOOTSTRAP), abi.encodeWithSelector(BOOTSTRAP.sacrifice.selector, token, amount, 1));
        require(success);

        uint256 processWarpMin = sacrificeStart + BOOTSTRAP.SACRIFICE_DURATION() - block.timestamp;
        hevm.warp(
            block.timestamp
                + clampBetween(_seconds, processWarpMin, processWarpMin + BOOTSTRAP.SACRIFICE_CLAIM_DURATION() - 1)
        );

        (success,) = address(BOOTSTRAP).call(abi.encodeWithSelector(BOOTSTRAP.processSacrifice.selector, 1));
        require(success);

        (, uint64 claimEnd,) = BOOTSTRAP.sacrificeSchedule();
        hevm.warp(block.timestamp + clampBetween(_seconds, 0, claimEnd - block.timestamp - 1));

        (success, data) = user.proxy(address(BOOTSTRAP), abi.encodeWithSelector(BOOTSTRAP.claimSacrifice.selector));
        require(success);

        (,, uint256 hexitMintedUser) = abi.decode(data, (uint256, uint256, uint256));

        (success, data) = newUser.proxy(address(BOOTSTRAP), abi.encodeWithSelector(BOOTSTRAP.claimSacrifice.selector));
        require(success);

        (,, uint256 hexitMintedNewUser) = abi.decode(data, (uint256, uint256, uint256));

        emit LogUint256("Hexit minted user: ", hexitMintedUser);
        emit LogUint256("Hexit minted newUser: ", hexitMintedNewUser);

        assert(hexitMintedUser > hexitMintedNewUser);
    }

    /// @custom:invariant If two users sacrificed the same amount in USD and have no HEX staked, the one who claimed the airdrop first should always receive more HEXIT
    function airdropPriorityNoHexStaked(
        uint256 randUser,
        uint256 randNewUser,
        uint256 randToken,
        uint256 randAmount,
        uint64 _seconds
    ) public {
        User user = users[randUser % users.length];
        User newUser = users[randNewUser % users.length];
        require(address(user) != address(newUser));

        (uint64 sacrificeStart,,) = BOOTSTRAP.sacrificeSchedule();
        (,, bool airdropProcessed) = BOOTSTRAP.airdropSchedule();
        require(airdropProcessed == false && block.timestamp < sacrificeStart + BOOTSTRAP.SACRIFICE_DURATION());

        (uint256 sacrificedUsdUser,,,) = BOOTSTRAP.userInfos(address(user));
        (uint256 sacrificedUsdNewUser,,,) = BOOTSTRAP.userInfos(address(newUser));
        require(sacrificedUsdUser == 0 && sacrificedUsdNewUser == 0);

        uint256 oldUserBalance = HEXIT.balanceOf(address(user));
        uint256 oldNewUserBalance = HEXIT.balanceOf(address(newUser));

        address token = sacrificeTokens[randToken % sacrificeTokens.length];
        uint256 amount = clampBetween(randAmount, 1, (token == address(HEX_TOKEN) ? HEX_AMOUNT : TOKEN_AMOUNT) / 100);
        require(IERC20(token).balanceOf(address(user)) >= amount && IERC20(token).balanceOf(address(newUser)) >= amount);

        bool success;

        (success,) =
            user.proxy(address(BOOTSTRAP), abi.encodeWithSelector(BOOTSTRAP.sacrifice.selector, token, amount, 1));
        require(success);

        (success,) =
            newUser.proxy(address(BOOTSTRAP), abi.encodeWithSelector(BOOTSTRAP.sacrifice.selector, token, amount, 1));
        require(success);

        (success,) =
            address(BOOTSTRAP).call(abi.encodeWithSelector(BOOTSTRAP.startAirdrop.selector, uint64(block.timestamp)));
        require(success);

        (, uint64 airdropClaimEnd,) = BOOTSTRAP.airdropSchedule();

        (success,) = user.proxy(address(BOOTSTRAP), abi.encodeWithSelector(BOOTSTRAP.claimAirdrop.selector));
        require(success);

        hevm.warp(block.timestamp + clampBetween(_seconds, 86400, airdropClaimEnd - block.timestamp - 1));

        (success,) = newUser.proxy(address(BOOTSTRAP), abi.encodeWithSelector(BOOTSTRAP.claimAirdrop.selector));
        require(success);

        uint256 finalUserBalance = HEXIT.balanceOf(address(user)) - oldUserBalance;
        uint256 finalNewUserBalance = HEXIT.balanceOf(address(newUser)) - oldNewUserBalance;

        emit LogUint256("Final user balance: ", finalUserBalance);
        emit LogUint256("Final new user balance: ", finalNewUserBalance);

        assert(finalUserBalance > finalNewUserBalance);
    }

    /// @custom:invariant If two users have the same amount of HEX staked and did not participate in the sacrifice, the one who claimed the airdrop first should always receive more HEXIT
    function airdropPriorityHexStaked(
        uint256 randUser,
        uint256 randNewUser,
        uint256 randAmount,
        uint256 randDuration,
        uint64 _seconds
    ) public {
        User user = users[randUser % users.length];
        User newUser = users[randNewUser % users.length];
        require(address(user) != address(newUser));

        (,, bool airdropProcessed) = BOOTSTRAP.airdropSchedule();
        require(airdropProcessed == false);

        (uint256 sacrificedUsdUser,,,) = BOOTSTRAP.userInfos(address(user));
        (uint256 sacrificedUsdNewUser,,,) = BOOTSTRAP.userInfos(address(newUser));
        require(sacrificedUsdUser == 0 && sacrificedUsdNewUser == 0);

        uint256 amount = clampBetween(randAmount, 1, HEX_AMOUNT / 100);
        require(HEX_TOKEN.balanceOf(address(user)) >= amount && HEX_TOKEN.balanceOf(address(newUser)) >= amount);

        uint256 duration = clampBetween(randDuration, 1, 5555);

        uint256 oldUserBalance = HEXIT.balanceOf(address(user));
        uint256 oldNewUserBalance = HEXIT.balanceOf(address(newUser));

        bool success;

        (success,) = user.proxy(
            address(HEX_TOKEN),
            abi.encodeWithSelector(IHexToken(address(HEX_TOKEN)).stakeStart.selector, amount, duration)
        );
        require(success);

        (success,) = newUser.proxy(
            address(HEX_TOKEN),
            abi.encodeWithSelector(IHexToken(address(HEX_TOKEN)).stakeStart.selector, amount, duration)
        );
        require(success);

        (success,) =
            address(BOOTSTRAP).call(abi.encodeWithSelector(BOOTSTRAP.startAirdrop.selector, uint64(block.timestamp)));
        require(success);

        (success,) = user.proxy(address(BOOTSTRAP), abi.encodeWithSelector(BOOTSTRAP.claimAirdrop.selector));
        require(success);

        (, uint64 airdropClaimEnd,) = BOOTSTRAP.airdropSchedule();
        hevm.warp(block.timestamp + clampBetween(_seconds, 86400, airdropClaimEnd - block.timestamp - 1));

        (success,) = newUser.proxy(address(BOOTSTRAP), abi.encodeWithSelector(BOOTSTRAP.claimAirdrop.selector));
        require(success);

        uint256 finalUserBalance = HEXIT.balanceOf(address(user)) - oldUserBalance;
        uint256 finalNewUserBalance = HEXIT.balanceOf(address(newUser)) - oldNewUserBalance;

        emit LogUint256("Final user balance: ", finalUserBalance);
        emit LogUint256("Final new user balance: ", finalNewUserBalance);

        assert(finalUserBalance > finalNewUserBalance);
    }

    /// @custom:invariant Sacrifices can only be made within the predefined timeframe
    function sacrificeTimeframe(uint256 randUser, uint256 randToken, uint256 randAmount) public {
        (,, bool processed) = BOOTSTRAP.sacrificeSchedule();
        require(processed == true);

        User user = users[randUser % users.length];
        address token = sacrificeTokens[randToken % sacrificeTokens.length];
        uint256 amount = clampBetween(randAmount, 1, (token == address(HEX_TOKEN) ? HEX_AMOUNT : TOKEN_AMOUNT) / 100);
        require(IERC20(token).balanceOf(address(user)) >= amount);

        (bool success,) =
            user.proxy(address(BOOTSTRAP), abi.encodeWithSelector(BOOTSTRAP.sacrifice.selector, token, amount, 1));
        assert(success == false);
    }

    /// @custom:invariant Sacrifice processing is only available after the sacrifice deadline has passed
    function processSacrificeTimeframe() public {
        (uint64 start,, bool processed) = BOOTSTRAP.sacrificeSchedule();
        require(
            block.timestamp < start + BOOTSTRAP.SACRIFICE_DURATION() && block.timestamp >= start && processed == false
        );

        (bool success,) = address(BOOTSTRAP).call(abi.encodeWithSelector(BOOTSTRAP.processSacrifice.selector, 1));
        assert(success == false);
    }

    /// @custom:invariant The sacrifice can only be claimed within the claim period
    function claimSacrificeTimeframe(uint256 randUser) public {
        (, uint64 claimEnd, bool processed) = BOOTSTRAP.sacrificeSchedule();
        require(processed == true);

        User user = users[randUser % users.length];
        (uint256 sacrificedUsd,,, bool sacrificeClaimed) = BOOTSTRAP.userInfos(address(user));
        require(sacrificedUsd > 0 && sacrificeClaimed == false && block.timestamp >= claimEnd);

        (bool success,) = user.proxy(address(BOOTSTRAP), abi.encodeWithSelector(BOOTSTRAP.claimSacrifice.selector));
        assert(success == false);
    }

    /// @custom:invariant The airdrop can only be claimed within the predefined airdrop timeframe
    function claimAirdropTimeframe(uint256 randUser) public {
        (, uint64 claimEnd, bool processed) = BOOTSTRAP.airdropSchedule();
        require(processed == false && block.timestamp >= claimEnd);

        User user = users[randUser % users.length];
        (uint256 sacrificedUsd,,, bool airdropClaimed) = BOOTSTRAP.userInfos(address(user));
        require(sacrificedUsd > 0 && airdropClaimed == false);

        (bool success,) = user.proxy(address(BOOTSTRAP), abi.encodeWithSelector(BOOTSTRAP.claimAirdrop.selector));
        assert(success == false);
    }

    // ---------------------- Vault ----------------------—------

    /// @dev The sum off each HDT stake.debt must always be equal to HEX1 total supply.
    function invariant_1() public {
        uint256 debtSum;
        for (uint256 i; i < VAULT.id(); ++i) {
            (uint256 debt,,,,,) = VAULT.stakes(i);
            debtSum += debt;
        }
        assertEq(debtSum, HEX1.totalSupply(), "invariant 1 broke");
    }

    /// @dev If an HDT has stake.debt == 0 it can not be took.
    function invariant_2(uint256 _user, uint256 _id, uint256 _amount) public {
        User user = users[_user % users.length];
        _id = _id % ids;
        require(status[_id], "id already burned");

        (uint256 debt,,,,,) = VAULT.stakes(_id);
        require(debt == 0, "debt is not zero");

        (bool success,) =
            user.proxy(address(VAULT), abi.encodeWithSelector(HexOneVaultHarness.take.selector, _id, _amount));
        assert(!success);
    }

    /*

    @notice BREAKS

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

    */

    /// @dev Users must only be able to borrow more HEX1 with the same HEX collateral if the HEX price in USD increases.
    function invariant_4(uint256 _user, uint256 _amount) public {
        User user = users[_user % users.length];
        _amount = clampBetween(_amount, HEX_AMOUNT / 100, HEX_AMOUNT / 10);

        FEED.setPrice(address(HEX_TOKEN), address(DAI_TOKEN), HEX_DAI_INIT_PRICE);
        FEED.setPrice(address(HEX_TOKEN), address(USDC_TOKEN), HEX_USDC_INIT_PRICE);
        FEED.setPrice(address(HEX_TOKEN), address(USDT_TOKEN), HEX_USDT_INIT_PRICE);

        (bool success, bytes memory data) =
            user.proxy(address(VAULT), abi.encodeWithSelector(HexOneVaultHarness.deposit.selector, _amount));
        require(success, "deposit failed");

        uint256 id = abi.decode(data, (uint256));
        stakes[user].push(id);
        status[id] = true;
        ids++;

        uint256 maxBorrowableBefore = VAULT.maxBorrowable(id);

        FEED.setPrice(address(HEX_TOKEN), address(DAI_TOKEN), HEX_DAI_INIT_PRICE * 2);
        FEED.setPrice(address(HEX_TOKEN), address(USDC_TOKEN), HEX_USDC_INIT_PRICE * 2);
        FEED.setPrice(address(HEX_TOKEN), address(USDT_TOKEN), HEX_USDT_INIT_PRICE * 2);

        uint256 maxBorrowableAfter = VAULT.maxBorrowable(id);

        assert(maxBorrowableAfter > maxBorrowableBefore);
    }

    /// @dev The number of stake days accrued + stake days estimated must be equal to 5555.
    function invariant_5(uint256 _id) public {
        _id = _id % ids;
        require(status[_id], "id already burned");

        (,,,, uint16 start, uint16 end) = VAULT.stakes(_id);

        uint256 currentDay = VAULT.currentDay();
        uint256 totalDays;

        if (currentDay >= end) {
            totalDays = end - start;
        } else {
            totalDays += currentDay - start;
            totalDays += end - currentDay;
        }

        emit LogUint256("total days", totalDays);
        assert(totalDays == 5555);
    }

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
        status[id] = true;

        assert(realAmount == expectedAmount);
    }

    /// @dev Withdraw must never be possible if HDT has not reached stake.end.
    function invariant_7(uint256 _user, uint256 _id) public {
        User user = users[_user % users.length];

        _id = stakes[user][_id % stakes[user].length];
        require(status[_id], "id already burned");

        (,,,,, uint16 end) = VAULT.stakes(_id);
        require(VAULT.currentDay() < end, "stake not mature");

        (bool success,) = user.proxy(address(VAULT), abi.encodeWithSelector(HexOneVaultHarness.withdraw.selector, _id));
        assert(!success);

        status[_id] = false;
    }

    /// @dev Liquidation must never be possible if HDT has not reached stake.end + GRACE_PERIOD.
    function invariant_8(uint256 _user, uint256 _id) public {
        User user = users[_user % users.length];

        _id = _id % ids;
        require(status[_id], "id already burned");

        (,,,,, uint16 end) = VAULT.stakes(_id);
        require(VAULT.currentDay() < end + VAULT.GRACE_PERIOD(), "stake not liquidatable");

        (bool success,) = user.proxy(address(VAULT), abi.encodeWithSelector(HexOneVaultHarness.liquidate.selector, _id));
        assert(!success);

        status[_id] = false;
    }

    /// @dev Borrowing must never be possible if HDT has reached stake.end.
    function invariant_9(uint256 _user, uint256 _depositAmount, uint256 _borrowAmount, uint256 _skip) public {
        User user = users[_user % users.length];
        _depositAmount = clampBetween(_depositAmount, HEX_AMOUNT / 100, HEX_AMOUNT / 10);

        (bool success, bytes memory data) =
            user.proxy(address(VAULT), abi.encodeWithSelector(HexOneVaultHarness.deposit.selector, _depositAmount));
        require(success, "deposit failed");

        uint256 id = abi.decode(data, (uint256));

        ids++;
        stakes[user].push(id);
        status[id] = true;

        _skip = clampBetween(_skip, 5555 days, 7500 days);
        hevm.warp(block.timestamp + _skip);

        _borrowAmount = clampBetween(_borrowAmount, 1, VAULT.maxBorrowable(id));

        (success,) =
            user.proxy(address(VAULT), abi.encodeWithSelector(HexOneVaultHarness.borrow.selector, id, _borrowAmount));
        assert(!success);
    }

    /// @dev Borrowing must never be possible if amount exceeds maxBorrowable().
    function invariant_10(uint256 _user, uint256 _id, uint256 _amount) public {
        User user = users[_user % users.length];

        _id = stakes[user][_id % stakes[user].length];
        require(status[_id], "id already burned");

        require(_amount > VAULT.maxBorrowable(_id), "amount < max borrowable");

        (bool success,) =
            user.proxy(address(VAULT), abi.encodeWithSelector(HexOneVaultHarness.borrow.selector, _id, _amount));
        assert(!success);
    }

    /// @dev Borrowing must never be possible if the resulting healthRatio is less than MIN_HEALTH_RATIO.
    function invariant_11(uint256 _user, uint256 _id, uint256 _amount) public {
        User user = users[_user % users.length];

        _amount = clampBetween(_amount, HEX_AMOUNT / 100, HEX_AMOUNT / 10);

        (bool success, bytes memory data) =
            user.proxy(address(VAULT), abi.encodeWithSelector(HexOneVaultHarness.deposit.selector, _amount));
        require(success, "deposit failed");

        uint256 id = abi.decode(data, (uint256));

        ids++;
        stakes[user].push(id);
        status[id] = true;

        FEED.setPrice(address(HEX_TOKEN), address(DAI_TOKEN), HEX_DAI_INIT_PRICE / 2);
        FEED.setPrice(address(HEX_TOKEN), address(USDC_TOKEN), HEX_USDC_INIT_PRICE / 2);
        FEED.setPrice(address(HEX_TOKEN), address(USDT_TOKEN), HEX_USDT_INIT_PRICE / 2);

        require(VAULT.healthRatio(_id) > VAULT.MIN_HEALTH_RATIO());

        (success, data) = user.proxy(
            address(VAULT), abi.encodeWithSelector(HexOneVaultHarness.borrow.selector, _id, VAULT.maxBorrowable(_id))
        );
        assert(!success);

        FEED.setPrice(address(HEX_TOKEN), address(DAI_TOKEN), HEX_DAI_INIT_PRICE);
        FEED.setPrice(address(HEX_TOKEN), address(USDC_TOKEN), HEX_USDC_INIT_PRICE);
        FEED.setPrice(address(HEX_TOKEN), address(USDT_TOKEN), HEX_USDT_INIT_PRICE);
    }

    /// @dev Take must never be possible if HDT has reached stake.end + GRACE_PERIOD.
    function invariant_12(uint256 _user1, uint256 _user2, uint256 _depositAmount, uint256 _takeAmount, uint256 _skip)
        public
    {
        User user1 = users[_user1 % users.length];
        User user2 = users[_user2 % users.length];

        _depositAmount = clampBetween(_depositAmount, HEX_AMOUNT / 100, HEX_AMOUNT / 10);

        (bool success, bytes memory data) =
            user1.proxy(address(VAULT), abi.encodeWithSelector(HexOneVaultHarness.deposit.selector, _depositAmount));
        require(success, "deposit failed");

        uint256 id = abi.decode(data, (uint256));

        ids++;
        stakes[user1].push(id);
        status[id] = true;

        _skip = clampBetween(_skip, 5555 days + 7 days, 7500 days);
        hevm.warp(block.timestamp + _skip);

        (uint256 debt,,,,,) = VAULT.stakes(id);
        _takeAmount = clampBetween(_takeAmount, debt / 2, debt);

        (success,) =
            user2.proxy(address(VAULT), abi.encodeWithSelector(HexOneVaultHarness.take.selector, id, _takeAmount));
        assert(!success);
    }

    // ---------------------- Pool ----------------------—------

    /// @dev The total HEXIT rewards per second must always be equal to rewardPerToken * totalStaked.
    function invariant_1_pool(uint256 _skipDays) public {
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
    function invariant_2_pool() public {
        for (uint256 i; i < NUMBER_OF_USERS; ++i) {
            User user = users[i];
            uint256 hexitFromBootstrap = INITIAL_MINT - IERC20(POOL.token()).balanceOf(address(user));
            uint256 userBalance = IERC20(POOL.token()).balanceOf(address(user)) - hexitFromBootstrap;
            uint256 userRewards = rewardsOf[address(user)];

            assertLte(userBalance - userRewards, INITIAL_MINT, "invariant 2 broke");
        }
    }

    /// @dev The total rewards to be distributed to Alice with N deposits of X value must always be equal to Bob with p * N deposits of X / p.
    function invariant_3_pool(uint256 _user, uint256 _amount, uint256 _n, uint256 _p, uint256 _skipDays) public {
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
    function invariant_4_pool() public {
        uint256 stakeOfSum;

        for (uint256 i; i < NUMBER_OF_USERS; ++i) {
            stakeOfSum += POOL.stakeOf(address(users[i]));
        }

        assertEq(POOL.totalStaked(), stakeOfSum, "invariant 4");
    }
}
