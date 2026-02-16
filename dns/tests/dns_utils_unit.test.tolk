import "@acton/emulation/network"
import "@acton/testing/expect"
import "../contracts/dns-utils"
import "../contracts/messages"

get fun `test dns-utils: readDomainFromComment concatenates snake-like chunks`() {
    val tail = beginCell().storeSlice("ce".beginParse()).endCell();
    var payload = beginCell().storeSlice("ali".beginParse()).storeRef(tail).endCell().beginParse();

    val parsed = readDomainFromComment(mutate payload);
    expect(parsed.bitsEqual("alice".beginParse())).toEqual(true);
}

get fun `test dns-utils: checkDomainString validates charset and hyphen placement`() {
    val valid = "abc-123".beginParse();
    expect(checkDomainString(valid, valid.remainingBitsCount())).toEqual(true);

    val uppercase = "aLice".beginParse();
    expect(checkDomainString(uppercase, uppercase.remainingBitsCount())).toEqual(false);

    val startsWithHyphen = "-alice".beginParse();
    expect(checkDomainString(startsWithHyphen, startsWithHyphen.remainingBitsCount())).toEqual(false);

    val endsWithHyphen = "alice-".beginParse();
    expect(checkDomainString(endsWithHyphen, endsWithHyphen.remainingBitsCount())).toEqual(false);
}

get fun `test dns-utils: getTopDomainBits stops at first zero-byte separator`() {
    val encoded = beginCell().storeSlice("alice".literalSlice()).storeUint(0, BYTE_SIZE).storeSlice("sub"
        .literalSlice())
        .storeUint(0, BYTE_SIZE)
        .endCell()
        .beginParse();

    expect(getTopDomainBits(encoded)).toEqual(5 * BYTE_SIZE);
}

get fun `test dns-utils: getMinPrice decays monthly and reaches floor`() {
    val start4 = getMinPrice(4 * BYTE_SIZE, AUCTION_START_TIME + 1);
    val month4 = getMinPrice(4 * BYTE_SIZE, AUCTION_START_TIME + ONE_MONTH + 1);
    val floor4 = getMinPrice(4 * BYTE_SIZE, AUCTION_START_TIME + 24 * ONE_MONTH);

    expect(start4).toEqual(1000 * ONE_TON);
    expect(month4).toEqual(900 * ONE_TON);
    expect(month4).toBeLess(start4);
    expect(floor4).toEqual(100 * ONE_TON);

    val start5 = getMinPrice(5 * BYTE_SIZE, AUCTION_START_TIME + 1);
    val floor5 = getMinPrice(5 * BYTE_SIZE, AUCTION_START_TIME + 24 * ONE_MONTH);
    expect(start5).toEqual(500 * ONE_TON);
    expect(floor5).toEqual(50 * ONE_TON);
}

get fun `test dns-utils: toNextResolver uses dns_next_resolver encoding`() {
    val resolver = net.randomAddress();
    val encoded = resolver.toNextResolver();

    val parsed = DnsNextResolver.fromCell(encoded);
    expect(parsed.resolver).toEqual(resolver);
}
