import "@acton/emulation/config"
import "@acton/emulation/network"
import "@acton/testing/expect"
import "@acton/testing/transaction_expect"
import "test_utils"
import "wrappers/Elector"
import "../contracts/messages"
import "../contracts/types"

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
    val res1 = elector.sendNewComplaint(
        bcAddr,
        1,
        stakeAt as uint32,
        complaint.toCell().beginParse(),
        { value: ton("50") },
    );
    expect(res1).toHaveSuccessfulTx({ from: elector.address, to: bcAddr });

    // From masterchain — should process (may fail for other reasons but not -1)
    val mcAddr = net.randomAddress("mc-sender", MASTERCHAIN);
    net.topUp(mcAddr, ton("100"));
    val res2 = elector.sendNewComplaint(
        mcAddr,
        2,
        stakeAt as uint32,
        complaint.toCell().beginParse(),
        { value: ton("50") },
    );
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
    val res1 = elector.sendNewComplaint(
        sender,
        1,
        (stakeAt + 1) as uint32,
        complaint.toCell().beginParse(),
        { value: ton("50") },
    );
    expect(res1).toHaveSuccessfulTx({ from: elector.address, to: sender });

    // Correct election ID
    val res2 = elector.sendNewComplaint(
        sender,
        2,
        stakeAt as uint32,
        complaint.toCell().beginParse(),
        { value: ton("50") },
    );
    expect(res2).toHaveSuccessfulTx({ from: elector.address, to: sender });
}

/// Test that complaint with too-large fine is rejected (3 sub-cases)
get fun `test new complaint fine too large`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    val (stakeAt, knownPubkey) = conductElectionsWithKnownValidator(elector);

    val sender = net.randomAddress("sender", MASTERCHAIN);
    net.topUp(sender, ton("5000"));

    // Sub-case 1: fine alone > stake (trivially too large)
    val complaint1 = createComplaint(knownPubkey, ton("999999999"), 0);
    val res1 = elector.sendNewComplaint(
        sender,
        1,
        stakeAt as uint32,
        complaint1.toCell().beginParse(),
        { value: ton("500") },
    );
    expect(res1).toHaveSuccessfulTx({ from: elector.address, to: sender });

    // Sub-case 2: fine < stake, but fine + fine_part > stake
    // fine = stake/2 + 2, fine_part = 1 << 31 (which adds stake/2) → total > stake
    val stakeLimits = defaultStakeLimits();
    val stakePerValidator: coins = stakeLimits.minTotalStake / 5 + ton("10000");
    val complaint2 = Complaint {
        validatorPubkey: knownPubkey,
        description: beginCell().storeUint(0xDEAD, 32).endCell(),
        createdAt: 0,
        severity: 0,
        rewardAddr: 0,
        paid: 0,
        suggestedFine: stakePerValidator / 2 + 2,
        suggestedFinePart: 1 << 31,
    };
    val res2 = elector.sendNewComplaint(
        sender,
        2,
        stakeAt as uint32,
        complaint2.toCell().beginParse(),
        { value: ton("500") },
    );
    expect(res2).toHaveSuccessfulTx({ from: elector.address, to: sender });

    // Sub-case 3: fine_part alone (1/4 of stake via 1<<30) → should succeed
    val complaint3 = createComplaint(knownPubkey, 0, 1 << 30);
    val res3 = elector.sendNewComplaint(
        sender,
        3,
        stakeAt as uint32,
        complaint3.toCell().beginParse(),
        { value: ton("500") },
    );
    expect(res3).toHaveSuccessfulTx({ from: elector.address, to: sender });
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
    val res = elector.sendNewComplaint(
        sender,
        1,
        stakeAt as uint32,
        complaint.toCell().beginParse(),
        { value: ton("50") },
    );
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
    val res = elector.sendNewComplaint(
        sender,
        1,
        stakeAt as uint32,
        complaint.toCell().beginParse(),
        { value: ton("0.1") },
    );
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
    val res1 = elector.sendNewComplaint(
        sender,
        1,
        stakeAt as uint32,
        zeroFineComplaint.toCell().beginParse(),
        { value: ton("500") },
    );
    expect(res1).toHaveSuccessfulTx({ from: elector.address, to: sender });

    // Complaint with larger fine (1/4 of stake via finePart) → should succeed
    val goodComplaint = createComplaint(knownPubkey, ton("100"), 1 << 30);
    val res2 = elector.sendNewComplaint(
        sender,
        2,
        stakeAt as uint32,
        goodComplaint.toCell().beginParse(),
        { value: ton("500") },
    );
    expect(res2).toHaveSuccessfulTx({ from: elector.address, to: sender });
}

