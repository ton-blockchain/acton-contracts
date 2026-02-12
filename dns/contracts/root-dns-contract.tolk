import "constants"
import "errors"
import "storage"
import "messages"

fun makeNextResolver(addr: address): cell {
    return DnsNextResolver { resolver: addr }.toCell();
}

fun onInternalMessage(in: InMessage) {
    // Root contract accepts internal messages as top-ups and keeps storage untouched.
}

fun onBouncedMessage(in: InMessageBounced) {
    // Ignore bounced messages.
}

get fun dnsresolve(subdomain: slice, category: int): (int, cell?) {
    assert (subdomain.remainingBitsCount() % 8 == 0) throw ERROR_DNS_INVALID_SUBDOMAIN_BITS;

    val startsWithZeroByte = subdomain.preloadInt(8) == 0;
    val subdomainLen = subdomain.remainingBitsCount();

    if (startsWithZeroByte && subdomainLen == 8) {
        return (8, null);
    }
    if (startsWithZeroByte) {
        subdomain.loadUint(8);
    }

    val st = RootDnsStorage.load();

    val tonWwwDomain = beginCell().storeSlice("ton".literalSlice()).storeUint(0, 8).storeSlice(
        "www".literalSlice()
    ).storeUint(0, 8).endCell().beginParse();

    if (subdomainLen >= 8 * 8) {
        if (subdomain.preloadBits(8 * 8).hash() == tonWwwDomain.hash()) {
            return (7 * 8 + (startsWithZeroByte ? 8 : 0), makeNextResolver(st.tonWwwAddress));
        }
    }

    val tonDomain = beginCell().storeSlice("ton".literalSlice()).storeUint(0, 8).endCell()
        .beginParse();

    if (subdomainLen >= 4 * 8) {
        if (subdomain.preloadBits(4 * 8).hash() == tonDomain.hash()) {
            return (3 * 8 + (startsWithZeroByte ? 8 : 0), makeNextResolver(st.tonAddress));
        }
    }

    val tMeDomain = beginCell().storeSlice("me".literalSlice()).storeUint(0, 8).storeSlice(
        "t".literalSlice()
    ).storeUint(0, 8).endCell().beginParse();

    if (subdomainLen >= 5 * 8) {
        if (subdomain.preloadBits(5 * 8).hash() == tMeDomain.hash()) {
            return (4 * 8 + (startsWithZeroByte ? 8 : 0), makeNextResolver(st.tMeAddress));
        }
    }

    return (0, null);
}
