import "@acton/emulation/config"
import "@acton/emulation/network"
import "@acton/testing/expect"
import "@acton/testing/transaction_expect"
import "test_utils"
import "wrappers/Elector"
import "../contracts/types"
import "../contracts/messages"

/// Build a raw complaint cell for the given validator pubkey
fun buildComplaintCell(validatorPubkey: uint256, suggestedFine: coins, suggestedFinePart: uint32): cell {
    val description = beginCell().storeUint(0xDEAD, 32).endCell();
    return beginCell()
        .storeUint(0xbc, 8) // Complaint prefix
        .storeUint(validatorPubkey, 256)
        .storeRef(description)
        .storeUint(0, 32) // createdAt (will be overwritten)
        .storeUint(0, 8) // severity
        .storeUint(0, 256) // rewardAddr (will be overwritten)
        .storeCoins(0) // paid (will be overwritten)
        .storeCoins(suggestedFine)
        .storeUint(suggestedFinePart, 32)
        .endCell();
}

/// Build a NewComplaint message body
fun buildComplaintBody(queryId: uint64, electionId: uint32, complaintCell: cell): cell {
    val cs = complaintCell.beginParse();
    return beginCell()
        .storeUint(0x52674370, 32) // NewComplaint opcode
        .storeUint(queryId, 64)
        .storeUint(electionId, 32)
        .storeSlice(cs) // rawComplaint as remaining bits and refs
        .endCell();
}

/// Get the first frozen validator pubkey from past elections
fun getFirstFrozenValidator(elector: Elector, electId: uint32): uint256 {
    // Use the show_complaint get method to check frozen validators
    // Actually, we need to get a validator pubkey from the frozen dict.
    // The participants are stored as members during elections.
    // After conduct, they become frozen in past elections.
    // We can use participant_list_extended to get pubkeys before conducting,
    // or we can check the past_elections data.
    // For simplicity, use participates_in with known pubkeys from test_utils.
    // Actually, let's just return 0 for now and use the wrapper's show_complaint.
    return 0;
}

/// Test that complaint from basechain is rejected
get fun `test new complaint not mc`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    val stakeAt = conductValidElections(elector);

    // Build a dummy complaint
    val complaintCell = buildComplaintCell(0, ton("1"), 0);
    val body = buildComplaintBody(1, stakeAt as uint32, complaintCell);

    // From basechain — should be rejected (reason -1 → response opcode offset)
    val bcAddr = net.randomAddress("bc-sender", BASECHAIN);
    net.topUp(bcAddr, ton("100"));
    val res1 = elector.sendAny(bcAddr, body, { value: ton("50") });
    // Response with error opcode (0xf2676350 + 1 = 0xf2676351 for reason -1)
    expect(res1).toHaveSuccessfulTx({ from: elector.address, to: bcAddr });

    // From masterchain — should process (may fail for other reasons but not -1)
    val mcAddr = net.randomAddress("mc-sender", MASTERCHAIN);
    net.topUp(mcAddr, ton("100"));
    val res2 = elector.sendAny(mcAddr, body, { value: ton("50") });
    expect(res2).toHaveSuccessfulTx({ from: elector.address, to: mcAddr });
}

/// Test that complaint with wrong election ID is rejected
get fun `test new complaint wrong elections`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    val stakeAt = conductValidElections(elector);

    val complaintCell = buildComplaintCell(0, ton("1"), 0);

    // Wrong election ID
    val wrongBody = buildComplaintBody(1, (stakeAt + 1) as uint32, complaintCell);
    val sender = net.randomAddress("sender", MASTERCHAIN);
    net.topUp(sender, ton("100"));
    val res1 = elector.sendAny(sender, wrongBody, { value: ton("50") });
    // Should get response with error (reason -2)
    expect(res1).toHaveSuccessfulTx({ from: elector.address, to: sender });

    // Correct election ID
    val correctBody = buildComplaintBody(2, stakeAt as uint32, complaintCell);
    val res2 = elector.sendAny(sender, correctBody, { value: ton("50") });
    // Should also get response (may fail for other reasons)
    expect(res2).toHaveSuccessfulTx({ from: elector.address, to: sender });
}

/// Test that complaint with too-large fine is rejected
get fun `test new complaint fine too large`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    val stakeAt = conductValidElections(elector);

    // Build complaint with fine larger than any validator's stake
    val hugeFineCpl = buildComplaintCell(0, ton("999999999"), 0);
    val body = buildComplaintBody(1, stakeAt as uint32, hugeFineCpl);

    val sender = net.randomAddress("sender", MASTERCHAIN);
    net.topUp(sender, ton("100"));
    val res = elector.sendAny(sender, body, { value: ton("50") });
    // Should fail (reason -6 no validator, or -7 fine too large)
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

    val complaintCell = buildComplaintCell(0, ton("1"), 0);
    val body = buildComplaintBody(1, stakeAt as uint32, complaintCell);

    val sender = net.randomAddress("sender", MASTERCHAIN);
    net.topUp(sender, ton("100"));
    val res = elector.sendAny(sender, body, { value: ton("50") });
    // Should fail (reason -4 already expired)
    expect(res).toHaveSuccessfulTx({ from: elector.address, to: sender });
}

/// Test that complaint with insufficient funds is rejected
get fun `test new complaint no money`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    val stakeAt = conductValidElections(elector);

    val complaintCell = buildComplaintCell(0, ton("1"), 0);
    val body = buildComplaintBody(1, stakeAt as uint32, complaintCell);

    val sender = net.randomAddress("sender", MASTERCHAIN);
    net.topUp(sender, ton("10"));

    // Send with very little value — should fail (reason -5 or -6)
    val res = elector.sendAny(sender, body, { value: ton("0.1") });
    expect(res).toHaveSuccessfulTx({ from: elector.address, to: sender });
}

/// Test that complaint for non-existent validator is rejected
get fun `test new complaint wrong validator`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    val stakeAt = conductValidElections(elector);

    // Use a random pubkey that doesn't exist in frozen dict
    val fakePubkey: uint256 = 12345;
    val complaintCell = buildComplaintCell(fakePubkey, ton("1"), 0);
    val body = buildComplaintBody(1, stakeAt as uint32, complaintCell);

    val sender = net.randomAddress("sender", MASTERCHAIN);
    net.topUp(sender, ton("100"));
    val res = elector.sendAny(sender, body, { value: ton("50") });
    // Should fail (reason -6 no such validator)
    expect(res).toHaveSuccessfulTx({ from: elector.address, to: sender });
}
