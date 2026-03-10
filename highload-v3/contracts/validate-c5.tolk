import "errors"

// SAFETY: we validate raw actions before setting them
fun setTvmRegisterC5(actions: cell): void
    asm "c5 POP"

struct CurrencyCollection {
    grams: coins
    other: map<int32, varuint32>
}

struct (0b0) IntMsgInfoRelaxed {
    ihrDisabled: bool
    bounce: bool
    bounced: bool
    src: any_address
    dest: address
    value: CurrencyCollection
    extraFlags: varuint16
    fwdFee: coins
    createdLt: uint64
    createdAt: uint32
}

type EitherBody = RemainingBitsAndRefs

// "body" is TL/B `(Either Cell ^Cell)`;
// we want to test, that if ^Cell, no other data exists in a slice
fun EitherBody.checkIsCorrectTlbEither(self) {
    var mutableCopy = self;
    if (mutableCopy.loadMaybeRef() != null) {
        // throw "cell underflow" if there is data besides a ref
        mutableCopy.assertEnd();
    }
}

struct MessageRelaxed {
    info: IntMsgInfoRelaxed
    maybeStateInit: bool
    body: EitherBody
}

fun validateMessageToSend(messageToSend: cell) {
    val msg = lazy MessageRelaxed.fromCell(
        messageToSend,
        { throwIfOpcodeDoesNotMatch: ERROR_INVALID_MESSAGE_TO_SEND },
    );

    var res: bool;

    if (msg.info.bounced) {
        res = false;
    } else {
        assert (msg.info.src.isNone()) throw ERROR_INVALID_MESSAGE_TO_SEND;
        assert (!msg.maybeStateInit) throw ERROR_INVALID_MESSAGE_TO_SEND;
        msg.body.checkIsCorrectTlbEither();

        res = true;
    }

    return res;
}
