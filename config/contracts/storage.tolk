const CUSTOM_PARAM_1 = -1024
const CUSTOM_PARAM_2 = -1025

const ADMIN_ADDRESS_FOR_CUSTOM_PARAMS = address("EQA_o6NFLu73wozeYNERTsW8lkU5OarbRbIkoNuWdy5SPDA_")

type ConfigDict = map<int32, cell>

type VoteDict = map<uint256, slice>

type VotersDict = map<uint16, uint32>

fun ConfigDict.getById(self, index: int32): cell? {
    val lookup = self.get(index);

    if (!lookup.isFound) {
        return null;
    }

    return lookup.loadValue();
}

// TODO: replace
fun ConfigDict.setById(mutate self, index: int32, value: cell) {
    self.set(index, value);
}

fun ConfigDict.setByIdAndGetPrevious(mutate self, index: int32, value: cell): cell? {
    val previous = self.setAndGetPrevious(index, value);

    if (!previous.isFound) {
        return null;
    }

    return previous.loadValue();
}

fun ConfigDict.deleteById(mutate self, index: int32) {
    self.delete(index);
}

fun ConfigDict.packToBuilder(self, mutate b: builder) {
    val dictRoot = self.toLowLevelDict();
    // TODO? 
    // assert (dictRoot != null) throw ERROR_EMPTY_CONFIG_DICT;
    b.storeRef(dictRoot!);
}

fun ConfigDict.unpackFromSlice(mutate s: slice): ConfigDict {
    return createMapFromLowLevelDict(s.loadRef());
}

struct Storage {
    config: ConfigDict
    storedSeqno: uint32
    publicKey: uint256
    voteDict: VoteDict
}

fun Storage.load(): Storage {
    return Storage.fromCell(contract.getData());
}

fun Storage.save(self) {
    contract.setData(self.toCell());
}

fun Storage.setConfigParam(index: int, value: cell) {
    var storage = lazy Storage.load();

    storage.config.setById(index, value);
    storage.save();
}
