// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract HedronTokenMock is ERC20 {
    mapping(uint40 => bool) internal claimed;

    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) {}

    function mintNative(uint256, uint40 stakeId) external returns (uint256) {
        require(!claimed[stakeId], "already claimed");
        claimed[stakeId] = true;

        _mint(msg.sender, 1000e18);

        return 1000e18;
    }
}
