import "errors"
import "types"

struct Storage {
    cfgDictRaw: cell
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

fun Storage.loadConfigDict(self): ConfigDict {
    return createMapFromLowLevelDict<int32, cell>(self.cfgDictRaw);
}

fun Storage.saveConfigDict(mutate self, cfgDict: ConfigDict) {
    val cfgDictRaw = cfgDict.toLowLevelDict();
    assert (cfgDictRaw != null) throw ERROR_EMPTY_CONFIG_DICT;
    self.cfgDictRaw = cfgDictRaw!;
}
