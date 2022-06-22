/*

  Proxy registry interface.

*/

pragma solidity 0.7.5;

import "./OwnableDelegateProxy.sol";

/**
 * @title ProxyRegistryInterface
 * @author Wyvern Protocol Developers
 */

 /**
 * 合约简介：代理注册接口
 * 功能简介：
 * 参数简介：
 */
 
interface ProxyRegistryInterface {
    // 实施委托代理
    function delegateProxyImplementation() external returns (address);

    // owner委托代理
    function proxies(address owner) external returns (OwnableDelegateProxy);

}
