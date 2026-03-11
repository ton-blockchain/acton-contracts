import "@acton/crypto/crypto"
import "@acton/emulation/config"
import "@acton/emulation/network"
import "@acton/testing/assert"
import "@acton/testing/expect"
import "@acton/testing/transaction_expect"
import "test_utils"
import "wrappers/Elector"
import "../contracts/messages"
import "../contracts/types"

get fun `test new stake no elections`() {
    val setup = setupElector();
    val elector = setup.elector;

    // No elections yet
    expect(elector.active_election_id()).toEqual(0);

    val kp = crypto.generateKeyPair();
    val srcAddr = net.randomAddress("staker", MASTERCHAIN);
    net.topUp(srcAddr, ton("100000"));
    val adnlAddr = net.randomAddress("adnl", MASTERCHAIN);
    val (_, adnlInt) = adnlAddr.getWorkchainAndHash();
    val (_, srcHash) = srcAddr.getWorkchainAndHash();

    val stake: coins = 11000 * ONECOIN;
    val maxFactor: uint32 = (1 << 16) + (1 << 15); // 1.5

    val signature = generateStakeSignature(
        kp.privateKey, net.now() as uint32, maxFactor, srcHash, adnlInt,
    );

    // Send stake when no elections — should be rejected (reason 0)
    val res = elector.sendNewStakeMessage(
        srcAddr, 0, kp.publicKey as uint256,
        net.now() as uint32, maxFactor, adnlInt, signature,
        { value: stake + ONECOIN },
    );
    // Should have a response (stake returned)
    expect(res).toHaveSuccessfulTx({ from: elector.address, to: srcAddr });

    // Now announce elections and submit same stake — should succeed
    announceElections(elector);
    val stakeAt = elector.active_election_id();
    expect(stakeAt).toNotEqual(0);

    val signature2 = generateStakeSignature(
        kp.privateKey, stakeAt as uint32, maxFactor, srcHash, adnlInt,
    );

    val res2 = elector.sendNewStakeMessage(
        srcAddr, 0, kp.publicKey as uint256,
        stakeAt as uint32, maxFactor, adnlInt, signature2,
        { value: stake + ONECOIN },
    );
    // With queryId == 0, no confirmation message on success
    expect(res2).toNotHaveTx({ from: elector.address, to: srcAddr });
}

get fun `test new stake not masterchain`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    val stakeAt = elector.active_election_id();
    expect(stakeAt).toNotEqual(0);

    val kp = crypto.generateKeyPair();
    // Source address on basechain (should be rejected)
    val srcAddr = net.randomAddress("staker", BASECHAIN);
    net.topUp(srcAddr, ton("100000"));
    val adnlAddr = net.randomAddress("adnl", MASTERCHAIN);
    val (_, adnlInt) = adnlAddr.getWorkchainAndHash();
    val (_, srcHash) = srcAddr.getWorkchainAndHash();

    val stake: coins = 11000 * ONECOIN;
    val maxFactor: uint32 = (1 << 16) + (1 << 15);

    val signature = generateStakeSignature(
        kp.privateKey, stakeAt as uint32, maxFactor, srcHash, adnlInt,
    );

    // Send from basechain — should be rejected (reason 0)
    val res = elector.sendNewStakeMessage(
        srcAddr, 0, kp.publicKey as uint256,
        stakeAt as uint32, maxFactor, adnlInt, signature,
        { value: stake + ONECOIN },
    );
    expect(res).toHaveSuccessfulTx({ from: elector.address, to: srcAddr });

    // Now send from masterchain — should succeed
    val mcSrcAddr = net.randomAddress("mc-staker", MASTERCHAIN);
    net.topUp(mcSrcAddr, ton("100000"));
    val (_, mcSrcHash) = mcSrcAddr.getWorkchainAndHash();

    val signature2 = generateStakeSignature(
        kp.privateKey, stakeAt as uint32, maxFactor, mcSrcHash, adnlInt,
    );

    val res2 = elector.sendNewStakeMessage(
        mcSrcAddr, 0, kp.publicKey as uint256,
        stakeAt as uint32, maxFactor, adnlInt, signature2,
        { value: stake + ONECOIN },
    );
    expect(res2).toNotHaveTx({ from: elector.address, to: mcSrcAddr });
}

