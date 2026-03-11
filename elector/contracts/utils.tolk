import "@stdlib/reflection"
import "types"

fun returnStake(to: address, queryId: uint64, reason: uint32): void {
    val returnMsg = createMessage({
        dest: to,
        bounce: BounceMode.Only256BitsOfBody,
        value: 0,
        body: ReturnMsg {
            op: 0xee6f454c,
            queryId,
            reason,
        },
    });
    returnMsg.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
}

fun sendMessageBack(to: address, ansTag: uint32, queryId: uint64, body: uint32, value: coins, mode: int): void {
    val returnMsg = createMessage({
        dest: to,
        bounce: BounceMode.Only256BitsOfBody,
        value,
        body: ReturnMsg {
            op: ansTag,
            queryId,
            reason: body,
        },
    });
    returnMsg.send(mode);
}

fun sendConfirmation(to: address, queryId: uint64, comment: uint32): void {
    val returnMsg = createMessage({
        dest: to,
        bounce: BounceMode.Only256BitsOfBody,
        value: ton("1"),
        body: ReturnMsg {
            op: 0xf374484c,
            queryId,
            reason: comment,
        },
    });
    returnMsg.send(SEND_MODE_IGNORE_ERRORS);
}

struct(0x4e565354) VSetWithOpcode {
    queryId: uint64;
    vset: Cell<VSet>
}

fun sendValidatorSetToConfig(configAddHashPart: uint256, vset: VSet, queryId: uint64) {
    val configAddr = beginCell()
        .storeUint(4, 3) // addr_std$10 anycast:(Maybe Anycast)
        .storeInt(-1, 8) // workchain_id:int8
        .storeUint(configAddHashPart, 256);

    val returnMsg = createMessage({
        dest: configAddr,
        bounce: BounceMode.Only256BitsOfBody,
        value: 1 << 30, // Approximately 1 TON
        body: VSetWithOpcode {
            queryId,
            vset: vset.toCell(),
        }
    });
    returnMsg.send(SEND_MODE_PAY_FEES_SEPARATELY);
}


fun InMessage.value(): coins asm "INMSG_VALUE";
fun InMessage.source(): address asm "INMSG_SRC";
fun T.getDeclaredPackPrefix(): int {
    return reflect.serializationPrefixOf<T>();
}