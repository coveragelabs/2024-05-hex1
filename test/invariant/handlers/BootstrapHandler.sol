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

        (bool success,) = 
            address(FEED).call(abi.encodeWithSelector(
                FEED.setPrice.selector, 
                address(HEX_TOKEN), 
                address(DAI_TOKEN), 
                _newPrice
            )
        );
        require(success);
    }

    function setWplsDaiPrice(uint256 _newPrice) public {
        _newPrice = clampBetween(_newPrice, WPLS_DAI_INIT_PRICE / 5, WPLS_DAI_INIT_PRICE * 5);
        
        (bool success,) = 
            address(FEED).call(abi.encodeWithSelector(
                FEED.setPrice.selector,
                address(WPLS_TOKEN), 
                address(DAI_TOKEN), 
                _newPrice
            )
        );
        require(success);
    }

    function setPlsxDaiPrice(uint256 _newPrice) public {
        _newPrice = clampBetween(_newPrice, PLSX_DAI_INIT_PRICE / 5, PLSX_DAI_INIT_PRICE * 5);
        
        (bool success,) = 
            address(FEED).call(abi.encodeWithSelector(
                FEED.setPrice.selector, 
                address(PLSX_TOKEN), 
                address(DAI_TOKEN), 
                _newPrice
            )
        );
        require(success);
    }

    // user functions
    function sacrifice(uint256 randUser, uint256 randToken, uint256 randAmount) public {
        User user = users [randUser % users.length];

        address token = sacrificeTokens[randToken % sacrificeTokens.length];
        uint256 amount = clampBetween(
            randAmount, 
            1, 
            (
                token == address(HEX_TOKEN) ? 
                    HEX_AMOUNT : 
                    TOKEN_AMOUNT
            ) / 100
        );
        require(IERC20(token).balanceOf(address(user)) >= amount);

        (bool success,) = user.proxy(
            address(BOOTSTRAP),
            abi.encodeWithSelector(BOOTSTRAP.sacrifice.selector, token, amount, 1)
        );
        require(success);
    }

    function processSacrifice() public {
        (bool successProcess,) = 
            address(BOOTSTRAP).call(abi.encodeWithSelector(BOOTSTRAP.processSacrifice.selector, 1));
        require(successProcess);
    }

    function claimSacrifice(uint256 randUser) public {
        User user = users[randUser % users.length];

        (bool success,) =
            user.proxy(address(BOOTSTRAP), abi.encodeWithSelector(BOOTSTRAP.claimSacrifice.selector));
        require(success);
    }

    function startAirdrop() public {
        (bool success,) = 
            address(BOOTSTRAP).call(abi.encodeWithSelector(BOOTSTRAP.startAirdrop.selector, uint64(block.timestamp)));
        require(success);
    }

    function claimAirdrop(uint256 randUser) public {
        User user = users[randUser % users.length];

        (bool success,) =
            user.proxy(address(BOOTSTRAP), abi.encodeWithSelector(BOOTSTRAP.claimAirdrop.selector));
        require(success);
    }

    /// CONTEXT INVARIANTS

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
        (
            uint64 sacrificeStart,,
            bool sacrificeProcessed
        ) = BOOTSTRAP.sacrificeSchedule();
        require(
            address(user) != address(newUser) &&
            sacrificeProcessed == false &&
            block.timestamp < sacrificeStart + BOOTSTRAP.SACRIFICE_DURATION()
        );

        address token = sacrificeTokens[randToken % sacrificeTokens.length];
        uint256 amount = clampBetween(
            randAmount, 
            1, 
            (
                token == address(HEX_TOKEN) ? 
                    HEX_AMOUNT : 
                    TOKEN_AMOUNT
            ) / 100
        );
        require(
            IERC20(token).balanceOf(address(user)) >= amount &&
            IERC20(token).balanceOf(address(newUser)) >= amount
        );

        bool success;
        bytes memory data;

        (success,) = user.proxy(
            address(BOOTSTRAP),
            abi.encodeWithSelector(BOOTSTRAP.sacrifice.selector, token, amount, 1)
        );
        require(success);

        hevm.warp(block.timestamp + clampBetween(
            _seconds, 
            86400, 
            sacrificeStart + BOOTSTRAP.SACRIFICE_DURATION() - block.timestamp - 1));

        (success,) = newUser.proxy(
            address(BOOTSTRAP),
            abi.encodeWithSelector(BOOTSTRAP.sacrifice.selector, token, amount, 1)
        );
        require(success);

        uint256 processWarpMin = sacrificeStart + BOOTSTRAP.SACRIFICE_DURATION() - block.timestamp;
        uint256 processWarpMax = processWarpMin + BOOTSTRAP.SACRIFICE_CLAIM_DURATION() - 1;
        hevm.warp(block.timestamp + clampBetween(
            _seconds, 
            sacrificeStart + BOOTSTRAP.SACRIFICE_DURATION() - block.timestamp, 
            processWarpMin + BOOTSTRAP.SACRIFICE_CLAIM_DURATION() - 1
            )
        );

        (success,) = 
            address(BOOTSTRAP).call(abi.encodeWithSelector(BOOTSTRAP.processSacrifice.selector, 1));
        require(success);

        (,uint64 claimEnd,) = BOOTSTRAP.sacrificeSchedule();
        hevm.warp(block.timestamp + clampBetween(_seconds, 0, claimEnd - block.timestamp - 1));

        (success, data) =
            user.proxy(address(BOOTSTRAP), abi.encodeWithSelector(BOOTSTRAP.claimSacrifice.selector));
        require(success);

        (,,uint256 hexitMintedUser) = abi.decode(data, (uint256, uint256, uint256));

        (success, data) =
            newUser.proxy(address(BOOTSTRAP), abi.encodeWithSelector(BOOTSTRAP.claimSacrifice.selector));
        require(success);

        (,,uint256 hexitMintedNewUser) = abi.decode(data, (uint256, uint256, uint256));

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
        (
            uint64 sacrificeStart,,
            bool sacrificeProcessed
        ) = BOOTSTRAP.sacrificeSchedule();
        (,,bool airdropProcessed) = BOOTSTRAP.airdropSchedule();
        require(
            address(user) != address(newUser) &&
            sacrificeProcessed == false &&
            airdropProcessed == false &&
            block.timestamp < sacrificeStart + BOOTSTRAP.SACRIFICE_DURATION()
        ); 

        uint256 oldUserBalance = HEXIT.balanceOf(address(user));
        uint256 oldNewUserBalance = HEXIT.balanceOf(address(newUser));

        address token = sacrificeTokens[randToken % sacrificeTokens.length];
        uint256 amount = clampBetween(
            randAmount, 
            1, 
            (
                token == address(HEX_TOKEN) ? 
                    HEX_AMOUNT : 
                    TOKEN_AMOUNT
            ) / 100
        );
        require(
            IERC20(token).balanceOf(address(user)) >= amount &&
            IERC20(token).balanceOf(address(newUser)) >= amount
        );

        bool success;

        (success,) = user.proxy(
            address(BOOTSTRAP),
            abi.encodeWithSelector(BOOTSTRAP.sacrifice.selector, token, amount, 1)
        );
        require(success);

        (success,) = newUser.proxy(
            address(BOOTSTRAP),
            abi.encodeWithSelector(BOOTSTRAP.sacrifice.selector, token, amount, 1)
        );
        require(success);

        (success,) = 
            address(BOOTSTRAP).call(abi.encodeWithSelector(BOOTSTRAP.startAirdrop.selector, uint64(block.timestamp)));
        require(success);

        (success,) =
            user.proxy(address(BOOTSTRAP), abi.encodeWithSelector(BOOTSTRAP.claimAirdrop.selector));
        require(success);

        (,uint64 airdropClaimEnd,) = BOOTSTRAP.airdropSchedule();
        uint256 maxWarp = airdropClaimEnd - block.timestamp - 1;
        hevm.warp(block.timestamp + clampBetween(_seconds, 86400, maxWarp));

        (success,) =
            newUser.proxy(address(BOOTSTRAP), abi.encodeWithSelector(BOOTSTRAP.claimAirdrop.selector));
        require(success);

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
        uint64 _seconds
    ) public {
        User user = users[randUser % users.length];
        User newUser = users[randNewUser % users.length];
        (,,bool airdropProcessed) = BOOTSTRAP.airdropSchedule();
        require(
            address(user) != address(newUser) &&
            airdropProcessed == false
        ); 

        (uint256 sacrificedUsdUser,,,) = BOOTSTRAP.userInfos(address(user));
        (uint256 sacrificedUsdNewUser,,,) = BOOTSTRAP.userInfos(address(newUser));
        require(
            sacrificedUsdUser == 0 &&
            sacrificedUsdNewUser == 0
        );

        uint256 amount = clampBetween(randAmount, 1, HEX_AMOUNT / 100);
        require(
            HEX_TOKEN.balanceOf(address(user)) >= amount &&
            HEX_TOKEN.balanceOf(address(newUser)) >= amount
        );

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

        (success,) = user.proxy(
            address(BOOTSTRAP), 
            abi.encodeWithSelector(BOOTSTRAP.claimAirdrop.selector)
        );
        require(success);

        (,uint64 airdropClaimEnd,) = BOOTSTRAP.airdropSchedule();
        uint256 maxWarp = airdropClaimEnd - block.timestamp - 1;
        hevm.warp(block.timestamp + clampBetween(_seconds, 86400, maxWarp));

        (success,) = newUser.proxy(
            address(BOOTSTRAP), 
            abi.encodeWithSelector(BOOTSTRAP.claimAirdrop.selector)
        );
        require(success);

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
    function sacrificeTimeframe(uint256 randUser, uint256 randToken, uint256 randAmount) public {
        (,,bool processed) = BOOTSTRAP.sacrificeSchedule();
        require(processed == true);

        User user = users[randUser % users.length];
        address token = sacrificeTokens[randToken % sacrificeTokens.length];
        uint256 amount = clampBetween(
            randAmount, 
            1, 
            (
                token == address(HEX_TOKEN) ? 
                    HEX_AMOUNT : 
                    TOKEN_AMOUNT
            ) / 100
        );
        require(IERC20(token).balanceOf(address(user)) >= amount);

        (bool success,) = user.proxy(
            address(BOOTSTRAP),
            abi.encodeWithSelector(BOOTSTRAP.sacrifice.selector, token, amount, 1)
        );
        assert(success == false);
    }

    /// @custom:invariant Sacrifice processing is only available after the sacrifice deadline has passed
    function processSacrificeTimeframe() public {
        (
            uint64 start,,
            bool processed
        ) = BOOTSTRAP.sacrificeSchedule();
        require(
            block.timestamp < start + BOOTSTRAP.SACRIFICE_DURATION() && 
            block.timestamp >= start &&
            processed == false
        );

        (bool success,) = 
            address(BOOTSTRAP).call(abi.encodeWithSelector(BOOTSTRAP.processSacrifice.selector, 1));
        assert(success == false);
    }

    /// @custom:invariant The sacrifice can only be claimed within the claim period
    function claimSacrificeTimeframe(uint256 randUser) public {
        (
            ,uint64 claimEnd,
            bool processed
        ) = BOOTSTRAP.sacrificeSchedule();
        require(processed == true);
        
        User user = users[randUser % users.length];
        (
            uint256 sacrificedUsd,,,
            bool sacrificeClaimed
        ) = BOOTSTRAP.userInfos(address(user));
        require(
            sacrificedUsd > 0 &&
            sacrificeClaimed == false &&
            block.timestamp >= claimEnd
        );

        (bool success,) = user.proxy(
            address(BOOTSTRAP), 
            abi.encodeWithSelector(BOOTSTRAP.claimSacrifice.selector)
        );
        assert(success == false);
    }

    /// @custom:invariant The airdrop can only be claimed within the predefined airdrop timeframe
    function claimAirdropTimeframe(uint256 randUser) public {
        (
            ,uint64 claimEnd,
            bool processed
        ) = BOOTSTRAP.airdropSchedule();
        require(
            processed == false && 
            block.timestamp >= claimEnd
        );

        User user = users[randUser % users.length];
        (
            uint256 sacrificedUsd,,,
            bool airdropClaimed
        ) = BOOTSTRAP.userInfos(address(user));
        require(
            sacrificedUsd > 0 &&
            airdropClaimed == false
        );

        (bool success,) = user.proxy(
            address(BOOTSTRAP), 
            abi.encodeWithSelector(BOOTSTRAP.claimAirdrop.selector)
        );
        assert(success == false);
    }
}
