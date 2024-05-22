// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

contract PulseXFactoryMock {
    address internal immutable HEX1_DAI_TOKEN;

    constructor(address _hex1dai) {
        HEX1_DAI_TOKEN = _hex1dai;
    }

    function getPair(address, address) public view returns (address) {
        return HEX1_DAI_TOKEN;
    }
}
