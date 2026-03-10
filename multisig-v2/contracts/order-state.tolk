import "@stdlib/exotic-cells"
import "@gen/multisig_v2_order_code"

struct OrderInitData {
    multisigAddress: address
    orderSeqno: uint256
}

fun getOrderCodeAsLibraryReference(): cell {
    return multisigV2OrderCompiledCode().toLibraryReference();
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
