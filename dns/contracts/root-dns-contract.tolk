import "errors"
import "storage"
import "dns-utils"

fun getPrefixLengthByDomain(domainLength: int, startsWithZeroByte: bool) {
    return (domainLength - 1) * BYTE_SIZE + (startsWithZeroByte ? BYTE_SIZE : 0);
}

fun onInternalMessage(_in: InMessage) {
    // do nothing
}

get fun dnsresolve(subdomain: slice, _category: int): DnsResolveResponse {
    assert (subdomain.remainingBitsCount() % BYTE_SIZE == 0) throw ERROR_DNS_INVALID_SUBDOMAIN_BITS;

    val startsWithZeroByte = subdomain.preloadInt(BYTE_SIZE) == 0;
    val subdomainLengthInBits = subdomain.remainingBitsCount();

    // "." is resolved, without dns record
    if (startsWithZeroByte && subdomainLengthInBits == BYTE_SIZE) {
        return {
            resolvedPrefixLengthBits: BYTE_SIZE,
            resolvedRecord: null,
        };
    }

    if (startsWithZeroByte) {
        subdomain.skipBits(BYTE_SIZE);
    }

    val rootStorage = lazy RootDnsStorage.fromCell(contract.getData());

    // TODO: discuss null-encoding, prefetched bytes
    // val wwwDomainBuilder = StringBuilder.create();
    // wwwDomainBuilder.append("ton");

    val tonWwwDomain = beginCell()
        .storeSlice("ton".literalSlice()).storeUint(0, BYTE_SIZE)
        .storeSlice("www".literalSlice()).storeUint(0, BYTE_SIZE)
        .toSlice();

    if (subdomainLengthInBits >= TON_WWW_DOMAIN_SIZE * BYTE_SIZE) {
        if (subdomain.preloadBits(TON_WWW_DOMAIN_SIZE * BYTE_SIZE).bitsEqual(tonWwwDomain)) {
            
            return {
                resolvedPrefixLengthBits: getPrefixLengthByDomain(TON_WWW_DOMAIN_SIZE, startsWithZeroByte),
                resolvedRecord: rootStorage.tonWwwAddress.toNextResolver()
            };
        }
    }

    val tonDomain = beginCell()
        .storeSlice("ton".literalSlice()).storeUint(0, BYTE_SIZE)
        .toSlice();

    if (subdomainLengthInBits >= TON_DOMAIN_SIZE * BYTE_SIZE) {
        if (subdomain.preloadBits(TON_DOMAIN_SIZE * BYTE_SIZE).bitsEqual(tonDomain)) {
            return {
                resolvedPrefixLengthBits: getPrefixLengthByDomain(TON_DOMAIN_SIZE, startsWithZeroByte),
                resolvedRecord: rootStorage.tonAddress.toNextResolver(),
            };
        }
    }

    val tMeDomain = beginCell()
        .storeSlice("me".literalSlice()).storeUint(0, BYTE_SIZE)
        .storeSlice("t".literalSlice()).storeUint(0, BYTE_SIZE)
        .toSlice();

    if (subdomainLengthInBits >= TELEGRAM_DOMAIN_SIZE * BYTE_SIZE) {
        if (subdomain.preloadBits(TELEGRAM_DOMAIN_SIZE * BYTE_SIZE).bitsEqual(tMeDomain)) {
            return {
                resolvedPrefixLengthBits: getPrefixLengthByDomain(TELEGRAM_DOMAIN_SIZE, startsWithZeroByte),
                resolvedRecord: rootStorage.tMeAddress.toNextResolver(),
            };
        }
    }

    return {
        resolvedPrefixLengthBits: 0,
        resolvedRecord: null,
    };
}
