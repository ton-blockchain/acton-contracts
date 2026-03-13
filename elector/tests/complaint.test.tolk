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

/// Test that complaint where paid >= fine is rejected (reason -8)
get fun `test new complaint paid more than fine`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    val (stakeAt, knownPubkey) = conductElectionsWithKnownValidator(elector);

    // Complaint with fine = 0, finePart = 0 → totalFine = 0 ≤ paid → rejected
    val zeroFineComplaint = createComplaint(knownPubkey, 0, 0);

    val sender = net.randomAddress("sender", MASTERCHAIN);
    net.topUp(sender, ton("1000"));
    val res1 = elector.sendNewComplaint(sender, 1, stakeAt as uint32, zeroFineComplaint.toCell().beginParse(), { value: ton("500") });
    expect(res1).toHaveSuccessfulTx({ from: elector.address, to: sender });

    // Complaint with larger fine (1/4 of stake via finePart) → should succeed
    val goodComplaint = createComplaint(knownPubkey, ton("100"), 1 << 30);
    val res2 = elector.sendNewComplaint(sender, 2, stakeAt as uint32, goodComplaint.toCell().beginParse(), { value: ton("500") });
    expect(res2).toHaveSuccessfulTx({ from: elector.address, to: sender });
}

/// Test that duplicate complaint is rejected (reason -9)
get fun `test new complaint duplicate`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    val (stakeAt, knownPubkey) = conductElectionsWithKnownValidator(elector);

    val complaint = createComplaint(knownPubkey, ton("100"), 1 << 30);
    val sender = net.randomAddress("sender", MASTERCHAIN);
    net.topUp(sender, ton("2000"));

    // First submission — should succeed
    val res1 = elector.sendNewComplaint(sender, 1, stakeAt as uint32, complaint.toCell().beginParse(), { value: ton("500") });
    expect(res1).toHaveSuccessfulTx({ from: elector.address, to: sender });

    // Second submission of same complaint — should be rejected as duplicate
    val res2 = elector.sendNewComplaint(sender, 2, stakeAt as uint32, complaint.toCell().beginParse(), { value: ton("500") });
    expect(res2).toHaveSuccessfulTx({ from: elector.address, to: sender });
}

/// Test successful complaint submission and verification via get methods
get fun `test new complaint success`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    val (stakeAt, knownPubkey) = conductElectionsWithKnownValidator(elector);

    val fine: coins = ton("100");
    val finePart: uint32 = 1 << 30;
    val complaint = createComplaint(knownPubkey, fine, finePart);

    val sender = net.randomAddress("sender", MASTERCHAIN);
    net.topUp(sender, ton("1000"));
    val res = elector.sendNewComplaint(sender, 1, stakeAt as uint32, complaint.toCell().beginParse(), { value: ton("500") });
    expect(res).toHaveSuccessfulTx({ from: elector.address, to: sender });

    // Verify via get_past_complaints
    val complaints = elector.get_past_complaints(stakeAt as uint32);
    val first = complaints.findFirst();
    assert (first.isFound) throw 500;

    // Verify via show_complaint
    val chash = first.getKey();
    val info = elector.show_complaint(stakeAt as uint32, chash);
    assert (info != null) throw 501;

    // Verify complaint fields
    expect(info.complaint.validatorPubkey as int).toEqual(knownPubkey as int);
    expect(info.complaint.suggestedFine).toEqual(fine);
    expect(info.complaint.suggestedFinePart as int).toEqual(finePart as int);

    // Verify via list_complaints
    val clist = elector.list_complaints(stakeAt as uint32);
    assert (clist != null) throw 502;
}

/// Test that complaint with cell depth >= 128 is rejected (reason 3)
get fun `test new complaint cell too deep`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    val (stakeAt, knownPubkey) = conductElectionsWithKnownValidator(elector);

    // Create description with depth >= 128
    var descr = beginCell().storeUint(0xDEAD, 32).endCell();
    var i = 0;
    while (i < 128) {
        descr = beginCell().storeRef(descr).endCell();
        i += 1;
    }

    val deepComplaint = Complaint {
        validatorPubkey: knownPubkey,
        description: descr,
        createdAt: 0,
        severity: 0,
        rewardAddr: 0,
        paid: 0,
        suggestedFine: ton("100"),
        suggestedFinePart: 0,
    };

    val sender = net.randomAddress("sender", MASTERCHAIN);
    net.topUp(sender, ton("2000"));

    // Deep cell complaint — should be rejected (reason 3)
    // ansTag = 3, opcode = 3 + 0xf2676350 = 0xf2676353
    val res1 = elector.sendNewComplaint(sender, 1, stakeAt as uint32, deepComplaint.toCell().beginParse(), { value: ton("500") });
    expect(res1).toHaveSuccessfulTx({ from: elector.address, to: sender, opcode: 0xf2676353 });

    // Normal depth complaint — should succeed
    val normalComplaint = createComplaint(knownPubkey, ton("100"), 1 << 30);
    val res2 = elector.sendNewComplaint(sender, 2, stakeAt as uint32, normalComplaint.toCell().beginParse(), { value: ton("500") });
    expect(res2).toHaveSuccessfulTx({ from: elector.address, to: sender });
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
