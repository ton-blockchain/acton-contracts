import "@acton/build"
import "@acton/emulation/network"
import "@acton/testing/assert"
import "Multisig.gen"
import "Order.gen"
import "../contracts/messages"
import "../contracts/storage"
import "../contracts/types"

fun toDirectIndexedAddressMap(addresses: array<address>): DirectIndexedAddressMap {
    var result: DirectIndexedAddressMap = [];
    var i = 0;
    while (i < addresses.size()) {
        result.set(i, addresses.get(i));
        i += 1;
    }
    return result;
}

fun toIndexedAddressMap(addresses: array<address>): IndexedAddressMap {
    var result: IndexedAddressMap = [];
    var i = 0;
    while (i < addresses.size()) {
        result.set(i, addresses.get(i));
        i += 1;
    }
    return result;
}

fun Multisig.fromConfig(
    threshold: int,
    signers: array<address>,
    proposers: array<address>,
    allowArbitraryOrderSeqno: bool = false,
    nextOrderSeqno: int = 0,
): Multisig {
    assert (signers.size() > 0) throw 7001;
    assert (threshold > 0) throw 7002;
    assert (threshold <= signers.size()) throw 7003;

    val storage: MultisigStorage = {
        nextOrderSeqno: nextOrderSeqno as uint256,
        threshold: threshold as uint8,
        signers: toDirectIndexedAddressMap(signers),
        signersNum: signers.size(),
        proposers: toIndexedAddressMap(proposers),
        allowArbitraryOrderSeqno,
    };
    return Multisig.fromStorage(storage);
}

fun Multisig.deployWithInitBody(self, from: address, config: SendParams = {}): SendResultList {
    if (self.stateInit == null) {
        Assert.fail("Cannot deploy contract created from address only");
    }

    val deployMessage = createMessage({
        bounce: config.bounce,
        value: config.value,
        dest: { stateInit: self.stateInit! },
        body: beginCell().storeUint(0, 32).storeUint(0, 64).endCell(),
    });
    return net.send(from, deployMessage);
}

fun Multisig.sendNewOrder(
    self,
    from: address,
    order: DirectOrderActionsMap,
    expirationDate: int,
    isAutoApprove: bool,
    index: int,
    orderSeqno: uint256 = MAX_ORDER_SEQNO,
    queryId: uint64 = 0,
    config: SendParams = {},
): SendResultList {
    return self.sendNewOrderRequest(
        from,
        queryId,
        orderSeqno,
        isAutoApprove,
        index as uint8,
        expirationDate as uint48,
        order,
        config,
    );
}

fun Multisig.sendExecuteInternal(
    self,
    from: address,
    order: DirectOrderActionsMap,
    queryId: uint64 = 0,
    config: SendParams = {},
): SendResultList {
    return self.sendExecuteInternalRequest(from, queryId, order, config);
}

fun Multisig.getData(self): MultisigDataReply {
    return self.getMultisigData();
}

fun Multisig.getOrderEstimateForOrder(
    self,
    order: DirectOrderActionsMap,
    expirationDate: int,
): int {
    return self.getOrderEstimate(order.toCell(), expirationDate);
}

fun MultisigDataReply.signersMap(self): DirectIndexedAddressMap {
    return createMapFromLowLevelDict<uint8, address>(self.signers);
}

fun MultisigDataReply.proposersMap(self): IndexedAddressMap {
    if (self.proposers == null) {
        return [];
    }
    return createMapFromLowLevelDict<uint8, address>(self.proposers!);
}

struct OrderInitData {
    multisigAddress: address
    orderSeqno: uint256
}

fun Order.fromConfig(
    multisigAddress: address,
    orderSeqno: uint256,
    toShard: AddressShardingOptions? = null,
): Order {
    val stateInit = ContractState {
        code: build("Order"),
        data: OrderInitData { multisigAddress, orderSeqno }.toCell(),
    };

    val address = AutoDeployAddress { stateInit, toShard }.calculateAddress();

    return Order { address, stateInit };
}

fun Order.deployWithInit(
    self,
    from: address,
    threshold: int,
    signers: DirectIndexedAddressMap,
    expirationDate: int,
    order: DirectOrderActionsMap,
    signerIndexOnInit: SignerIndexOnInit = null,
    queryId: uint64 = 0,
    config: SendParams = {},
): SendResultList {
    if (self.stateInit == null) {
        Assert.fail("Cannot deploy contract created from address only");
    }

    val initOrderDeployMessage = createMessage({
        bounce: config.bounce,
        value: config.value,
        dest: { stateInit: self.stateInit! },
        body: InitOrderRequest {
            queryId,
            threshold: threshold as uint8,
            signers,
            expirationDate: expirationDate as uint48,
            order,
            signerIndexOnInit,
        },
    });
    return net.send(from, initOrderDeployMessage);
}

fun Order.sendInit(
    self,
    from: address,
    threshold: int,
    signers: DirectIndexedAddressMap,
    expirationDate: int,
    order: DirectOrderActionsMap,
    signerIndexOnInit: SignerIndexOnInit = null,
    queryId: uint64 = 0,
    config: SendParams = {},
): SendResultList {
    return self.sendInitOrderRequest(
        from,
        queryId,
        threshold as uint8,
        signers,
        expirationDate as uint48,
        order,
        signerIndexOnInit,
        config,
    );
}

fun Order.sendApprove(
    self,
    from: address,
    signerIndex: int,
    queryId: uint64 = 0,
    config: SendParams = {},
): SendResultList {
    return self.sendApproveRequest(from, queryId, signerIndex as uint8, config);
}

fun Order.sendComment(
    self,
    from: address,
    comment: RemainingBitsAndRefs,
    config: SendParams = {},
): SendResultList {
    return self.sendTextComment(from, comment, config);
}

fun Order.getData(self): OrderDataReply {
    return self.getOrderData();
}

fun OrderDataReply.isInitialized(self): bool {
    return self.threshold != null;
}

fun OrderDataReply.signersMap(self): DirectIndexedAddressMap {
    if (self.signers == null) {
        return [];
    }
    return createMapFromLowLevelDict<uint8, address>(self.signers!);
}

fun OrderDataReply.orderMap(self): DirectOrderActionsMap {
    if (self.order == null) {
        return [];
    }
    return createMapFromLowLevelDict<uint8, cell>(self.order!);
}
