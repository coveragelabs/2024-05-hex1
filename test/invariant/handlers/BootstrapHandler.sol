// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../Base.sol";

contract BootstrapHandler is Base {
    // whales
    address internal constant HEX_WHALE = 0x5280aa3cF5D6246B8a17dFA3D75Db26617B73937;
    address internal constant DAI_WHALE = 0xE56043671df55dE5CDf8459710433C10324DE0aE;
    address internal constant WPLS_WHALE = 0x930409e3c77ba9e6d2F6C95Ac16b64E273bc95C6;
    address internal constant PLSX_WHALE = 0x39cF6f8620CbfBc20e1cC1caba1959Bd2FDf0954;

    // amounts
    uint256 internal constant HEX_AMOUNT = 100_000_000e8;
    uint256 internal constant DAI_AMOUNT = 1_000_000e18;
    uint256 internal constant WPLS_AMOUNT = 10_000_000_000e18;
    uint256 internal constant PLSX_AMOUNT = 2_000_000_000e18;

    uint256 internal constant TOKEN_AMOUNT = 1_000_000e18;

    // users
    mapping(User => uint256[]) userToTokenIds;
    
    // setup users
    constructor() {
        for (uint256 i; i < NUMBER_OF_USERS; ++i) {
            // deal tokens to users
            hevm.prank(HEX_WHALE);
            IERC20(HEX_TOKEN).transfer(address(users[i]), HEX_AMOUNT);

            hevm.prank(DAI_WHALE);
            IERC20(DAI_TOKEN).transfer(address(users[i]), DAI_AMOUNT);

            hevm.prank(WPLS_WHALE);
            IERC20(WPLS_TOKEN).transfer(address(users[i]), WPLS_AMOUNT);

            hevm.prank(PLSX_WHALE);
            IERC20(PLSX_TOKEN).transfer(address(users[i]), PLSX_AMOUNT);

            // approve bootstrap to spend tokens
            users[i].approve(HEX_TOKEN, address(bootstrap));
            users[i].approve(DAI_TOKEN, address(bootstrap));
            users[i].approve(WPLS_TOKEN, address(bootstrap));
            users[i].approve(PLSX_TOKEN, address(bootstrap));
        }

        hevm.warp(block.timestamp + feed.period());

        feed.update();
    }

    // time warp
    function increaseTimestamp(uint256 _days) public {
        _days = clampBetween(_days, 1, vault.DURATION());
        hevm.warp(block.timestamp + _days * 1 days);
    }

    // admin functions
    function startAirdrop() public {
        bootstrap.startAirdrop(uint64(block.timestamp));
    }

    function processSacrifice() public {
        bootstrap.processSacrifice(1);
    }

    // user functions
    function sacrifice(uint256 randUser, uint256 randToken, uint256 randAmountIn) public {
        User user = users [randUser % users.length];

        address token = sacrificeTokens[randToken % sacrificeTokens.length];

        uint256 amountIn = clampBetween(randAmountIn, 1, (token == HEX_TOKEN ? HEX_AMOUNT : TOKEN_AMOUNT) / 100);

        (bool success,) = user.proxy(
            address(bootstrap),
            abi.encodeWithSelector(bootstrap.sacrifice.selector, token, amountIn, 1) // minOut = 1 because 0 reverts
        );
        require(success);

        string memory tokenName;
        if (address(token) == HEX_TOKEN) {
            tokenName = "Sacrifice token: HEX";
        } else if (address(token) == DAI_TOKEN) {
            tokenName = "Sacrifice token: DAI";
        } else if (address(token) == PLSX_TOKEN) {
            tokenName = "Sacrifice token: PLSX";
        } else {
            tokenName = "Sacrifice token: WPLS";
        }

        emit LogAddress("User", address(user));
        emit LogString(tokenName);
        emit LogUint256("Sacrifice amount", amountIn);
    }

    function claimSacrifice(uint256 randUser) public {
        User user = users[randUser % users.length];

        (bool success, bytes memory data) =
            user.proxy(address(bootstrap), abi.encodeWithSelector(bootstrap.claimSacrifice.selector));
        require(success);

        (uint256 tokenId,,) = abi.decode(data, (uint256, uint256, uint256));

        userToTokenIds[user].push(tokenId);

        emit LogAddress("User", address(user));
    }

    function claimAirdrop(uint256 randUser) public {
        User user = users[randUser % users.length];

        (bool success,) =
            user.proxy(address(bootstrap), abi.encodeWithSelector(bootstrap.claimAirdrop.selector));
        require(success);

        emit LogAddress("User", address(user));
    }

    /// CONTEXT INVARIANTS

    /// @custom:invariant - If two users sacrifice the same amount in USD on different days, the one who sacrificed first should always receive more HEXIT
    function sacrificePriorityDifferentDays(
        uint256 randUser,
        uint256 randNewUser,
        uint256 randToken,
        uint256 randAmount
    ) public {
        User user = users[randUser % users.length];
        User newUser = users[randNewUser % users.length];

        address token = sacrificeTokens[randToken % sacrificeTokens.length];
        uint256 amount = clampBetween(randAmount, 1, TOKEN_AMOUNT / 100);

        (bool success, bytes memory dataSacrifice) = user.proxy(
            address(bootstrap),
            abi.encodeWithSelector(bootstrap.sacrifice.selector, token, amount, 1) // minOut = 1 because 0 reverts
        );

        (uint256 tokenId,,) = abi.decode(dataSacrifice, (uint256, uint256, uint256));

        userToTokenIds[user].push(tokenId);

        hevm.warp(block.timestamp + 86401);

        (bool success1, bytes memory dataSacrifice1) = newUser.proxy(
            address(bootstrap),
            abi.encodeWithSelector(bootstrap.sacrifice.selector, token, amount, 1) // minOut = 1 because 0 reverts
        );

        (uint256 tokenId1,,) = abi.decode(dataSacrifice1, (uint256, uint256, uint256));

        userToTokenIds[newUser].push(tokenId1);

        hevm.prank(address(0x10000));
        bootstrap.processSacrifice(1);

        hevm.warp(block.timestamp + 86401);

        (bool successSacrifice, bytes memory data) =
            user.proxy(address(bootstrap), abi.encodeWithSelector(bootstrap.claimSacrifice.selector));

        (,, uint256 hexitMinted) = abi.decode(data, (uint256, uint256, uint256));

        (uint256 hexitShares,,,) = bootstrap.userInfos(address(user));

        assert(hexitMinted == hexitShares);

        (bool successSacrifice1, bytes memory data1) =
            newUser.proxy(address(bootstrap), abi.encodeWithSelector(bootstrap.claimSacrifice.selector));

        (,, uint256 hexitMinted1) = abi.decode(data1, (uint256, uint256, uint256));

        assert(hexitMinted > hexitMinted1);
    }

    /// @custom:invariant If two users sacrificed the same amount in USD and have no HEX staked, the one who claimed the airdrop first should always receive more HEXIT
    function airdropPriorityNoHexStaked(
        uint256 randUser,
        uint256 randNewUser,
        uint256 randToken,
        uint256 randAmount
    ) public {
        User user = users[randUser % users.length];
        User newUser = users[randNewUser % users.length];

        address token = sacrificeTokens[randToken % sacrificeTokens.length];
        uint256 amount = clampBetween(randAmount, 1, TOKEN_AMOUNT / 100);

        (bool success,) = user.proxy(
            address(bootstrap),
            abi.encodeWithSelector(bootstrap.sacrifice.selector, token, amount, 1) // minOut = 1 because 0 reverts
        );

        (bool success1,) = newUser.proxy(
            address(bootstrap),
            abi.encodeWithSelector(bootstrap.sacrifice.selector, token, amount, 1) // minOut = 1 because 0 reverts
        );

        hevm.prank(address(0x10000));
        bootstrap.processSacrifice(1);

        (bool successSacrifice,) =
            user.proxy(address(bootstrap), abi.encodeWithSelector(bootstrap.claimSacrifice.selector));

        (bool successSacrifice1,) =
            newUser.proxy(address(bootstrap), abi.encodeWithSelector(bootstrap.claimSacrifice.selector));

        uint256 oldUserBalance = hexit.balanceOf(address(user));
        uint256 oldNewUserBalance = hexit.balanceOf(address(newUser));

        hevm.warp(block.timestamp + 86401);

        hevm.prank(address(0x10000));
        bootstrap.startAirdrop(uint64(block.timestamp));

        (bool successAirdrop,) =
            user.proxy(address(bootstrap), abi.encodeWithSelector(bootstrap.claimAirdrop.selector));

        hevm.warp(block.timestamp + 86401);

        (bool successAirdrop1,) =
            newUser.proxy(address(bootstrap), abi.encodeWithSelector(bootstrap.claimAirdrop.selector));

        uint256 newUserBalance = hexit.balanceOf(address(newUser));
        uint256 newNewUserBalance = hexit.balanceOf(address(newUser));

        uint256 finalUserBalance = newUserBalance - oldUserBalance;
        uint256 finalNewUserBalance = newNewUserBalance - oldNewUserBalance;

        assert(finalUserBalance > finalNewUserBalance);
    }

    /// @custom:invariant If two users have the same amount of HEX staked and did not participate in the sacrifice, the one who claimed the airdrop first should always receive more HEXIT
    function airdropPriorityHexStaked(
        uint256 randUser,
        uint256 randNewUser
    ) public {
        User user = users[randUser % users.length];
        User newUser = users[randNewUser % users.length];

        HexOnePool hexOnePool = HexOnePool(poolTokens[1]);

        (bool success,) = user.proxy(
            address(hexOnePool),
            abi.encodeWithSelector(hexOnePool.stake.selector, TOKEN_AMOUNT)
        );

        (bool success1,) = newUser.proxy(
            address(hexOnePool),
            abi.encodeWithSelector(hexOnePool.stake.selector, TOKEN_AMOUNT)
        );

        hevm.prank(address(0x10000));
        bootstrap.startAirdrop(uint64(block.timestamp));

        (bool successAirdrop,) =
            user.proxy(address(bootstrap), abi.encodeWithSelector(bootstrap.claimAirdrop.selector));

        hevm.warp(block.timestamp + 86401);

        (bool successAirdrop1,) =
            newUser.proxy(address(bootstrap), abi.encodeWithSelector(bootstrap.claimAirdrop.selector));

        uint256 oldUserBalance = hexit.balanceOf(address(user));
        uint256 oldNewUserBalance = hexit.balanceOf(address(newUser));

        hevm.warp(block.timestamp + 86401);

        (bool successAirdrop2,) =
            user.proxy(address(bootstrap), abi.encodeWithSelector(bootstrap.claimAirdrop.selector));

        (bool successAirdrop3,) =
            newUser.proxy(address(bootstrap), abi.encodeWithSelector(bootstrap.claimAirdrop.selector));

        uint256 newUserBalance = hexit.balanceOf(address(newUser));
        uint256 newNewUserBalance = hexit.balanceOf(address(newUser));

        uint256 finalUserBalance = newUserBalance - oldUserBalance;
        uint256 finalNewUserBalance = newNewUserBalance - oldNewUserBalance;

        assert(finalUserBalance > finalNewUserBalance);
    }
    
    /// LOGIC INVARIANTS

    /// @custom:invariant Sacrifices can only be made within the predefined timeframe


}
