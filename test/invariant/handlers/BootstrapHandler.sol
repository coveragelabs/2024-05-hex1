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

            // approve vault to spend tokens
            users[i].approve(HEX_TOKEN, address(vault));
            users[i].approve(DAI_TOKEN, address(vault));
            users[i].approve(WPLS_TOKEN, address(vault));
            users[i].approve(PLSX_TOKEN, address(vault));
        }
    }

    function sacrifice() public {}

    function processSacrifice() public {
        // bootstrap.processSacrifice(_amountOutMin);
    }

    function claimSacrifice() public {}

    function startAirdrop() public {
        bootstrap.startAirdrop(uint64(block.timestamp));
    }

    function claimAirdrop() public {}
}
