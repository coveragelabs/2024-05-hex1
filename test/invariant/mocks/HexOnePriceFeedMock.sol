// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {TokenUtils} from "../../../src/utils/TokenUtils.sol";

contract HexOnePriceFeedMock {
    mapping(address => mapping(address => uint256)) public prices;

    function setPrice(address _tokenIn, address _tokenOut, uint256 _price) external {
        prices[_tokenIn][_tokenOut] = _price;
    }

    function update() external {}

    function quote(address _tokenIn, uint256 _amountIn, address _tokenOut) external view returns (uint256 amountOut) {
        uint8 decimals = TokenUtils.expectDecimals(address(_tokenIn));
        return (_amountIn * prices[_tokenIn][_tokenOut]) / 10 ** decimals;
    }
}
