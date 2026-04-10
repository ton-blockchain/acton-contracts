import "@acton/build/build"
import "@acton/emulation/network"
import "@acton/testing/assert"
import "../../contracts/messages"
import "../../contracts/types"

struct OrderInitData {
    multisigAddress: address
    orderSeqno: uint256
}

struct MultisigV2Order {
    address: address
    stateInit: ContractState? = null
}

struct OrderDataReply {
    multisigAddress: address
    orderSeqno: int
    threshold: int?
    sentForExecution: bool?
    signers: dict
    approvalsMask: int?
    approvalsNum: int?
    expirationDate: int?
    order: dict
}

fun MultisigV2Order.fromConfig(
    multisigAddress: address,
    orderSeqno: uint256,
    toShard: AddressShardingOptions? = null,
) {
    val stateInit = ContractState {
        code: build("Order"),
        data: OrderInitData { multisigAddress, orderSeqno }.toCell(),
    };

    val address = toShard == null
        ? AutoDeployAddress { stateInit }.calculateAddress()
        : AutoDeployAddress { stateInit, toShard }.calculateAddress();

    return MultisigV2Order { address, stateInit };
}

fun MultisigV2Order.fromAddress(address: address) {
    return MultisigV2Order { address };
}

fun MultisigV2Order.deployWithInit(
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

fun MultisigV2Order.sendInit(
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
    val initOrderMessage = createMessage({
        bounce: config.bounce,
        value: config.value,
        dest: self.address,
        body: InitOrderRequest {
            queryId,
            threshold: threshold as uint8,
            signers,
            expirationDate: expirationDate as uint48,
            order,
            signerIndexOnInit,
        },
    });
    return net.send(from, initOrderMessage);
}

fun MultisigV2Order.sendApprove(
    self,
    from: address,
    signerIndex: int,
    queryId: uint64 = 0,
    config: SendParams = {},
): SendResultList {
    val approveMessage = createMessage({
        bounce: config.bounce,
        value: config.value,
        dest: self.address,
        body: ApproveRequest {
            queryId,
            signerIndex: signerIndex as uint8,
        },
    });
    return net.send(from, approveMessage);
}

fun MultisigV2Order.sendComment(
    self,
    from: address,
    comment: RemainingBitsAndRefs,
    config: SendParams = {},
): SendResultList {
    val commentMessage = createMessage({
        bounce: config.bounce,
        value: config.value,
        dest: self.address,
        body: TextComment { comment },
    });
    return net.send(from, commentMessage);
}

fun MultisigV2Order.sendAny(
    self,
    from: address,
    body: cell,
    config: SendParams = {},
): SendResultList {
    val customBodyMessage = createMessage({
        bounce: config.bounce,
        value: config.value,
        dest: self.address,
        body,
    });
    return net.send(from, customBodyMessage);
}

fun MultisigV2Order.getData(self): OrderDataReply {
    return net.runGetMethod(self.address, "get_order_data");
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