get fun `test new stake already finished`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    val stakeAt = elector.active_election_id();
    expect(stakeAt).toNotEqual(0);

    // Conduct elections until finished
    conductValidElections(elector);

    // Verify elections are finished
    val (_, _, _, totalStake, _, _, isFinished) = elector.participant_list_extended();
    expect(isFinished).toEqual(true);

    // Try to submit a new stake after elections finished — should be rejected (reason 0)
    val (res, srcAddr, _, _, _) = submitValidStake(elector, totalStake);
    expect(res).toHaveSuccessfulTx({ from: elector.address, to: srcAddr });
}

get fun `test new stake invalid signature`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    val stakeAt = elector.active_election_id();
    expect(stakeAt).toNotEqual(0);

    val kp = crypto.generateKeyPair();
    val wrongKp = crypto.generateKeyPair();
    val srcAddr = net.randomAddress("staker", MASTERCHAIN);
    net.topUp(srcAddr, ton("100000"));
    val adnlAddr = net.randomAddress("adnl", MASTERCHAIN);
    val (_, adnlInt) = adnlAddr.getWorkchainAndHash();
    val (_, srcHash) = srcAddr.getWorkchainAndHash();

    val stake: coins = 11000 * ONECOIN;
    val maxFactor: uint32 = (1 << 16) + (1 << 15);

    // Sign with wrong private key
    val wrongSig = generateStakeSignature(
        wrongKp.privateKey, stakeAt as uint32, maxFactor, srcHash, adnlInt,
    );

    val res = elector.sendNewStakeMessage(
        srcAddr, 0, kp.publicKey as uint256,
        stakeAt as uint32, maxFactor, adnlInt, wrongSig,
        { value: stake + ONECOIN },
    );
    // Should be rejected (reason 1 — invalid signature)
    expect(res).toHaveSuccessfulTx({ from: elector.address, to: srcAddr });

    // Now sign with correct key — should succeed
    val correctSig = generateStakeSignature(
        kp.privateKey, stakeAt as uint32, maxFactor, srcHash, adnlInt,
    );

    val res2 = elector.sendNewStakeMessage(
        srcAddr, 0, kp.publicKey as uint256,
        stakeAt as uint32, maxFactor, adnlInt, correctSig,
        { value: stake + ONECOIN },
    );
    expect(res2).toNotHaveTx({ from: elector.address, to: srcAddr });
}

get fun `test new stake low factor`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    val stakeAt = elector.active_election_id();
    expect(stakeAt).toNotEqual(0);

    val kp = crypto.generateKeyPair();
    val srcAddr = net.randomAddress("staker", MASTERCHAIN);
    net.topUp(srcAddr, ton("100000"));
    val adnlAddr = net.randomAddress("adnl", MASTERCHAIN);
    val (_, adnlInt) = adnlAddr.getWorkchainAndHash();
    val (_, srcHash) = srcAddr.getWorkchainAndHash();

    val stake: coins = 11000 * ONECOIN;
    val lowFactor: uint32 = 0x10000 - 1; // Just below minimum factor (1.0)

    val signature = generateStakeSignature(
        kp.privateKey, stakeAt as uint32, lowFactor, srcHash, adnlInt,
    );

    // Should be rejected (reason 6 — low factor)
    val res = elector.sendNewStakeMessage(
        srcAddr, 0, kp.publicKey as uint256,
        stakeAt as uint32, lowFactor, adnlInt, signature,
        { value: stake + ONECOIN },
    );
    expect(res).toHaveSuccessfulTx({ from: elector.address, to: srcAddr });
}

get fun `test new stake wrong elections`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    val stakeAt = elector.active_election_id();
    expect(stakeAt).toNotEqual(0);

    val kp = crypto.generateKeyPair();
    val srcAddr = net.randomAddress("staker", MASTERCHAIN);
    net.topUp(srcAddr, ton("100000"));
    val adnlAddr = net.randomAddress("adnl", MASTERCHAIN);
    val (_, adnlInt) = adnlAddr.getWorkchainAndHash();
    val (_, srcHash) = srcAddr.getWorkchainAndHash();

    val stake: coins = 11000 * ONECOIN;
    val maxFactor: uint32 = (1 << 16) + (1 << 15);
    val wrongStakeAt: uint32 = (stakeAt + 12345) as uint32;

    val signature = generateStakeSignature(
        kp.privateKey, wrongStakeAt, maxFactor, srcHash, adnlInt,
    );

    // Wrong election ID — should be rejected (reason 3)
    val res = elector.sendNewStakeMessage(
        srcAddr, 0, kp.publicKey as uint256,
        wrongStakeAt, maxFactor, adnlInt, signature,
        { value: stake + ONECOIN },
    );
    expect(res).toHaveSuccessfulTx({ from: elector.address, to: srcAddr });

    // Correct election ID — should succeed
    val correctSig = generateStakeSignature(
        kp.privateKey, stakeAt as uint32, maxFactor, srcHash, adnlInt,
    );

    val res2 = elector.sendNewStakeMessage(
        srcAddr, 0, kp.publicKey as uint256,
        stakeAt as uint32, maxFactor, adnlInt, correctSig,
        { value: stake + ONECOIN },
    );
    expect(res2).toNotHaveTx({ from: elector.address, to: srcAddr });
}

