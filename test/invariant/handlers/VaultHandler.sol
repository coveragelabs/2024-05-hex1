// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../Base.sol";

contract VaultHandler is Base {
    uint256 internal constant HEX_AMOUNT = 100_000_000e8;
    address internal constant HEX_WHALE = 0x5280aa3cF5D6246B8a17dFA3D75Db26617B73937;

    constructor() {
        for (uint256 i; i < NUMBER_OF_USERS; ++i) {
            emit LogAddress("address of the user", address(users[i]));

            // deal hex to users
            hevm.prank(HEX_WHALE);
            IERC20(HEX_TOKEN).transfer(address(users[i]), HEX_AMOUNT);

            // approve vault to spend users hex
            users[i].approve(HEX_TOKEN, address(vault));
        }
    }

    function enableBuyback() public {
        hevm.prank(address(bootstrap));
        vault.enableBuyback();
    }

    function deposit() public {}

    function withdraw() public {}

    function liquidate() public {}

    function repay() public {}

    function borrow() public {}

    function take() public {}
}
