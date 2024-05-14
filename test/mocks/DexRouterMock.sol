// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import "../mocks/ERC20Mock.sol";

// this contract need to be funded in tokens to work
contract DexRouterMock {
    mapping(address => mapping(address => uint256)) rates; // base rate 10000

    address poolAddress;

    constructor(address _poolAddress) {
        poolAddress = _poolAddress;
    }

    function setRate(address tokenIn, address tokenOut, uint256 r) public {
        rates[tokenIn][tokenOut] = r;
    }

    // we assume path.lenght == 2
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256
    ) external returns (uint256[] memory amounts) {
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        ERC20Mock(path[0]).transferFrom(msg.sender, address(this), amountIn);
        uint256 amountOut = amountIn * rates[path[0]][path[1]] / 10000;
        require(amountOut >= amountOutMin, "UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT");
        ERC20Mock(path[1]).transfer(to, amountOut);
        amounts[1] = amountOut;
    }

    function addLiquidity(
        address tokenIn,
        address tokenOut,
        uint256 tokenInAmount,
        uint256 tokenOutAmount,
        uint256,
        uint256,
        address,
        uint256
    ) external returns (uint256, uint256, uint256) {
        ERC20Mock(tokenIn).transferFrom(msg.sender, address(this), tokenInAmount);
        ERC20Mock(tokenOut).transferFrom(msg.sender, address(this), tokenOutAmount);
        ERC20Mock(poolAddress).mint(msg.sender, tokenInAmount);
        return (tokenInAmount, tokenOutAmount, tokenInAmount);
    }
}

// setRate() => change the exchange rate of swapExactTokensForTokens
// swapExactTokensForTokens(_amountIn, _amountOutMin, path, address(this), deadline) => no slippage
// addLiquidity(hexOneToken,tokenOutToken,hexOneMinted,amountOut[1],hexOneMinted, amountOut[1], address(this), deadline); => do nothng