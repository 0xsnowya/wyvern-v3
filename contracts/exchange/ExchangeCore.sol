/*

  << Exchange Core >>

*/

pragma solidity 0.7.5;

import "openzeppelin-solidity/contracts/access/Ownable.sol";

import "../lib/StaticCaller.sol";
import "../lib/ReentrancyGuarded.sol";
import "../lib/EIP712.sol";
import "../lib/EIP1271.sol";
import "../registry/ProxyRegistryInterface.sol";
import "../registry/AuthenticatedProxy.sol";

/**
 * @title ExchangeCore
 * @author Wyvern Protocol Developers
 */

  /**
 * 合约简介：交易核心要素，struc一个Order订单结构体，Call结构体
 * 功能简介：
 * 参数简介：
 */

contract ExchangeCore is ReentrancyGuarded, StaticCaller, EIP712 {

    // 签名验证码
    bytes4 constant internal EIP_1271_MAGICVALUE = 0x1626ba7e;
    // 签名前缀
    bytes internal personalSignPrefix = "\x19Ethereum Signed Message:\n";

    /* Struct definitions. */
    
    /* An order, convenience struct. */
    struct Order {
        /* Order registry address. */
        // 订单注册方的地址：from（藏品owner）
        address registry;
        /* Order maker address. */
        // 订单发起方地址：to（购买者）
        address maker;
        /* Order static target. */
        // 藏品目标
        address staticTarget;
        /* Order static selector. */
        // 选择器：与藏品绑定
        bytes4 staticSelector;
        /* Order static extradata. */
        // 其他数据信息
        bytes staticExtradata;
        /* Order maximum fill factor. */
        // 订单进展进度值上限
        uint maximumFill;
        /* Order listing timestamp. */
        // 订单时间戳
        uint listingTime;
        /* Order expiration timestamp - 0 for no expiry. */
        // 订单结束时间
        uint expirationTime;
        /* Order salt to prevent duplicate hashes. */
        // 加盐
        uint salt;
    }

    /* A call, convenience struct. */
    struct Call {
        /* Target */
        // 目标藏品
        address target;
        /* How to call */
        // 如何调用
        AuthenticatedProxy.HowToCall howToCall;
        /* Calldata */
        // 调用数据：to
        bytes data;
    }

    /* Constants */

    /* Order typehash for EIP 712 compatibility. */
    bytes32 constant ORDER_TYPEHASH = keccak256(
        "Order(address registry,address maker,address staticTarget,bytes4 staticSelector,bytes staticExtradata,uint256 maximumFill,uint256 listingTime,uint256 expirationTime,uint256 salt)"
    );

    /* Variables */

    /* Trusted proxy registry contracts. */
    // 可信的代理注册合约
    mapping(address => bool) public registries;

    /* Order fill status, by maker address then by hash. */
    // 订单总量状态
    mapping(address => mapping(bytes32 => uint)) public fills;

    /* Orders verified by on-chain approval.
       Alternative to ECDSA signatures so that smart contracts can place orders directly.
       By maker address, then by hash. */
    //to(藏品购买者地址，是否授权，授权的token数量)
    mapping(address => mapping(bytes32 => bool)) public approved;

    /* Events */
    // 订单授权事件：参数为，藏品索引哈希,from，to，藏品发布的合约...
    event OrderApproved     (bytes32 indexed hash, address registry, address indexed maker, address staticTarget, bytes4 staticSelector, bytes staticExtradata, uint maximumFill, uint listingTime, uint expirationTime, uint salt, bool orderbookInclusionDesired);
    // 订单总量改变事件
    event OrderFillChanged  (bytes32 indexed hash, address indexed maker, uint newFill);
    // ？
    event OrdersMatched     (bytes32 firstHash, bytes32 secondHash, address indexed firstMaker, address indexed secondMaker, uint newFirstFill, uint newSecondFill, bytes32 indexed metadata);

    /* Functions */
    // 订单哈希
    function hashOrder(Order memory order)
        internal
        pure
        returns (bytes32 hash)
    {
        /* Per EIP 712. */
        // keccak256,abi.encode编码
        return keccak256(abi.encode(
            ORDER_TYPEHASH,
            order.registry,
            order.maker,
            order.staticTarget,
            order.staticSelector,
            keccak256(order.staticExtradata),
            order.maximumFill,
            order.listingTime,
            order.expirationTime,
            order.salt
        ));
    }

    // to订单购买者，签名
    function hashToSign(bytes32 orderHash)
        internal
        view
        returns (bytes32 hash)
    {
        /* Calculate the string a user must sign. */
        return keccak256(abi.encodePacked(
            "\x19\x01",
            DOMAIN_SEPARATOR,
            orderHash
        ));
    }

    function exists(address what)
        internal
        view
        returns (bool)
    {
        uint size;
        assembly {
            size := extcodesize(what)
        }
        return size > 0;
    }
 
    // 有效的订单参数
    function validateOrderParameters(Order memory order, bytes32 hash)
        internal
        view
        returns (bool)
    {
        /* Order must be listed and not be expired. */
        if (order.listingTime > block.timestamp || (order.expirationTime != 0 && order.expirationTime <= block.timestamp)) {
            return false;
        }

        /* Order must not have already been completely filled. */
        if (fills[order.maker][hash] >= order.maximumFill) {
            return false;
        }

        /* Order static target must exist. */
        if (!exists(order.staticTarget)) {
            return false;
        }

        return true;
    }
    
    // 有效的订单签名
    function validateOrderAuthorization(bytes32 hash, address maker, bytes memory signature)
        internal
        view
        returns (bool)
    {
        /* Memoized authentication. If order has already been partially filled, order must be authenticated. */
        if (fills[maker][hash] > 0) {
            return true;
        }

        /* Order authentication. Order must be either: */

        /* (a): sent by maker */
        if (maker == msg.sender) {
            return true;
        }

        /* (b): previously approved */
        if (approved[maker][hash]) {
            return true;
        }

        /* Calculate hash which must be signed. */
        bytes32 calculatedHashToSign = hashToSign(hash);

        /* Determine whether signer is a contract or account. */
        bool isContract = exists(maker);

        /* (c): Contract-only authentication: EIP/ERC 1271. */
        if (isContract) {
            if (ERC1271(maker).isValidSignature(calculatedHashToSign, signature) == EIP_1271_MAGICVALUE) {
                return true;
            }
            return false;
        }

        /* (d): Account-only authentication: ECDSA-signed by maker. */
        (uint8 v, bytes32 r, bytes32 s) = abi.decode(signature, (uint8, bytes32, bytes32));

        if (signature.length > 65 && signature[signature.length-1] == 0x03) { // EthSign byte
            /* (d.1): Old way: order hash signed by maker using the prefixed personal_sign */
            if (ecrecover(keccak256(abi.encodePacked(personalSignPrefix,"32",calculatedHashToSign)), v, r, s) == maker) {
                return true;
            }
        }
        /* (d.2): New way: order hash signed by maker using sign_typed_data */
        else if (ecrecover(calculatedHashToSign, v, r, s) == maker) {
            return true;
        }
        return false;
    }
    // 编码
    function encodeStaticCall(Order memory order, Call memory call, Order memory counterorder, Call memory countercall, address matcher, uint value, uint fill)
        internal
        pure
        returns (bytes memory)
    {
        /* This array wrapping is necessary to preserve static call target function stack space. */
        address[7] memory addresses = [order.registry, order.maker, call.target, counterorder.registry, counterorder.maker, countercall.target, matcher];
        AuthenticatedProxy.HowToCall[2] memory howToCalls = [call.howToCall, countercall.howToCall];
        uint[6] memory uints = [value, order.maximumFill, order.listingTime, order.expirationTime, counterorder.listingTime, fill];
        return abi.encodeWithSelector(order.staticSelector, order.staticExtradata, addresses, howToCalls, uints, call.data, countercall.data);
    }
    
    // 静态执行
    function executeStaticCall(Order memory order, Call memory call, Order memory counterorder, Call memory countercall, address matcher, uint value, uint fill)
        internal
        view
        returns (uint)
    {
        return staticCallUint(order.staticTarget, encodeStaticCall(order, call, counterorder, countercall, matcher, value, fill));
    }

    // 执行
    function executeCall(ProxyRegistryInterface registry, address maker, Call memory call)
        internal
        returns (bool)
    {
        /* Assert valid registry. */
        require(registries[address(registry)]);

        /* Assert target exists. */
        require(exists(call.target), "Call target does not exist");

        /* Retrieve delegate proxy contract. */
        OwnableDelegateProxy delegateProxy = registry.proxies(maker);

        /* Assert existence. */
        require(delegateProxy != OwnableDelegateProxy(0), "Delegate proxy does not exist for maker");

        /* Assert implementation. */
        require(delegateProxy.implementation() == registry.delegateProxyImplementation(), "Incorrect delegate proxy implementation for maker");

        /* Typecast. */
        AuthenticatedProxy proxy = AuthenticatedProxy(address(delegateProxy));

        /* Execute order. */
        return proxy.proxy(call.target, call.howToCall, call.data);
    }
    
    // 授权订单哈希
    function approveOrderHash(bytes32 hash)
        internal
    {
        /* CHECKS */

        /* Assert order has not already been approved. */
        require(!approved[msg.sender][hash], "Order has already been approved");

        /* EFFECTS */

        /* Mark order as approved. */
        approved[msg.sender][hash] = true;
    }

    // 订单授权
    function approveOrder(Order memory order, bool orderbookInclusionDesired)
        internal
    {
        /* CHECKS */

        /* Assert sender is authorized to approve order. */
        require(order.maker == msg.sender, "Sender is not the maker of the order and thus not authorized to approve it");

        /* Calculate order hash. */
        bytes32 hash = hashOrder(order);

        /* Approve order hash. */
        approveOrderHash(hash);

        /* Log approval event. */
        emit OrderApproved(hash, order.registry, order.maker, order.staticTarget, order.staticSelector, order.staticExtradata, order.maximumFill, order.listingTime, order.expirationTime, order.salt, orderbookInclusionDesired);
    }

    // 设置订单总量
    function setOrderFill(bytes32 hash, uint fill)
        internal
    {
        /* CHECKS */

        /* Assert fill is not already set. */
        require(fills[msg.sender][hash] != fill, "Fill is already set to the desired value");

        /* EFFECTS */

        /* Mark order as accordingly filled. */
        fills[msg.sender][hash] = fill;

        /* Log order fill change event. */
        emit OrderFillChanged(hash, msg.sender, fill);
    }

    // 自动匹配：secondOrder
    function atomicMatch(Order memory firstOrder, Call memory firstCall, Order memory secondOrder, Call memory secondCall, bytes memory signatures, bytes32 metadata)
        internal
        reentrancyGuard
    {
        /* CHECKS */

        /* Calculate first order hash. */
        bytes32 firstHash = hashOrder(firstOrder);

        /* Check first order validity. */
        require(validateOrderParameters(firstOrder, firstHash), "First order has invalid parameters");

        /* Calculate second order hash. */
        bytes32 secondHash = hashOrder(secondOrder);

        /* Check second order validity. */
        require(validateOrderParameters(secondOrder, secondHash), "Second order has invalid parameters");

        /* Prevent self-matching (possibly unnecessary, but safer). */
        require(firstHash != secondHash, "Self-matching orders is prohibited");

        {
            /* Calculate signatures (must be awkwardly decoded here due to stack size constraints). */
            (bytes memory firstSignature, bytes memory secondSignature) = abi.decode(signatures, (bytes, bytes));

            /* Check first order authorization. */
            require(validateOrderAuthorization(firstHash, firstOrder.maker, firstSignature), "First order failed authorization");

            /* Check second order authorization. */
            require(validateOrderAuthorization(secondHash, secondOrder.maker, secondSignature), "Second order failed authorization");
        }

        /* INTERACTIONS */

        /* Transfer any msg.value.
           This is the first "asymmetric" part of order matching: if an order requires Ether, it must be the first order. */
        if (msg.value > 0) {
            /* Reentrancy prevented by reentrancyGuard modifier */
            (bool success,) = address(uint160(firstOrder.maker)).call{value: msg.value}("");
            require(success, "native token transfer failed.");
        }

        /* Execute first call, assert success.
           This is the second "asymmetric" part of order matching: execution of the second order can depend on state changes in the first order, but not vice-versa. */
        require(executeCall(ProxyRegistryInterface(firstOrder.registry), firstOrder.maker, firstCall), "First call failed");

        /* Execute second call, assert success. */
        require(executeCall(ProxyRegistryInterface(secondOrder.registry), secondOrder.maker, secondCall), "Second call failed");

        /* Static calls must happen after the effectful calls so that they can check the resulting state. */

        /* Fetch previous first order fill. */
        uint previousFirstFill = fills[firstOrder.maker][firstHash];

        /* Fetch previous second order fill. */
        uint previousSecondFill = fills[secondOrder.maker][secondHash];

        /* Execute first order static call, assert success, capture returned new fill. */
        uint firstFill = executeStaticCall(firstOrder, firstCall, secondOrder, secondCall, msg.sender, msg.value, previousFirstFill);

        /* Execute second order static call, assert success, capture returned new fill. */
        uint secondFill = executeStaticCall(secondOrder, secondCall, firstOrder, firstCall, msg.sender, uint(0), previousSecondFill);

        /* EFFECTS */

        /* Update first order fill, if necessary. */
        if (firstOrder.maker != msg.sender) {
            if (firstFill != previousFirstFill) {
                fills[firstOrder.maker][firstHash] = firstFill;
            }
        }

        /* Update second order fill, if necessary. */
        if (secondOrder.maker != msg.sender) {
            if (secondFill != previousSecondFill) {
                fills[secondOrder.maker][secondHash] = secondFill;
            }
        }

        /* LOGS */

        /* Log match event. */
        emit OrdersMatched(firstHash, secondHash, firstOrder.maker, secondOrder.maker, firstFill, secondFill, metadata);
    }

}
