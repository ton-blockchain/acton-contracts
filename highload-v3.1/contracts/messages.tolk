const OP_INTERNAL_TRANSFER = 0xae42e5a4

struct (0xae42e5a4) InternalTransfer {
    queryId: uint64
    actions: cell // c5
}

struct MsgInner {
    subwalletId: uint32
    messageToSend: cell
    sendMode: uint8
    shift: uint13
    bitNumber: uint10
    createdAt: uint64
    timeout: uint22
}

struct ExternalTransferRequest {
    signature: bits512
    inner: Cell<MsgInner>
}
