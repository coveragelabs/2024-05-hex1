// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

import {HexitToken} from "../../../src/HexitToken.sol";

contract HexitTokenWrap is HexitToken {
    function mintAdmin(address _account, uint256 _amount) external {
        _mint(_account, _amount);
    }
}
