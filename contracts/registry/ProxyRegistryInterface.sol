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
 * 功能简介：用户进行委托代理、执行委托代理
 * 参数简介：
 */
 
interface ProxyRegistryInterface {
    // 执行委托代理
    function delegateProxyImplementation() external returns (address);

    // owner进行委托代理
    function proxies(address owner) external returns (OwnableDelegateProxy);

}
