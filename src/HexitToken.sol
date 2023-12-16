// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IHexitToken} from "./interfaces/IHexitToken.sol";

/// @title Hexit Token
contract HexitToken is ERC20, Ownable, IHexitToken {
    /// @notice HexOneBootstrap address
    address public hexOneBootstrap;
    /// @notice dead wallet address
    address public constant DEAD_WALLET = 0x000000000000000000000000000000000000dEaD;

    /// @notice checks if the sender is the bootstrap
    modifier onlyHexOneBootstrap() {
        require(msg.sender == hexOneBootstrap, "Only HexOneBootstrap");
        _;
    }

    /// @param _name of the token: Hexit Token.
    /// @param _symbol ticker of the token: $HEXIT.
    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) Ownable(msg.sender) {}

    /// @dev set the address of the bootstrap.
    /// @param _hexOneBootstrap address of the hexOneBootstrap.
    function setBootstrap(address _hexOneBootstrap) external onlyOwner {
        require(_hexOneBootstrap != address(0), "Invalid address");
        hexOneBootstrap = _hexOneBootstrap;
    }

    /// @notice mint HEXIT tokens to a specified account.
    /// @dev only HexOneBootstrap can call this function.
    /// @param _recipient address of the receiver.
    /// @param _amount amount of HEX1 being minted.
    function mint(address _recipient, uint256 _amount) external onlyHexOneBootstrap {
        _mint(_recipient, _amount);
    }

    /// @notice checks if HEXIT tokens are being transfered to the dead wallet.
    /// @param _to address to where HEXIT is being transfered.
    /// @param _amount amount of HEXIT being transfered.
    function transfer(address _to, uint256 _amount) public virtual override returns (bool) {
        require(_to != DEAD_WALLET, "Invalid transfer to dead address");
        return super.transfer(_to, _amount);
    }

    /// @notice checks if HEXIT tokens are being transfered to the dead wallet.
    /// @param _from address from where HEXIT is being transfered.
    /// @param _to address to where HEXIT is being transfered.
    /// @param _amount amount of HEXIT being transfered.
    function transferFrom(address _from, address _to, uint256 _amount) public virtual override returns (bool) {
        require(_to != DEAD_WALLET, "Invalid transfer to dead address");
        return super.transferFrom(_from, _to, _amount);
    }
}
