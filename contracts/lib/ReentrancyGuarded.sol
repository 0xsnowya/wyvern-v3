/*

  Simple contract extension to provide a contract-global reentrancy guard on functions.

*/

pragma solidity 0.7.5;

/**
 * @title ReentrancyGuarded
 * @author Wyvern Protocol Developers
 */
 /**
 * 合约简介：重入保护
 * 功能简介：防止双花
 * 参数简介：
 */
contract ReentrancyGuarded {

    bool reentrancyLock = false;

    /* Prevent a contract function from being reentrant-called. */
    modifier reentrancyGuard {
        require(!reentrancyLock, "Reentrancy detected");
        reentrancyLock = true;
        _;
        reentrancyLock = false;
    }

}
