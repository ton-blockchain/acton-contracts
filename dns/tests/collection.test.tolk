import "test_utils"
import "@acton/emulation/network"
import "@acton/testing/expect"
import "@acton/testing/transaction_expect"
import "../contracts/errors"
import "../contracts/constants"

get fun `test collection: validates domain format and chars`() {
    val (collection, _, user) = deployCollectionContract();

    val tooShort = collection.sendAny(
        user,
        makeDeployBody("bob"),
        { value: ton("1000"), bounce: true },
    );
    expect(tooShort).toHaveFailedTx({
        from: user,
        to: collection.address,
        exitCode: ERROR_DOMAIN_TOO_SHORT,
    });

    val badChar = collection.sendAny(
        user,
        makeDeployBody("aLice"),
        { value: ton("1000"), bounce: true },
    );
    expect(badChar).toHaveFailedTx({
        from: user,
        to: collection.address,
        exitCode: ERROR_DOMAIN_HAS_INVALID_CHARS,
    });

    var veryLong = repeatAsciiChar(97, 127);
    val tooLong = collection.sendAny(
        user,
        makeDeployBodyFromDomain(mutate veryLong),
        { value: ton("1000"), bounce: true },
    );
    expect(tooLong).toHaveFailedTx({
        from: user,
        to: collection.address,
        exitCode: ERROR_DOMAIN_TOO_LONG,
    });
}

get fun `test collection: deploys item for a valid domain`() {
    val (collection, _, user) = deployCollectionContract();
    val minPrice = getMinPrice(4 * 8, net.now());
    val bid = collection.sendAny(user, makeDeployBody("appl"), { value: minPrice, bounce: true });
    expect(bid).toHaveSuccessfulTx({ from: user, to: collection.address });

    expect(bid.findTransaction({ from: collection.address, deploy: true })).toBeDefined();
}

get fun `test collection: getter stability`() {
    val (collection, _, _) = deployCollectionContract();

    val idx = "alice".sha256();
    val addr1 = collection.get_nft_address_by_index(idx as int);
    val addr2 = collection.get_nft_address_by_index(idx as int);
    expect(addr1).toEqual(addr2);

    val sample = makeCollectionContentCell();
    val passThrough = collection.get_nft_content(0, sample);
    expect(passThrough.hash()).toEqual(sample.hash());
}
