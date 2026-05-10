import "@gen/Order.code"

struct OrderInitData {
    multisigAddress: address
    orderSeqno: uint256
}

fun getOrderCodeAsLibraryReference(): cell {
    return orderCompiledCodeLibraryRef();
}

fun calculateOrderStateInit(multisigAddress: address, orderSeqno: uint256): AutoDeployAddress {
    return {
        stateInit: ContractState {
            code: getOrderCodeAsLibraryReference(),
            data: OrderInitData { multisigAddress, orderSeqno }.toCell(),
        },
        workchain: BASECHAIN,
    };
}

fun calculateOrderAddress(multisigAddress: address, orderSeqno: uint256): address {
    return calculateOrderStateInit(multisigAddress, orderSeqno).calculateAddress();
}
