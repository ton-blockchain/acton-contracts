import "@acton/emulation/config"
import "@acton/emulation/network"
import "@acton/testing/expect"
import "@acton/testing/transaction_expect"
import "test_utils"
import "../contracts/messages"
import "../wrappers/Elector"

/// Build an upgrade code message body (op=0x4e436f64, queryId, newCode, empty remaining)
fun buildUpgradeCodeBody(queryId: uint64): cell {
    val dummyCode = beginCell().storeUint(0, 32).endCell();
    return beginCell()
        .storeUint(0x4e436f64, 32)
        .storeUint(queryId, 64)
        .storeRef(dummyCode)
        .endCell();
}

/// Test that upgrade code from basechain is rejected
get fun `test upgrade code not mc`() {
    val setup = setupElector();
    val elector = setup.elector;

    val (_, configHash) = setup.configAddr.getWorkchainAndHash();

    // Create a basechain address with the same hash as config
    val bcAddr = beginCell()
        .storeUint(4, 3)
        .storeInt(BASECHAIN, 8)
        .storeUint(configHash, 256)
        .endCell()
        .beginParse()
        .loadAddress();
    net.topUp(bcAddr, ton("10"));

    val body = buildUpgradeCodeBody(1);

    // From basechain — should be rejected (0xffffffff response)
    val res1 = elector.sendAny(bcAddr, body, { value: ton("1") });
    expect(res1).toHaveSuccessfulTx({
        from: elector.address,
        to: bcAddr,
        opcode: 0xffffffff,
    });

    // From masterchain config address — should succeed (0xce436f64 response)
    net.topUp(setup.configAddr, ton("10"));
    val res2 = elector.sendAny(setup.configAddr, body, { value: ton("1") });
    expect(res2).toHaveSuccessfulTx({
        from: elector.address,
        to: setup.configAddr,
        opcode: 0xce436f64,
    });
}

/// Test that upgrade code from wrong masterchain address is rejected
get fun `test upgrade code not config`() {
    val setup = setupElector();
    val elector = setup.elector;

    val otherAddr = net.randomAddress("not-config", MASTERCHAIN);
    net.topUp(otherAddr, ton("10"));

    val body = buildUpgradeCodeBody(1);

    // From wrong masterchain address — should be rejected (0xffffffff response)
    val res1 = elector.sendAny(otherAddr, body, { value: ton("1") });
    expect(res1).toHaveSuccessfulTx({
        from: elector.address,
        to: otherAddr,
        opcode: 0xffffffff,
    });

    // From correct config address — should succeed (0xce436f64 response)
    net.topUp(setup.configAddr, ton("10"));
    val res2 = elector.sendAny(setup.configAddr, body, { value: ton("1") });
    expect(res2).toHaveSuccessfulTx({
        from: elector.address,
        to: setup.configAddr,
        opcode: 0xce436f64,
    });
}
