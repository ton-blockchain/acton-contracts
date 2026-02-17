import "errors"

const ONE_MONTH = 60 * 60 * 24 * 30
const ONE_YEAR = 60 * 60 * 24 * 366

const AUCTION_START_TIME = 1659171600 // GMT: Monday, 30 July 2022 г., 09:00:00
const AUCTION_START_DURATION = 60 * 60 * 24 * 7
const AUCTION_END_DURATION = 60 * 60
const AUCTION_PROLONGATION = 60 * 60

const MIN_TONS_FOR_STORAGE = ton("1")
const ONE_TON = ton("1")

// https://github.com/ton-blockchain/ton/blob/7e3df93ca2ab336716a230fceb1726d81bac0a06/crypto/block/block.tlb#L819
const DNS_NEXT_RESOLVER_PREFIX = 0xba93
const BYTE_SIZE = 8
const DNS_CONFIG_ID = 80

const TON_WWW_DOMAIN_SIZE = 8 // "ton.www" (6) + 2 null-encoding symbols
const TON_DOMAIN_SIZE = 4 // "ton" (3) + 1 null-encoding symbol
const TELEGRAM_DOMAIN_SIZE = 5 // "t.me" (3) + 2 null-encoding symbols
const MIN_DOMAIN_SIZE = 3
const MAX_DOMAIN_SIZE = 126

fun address.toNextResolver(self) {
    return beginCell().storeUint(DNS_NEXT_RESOLVER_PREFIX, 16).storeAddress(self).endCell();
}

// Snake-like domain in remaining bits/refs.
// "ab".ref("cd").ref("ef") -> "abcdef"
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

    return result.toSlice();
}

// "ton\0test\0" -> "ton"
fun getTopDomainBits(domain: slice): int {
    var bytes = domain;

    var bits = 0;
    var shouldStop = false;

    while (!shouldStop) {
        // we do not check domain.length because it MUST contains \0 character
        val ch = bytes.loadUint(BYTE_SIZE);

        shouldStop = ch == 0;

        if (!shouldStop) {
            bits += BYTE_SIZE;
        }
    }

    // matches original FunC exit code
    assert (bits > 0) throw ERROR_DOMAIN_TOO_LONG;
    return bits;
}

enum DomainChar {
    Hyphen = 45 // ASCII '-': allowed only inside a label, not as the first/last checked char.,,,
    DigitZero = 48 // ASCII '0': lower bound for allowed digits,,,
    DigitNine = 57 // ASCII '9': upper bound for allowed digits,,,
    LowercaseA = 97 // ASCII 'a': lower bound for allowed lowercase letters,,,
    LowercaseZ = 122 // ASCII 'z': upper bound for allowed lowercase letters,,,
}

fun checkDomainString(domain: slice, len: int): bool {
    var bytes = domain;
    var i = 0;

    while (i < len) {
        val ch = bytes.loadUint(BYTE_SIZE);

        // it is safe to use casts, since we are only casting to compare
        val isHyphen = ch == (DomainChar.Hyphen as int);
        val isDigit = ch >= (DomainChar.DigitZero as int) && ch <= (DomainChar.DigitNine as int);

        val isLowercaseLetter = ch >= (DomainChar.LowercaseA as int) &&
        ch <= (DomainChar.LowercaseZ as int);
        val isInnerHyphen = isHyphen && i > 0 && i < len - BYTE_SIZE;

        val valid = isInnerHyphen || isDigit || isLowercaseLetter;
        if (!valid) {
            return false;
        }

        i += BYTE_SIZE;
    }

    return true;
}

struct MinPriceConfig {
    startMinPrice: int
    endMinPrice: int
}

fun getMinPriceConfig(domainCharCount: int): MinPriceConfig {
    if (domainCharCount == 4) {
        return { startMinPrice: 1000, endMinPrice: 100 };
    }
    if (domainCharCount == 5) {
        return { startMinPrice: 500, endMinPrice: 50 };
    }
    if (domainCharCount == 6) {
        return { startMinPrice: 400, endMinPrice: 40 };
    }
    if (domainCharCount == 7) {
        return { startMinPrice: 300, endMinPrice: 30 };
    }
    if (domainCharCount == 8) {
        return { startMinPrice: 200, endMinPrice: 20 };
    }
    if (domainCharCount == 9) {
        return { startMinPrice: 100, endMinPrice: 10 };
    }
    if (domainCharCount == 10) {
        return { startMinPrice: 50, endMinPrice: 5 };
    }

    return { startMinPrice: 10, endMinPrice: 1 };
}

fun getMinPrice(domainBitsLength: int, nowTime: int): int {
    val config = getMinPriceConfig(domainBitsLength / BYTE_SIZE);
    var startMinPrice = config.startMinPrice * ONE_TON;
    val endMinPrice = config.endMinPrice * ONE_TON;

    val seconds = nowTime - AUCTION_START_TIME;
    val months = seconds / ONE_MONTH;

    if (months > 21) {
        return endMinPrice;
    }

    repeat (months) {
        // -10% each passing month
        startMinPrice = startMinPrice * 90 / 100;
    }

    return startMinPrice;
}
