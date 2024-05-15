// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../../lib/properties/contracts/util/Hevm.sol";
import "../../lib/properties/contracts/util/PropertiesHelper.sol";

import {User} from "./utils/User.sol";

import {HexitToken} from "../../src/HexitToken.sol";
import {HexOneToken} from "../../src/HexOneToken.sol";
import {HexOnePriceFeed} from "../../src/HexOnePriceFeed.sol";
import {HexOneBootstrap} from "../../src/HexOneBootstrap.sol";
import {HexOneVault} from "../../src/HexOneVault.sol";
import {HexOnePoolManager} from "../../src/HexOnePoolManager.sol";
import {HexOnePool} from "../../src/HexOnePool.sol";

import {IPulseXFactory} from "../../src/interfaces/pulsex/IPulseXFactory.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract Base is PropertiesAsserts {
    // constants
    uint256 internal constant NUMBER_OF_USERS = 10;
    uint256 internal constant NUMBER_OF_POOL_TOKENS = 2;
    uint256 internal constant NUMBER_OF_SACRIFICE_TOKENS = 4;

    // contracts
    HexitToken internal hexit;
    HexOneToken internal hex1;
    HexOnePriceFeed internal feed;
    HexOneBootstrap internal bootstrap;
    HexOneVault internal vault;
    HexOnePoolManager internal manager;

    // pulsex v1
    address internal constant PULSEX_ROUTER_V1 = 0x98bf93ebf5c380C0e6Ae8e192A7e2AE08edAcc02;
    address internal constant PULSEX_FACTORY_V1 = 0x1715a3E4A142d8b698131108995174F37aEBA10D;

    // pulsex v2
    address internal constant PULSEX_ROUTER_V2 = 0x165C3410fC91EF562C50559f7d2289fEbed552d9;
    address internal constant PULSEX_FACTORY_V2 = 0x29eA7545DEf87022BAdc76323F373EA1e707C523;

    // tokens
    address internal constant HEX_TOKEN = 0x2b591e99afE9f32eAA6214f7B7629768c40Eeb39;
    address internal constant HDRN_TOKEN = 0x3819f64f282bf135d62168C1e513280dAF905e06;
    address internal constant WPLS_TOKEN = 0xA1077a294dDE1B09bB078844df40758a5D0f9a27;
    address internal constant PLSX_TOKEN = 0x95B303987A60C71504D99Aa1b13B4DA07b0790ab;
    address internal constant DAI_TOKEN = 0xefD766cCb38EaF1dfd701853BFCe31359239F305;
    address internal constant USDC_TOKEN = 0x15D38573d2feeb82e7ad5187aB8c1D52810B1f07;
    address internal constant USDT_TOKEN = 0x0Cb6F5a34ad42ec934882A05265A7d5F59b51A2f;

    // lp tokens
    address internal hex1Dai;
    address internal hexitHex1;

    // tokens that can be used to sacrifice
    address[] internal sacrificeTokens;

    // tokens that can be staked in pools
    address[] internal poolTokens;

    // users
    User[] internal users;

    constructor() {
        // deploy hexit
        hexit = new HexitToken();

        // deploy feed
        feed = new HexOnePriceFeed(address(hexit), 500);

        // deploy bootstrap
        sacrificeTokens = new address[](NUMBER_OF_SACRIFICE_TOKENS);
        sacrificeTokens[0] = HEX_TOKEN;
        sacrificeTokens[1] = DAI_TOKEN;
        sacrificeTokens[2] = WPLS_TOKEN;
        sacrificeTokens[3] = PLSX_TOKEN;
        bootstrap = new HexOneBootstrap(uint64(block.timestamp), address(feed), address(hexit), sacrificeTokens);

        // deploy vault and hex one token
        vault = new HexOneVault(address(feed), address(bootstrap));
        hex1 = HexOneToken(vault.hex1());

        // deploy pool manager
        manager = new HexOnePoolManager(address(hexit));

        // configure hexit
        hexit.initBootstrap(address(bootstrap));
        hexit.initFeed(address(feed));
        hexit.initManager(address(manager));

        // configure feed
        address[] memory hexDaiPath = new address[](3);
        hexDaiPath[0] = HEX_TOKEN;
        hexDaiPath[1] = WPLS_TOKEN;
        hexDaiPath[2] = DAI_TOKEN;
        feed.addPath(hexDaiPath);

        address[] memory hexUsdcPath = new address[](3);
        hexUsdcPath[0] = HEX_TOKEN;
        hexUsdcPath[1] = WPLS_TOKEN;
        hexUsdcPath[2] = USDC_TOKEN;
        feed.addPath(hexUsdcPath);

        address[] memory hexUsdtPath = new address[](3);
        hexUsdtPath[0] = HEX_TOKEN;
        hexUsdtPath[1] = WPLS_TOKEN;
        hexUsdtPath[2] = USDT_TOKEN;
        feed.addPath(hexUsdtPath);

        address[] memory wplsDaiPath = new address[](2);
        wplsDaiPath[0] = WPLS_TOKEN;
        wplsDaiPath[1] = DAI_TOKEN;
        feed.addPath(wplsDaiPath);

        address[] memory plsxDaiPath = new address[](2);
        plsxDaiPath[0] = PLSX_TOKEN;
        plsxDaiPath[1] = DAI_TOKEN;
        feed.addPath(plsxDaiPath);

        // configure bootstrap
        bootstrap.initVault(address(vault));

        // create HEX1/DAI pair in pulsex v2
        hex1Dai = IPulseXFactory(PULSEX_FACTORY_V2).createPair(address(hex1), DAI_TOKEN);

        // create HEXIT/HEX1 pair in pulsex v2
        hexitHex1 = IPulseXFactory(PULSEX_FACTORY_V2).createPair(address(hexit), address(hex1));

        // deploy HEX1/DAI and HEXIT pools
        poolTokens = new address[](NUMBER_OF_POOL_TOKENS);
        poolTokens[0] = address(hex1Dai);
        poolTokens[1] = address(hexit);

        uint256[] memory rewardsPerPoolToken = new uint256[](NUMBER_OF_POOL_TOKENS);
        rewardsPerPoolToken[0] = 420e18;
        rewardsPerPoolToken[1] = 69e18;

        manager.createPools(poolTokens, rewardsPerPoolToken);

        // setup users
        users = new User[](NUMBER_OF_USERS);
        for (uint256 i; i < NUMBER_OF_USERS; ++i) {
            users[i] = new User();
        }
    }
}
