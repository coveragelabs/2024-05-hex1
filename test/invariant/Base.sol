// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../../lib/properties/contracts/util/Hevm.sol";
import "../../lib/properties/contracts/util/PropertiesHelper.sol";
import {User} from "./utils/User.sol";
import {HexitToken} from "../../src/HexitToken.sol";
import {HexOneToken} from "../../src/HexOneToken.sol";
import {HexOnePriceFeedMock} from "../mocks/HexOnePriceFeedMock.sol";
import {HexOneBootstrap} from "../../src/HexOneBootstrap.sol";
import {HexOneVault} from "../../src/HexOneVault.sol";
import {HexOnePoolManager} from "../../src/HexOnePoolManager.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {StableMock} from "../mocks/StableMock.sol";

contract Base is PropertiesAsserts {
    uint256 constant NUMBER_OF_USERS = 10;
    uint256 constant NUMBER_OF_STAKE_TOKENS = 2;
    uint256 constant NUMBER_OF_SACRIFICE_TOKENS = 4;
    uint256 constant INITIAL_TOKEN_MINT = 1_000_000_000 ether;
    uint256 constant INITIAL_HEX_MINT = 1_000_000_000e8;
    uint256 constant INITIAL_STABLE_MINT = 1_000_000_000e6;

    User[] users;
    HexitToken hexit;
    HexOneToken hex1;
    HexOnePriceFeedMock feed;
    HexOneBootstrap bootstrap;
    HexOneVault vault;
    HexOnePoolManager manager;
    // HexMockToken hx;
    ERC20Mock hx; // @todo fix
    ERC20Mock dai;
    ERC20Mock wpls;
    ERC20Mock plsx;
    ERC20Mock hex1Dai;
    ERC20Mock hexitHex1;
    StableMock usdc;
    StableMock usdt;

    address[] stakeTokens;
    address[] sacrificeTokens;

    constructor() {
        _deploy();
        _configure();
        _users();
    }

    function _deploy() internal {
        hexit = new HexitToken();
        feed = new HexOnePriceFeedMock();

        hx = new ERC20Mock("HEX", "HEX");
        dai = new ERC20Mock("DAI", "DAI");
        wpls = new ERC20Mock("WPLS", "WPLS");
        plsx = new ERC20Mock("PLSX", "PLSX");
        usdc = new StableMock("USDC", "USDC");
        usdt = new StableMock("USDT", "USDT");

        sacrificeTokens = new address[](NUMBER_OF_SACRIFICE_TOKENS);
        sacrificeTokens[0] = address(hx);
        sacrificeTokens[1] = address(dai);
        sacrificeTokens[2] = address(wpls);
        sacrificeTokens[3] = address(plsx);

        uint64 sacrificeStart = uint64(block.timestamp + 1 minutes);

        bootstrap = new HexOneBootstrap(sacrificeStart, address(feed), address(hexit), sacrificeTokens);
        vault = new HexOneVault(address(feed), address(bootstrap));
        hex1 = HexOneToken(vault.hex1());
        manager = new HexOnePoolManager(address(hexit));
    }

    function _configure() internal {
        // configure hexit
        hexit.initFeed(address(feed));
        hexit.initBootstrap(address(bootstrap));
        hexit.initManager(address(manager));

        // configure feed
        // HEX/DAI
        address[] memory hexDaiPath = new address[](3);
        hexDaiPath[0] = address(hx);
        hexDaiPath[1] = address(wpls);
        hexDaiPath[2] = address(dai);
        feed.addPath(hexDaiPath);

        // HEX/USDC
        address[] memory hexUsdcPath = new address[](3);
        hexUsdcPath[0] = address(hx);
        hexUsdcPath[1] = address(wpls);
        hexUsdcPath[2] = address(usdc);
        feed.addPath(hexUsdcPath);

        // HEX/USDT
        address[] memory hexUsdtPath = new address[](3);
        hexUsdtPath[0] = address(hx);
        hexUsdtPath[1] = address(wpls);
        hexUsdtPath[2] = address(usdt);
        feed.addPath(hexUsdtPath);

        // WPLS/DAI path
        address[] memory wplsDaiPath = new address[](2);
        wplsDaiPath[0] = address(wpls);
        wplsDaiPath[1] = address(dai);
        feed.addPath(wplsDaiPath);

        // PLSX/DAI path
        address[] memory plsxDaiPath = new address[](2);
        plsxDaiPath[0] = address(plsx);
        plsxDaiPath[1] = address(dai);
        feed.addPath(plsxDaiPath);

        // configure bootstrap
        bootstrap.initVault(address(vault));

        // create HEX1/DAI and HEXIT/HEX1 pairs in pulsex v2
        hex1Dai = ERC20Mock(address(uint160(uint256(keccak256(abi.encode(hex1, dai))))));
        hexitHex1 = ERC20Mock(address(uint160(uint256(keccak256(abi.encode(hexit, hex1))))));

        // deploy HEX1/DAI and HEXIT pools
        stakeTokens = new address[](NUMBER_OF_STAKE_TOKENS);
        stakeTokens[0] = address(hex1Dai);
        stakeTokens[1] = address(hexit);

        uint256[] memory rewardsPerToken = new uint256[](NUMBER_OF_STAKE_TOKENS);
        rewardsPerToken[0] = 420e18;
        rewardsPerToken[1] = 69e18;

        manager.createPools(stakeTokens, rewardsPerToken);
    }

    function _users() internal {
        users = new User[](NUMBER_OF_USERS);

        for (uint256 i; i < NUMBER_OF_USERS; ++i) {
            User user = new User();
            users.push(user);

            dai.mint(address(user), INITIAL_TOKEN_MINT);
            usdc.mint(address(user), INITIAL_STABLE_MINT);
            usdt.mint(address(user), INITIAL_STABLE_MINT);

            hx.mint(address(user), INITIAL_HEX_MINT);
            wpls.mint(address(user), INITIAL_TOKEN_MINT);
            plsx.mint(address(user), INITIAL_TOKEN_MINT);

            user.approveERC20(dai, address(bootstrap));
            user.approveERC20(hx, address(bootstrap));
            user.approveERC20(wpls, address(bootstrap));
            user.approveERC20(plsx, address(bootstrap));

            // user.approveERC20(hex1, address(vault));
        }

        // @todo setPrices
    }

    function foo() public {
        assert(true);
    }
}
