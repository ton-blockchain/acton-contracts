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

fun QueryBitmapMap.markProcessedInQueryMap(self, shift: uint13, bitNumber: int): (
    QueryBitmapMap, bool
) {
    var nextQueries = self;
    val lookup = nextQueries.get(shift);

    if (!lookup.isFound) {
        nextQueries.set(shift, Bitmap.build(bitNumber));
        return (nextQueries, true);
    }

    var valueSlice = lookup.loadValue().beginParse();
    val prefix = valueSlice.loadBits(bitNumber);

    if (valueSlice.preloadInt(1) != 0) {
        return (nextQueries, false);
    }

    valueSlice.skipBits(1);

    val newValue = beginCell().storeSlice(prefix).storeBool(true).storeSlice(valueSlice).endCell();

    nextQueries.set(shift, newValue);
    return (nextQueries, true);
}
