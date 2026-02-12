import "errors"

const ONE_MONTH = 2592000
const ONE_YEAR = 31622400

const AUCTION_START_TIME = 1659171600
const AUCTION_START_DURATION = 604800
const AUCTION_END_DURATION = 3600
const AUCTION_PROLONGATION = 3600

const MIN_TONS_FOR_STORAGE = ton("1")
const ONE_TON = ton("1")

const DNS_NEXT_RESOLVER_PREFIX = 0xba93
const DNS_CONFIG_ID = 80

const OP_FILL_UP = 0x370fec51
const OP_OUTBID_NOTIFICATION = 0x557cea20
const OP_CHANGE_DNS_RECORD = 0x4eb1f0f9
const OP_PROCESS_GOVERNANCE_DECISION = 0x44beae41
const OP_DNS_BALANCE_RELEASE = 0x4ed14b65

const OP_TRANSFER = 0x5fcc3d14
const OP_OWNERSHIP_ASSIGNED = 0x05138d91
const OP_EXCESSES = 0xd53276db
const OP_GET_STATIC_DATA = 0x2fcb26a2
const OP_REPORT_STATIC_DATA = 0x8b771735
const OP_EDIT_CONTENT = 0x1a0b9d51

fun zeroAddress(): address? {
    return null;
}

fun forceBasechain(addr: address) {
    assert (addr.getWorkchain() == BASECHAIN) throw ERROR_WRONG_WORKCHAIN;
}

fun getTopDomainBits(mutate domain: slice): int {
    var bits = 0;
    var shouldStop = false;
    while (!shouldStop) {
        val ch = domain.loadUint(8);
        shouldStop = ch == 0;
        if (!shouldStop) {
            bits += 8;
        }
    }

    // Matches original FunC behavior/code.
    assert (bits > 0) throw ERROR_DOMAIN_TOO_LONG;
    return bits;
}

fun readDomainFromComment(mutate inMsgBody: slice): slice {
    var result = beginCell();
    var shouldStop = false;
    while (!shouldStop) {
        result.storeSlice(inMsgBody.loadBits(inMsgBody.remainingBitsCount()));
        val refsLen = inMsgBody.remainingRefsCount();
        shouldStop = refsLen == 0;

        if (!shouldStop) {
            assert (refsLen == 1) throw ERROR_DOMAIN_FORMAT_INVALID;
            inMsgBody = inMsgBody.loadRef().beginParse();
        }
    }

    return result.endCell().beginParse();
}

fun checkDomainString(mutate domain: slice): bool {
    var i = 0;
    val len = domain.remainingBitsCount();

    while (i < len) {
        val ch = domain.loadUint(8);
        val isHyphen = ch == 45;
        val valid =
            (isHyphen && i > 0 && i < len - 8)
            || (ch >= 48 && ch <= 57)
            || (ch >= 97 && ch <= 122);

        if (!valid) {
            return false;
        }

        i += 8;
    }

    return true;
}

fun getMinPriceConfig(domainCharCount: int): (int, int) {
    if (domainCharCount == 4) {
        return (1000, 100);
    }
    if (domainCharCount == 5) {
        return (500, 50);
    }
    if (domainCharCount == 6) {
        return (400, 40);
    }
    if (domainCharCount == 7) {
        return (300, 30);
    }
    if (domainCharCount == 8) {
        return (200, 20);
    }
    if (domainCharCount == 9) {
        return (100, 10);
    }
    if (domainCharCount == 10) {
        return (50, 5);
    }

    return (10, 1);
}

fun getMinPrice(domainBitsLength: int, nowTime: int): int {
    var (startMinPrice, endMinPrice) = getMinPriceConfig(domainBitsLength / 8);
    startMinPrice *= ONE_TON;
    endMinPrice *= ONE_TON;

    val seconds = nowTime - AUCTION_START_TIME;
    val months = seconds / ONE_MONTH;
    if (months > 21) {
        return endMinPrice;
    }

    repeat (months) {
        startMinPrice = startMinPrice * 90 / 100;
    }

    return startMinPrice;
}
