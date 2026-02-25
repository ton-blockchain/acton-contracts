import "errors"

const CELL_BITS_SIZE = 1023
const BIT_NUMBER_SIZE = 10

// SAFETY: single safe builder mutation
fun builder.storeZeroes(mutate self, len: int): self
    asm "STZEROES"

type Bitmap = cell

fun Bitmap.build(bitNumber: int): Bitmap {
    var b = beginCell();
    b.storeZeroes(bitNumber);
    b.storeBool(true);
    b.storeZeroes(CELL_BITS_SIZE - bitNumber - 1);
    return b.endCell();
}

type QueryBitmapMap = map<uint13, Bitmap>

fun QueryBitmapMap.isProcessedInQueryMap(self, shift: uint13, bitNumber: int): bool {
    val lookup = self.get(shift);
    if (!lookup.isFound) {
        return false;
    }

    var valueSlice = lookup.loadValue().beginParse();
    valueSlice.skipBits(bitNumber);
    return valueSlice.preloadInt(1) != 0;
}

fun QueryBitmapMap.markProcessed(self, shift: uint13, bitNumber: int): Bitmap {
    var nextQueries = self;
    val lookup = nextQueries.get(shift);

    var res: Bitmap;

    if (lookup.isFound) {
        var tail = lookup.loadValue().beginParse();
        val head = tail.loadBits(bitNumber);
        assert (!tail.loadBool()) throw ERROR_ALREADY_EXECUTED;
        res = beginCell().storeSlice(head).storeBool(true).storeSlice(tail).endCell();
    } else {
        res = Bitmap.build(bitNumber);
    }

    return res;
}
