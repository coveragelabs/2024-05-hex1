// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test} from "../../lib/forge-std/src/Test.sol";

import {HexOneVaultHarness} from "../invariant/harness/HexOneVaultHarness.sol";
import {HexOnePriceFeedMock} from "../invariant/mocks/HexOnePriceFeedMock.sol";
import {PulseXRouterMock} from "../invariant/mocks/PulseXRouterMock.sol";
import {PulseXFactoryMock} from "../invariant/mocks/PulseXFactoryMock.sol";
import {HexTokenMock} from "../invariant/mocks/HexTokenMock.sol";
import {HedronTokenMock} from "../invariant/mocks/HedronTokenMock.sol";
import {ERC20Mock} from "../invariant/mocks/ERC20Mock.sol";

contract FindingTest is Test {
    uint256 internal constant HEX_DAI_INIT_PRICE = 9000000000000000;
    uint256 internal constant HEX_USDC_INIT_PRICE = 9000;
    uint256 internal constant HEX_USDT_INIT_PRICE = 9000;
    uint256 internal constant WPLS_DAI_INIT_PRICE = 75000000000000;

    address internal immutable USER1 = makeAddr("user1");
    address internal immutable USER2 = makeAddr("user2");

    HexOneVaultHarness internal vault;
    HexOnePriceFeedMock internal feed;
    PulseXRouterMock internal router;
    PulseXFactoryMock internal factory;

    HexTokenMock internal hx;
    HedronTokenMock internal hdrn;

    ERC20Mock internal wpls = new ERC20Mock("Wrapped PLS", "WPLS", 18);
    ERC20Mock internal dai = new ERC20Mock("DAI Token", "WPLS", 6);
    ERC20Mock internal usdc = new ERC20Mock("USDC Token", "USDC", 6);
    ERC20Mock internal usdt = new ERC20Mock("USDT Token", "USDT", 6);
    ERC20Mock internal hex1dai = new ERC20Mock("HEX1/DAI Token", "HEX1/DAI", 18);

    function setUp() external {
        feed = new HexOnePriceFeedMock();
        vault = new HexOneVaultHarness(address(feed), makeAddr("bootstrap"));

        router = new PulseXRouterMock(address(feed));
        factory = new PulseXFactoryMock(address(hex1dai));

        vault.initialize(
            address(router), address(hx), address(hdrn), address(wpls), address(dai), address(usdc), address(usdt)
        );

        feed.setPrice(address(HEX_TOKEN), address(DAI_TOKEN), HEX_DAI_INIT_PRICE);
        feed.setPrice(address(HEX_TOKEN), address(USDC_TOKEN), HEX_USDC_INIT_PRICE);
        feed.setPrice(address(HEX_TOKEN), address(USDT_TOKEN), HEX_USDT_INIT_PRICE);
        feed.setPrice(address(WPLS_TOKEN), address(DAI_TOKEN), WPLS_DAI_INIT_PRICE);
    }
}