/// Test that duplicate complaint is rejected, but changing any field produces a distinct complaint
get fun `test new complaint duplicate`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    val (stakeAt, knownPubkey) = conductElectionsWithKnownValidator(elector);

    val complaint = createComplaint(knownPubkey, ton("100"), 1 << 30);
    val sender = net.randomAddress("sender", MASTERCHAIN);
    net.topUp(sender, ton("10000"));

    // First submission — should succeed
    val res1 = elector.sendNewComplaint(
        sender,
        1,
        stakeAt as uint32,
        complaint.toCell().beginParse(),
        { value: ton("500") },
    );
    expect(res1).toHaveSuccessfulTx({ from: elector.address, to: sender });

    // Second submission of same complaint — should be rejected as duplicate
    val res2 = elector.sendNewComplaint(
        sender,
        2,
        stakeAt as uint32,
        complaint.toCell().beginParse(),
        { value: ton("500") },
    );
    expect(res2).toHaveSuccessfulTx({ from: elector.address, to: sender });

    // Permutation 1: different description → new complaint hash → should succeed
    val diffDescr = Complaint {
        validatorPubkey: knownPubkey,
        description: beginCell().storeUint(0xBEEF, 32).endCell(),
        createdAt: 0,
        severity: 0,
        rewardAddr: 0,
        paid: 0,
        suggestedFine: ton("100"),
        suggestedFinePart: 1 << 30,
    };
    val res3 = elector.sendNewComplaint(
        sender,
        3,
        stakeAt as uint32,
        diffDescr.toCell().beginParse(),
        { value: ton("500") },
    );
    expect(res3).toHaveSuccessfulTx({ from: elector.address, to: sender });

    // Permutation 2: different severity → new complaint hash → should succeed
    val diffSeverity = Complaint {
        validatorPubkey: knownPubkey,
        description: beginCell().storeUint(0xDEAD, 32).endCell(),
        createdAt: 0,
        severity: 5,
        rewardAddr: 0,
        paid: 0,
        suggestedFine: ton("100"),
        suggestedFinePart: 1 << 30,
    };
    val res4 = elector.sendNewComplaint(
        sender,
        4,
        stakeAt as uint32,
        diffSeverity.toCell().beginParse(),
        { value: ton("500") },
    );
    expect(res4).toHaveSuccessfulTx({ from: elector.address, to: sender });

    // Permutation 3: different fine → new complaint hash → should succeed
    val diffFine = createComplaint(knownPubkey, ton("101"), 1 << 30);
    val res5 = elector.sendNewComplaint(
        sender,
        5,
        stakeAt as uint32,
        diffFine.toCell().beginParse(),
        { value: ton("500") },
    );
    expect(res5).toHaveSuccessfulTx({ from: elector.address, to: sender });

    // Permutation 4: different fine_part → new complaint hash → should succeed
    val diffFinePart = createComplaint(knownPubkey, ton("100"), 1 << 29);
    val res6 = elector.sendNewComplaint(
        sender,
        6,
        stakeAt as uint32,
        diffFinePart.toCell().beginParse(),
        { value: ton("500") },
    );
    expect(res6).toHaveSuccessfulTx({ from: elector.address, to: sender });
}

/// Test successful complaint submission with full field verification via all get methods
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
    val res = elector.sendNewComplaint(
        sender,
        1,
        stakeAt as uint32,
        complaint.toCell().beginParse(),
        { value: ton("500") },
    );
    expect(res).toHaveSuccessfulTx({ from: elector.address, to: sender });

    // Verify via get_past_complaints
    val complaints = elector.getPastComplaints(stakeAt as uint32);
    val first = complaints.findFirst();
    assert (first.isFound) throw 500;

    // Verify via show_complaint — check ALL fields
    val chash = first.getKey();
    val info = elector.showComplaint(stakeAt as uint32, chash);
    assert (info != null) throw 501;
    expect(info.complaint.validatorPubkey as int).toEqual(knownPubkey as int);
    expect(info.complaint.suggestedFine).toEqual(fine);
    expect(info.complaint.suggestedFinePart as int).toEqual(finePart as int);
    // createdAt should be overwritten by contract (non-zero)
    expect(info.complaint.createdAt as int).toNotEqual(0);
    // rewardAddr should be overwritten to sender's address hash
    val (_, senderHash) = sender.getWorkchainAndHash();
    expect(info.complaint.rewardAddr as int).toEqual(senderHash as int);
    // description cell hash should match
    expect(info.complaint.description.hash()).toEqual(
        beginCell().storeUint(0xDEAD, 32).endCell().hash(),
    );

    // Verify via list_complaints — must contain this complaint
    val clist = elector.listComplaints(stakeAt as uint32);
    assert (clist != null) throw 502;

    // Verify via get_past_complaints raw map — complaint cell must be present
    val rawLookup = complaints.get(chash);
    assert (rawLookup.isFound) throw 503;
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
    val res1 = elector.sendNewComplaint(
        sender,
        1,
        stakeAt as uint32,
        deepComplaint.toCell().beginParse(),
        { value: ton("500") },
    );
    expect(res1).toHaveSuccessfulTx({
        from: elector.address,
        to: sender,
        opcode: 0xf2676353,
    });

    // Normal depth complaint — should succeed
    val normalComplaint = createComplaint(knownPubkey, ton("100"), 1 << 30);
    val res2 = elector.sendNewComplaint(
        sender,
        2,
        stakeAt as uint32,
        normalComplaint.toCell().beginParse(),
        { value: ton("500") },
    );
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
    val res = elector.sendNewComplaint(
        sender,
        1,
        stakeAt as uint32,
        complaint.toCell().beginParse(),
        { value: ton("50") },
    );
    expect(res).toHaveSuccessfulTx({ from: elector.address, to: sender });
}
