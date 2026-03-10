import "@acton/build/build"
import "@acton/emulation/network"
import "@acton/testing/assert"
import "../../contracts/messages"
import "../../contracts/storage"
import "../../contracts/types"

struct MultisigV2 {
    address: address
    stateInit: ContractState? = null
}

struct MultisigDataReply {
    nextOrderSeqno: int
    threshold: int
    signers: dict
    proposers: dict
}

fun toDirectIndexedAddressMap(addresses: array<address>): DirectIndexedAddressMap {
    var result: DirectIndexedAddressMap = [];
    var i = 0;
    while (i < addresses.size()) {
        result.set(i as uint8, addresses.get(i));
        i += 1;
    }
    return result;
}

fun toIndexedAddressMap(addresses: array<address>): IndexedAddressMap {
    var result: IndexedAddressMap = [];
    var i = 0;
    while (i < addresses.size()) {
        result.set(i as uint8, addresses.get(i));
        i += 1;
    }
    return result;
}

fun MultisigV2.fromStorage(storage: MultisigStorage, toShard: AddressShardingOptions? = null) {
    val stateInit = ContractState {
        code: build("multisig_v2"),
        data: storage.toCell(),
    };

    val address = toShard == null
        ? AutoDeployAddress { stateInit }.calculateAddress()
        : AutoDeployAddress { stateInit, toShard }.calculateAddress();

    return MultisigV2 { address, stateInit };
}

fun MultisigV2.fromConfig(
    threshold: int,
    signers: array<address>,
    proposers: array<address>,
    allowArbitraryOrderSeqno: bool = false,
    nextOrderSeqno: int = 0,
) {
    assert (signers.size() > 0) throw 7001;
    assert (threshold > 0) throw 7002;
    assert (threshold <= signers.size()) throw 7003;

    val storage: MultisigStorage = {
        nextOrderSeqno: nextOrderSeqno as uint256,
        threshold: threshold as uint8,
        signers: toDirectIndexedAddressMap(signers),
        signersNum: signers.size() as uint8,
        proposers: toIndexedAddressMap(proposers),
        allowArbitraryOrderSeqno,
    };
    return MultisigV2.fromStorage(storage);
}

fun MultisigV2.fromAddress(address: address) {
    return MultisigV2 { address };
}

fun MultisigV2.deploy(self, from: address, config: SendParams = {}): SendResultList {
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

fun MultisigV2.sendAny(self, from: address, body: cell, config: SendParams = {}): SendResultList {
    val customBodyMessage = createMessage({
        bounce: config.bounce,
        value: config.value,
        dest: self.address,
        body,
    });
    return net.send(from, customBodyMessage);
}

fun MultisigV2.sendNewOrder(
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
    val newOrderMessage = createMessage({
        bounce: config.bounce,
        value: config.value,
        dest: self.address,
        body: NewOrderRequest {
            queryId,
            orderSeqno,
            isAutoApprove,
            index: index as uint8,
            expirationDate: expirationDate as uint48,
            order,
        },
    });
    return net.send(from, newOrderMessage);
}

fun MultisigV2.sendExecuteInternal(
    self,
    from: address,
    order: DirectOrderActionsMap,
    queryId: uint64 = 0,
    config: SendParams = {},
): SendResultList {
    val executeInternalMessage = createMessage({
        bounce: config.bounce,
        value: config.value,
        dest: self.address,
        body: ExecuteInternalRequest { queryId, order },
    });
    return net.send(from, executeInternalMessage);
}

fun MultisigV2.getData(self): MultisigDataReply {
    return net.runGetMethod(self.address, "get_multisig_data");
}

fun MultisigV2.getOrderAddress(self, orderSeqno: int): address {
    return net.runGetMethod(self.address, "get_order_address", orderSeqno);
}

fun MultisigV2.getOrderEstimate(self, order: DirectOrderActionsMap, expirationDate: int): int {
    return net.runGetMethod(
        self.address,
        "get_order_estimate",
        [order.toCell(), expirationDate] as tuple,
    );
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
