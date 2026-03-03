import "errors"

const TIMESTAMP_SIZE = 48
const HASH_SIZE = 256

const INDEX_SIZE = 8
const ACTION_INDEX_SIZE = 8
const MASK_SIZE = 1 << INDEX_SIZE

const ORDER_SEQNO_SIZE = 256
const MAX_ORDER_SEQNO = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff

type IndexedAddressMap = map<uint8, address>
type OrderActionsMap = map<uint8, cell>

type NonEmptyIndexedAddressMap = map<uint8, address>
type NonEmptyOrderActionsMap = map<uint8, cell>

fun NonEmptyIndexedAddressMap.packToBuilder(self, mutate b: builder) {
    val dictRoot = self.toLowLevelDict();
    assert (dictRoot != null) throw ERROR_INVALID_SIGNERS;
    b.storeRef(dictRoot);
}

fun NonEmptyIndexedAddressMap.unpackFromSlice(mutate s: slice): NonEmptyIndexedAddressMap {
    return createMapFromLowLevelDict<uint8, address>(s.loadRef());
}

fun NonEmptyOrderActionsMap.packToBuilder(self, mutate b: builder) {
    val dictRoot = self.toLowLevelDict();
    assert (dictRoot != null) throw ERROR_INVALID_DICTIONARY_SEQUENCE;
    b.storeRef(dictRoot!);
}

fun NonEmptyOrderActionsMap.unpackFromSlice(mutate s: slice): NonEmptyOrderActionsMap {
    return createMapFromLowLevelDict<uint8, cell>(s.loadRef());
}

fun validateDictionarySequence<T>(m: map<uint8, T>): int {
    var expectedIndex = 0;

    var item = m.findFirst();
    while (item.isFound) {
        assert (item.getKey() == expectedIndex as uint8) throw ERROR_INVALID_DICTIONARY_SEQUENCE;
        expectedIndex += 1;
        item = m.iterateNext(item);
    }

    return expectedIndex;
}

fun NonEmptyIndexedAddressMap.hashCell(self): uint256 {
    return self.toLowLevelDict()!.hash();
}

fun NonEmptyOrderActionsMap.hashCell(self): uint256 {
    return self.toLowLevelDict()!.hash();
}
