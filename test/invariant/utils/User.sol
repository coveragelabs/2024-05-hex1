// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract User {
    function proxy(address target, bytes memory data) public returns (bool success, bytes memory err) {
        return target.call(data);
    }

    function approve(address target, address spender) public {
        ERC20(target).approve(spender, type(uint256).max);
    }
}
