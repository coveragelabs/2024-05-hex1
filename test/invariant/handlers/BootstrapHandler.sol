// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../Base.sol";

import {hevm} from "../../../lib/properties/contracts/util/Hevm.sol";

contract BootstrapHandler is Base {
    // amounts
    uint256 internal constant HEX_AMOUNT = 100_000_000e8;
    uint256 internal constant DAI_AMOUNT = 1_000_000e18;
    uint256 internal constant WPLS_AMOUNT = 10_000_000_000e18;
    uint256 internal constant PLSX_AMOUNT = 2_000_000_000e18;
    uint256 internal constant TOKEN_AMOUNT = 1_000_000e18;
    
    // setup users
    constructor() {
        for (uint256 i; i < NUMBER_OF_USERS; ++i) {
            // deal tokens to users
            HEX_TOKEN.mint(address(users[i]), HEX_AMOUNT);
            DAI_TOKEN.mint(address(users[i]), DAI_AMOUNT);
            WPLS_TOKEN.mint(address(users[i]), WPLS_AMOUNT);
            PLSX_TOKEN.mint(address(users[i]), PLSX_AMOUNT);

            // approve BOOTSTRAP to spend tokens
            users[i].approve(address(HEX_TOKEN), address(BOOTSTRAP));
            users[i].approve(address(DAI_TOKEN), address(BOOTSTRAP));
            users[i].approve(address(WPLS_TOKEN), address(BOOTSTRAP));
            users[i].approve(address(PLSX_TOKEN), address(BOOTSTRAP));
        }
    }

    //utilities
    function setHexDaiPrice(uint256 _newPrice) public {
        _newPrice = clampBetween(_newPrice, HEX_DAI_INIT_PRICE / 5, HEX_DAI_INIT_PRICE * 5);
        FEED.setPrice(address(address(HEX_TOKEN)), address(DAI_TOKEN), _newPrice);
    }

    function setWplsDaiPrice(uint256 _newPrice) public {
        _newPrice = clampBetween(_newPrice, WPLS_DAI_INIT_PRICE / 5, WPLS_DAI_INIT_PRICE * 5);
        FEED.setPrice(address(WPLS_TOKEN), address(DAI_TOKEN), _newPrice);
    }

    function setPlsxDaiPrice(uint256 _newPrice) public {
        _newPrice = clampBetween(_newPrice, PLSX_DAI_INIT_PRICE / 5, PLSX_DAI_INIT_PRICE * 5);
        FEED.setPrice(address(PLSX_TOKEN), address(DAI_TOKEN), _newPrice);
    }

    // user functions
    function sacrifice(uint256 randUser, uint256 randToken, uint256 randAmountIn) public {
        User user = users [randUser % users.length];

        address token = sacrificeTokens[randToken % sacrificeTokens.length];
        uint256 amountIn = clampBetween(randAmountIn, 1, (token == address(HEX_TOKEN) ? HEX_AMOUNT : TOKEN_AMOUNT) / 100);

        (bool success,) = user.proxy(
            address(BOOTSTRAP),
            abi.encodeWithSelector(BOOTSTRAP.sacrifice.selector, token, amountIn, 1) // minOut = 1 because 0 reverts
        );
        require(success);

        string memory tokenName;
        if (address(token) == address(HEX_TOKEN)) {
            tokenName = "Sacrifice token: HEX";
        } else if (address(token) == address(DAI_TOKEN)) {
            tokenName = "Sacrifice token: DAI";
        } else if (address(token) == address(PLSX_TOKEN)) {
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
            user.proxy(address(BOOTSTRAP), abi.encodeWithSelector(BOOTSTRAP.claimSacrifice.selector));
        require(success);

        emit LogAddress("User", address(user));
    }

    function claimAirdrop(uint256 randUser) public {
        User user = users[randUser % users.length];

        (bool success,) =
            user.proxy(address(BOOTSTRAP), abi.encodeWithSelector(BOOTSTRAP.claimAirdrop.selector));
        require(success);

        emit LogAddress("User", address(user));
    }

    function startAirdrop() public {
        (bool successAirdrop,) = 
            address(BOOTSTRAP).call(abi.encodeWithSelector(BOOTSTRAP.startAirdrop.selector, uint64(block.timestamp)));
            
        require(successAirdrop);

    }

    function processSacrifice() public {
        (,uint256 sacrificedAmount,,) = BOOTSTRAP.sacrificeInfo();
        uint256 minAmountOut = (sacrificedAmount * 1250) / 10000;
        
        (bool successProcess,) = 
            address(BOOTSTRAP).call(abi.encodeWithSelector(BOOTSTRAP.processSacrifice.selector, minAmountOut));
        require(successProcess);
    }

     // user calls
    function randAddLiquidity(uint256 randUser, uint256 randAmount, uint256 randToken) public {
        User user = users[randUser % users.length];

        address tokenIn = sacrificeTokens[randToken % sacrificeTokens.length];

        uint256 amountIn = clampBetween(randAmount, 1, (tokenIn == address(HEX_TOKEN) ? HEX_AMOUNT : TOKEN_AMOUNT) / 100);
        uint256 amountOut = FEED.quote(tokenIn, amountIn, address(DAI_TOKEN));

        (bool success, bytes memory data) = user.proxy(
            address(ROUTER),
            abi.encodeWithSelector(
                ROUTER.addLiquidity.selector,
                tokenIn,
                address(DAI_TOKEN),
                amountIn,
                amountOut,
                0,
                0,
                address(0),
                0
            )
        );
        require(success);

        (,, uint256 lpAmount) = abi.decode(data, (uint256, uint256, uint256));

        emit LogAddress("User", address(user));
        emit LogUint256("tokenIn amount", amountIn);
        emit LogUint256("DAI amount", amountOut);
        emit LogUint256("LP amount", lpAmount);
    }

    /// CONTEXT INVARIANTS

    /// @custom:invariant - If two users sacrifice the same amount in USD on different days, the one who sacrificed first should always receive more HEXIT
    function sacrificePriorityDifferentDays(
        uint256 randUser,
        uint256 randNewUser,
        uint256 randToken,
        uint256 randAmount,
        uint8 _day
    ) public {
        User user = users[randUser % users.length];
        User newUser = users[randNewUser % users.length];
        require(address(user) != address(newUser));

        address token = sacrificeTokens[randToken % sacrificeTokens.length];
        uint256 amount = clampBetween(randAmount, 1, (token == address(HEX_TOKEN) ? HEX_AMOUNT : TOKEN_AMOUNT) / 100);

        (bool success,) = user.proxy(
            address(BOOTSTRAP),
            abi.encodeWithSelector(BOOTSTRAP.sacrifice.selector, token, amount, 1) // minOut = 1 because 0 reverts
        );
        require(success);

        hevm.warp(block.timestamp + 1 days);

        (bool successNew,) = newUser.proxy(
            address(BOOTSTRAP),
            abi.encodeWithSelector(BOOTSTRAP.sacrifice.selector, token, amount, 1) // minOut = 1 because 0 reverts
        );
        require(successNew);

        hevm.warp(block.timestamp + clampBetween(_day, 30, 255) * 1 days);

        (bool successProcess,) = 
            address(BOOTSTRAP).call(abi.encodeWithSelector(BOOTSTRAP.processSacrifice.selector, 1));
        require(successProcess);
        //setup router proxy liquidity

        hevm.warp(block.timestamp + 1 days);

        (bool successClaim, bytes memory data) =
            user.proxy(address(BOOTSTRAP), abi.encodeWithSelector(BOOTSTRAP.claimSacrifice.selector));

        (,, uint256 hexitMinted) = abi.decode(data, (uint256, uint256, uint256));

        (bool successClaimNew, bytes memory dataNew) =
            newUser.proxy(address(BOOTSTRAP), abi.encodeWithSelector(BOOTSTRAP.claimSacrifice.selector));

        (,, uint256 hexitMinted1) = abi.decode(dataNew, (uint256, uint256, uint256));

        emit LogUint256("Hexit minted: ", hexitMinted);
        emit LogUint256("Hexit minted 1: ", hexitMinted1);

        assert(hexitMinted > hexitMinted1);
    }

    /// @custom:invariant If two users sacrificed the same amount in USD and have no HEX staked, the one who claimed the airdrop first should always receive more HEXIT
    function airdropPriorityNoHexStaked(
        uint256 randUser,
        uint256 randNewUser,
        uint256 randToken,
        uint256 randAmount,
        uint8 _day
    ) public {
        User user = users[randUser % users.length];
        User newUser = users[randNewUser % users.length];
        require(address(user) != address(newUser));

        address token = sacrificeTokens[randToken % sacrificeTokens.length];
        uint256 amount = clampBetween(randAmount, 1, (token == address(HEX_TOKEN) ? HEX_AMOUNT : TOKEN_AMOUNT) / 100);

        uint256 oldUserBalance = HEXIT.balanceOf(address(user));
        uint256 oldNewUserBalance = HEXIT.balanceOf(address(newUser));

        hevm.warp(block.timestamp + 1 days);

        (bool success,) = user.proxy(
            address(BOOTSTRAP),
            abi.encodeWithSelector(BOOTSTRAP.sacrifice.selector, token, amount, 1) // minOut = 1 because 0 reverts
        );
        require(success);

        (bool success1,) = newUser.proxy(
            address(BOOTSTRAP),
            abi.encodeWithSelector(BOOTSTRAP.sacrifice.selector, token, amount, 1) // minOut = 1 because 0 reverts
        );
        require(success1);

        hevm.warp(block.timestamp + clampBetween(_day, 30, 255) * 1 days);

        (bool successAirdrop,) = 
            address(BOOTSTRAP).call(abi.encodeWithSelector(BOOTSTRAP.startAirdrop.selector, uint64(block.timestamp)));
        require(successAirdrop);

        hevm.warp(block.timestamp + clampBetween(_day, 0, 13) * 1 days);

        (bool successClaimAirdrop,) =
            user.proxy(address(BOOTSTRAP), abi.encodeWithSelector(BOOTSTRAP.claimAirdrop.selector));
        require(successClaimAirdrop);

        hevm.warp(block.timestamp + 1 days);

        (bool successAirdropClaim1,) =
            newUser.proxy(address(BOOTSTRAP), abi.encodeWithSelector(BOOTSTRAP.claimAirdrop.selector));
        require(successAirdropClaim1);

        uint256 newUserBalance = HEXIT.balanceOf(address(user));
        uint256 newNewUserBalance = HEXIT.balanceOf(address(newUser));

        uint256 finalUserBalance = newUserBalance - oldUserBalance;
        uint256 finalNewUserBalance = newNewUserBalance - oldNewUserBalance;

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
        uint8 _day
    ) public {
        User user = users[randUser % users.length];
        User newUser = users[randNewUser % users.length];
        require(address(user) != address(newUser));

        uint256 amount = clampBetween(randAmount, 1, HEX_AMOUNT / 100);
        uint256 duration = clampBetween(randDuration, 1, 5555);

        uint256 oldUserBalance = HEXIT.balanceOf(address(user));
        uint256 oldNewUserBalance = HEXIT.balanceOf(address(newUser));

        (bool successHexStake,) =
            user.proxy(address(address(HEX_TOKEN)), abi.encodeWithSelector(IHexToken(address(HEX_TOKEN)).stakeStart.selector, amount, duration));
        require(successHexStake);

        (bool successHexStake1,) =
            newUser.proxy(address(address(HEX_TOKEN)), abi.encodeWithSelector(IHexToken(address(HEX_TOKEN)).stakeStart.selector, amount, duration));
        require(successHexStake1);

        (bool successAirdrop,) = 
            address(BOOTSTRAP).call(abi.encodeWithSelector(BOOTSTRAP.startAirdrop.selector, uint64(block.timestamp)));
        require(successAirdrop);

        hevm.warp(block.timestamp + clampBetween(_day, 0, 13) * 1 days);

        (bool successAirdrop2,) =
            user.proxy(address(BOOTSTRAP), abi.encodeWithSelector(BOOTSTRAP.claimAirdrop.selector));
        require(successAirdrop2);

        hevm.warp(block.timestamp + 1 days);

        (bool successAirdrop3,) =
            newUser.proxy(address(BOOTSTRAP), abi.encodeWithSelector(BOOTSTRAP.claimAirdrop.selector));
        require(successAirdrop3);

        uint256 newUserBalance = HEXIT.balanceOf(address(user));
        uint256 newNewUserBalance = HEXIT.balanceOf(address(newUser));

        uint256 finalUserBalance = newUserBalance - oldUserBalance;
        uint256 finalNewUserBalance = newNewUserBalance - oldNewUserBalance;

        emit LogUint256("Final user balance: ", finalUserBalance);
        emit LogUint256("Final new user balance: ", finalNewUserBalance);

        assert(finalUserBalance > finalNewUserBalance);
    }
    
    /// LOGIC INVARIANTS

    /// @custom:invariant Sacrifices can only be made within the predefined timeframe
    function sacrificeTimeframe(uint256 randUser, uint256 randToken, uint256 randAmount, uint8 _day) public {
        hevm.warp(block.timestamp + clampBetween(_day, 30, 255) * 1 days);

        User user = users[randUser % users.length];

        address token = sacrificeTokens[randToken % sacrificeTokens.length];
        uint256 amount = clampBetween(randAmount, 1, (token == address(HEX_TOKEN) ? HEX_AMOUNT : TOKEN_AMOUNT) / 100);

        (bool success,) = user.proxy(
            address(BOOTSTRAP),
            abi.encodeWithSelector(BOOTSTRAP.sacrifice.selector, token, amount, 1) // minOut = 1 because 0 reverts
        );

        assert (success == false);
    }

    /// @custom:invariant Sacrifice processing is only available after the sacrifice deadline has passed
    function processSacrificeTimeframe() public {
        (uint64 start,,bool processed) = BOOTSTRAP.sacrificeSchedule();
        require(block.timestamp < start + BOOTSTRAP.SACRIFICE_DURATION() && processed == false);

        (bool success,) = 
            address(BOOTSTRAP).call(abi.encodeWithSelector(BOOTSTRAP.processSacrifice.selector, 1));

        assert (success == false);
    }

    /// @custom:invariant The sacrifice can only be claimed within the claim period
    function claimSacrificeTimeframe(uint256 randUser, uint256 randAmount, uint256 randToken, uint8 _day) public {
        User user = users[randUser % users.length];

        address token = sacrificeTokens[randToken % sacrificeTokens.length];
        uint256 amount = clampBetween(randAmount, 1, (token == address(HEX_TOKEN) ? HEX_AMOUNT : TOKEN_AMOUNT) / 100);

        (bool success,) = user.proxy(
            address(BOOTSTRAP),
            abi.encodeWithSelector(BOOTSTRAP.sacrifice.selector, token, amount, 1) // minOut = 1 because 0 reverts
        );
        require(success);

        hevm.warp(block.timestamp + clampBetween(_day, 30, 255) * 1 days);

        (bool successProcess,) = 
            address(BOOTSTRAP).call(abi.encodeWithSelector(BOOTSTRAP.processSacrifice.selector, 1));
        require(successProcess);
        //setup router proxy liquidity

        hevm.warp(block.timestamp + clampBetween(_day, 7, 255) * 1 days);

        (bool successClaim,) =
            user.proxy(address(BOOTSTRAP), abi.encodeWithSelector(BOOTSTRAP.claimSacrifice.selector));

        assert (successClaim == false);
    }

    /// @custom:invariant The airdrop can only be claimed within the predefined airdrop timeframe
    function claimAirdropTimeframe(uint256 randUser, uint8 _day) public {
        (bool successAirdrop,) = 
            address(BOOTSTRAP).call(abi.encodeWithSelector(BOOTSTRAP.startAirdrop.selector, uint64(block.timestamp)));
        require(successAirdrop);

        User user = users[randUser % users.length];

        hevm.warp(block.timestamp + clampBetween(_day, 15, 255) * 1 days);

        (bool success,) =
            user.proxy(address(BOOTSTRAP), abi.encodeWithSelector(BOOTSTRAP.claimAirdrop.selector));

        assert (success == false);
    }
}
