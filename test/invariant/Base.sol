// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

// libraries
import {PropertiesAsserts} from "../../lib/properties/contracts/util/PropertiesHelper.sol";

// utils
import {User} from "./utils/User.sol";

// protocol contracts
import {HexOneToken} from "../../src/HexOneToken.sol";
import {HexOnePoolManager} from "../../src/HexOnePoolManager.sol";

// wraps
import {HexitTokenWrap} from "./wraps/HexitTokenWrap.sol";

// harness
import {HexOneBootstrapHarness} from "./harness/HexOneBootstrapHarness.sol";
import {HexOneVaultHarness} from "./harness/HexOneVaultHarness.sol";

// mocks
import {HexOnePriceFeedMock} from "./mocks/HexOnePriceFeedMock.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {HexTokenMock} from "./mocks/HexTokenMock.sol";
import {HedronTokenMock} from "./mocks/HedronTokenMock.sol";
import {PulseXRouterMock} from "./mocks/PulseXRouterMock.sol";
import {PulseXFactoryMock} from "./mocks/PulseXFactoryMock.sol";

// interfaces
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract Base is PropertiesAsserts {
    // constants
    uint256 internal constant NUMBER_OF_USERS = 10;
    uint256 internal constant NUMBER_OF_SACRIFICE_TOKENS = 4;
    uint256 internal constant NUMBER_OF_POOL_TOKENS = 2;
    uint256 internal constant HEX_DAI_INIT_PRICE = 9000000000000000;
    uint256 internal constant HEX_USDC_INIT_PRICE = 9000;
    uint256 internal constant HEX_USDT_INIT_PRICE = 9000;
    uint256 internal constant WPLS_DAI_INIT_PRICE = 75000000000000;
    uint256 internal constant PLSX_DAI_INIT_PRICE = 30000000000000;

    // contracts
    HexitTokenWrap internal HEXIT;
    HexOnePriceFeedMock internal FEED;
    HexOneBootstrapHarness internal BOOTSTRAP;
    HexOneVaultHarness internal VAULT;
    HexOneToken internal HEX1;
    HexOnePoolManager internal MANAGER;

    // tokens
    HexTokenMock internal HEX_TOKEN;
    HedronTokenMock internal HDRN_TOKEN;
    ERC20Mock internal WPLS_TOKEN;
    ERC20Mock internal PLSX_TOKEN;
    ERC20Mock internal DAI_TOKEN;
    ERC20Mock internal USDC_TOKEN;
    ERC20Mock internal USDT_TOKEN;
    ERC20Mock internal HEX1_DAI_LP_TOKEN;

    // pulsex mocks
    PulseXRouterMock internal ROUTER;
    PulseXFactoryMock internal FACTORY;

    // users
    User[] internal users;

    // tokens that can be used as sacrifice
    address[] internal sacrificeTokens;

    // tokens that can be staked in pools
    address[] internal poolTokens;

    constructor() {
        _deployTokens();
        _deployProtocol();
        _initializeProtocol();
        _setPrices();
        _createUsers();
    }

    function _deployTokens() private {
        HEX_TOKEN = new HexTokenMock();
        HDRN_TOKEN = new HedronTokenMock("Hedron Token", "HDRN");
        WPLS_TOKEN = new ERC20Mock("Wrapped PLS", "WPLS", 18);
        PLSX_TOKEN = new ERC20Mock("PulseX", "PLSX", 18);
        DAI_TOKEN = new ERC20Mock("Dai Token", "DAI", 18);
        USDC_TOKEN = new ERC20Mock("USDC Token", "USDC", 6);
        USDT_TOKEN = new ERC20Mock("USDT Token", "USDT", 6);
        HEX1_DAI_LP_TOKEN = new ERC20Mock("HEX1/DAI LP Token", "HEX1/DAI", 18);
    }

    function _deployProtocol() private {
        HEXIT = new HexitTokenWrap();
        FEED = new HexOnePriceFeedMock();

        sacrificeTokens = new address[](NUMBER_OF_SACRIFICE_TOKENS);
        sacrificeTokens[0] = address(HEX_TOKEN);
        sacrificeTokens[1] = address(DAI_TOKEN);
        sacrificeTokens[2] = address(WPLS_TOKEN);
        sacrificeTokens[3] = address(PLSX_TOKEN);

        BOOTSTRAP = new HexOneBootstrapHarness(uint64(block.timestamp), address(FEED), address(HEXIT), sacrificeTokens);
        VAULT = new HexOneVaultHarness(address(FEED), address(BOOTSTRAP));
        HEX1 = HexOneToken(VAULT.hex1());
        MANAGER = new HexOnePoolManager(address(HEXIT));
    }

    function _initializeProtocol() private {
        ROUTER = new PulseXRouterMock(address(FEED));
        FACTORY = new PulseXFactoryMock(address(HEX1_DAI_LP_TOKEN));

        HEXIT.initBootstrap(address(address(BOOTSTRAP)));
        HEXIT.initFeed(address(FEED));
        HEXIT.initManager(address(MANAGER));

        VAULT.initialize(
            address(ROUTER),
            address(HEX_TOKEN),
            address(HDRN_TOKEN),
            address(WPLS_TOKEN),
            address(DAI_TOKEN),
            address(USDC_TOKEN),
            address(USDT_TOKEN)
        );

        BOOTSTRAP.initialize(address(ROUTER), address(ROUTER), address(FACTORY), address(HEX_TOKEN), address(DAI_TOKEN));

        BOOTSTRAP.initVault(address(VAULT));

        poolTokens = new address[](NUMBER_OF_POOL_TOKENS);
        poolTokens[0] = address(HEX1_DAI_LP_TOKEN);
        poolTokens[1] = address(HEXIT);

        uint256[] memory rewardsPerPoolToken = new uint256[](NUMBER_OF_POOL_TOKENS);
        rewardsPerPoolToken[0] = 420e18;
        rewardsPerPoolToken[1] = 69e18;

        MANAGER.createPools(poolTokens, rewardsPerPoolToken);
    }

    function _createUsers() private {
        users = new User[](NUMBER_OF_USERS);
        for (uint256 i; i < NUMBER_OF_USERS; ++i) {
            users[i] = new User();
        }
    }

    function _setPrices() private {
        FEED.setPrice(address(HEX_TOKEN), address(DAI_TOKEN), HEX_DAI_INIT_PRICE);
        FEED.setPrice(address(HEX_TOKEN), address(USDC_TOKEN), HEX_USDC_INIT_PRICE);
        FEED.setPrice(address(HEX_TOKEN), address(USDT_TOKEN), HEX_USDT_INIT_PRICE);
        FEED.setPrice(address(WPLS_TOKEN), address(DAI_TOKEN), WPLS_DAI_INIT_PRICE);
        FEED.setPrice(address(PLSX_TOKEN), address(DAI_TOKEN), PLSX_DAI_INIT_PRICE);
    }
}
