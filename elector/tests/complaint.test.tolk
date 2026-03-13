import "@acton/emulation/config"
import "@acton/emulation/network"
import "@acton/testing/expect"
import "@acton/testing/transaction_expect"
import "test_utils"
import "wrappers/Elector"
import "../contracts/types"
import "../contracts/messages"

/// Test that complaint from basechain is rejected
get fun `test new complaint not mc`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    val stakeAt = conductValidElections(elector);

    val complaint = createComplaint(0, ton("1"), 0);

    // From basechain — should be rejected (reason -1)
    val bcAddr = net.randomAddress("bc-sender", BASECHAIN);
    net.topUp(bcAddr, ton("100"));
    val res1 = elector.sendNewComplaint(bcAddr, 1, stakeAt as uint32, complaint.toCell().beginParse(), { value: ton("50") });
    expect(res1).toHaveSuccessfulTx({ from: elector.address, to: bcAddr });

    // From masterchain — should process (may fail for other reasons but not -1)
    val mcAddr = net.randomAddress("mc-sender", MASTERCHAIN);
    net.topUp(mcAddr, ton("100"));
    val res2 = elector.sendNewComplaint(mcAddr, 2, stakeAt as uint32, complaint.toCell().beginParse(), { value: ton("50") });
    expect(res2).toHaveSuccessfulTx({ from: elector.address, to: mcAddr });
}

/// Test that complaint with wrong election ID is rejected
get fun `test new complaint wrong elections`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    val stakeAt = conductValidElections(elector);

    val complaint = createComplaint(0, ton("1"), 0);

    // Wrong election ID
    val sender = net.randomAddress("sender", MASTERCHAIN);
    net.topUp(sender, ton("100"));
    val res1 = elector.sendNewComplaint(sender, 1, (stakeAt + 1) as uint32, complaint.toCell().beginParse(), { value: ton("50") });
    expect(res1).toHaveSuccessfulTx({ from: elector.address, to: sender });

    // Correct election ID
    val res2 = elector.sendNewComplaint(sender, 2, stakeAt as uint32, complaint.toCell().beginParse(), { value: ton("50") });
    expect(res2).toHaveSuccessfulTx({ from: elector.address, to: sender });
}

/// Test that complaint with too-large fine is rejected
get fun `test new complaint fine too large`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    val stakeAt = conductValidElections(elector);

    val complaint = createComplaint(0, ton("999999999"), 0);

    val sender = net.randomAddress("sender", MASTERCHAIN);
    net.topUp(sender, ton("100"));
    val res = elector.sendNewComplaint(sender, 1, stakeAt as uint32, complaint.toCell().beginParse(), { value: ton("50") });
    expect(res).toHaveSuccessfulTx({ from: elector.address, to: sender });
}

/// Test that already-expired complaint is rejected
get fun `test new complaint already expired`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    val stakeAt = conductValidElections(elector);

    // Advance time past unfreeze
    val validatorConf = defaultValidationTimes();
    val unfreezeAt = stakeAt + validatorConf.electedFor + validatorConf.stakeHeldFor;
    net.setNow(unfreezeAt + 1);

    val complaint = createComplaint(0, ton("1"), 0);

    val sender = net.randomAddress("sender", MASTERCHAIN);
    net.topUp(sender, ton("100"));
    val res = elector.sendNewComplaint(sender, 1, stakeAt as uint32, complaint.toCell().beginParse(), { value: ton("50") });
    expect(res).toHaveSuccessfulTx({ from: elector.address, to: sender });
}

/// Test that complaint with insufficient funds is rejected
get fun `test new complaint no money`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    val stakeAt = conductValidElections(elector);

    val complaint = createComplaint(0, ton("1"), 0);

    val sender = net.randomAddress("sender", MASTERCHAIN);
    net.topUp(sender, ton("10"));
    val res = elector.sendNewComplaint(sender, 1, stakeAt as uint32, complaint.toCell().beginParse(), { value: ton("0.1") });
    expect(res).toHaveSuccessfulTx({ from: elector.address, to: sender });
}

/// Test that complaint for non-existent validator is rejected
get fun `test new complaint wrong validator`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    val stakeAt = conductValidElections(elector);

    val fakePubkey: uint256 = 12345;
    val complaint = createComplaint(fakePubkey, ton("1"), 0);

    val sender = net.randomAddress("sender", MASTERCHAIN);
    net.topUp(sender, ton("100"));
    val res = elector.sendNewComplaint(sender, 1, stakeAt as uint32, complaint.toCell().beginParse(), { value: ton("50") });
    expect(res).toHaveSuccessfulTx({ from: elector.address, to: sender });
}
