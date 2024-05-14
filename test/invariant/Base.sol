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
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

contract Base is PropertiesAsserts {
    uint256 public constant NUMBER_OF_USERS = 10;
    uint256 public constant INITIAL_TOKEN_MINT = 10; // @todo set
    uint256 public constant INITIAL_HEX_MINT = 10; // @todo set

    User[] public users;
    HexitToken public hexit;
    HexOneToken public hex1;
    HexOnePriceFeed public feed;
    HexOneBootstrap public bootstrap;
    HexOneVault public vault;
    HexOnePoolManager public manager;
    // HexMockToken public hx;
    ERC20Mock public hx; // @todo fix
    ERC20Mock public dai;
    ERC20Mock public wpls;
    ERC20Mock public plsx;
    ERC20Mock public hex1dai;

    address[] public stakeTokens;
    address[] public sacrificeTokens;

    constructor() {
        users = new User[](NUMBER_OF_USERS);

        hexit = new HexitToken();
        dai = new ERC20Mock("DAI", "DAI");
        hx = new ERC20Mock("HEX", "HEX");
        wpls = new ERC20Mock("WPLS", "WPLS");
        plsx = new ERC20Mock("PLSX", "PLSX");

        feed = new HexOnePriceFeed(address(hexit), 500);

        sacrificeTokens = new address[](4);
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
}
