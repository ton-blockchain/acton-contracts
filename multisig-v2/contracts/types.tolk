import "errors"

const MAX_ORDER_SEQNO = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff

type IndexedAddressMap = map<uint8, address>

type DirectIndexedAddressMap = map<uint8, address>
type DirectOrderActionsMap = map<uint8, cell>

fun DirectIndexedAddressMap.packToBuilder(self, mutate b: builder) {
    val dictRoot = self.toLowLevelDict();
    b.storeRef(dictRoot!);
}

fun DirectIndexedAddressMap.unpackFromSlice(mutate s: slice): DirectIndexedAddressMap {
    return createMapFromLowLevelDict<uint8, address>(s.loadRef());
}

fun DirectOrderActionsMap.packToBuilder(self, mutate b: builder) {
    val dictRoot = self.toLowLevelDict();
    b.storeRef(dictRoot!);
}

fun DirectOrderActionsMap.unpackFromSlice(mutate s: slice): DirectOrderActionsMap {
    return createMapFromLowLevelDict<uint8, cell>(s.loadRef());
}

@inline
fun validateDictionarySequence<T>(m: map<uint8, T>): int {
    var expectedIndex = 0;

    var item = m.findFirst();
    while (item.isFound) {
        assert (item.getKey() == expectedIndex) throw ERROR_INVALID_DICTIONARY_SEQUENCE;
        expectedIndex += 1;
        item = m.iterateNext(item);
    }

    return expectedIndex;
}

fun DirectIndexedAddressMap.hashCell(self): uint256 {
    return self.toLowLevelDict()!.hash();
}

fun DirectOrderActionsMap.hashCell(self): uint256 {
    return self.toLowLevelDict()!.hash();
}