get fun `test new stake pkey addr pair`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    val stakeAt = elector.active_election_id();
    expect(stakeAt).toNotEqual(0);

    val kp = crypto.generateKeyPair();
    val srcAddr1 = net.randomAddress("staker1", MASTERCHAIN);
    val srcAddr2 = net.randomAddress("staker2", MASTERCHAIN);
    net.topUp(srcAddr1, ton("100000"));
    net.topUp(srcAddr2, ton("100000"));
    val adnlAddr = net.randomAddress("adnl", MASTERCHAIN);
    val (_, adnlInt) = adnlAddr.getWorkchainAndHash();
    val (_, srcHash1) = srcAddr1.getWorkchainAndHash();
    val (_, srcHash2) = srcAddr2.getWorkchainAndHash();

    val stake: coins = 11000 * ONECOIN;
    val maxFactor: uint32 = (1 << 16) + (1 << 15);

    // First stake from srcAddr1 — should succeed
    val sig1 = generateStakeSignature(
        kp.privateKey, stakeAt as uint32, maxFactor, srcHash1, adnlInt,
    );
    val res1 = elector.sendNewStakeMessage(
        srcAddr1, 0, kp.publicKey as uint256,
        stakeAt as uint32, maxFactor, adnlInt, sig1,
        { value: stake + ONECOIN },
    );
    expect(res1).toNotHaveTx({ from: elector.address, to: srcAddr1 });

    // Verify stake is recorded
    val curStake = elector.participates_in(kp.publicKey as uint256);
    expect(curStake).toEqual(stake);

    // Same pubkey from different address — should be rejected (reason 4)
    val sig2 = generateStakeSignature(
        kp.privateKey, stakeAt as uint32, maxFactor, srcHash2, adnlInt,
    );
    val res2 = elector.sendNewStakeMessage(
        srcAddr2, 0, kp.publicKey as uint256,
        stakeAt as uint32, maxFactor, adnlInt, sig2,
        { value: stake + ONECOIN },
    );
    expect(res2).toHaveSuccessfulTx({ from: elector.address, to: srcAddr2 });

    // Same pubkey from original address — should succeed (adds to existing stake)
    val adnlAddr2 = net.randomAddress("adnl2", MASTERCHAIN);
    val (_, adnlInt2) = adnlAddr2.getWorkchainAndHash();
    val sig3 = generateStakeSignature(
        kp.privateKey, stakeAt as uint32, maxFactor, srcHash1, adnlInt2,
    );
    val res3 = elector.sendNewStakeMessage(
        srcAddr1, 0, kp.publicKey as uint256,
        stakeAt as uint32, maxFactor, adnlInt2, sig3,
        { value: stake + ONECOIN },
    );
    expect(res3).toNotHaveTx({ from: elector.address, to: srcAddr1 });

    // Verify total stake increased
    val newStake = elector.participates_in(kp.publicKey as uint256);
    expect(newStake).toEqual(stake + stake);
}

get fun `test new stake lower min stake`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    val stakeAt = elector.active_election_id();
    expect(stakeAt).toNotEqual(0);

    val kp = crypto.generateKeyPair();
    val srcAddr = net.randomAddress("staker", MASTERCHAIN);
    net.topUp(srcAddr, ton("100000"));
    val adnlAddr = net.randomAddress("adnl", MASTERCHAIN);
    val (_, adnlInt) = adnlAddr.getWorkchainAndHash();
    val (_, srcHash) = srcAddr.getWorkchainAndHash();

    val stakeLimits = defaultStakeLimits();
    // Stake less than min_stake (send half of min_stake)
    val lowStake: coins = stakeLimits.minStake / 2;
    val maxFactor: uint32 = (1 << 16) + (1 << 15);

    val signature = generateStakeSignature(
        kp.privateKey, stakeAt as uint32, maxFactor, srcHash, adnlInt,
    );

    // Should be rejected (reason 5 — stake too low)
    val res = elector.sendNewStakeMessage(
        srcAddr, 0, kp.publicKey as uint256,
        stakeAt as uint32, maxFactor, adnlInt, signature,
        { value: lowStake + ONECOIN },
    );
    expect(res).toHaveSuccessfulTx({ from: elector.address, to: srcAddr });

    // Now send with min_stake + confirmation fee — should succeed
    val res2 = elector.sendNewStakeMessage(
        srcAddr, 0, kp.publicKey as uint256,
        stakeAt as uint32, maxFactor, adnlInt, signature,
        { value: stakeLimits.minStake + ONECOIN },
    );
    expect(res2).toNotHaveTx({ from: elector.address, to: srcAddr });
}

