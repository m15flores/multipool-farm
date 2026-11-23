// SPDX-License-Identifier: MIT

pragma solidity 0.8.34;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockToken
 * @notice Token ERC-20 mock to test the yield farming project
 */
contract MockToken is ERC20, Ownable {
    constructor(string memory name, string memory symbol, uint256 initialSupply)
        ERC20(name, symbol)
        Ownable(msg.sender)
    {
        _mint(msg.sender, initialSupply);
    }

    /**
     * @dev Function to mint tokens
     * @param to Recipient address
     * @param amount amount to mint
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}
