// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

contract HexOnePriceFeedMock {
    mapping(address => mapping(address => uint256)) rates; // base rate 10000
    // tokenIn -> tokenOut -> path
    mapping(address => mapping(address => address[])) paths;

    constructor() {}

    function setRate(address tokenIn, address tokenOut, uint256 r) external {
        rates[tokenIn][tokenOut] = r;
    }

    function getRate(address tokenIn, address tokenOut) external view returns (uint256) {
        return rates[tokenIn][tokenOut];
    }

    function getPath(address _tokenIn, address _tokenOut) external view returns (address[] memory) {
        return paths[_tokenIn][_tokenOut];
    }

    function setPath(address _tokenIn, address _tokenOut, address[] memory _path) external {
        paths[_tokenIn][_tokenOut] = _path;
    }

    function update(address, address) external {}

    function consult(address tokenIn, uint256 amountIn, address tokenOut) external view returns (uint256 amountOut) {
        return amountIn * rates[tokenIn][tokenOut] / 1e18;
    }
}