// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC20} from "../../../src/interfaces/IERC20.sol";

import {HexOnePriceFeedMock} from "./HexOnePriceFeedMock.sol";

contract PulseXRouterMock {
    HexOnePriceFeedMock internal immutable FEED;

    constructor(address _feed) {
        FEED = HexOnePriceFeedMock(_feed);
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256
    ) external returns (uint256[] memory amounts) {
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;

        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);

        uint256 amountOut = FEED.quote(path[0], amountIn, path[1]);
        require(amountOut >= amountOutMin, "UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT");

        IERC20(path[1]).transfer(to, amountOut);

        amounts[1] = amountOut;
    }
}
