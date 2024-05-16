pragma solidity ^0.8.0;

import "../../../src/HexOneVault.sol";
import "../../../lib/properties/contracts/ERC721/internal/properties/ERC721BasicProperties.sol";
import "../../../lib/properties/contracts/ERC721/internal/properties/ERC721BurnableProperties.sol";
import "../../../lib/properties/contracts/ERC721/internal/properties/ERC721MintableProperties.sol";

contract CryticERC721InternalHarness is HexOneVault, CryticERC721BasicProperties, CryticERC721BurnableProperties, CryticERC721MintableProperties {

    constructor() {
    }
}