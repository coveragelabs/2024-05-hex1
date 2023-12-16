// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import {IHexOnePriceFeed} from "./interfaces/IHexOnePriceFeed.sol";

contract HexOneVault {
    IHexOnePriceFeed public hexOnePriceFeed;

    function _getHexPrice() internal view returns (uint256 hexPrice) {}
}
