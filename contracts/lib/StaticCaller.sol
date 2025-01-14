/*

  << Static Caller >>

*/

pragma solidity 0.7.5;

/**
 * @title StaticCaller
 * @author Wyvern Protocol Developers
 */

 /**
 * 合约简介：发起交易
 * 功能简介：针对某个地址对应的token，发起交易
 * 参数简介：
 */

contract StaticCaller {

    function staticCall(address target, bytes memory data)
        internal
        view
        returns (bool result)
    {
        assembly {
            result := staticcall(gas(), target, add(data, 0x20), mload(data), mload(0x40), 0)
        }
        return result;
    }

    function staticCallUint(address target, bytes memory data)
        internal
        view
        returns (uint ret)
    {
        bool result;
        assembly {
            let size := 0x20
            let free := mload(0x40)
            result := staticcall(gas(), target, add(data, 0x20), mload(data), free, size)
            ret := mload(free)
        }
        require(result, "Static call failed");
        return ret;
    }

}
