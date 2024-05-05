# Hex One Protocol Security Review Details

## Executive Summary
Coverage reviewed Hex One Protocol smart contracts over the course of a 5 week engagement with three engineers. The review was conducted from 2024-05-06 to 2024-05-31.

### People Involved
| Name                      | Role                      | Contact                   |
|---------------------------|---------------------------|---------------------------|
| José Garção               | Lead Security Researcher  | garcao.random@gmail.com   |
| Rafael Nicolau            | Security Researcher       | 0xrafaelnicolau@gmail.com |
| nexusflip                 | Security Researcher       | 0xnexusflip@gmail.com     |

### Application Summary
| Name            | Repository                                                | Language | Platform   |
|-----------------|-----------------------------------------------------------|----------|------------|
| Hex One Protocol | https://github.com/HexOneProtocol/hex1-contracts         | Solidity | Pulsechain |

### Code Scope Version Control
- **Review commit hash - [45514b8](https://github.com/coveragelabs/2024-05-hex1/tree/45514b8a25a24679dffbe99db3e41196c06a2427).**

- **Fix review commit hash - [\<commit hash of the fix review>](link-to-the-commit).**

### Scope
The following smart contracts were within review scope:
* `src/HexOneBootstrap.sol`
* `src/HexOnePool.sol`
* `src/HexOnePoolManager.sol`
* `src/HexOnePriceFeed.sol`
* `src/HexOneToken.sol`
* `src/HexOneVault.sol`
* `src/HexitToken.sol`
