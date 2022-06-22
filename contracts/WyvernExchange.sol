/*

  << Wyvern Exchange >>

*/

pragma solidity 0.7.5;

import "./exchange/Exchange.sol";

/**
 * @title WyvernExchange
 * @author Wyvern Protocol Developers
 */
 /**
 * 合约简介：WyvernExchange合约，继承Exchange合约，确认交互的公链
 * 方法简介：构造函数constructor，
 * 参数简介：
 */
contract WyvernExchange is Exchange {

    string public constant name = "Wyvern Exchange";
  
    string public constant version = "3.1";

    string public constant codename = "Ancalagon";

    // 构造函数：交易的公链信息，注册方数组（from）
    constructor (uint chainId, address[] memory registryAddrs, bytes memory customPersonalSignPrefix) public {
        DOMAIN_SEPARATOR = hash(EIP712Domain({
            name              : name,
            version           : version,
            chainId           : chainId,
            verifyingContract : address(this)
        }));
        for (uint ind = 0; ind < registryAddrs.length; ind++) {
          registries[registryAddrs[ind]] = true;
        }
        if (customPersonalSignPrefix.length > 0) {
          personalSignPrefix = customPersonalSignPrefix;
        }
    }

}