get fun `test new stake success`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    val stakeAt = elector.active_election_id();
    expect(stakeAt).toNotEqual(0);

    // Submit a valid stake
    val (res, srcAddr, _, pubkey, stake) = submitValidStake(elector, 0);

    // No response message (queryId = 0)
    expect(res).toNotHaveTx({ from: elector.address, to: srcAddr });

    // Verify via participant_list_extended
    val (_, _, _, totalStake, _, _, _) = elector.participant_list_extended();
    expect(totalStake).toEqual(stake);

    // Verify via participates_in
    val curStake = elector.participates_in(pubkey);
    expect(curStake).toEqual(stake);
}

get fun `test new stake success query id`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    val stakeAt = elector.active_election_id();
    expect(stakeAt).toNotEqual(0);

    val kp = crypto.generateKeyPair();
    val srcAddr = net.randomAddress("staker", MASTERCHAIN);
    net.topUp(srcAddr, ton("100000"));
    val adnlAddr = net.randomAddress("adnl", MASTERCHAIN);
    val (_, adnlInt) = adnlAddr.getWorkchainAndHash();
    val (_, srcHash) = srcAddr.getWorkchainAndHash();

    val stake: coins = 11000 * ONECOIN;
    val maxFactor: uint32 = (1 << 16) + (1 << 15);
    val queryId: uint64 = 12345;

    val signature = generateStakeSignature(
        kp.privateKey, stakeAt as uint32, maxFactor, srcHash, adnlInt,
    );

    val res = elector.sendNewStakeMessage(
        srcAddr, queryId, kp.publicKey as uint256,
        stakeAt as uint32, maxFactor, adnlInt, signature,
        { value: stake + ONECOIN },
    );

    // With queryId > 0, should have a confirmation message back
    expect(res).toHaveSuccessfulTx({ from: elector.address, to: srcAddr });

    // Verify stake recorded
    val curStake = elector.participates_in(kp.publicKey as uint256);
    expect(curStake).toEqual(stake);
}

get fun `test new stake low fraction`() {
    val setup = setupElector();
    val elector = setup.elector;

    announceElections(elector);
    val stakeAt = elector.active_election_id();
    expect(stakeAt).toNotEqual(0);

    // First submit several valid stakes to build up totalStake
    var totalStake: coins = 0;
    var i = 0;
    while (i < 3) {
        val (_, _, _, _, stake) = submitValidStake(elector, totalStake);
        totalStake += stake;
        i += 1;
    }

    // Verify total stake
    val (_, _, _, contractTotalStake, _, _, _) = elector.participant_list_extended();
    expect(contractTotalStake).toEqual(totalStake);

    // Now try to submit a stake that is less than 1/4096 of totalStake
    val kp = crypto.generateKeyPair();
    val srcAddr = net.randomAddress("low-staker", MASTERCHAIN);
    net.topUp(srcAddr, ton("100000"));
    val adnlAddr = net.randomAddress("adnl-low", MASTERCHAIN);
    val (_, adnlInt) = adnlAddr.getWorkchainAndHash();
    val (_, srcHash) = srcAddr.getWorkchainAndHash();

    val maxFactor: uint32 = (1 << 16) + (1 << 15);
    // Stake value that will be < 1/4096 of totalStake after 1 TON confirmation fee deduction
    // msgValue = value - 1 TON. Need (msgValue << 12) < totalStake
    // i.e. msgValue < totalStake / 4096
    val tinyStake: coins = totalStake >> 13; // Half of 1/4096 of totalStake

    val signature = generateStakeSignature(
        kp.privateKey, stakeAt as uint32, maxFactor, srcHash, adnlInt,
    );

    // Should be rejected (reason 2 — low fraction)
    val res = elector.sendNewStakeMessage(
        srcAddr, 0, kp.publicKey as uint256,
        stakeAt as uint32, maxFactor, adnlInt, signature,
        { value: tinyStake },
    );
    expect(res).toHaveSuccessfulTx({ from: elector.address, to: srcAddr });
}
