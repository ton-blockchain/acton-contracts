import "@stdlib/exotic-cells"
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "test-utils"
import "../contracts/messages"
import "../contracts/storage"
import "../wrappers/Config.gen"

get fun `test custom params: should set custom slot -1024`() {
    val ctx = setupConfigTest();

    val testCellA = beginCell().storeSlice("Hop hey La La Ley".beginParse()).endCell();
    val testCellB = beginCell().storeUint(testCellA.hash(), 256).endCell();

    val testCells = [testCellA, testCellB];
    var i = 0;
    while (i < testCells.size()) {
        val testCell = testCells.get(i);
        expect(emptyOrDifferent(getConfigParam(ctx.contract, CUSTOM_SLOT_1), testCell)).toEqual(
            true,
        );

        val res = ctx
            .contract
            .sendSetCustomParamRequest(
                ADMIN_ADDRESS_FOR_CUSTOM_PARAMS,
                0,
                CUSTOM_SLOT_1,
                ctx.deployer.address,
                testCell,
                { value: ton("10"), bounce: true },
            );

        expect(res).toHaveSuccessfulTx<SetCustomParamRequest>({
            from: ADMIN_ADDRESS_FOR_CUSTOM_PARAMS,
            to: ctx.contract.address,
        });
        expect(res).toHaveTx({
            from: ctx.contract.address,
            to: ctx.deployer.address,
            opcode: TAG_SET_CUSTOM_PARAM_ACCEPTED,
        });

        assertConfigParam(ctx.contract, CUSTOM_SLOT_1, testCell);

        i += 1;
    }
}

get fun `test custom params: should set custom slot -1025`() {
    val ctx = setupConfigTest();

    val testCellA = beginCell().storeSlice("Hop hey La La Ley".beginParse()).endCell();
    val testCellB = beginCell().storeUint(testCellA.hash(), 256).endCell();

    val testCells = [testCellA, testCellB];
    var i = 0;
    while (i < testCells.size()) {
        val testCell = testCells.get(i);
        expect(emptyOrDifferent(getConfigParam(ctx.contract, CUSTOM_SLOT_2), testCell)).toEqual(
            true,
        );

        val res = ctx
            .contract
            .sendSetCustomParamRequest(
                ADMIN_ADDRESS_FOR_CUSTOM_PARAMS,
                0,
                CUSTOM_SLOT_2,
                ctx.deployer.address,
                testCell,
                { value: ton("10"), bounce: true },
            );

        expect(res).toHaveSuccessfulTx<SetCustomParamRequest>({
            from: ADMIN_ADDRESS_FOR_CUSTOM_PARAMS,
            to: ctx.contract.address,
        });
        expect(res).toHaveTx({
            from: ctx.contract.address,
            to: ctx.deployer.address,
            opcode: TAG_SET_CUSTOM_PARAM_ACCEPTED,
        });

        assertConfigParam(ctx.contract, CUSTOM_SLOT_2, testCell);

        i += 1;
    }
}

get fun `test custom params: only admin should be able to set slots`() {
    val ctx = setupConfigTest();

    val (_, adminHash) = ADMIN_ADDRESS_FOR_CUSTOM_PARAMS.getWorkchainAndHash();
    val senderWithSameHashInMasterchain = address.fromWorkchainAndHash(MASTERCHAIN, adminHash);
    val senderWithDifferentHashInMasterchain = differentAddress(senderWithSameHashInMasterchain);

    val testSenders = [
        ctx.deployer.address,
        randomAddress("cfg_random_wc0", BASECHAIN),
        senderWithSameHashInMasterchain,
        senderWithDifferentHashInMasterchain,
    ];

    val slots = customSlots();
    var i = 0;
    while (i < slots.size()) {
        val slot = slots.get(i);

        var j = 0;
        while (j < testSenders.size()) {
            val sender = testSenders.get(j);
            val testCell = beginCell().storeAddress(sender).endCell();
            val before = contractDataHash(ctx.contract);

            val res = ctx
                .contract
                .sendAny(
                    sender,
                    setCustomSlotBody(slot, testCell, ctx.deployer.address),
                    { value: ton("10"), bounce: true },
                );

            if (sender.getWorkchain() == MASTERCHAIN) {
                expect(res).toHaveTx({
                    from: ctx.contract.address,
                    to: ctx.deployer.address,
                    opcode: TAG_SET_CUSTOM_PARAM_REJECTED,
                });
            } else {
                expect(res).toNotHaveTx({
                    from: ctx.contract.address,
                    to: ctx.deployer.address,
                    opcode: TAG_SET_CUSTOM_PARAM_REJECTED,
                });
            }

            expect(contractDataHash(ctx.contract)).toEqual(before);

            j += 1;
        }

        i += 1;
    }
}

get fun `test custom params: should bounce set_custom_slot when response address is not standard`() {
    val ctx = setupConfigTest();

    val testCell = beginCell().storeSlice("Hop hey La La Ley".beginParse()).endCell();

    var payloads = array<cell> [];

    val slots = customSlots();
    var i = 0;
    while (i < slots.size()) {
        val slot = slots.get(i);
        payloads.push(
            beginCell()
                .storeUint(OP_SET_CUSTOM_PARAM, 32)
                .storeUint(0, 64)
                .storeInt(slot, 32)
                .storeUint(0b00, 2) // addr_none
                .storeRef(testCell)
                .endCell(),
        );

        payloads.push(
            beginCell()
                .storeUint(OP_SET_CUSTOM_PARAM, 32)
                .storeUint(0, 64)
                .storeInt(slot, 32)
                .storeUint(0b01, 2) // addr_extern
                .storeUint(256, 9)
                .storeUint(42, 256)
                .storeRef(testCell)
                .endCell(),
        );

        payloads.push(
            beginCell()
                .storeUint(OP_SET_CUSTOM_PARAM, 32)
                .storeUint(0, 64)
                .storeInt(slot, 32)
                .storeUint(0b110, 3) // addr_var + no anycast
                .storeUint(256, 9)
                .storeUint(0, 32)
                .storeUint(42, 256)
                .storeRef(testCell)
                .endCell(),
        );

        i += 1;
    }

    var payloadIdx = 0;
    while (payloadIdx < payloads.size()) {
        val msgBody = payloads.get(payloadIdx);
        val res = ctx
            .contract
            .sendAny(ADMIN_ADDRESS_FOR_CUSTOM_PARAMS, msgBody, { value: ton("10"), bounce: true });

        expect(res).toHaveTx({
            from: ADMIN_ADDRESS_FOR_CUSTOM_PARAMS,
            to: ctx.contract.address,
            opcode: OP_SET_CUSTOM_PARAM,
            aborted: true,
        });

        expect(res).toHaveBouncedTx({
            from: ctx.contract.address,
            to: ADMIN_ADDRESS_FOR_CUSTOM_PARAMS,
        });

        payloadIdx += 1;
    }
}

get fun `test custom params: should not allow more than a single cell payload`() {
    val ctx = setupConfigTest();

    val nestedCell = beginCell()
        .storeRef(beginCell().storeSlice("Hop hey La La Ley".beginParse()).endCell())
        .endCell();

    val slots = customSlots();
    var i = 0;
    while (i < slots.size()) {
        val slot = slots.get(i);
        val before = contractDataHash(ctx.contract);
        val res = ctx
            .contract
            .sendSetCustomParamRequest(
                ADMIN_ADDRESS_FOR_CUSTOM_PARAMS,
                0,
                slot,
                ctx.deployer.address,
                nestedCell,
                { value: ton("10"), bounce: true },
            );

        expect(res).toHaveTx({
            from: ctx.contract.address,
            to: ctx.deployer.address,
            opcode: TAG_SET_CUSTOM_PARAM_REJECTED,
        });
        expect(contractDataHash(ctx.contract)).toEqual(before);

        i += 1;
    }
}

get fun `test custom params: should not allow setting other parameters`() {
    val ctx = setupConfigTest();

    val testCell = beginCell().storeSlice("Hop hey La La Ley".beginParse()).endCell();
    val disallowedParams = [
        1,
        17,
        40,
        80,
        -1,
        -10,
        -1023,
        -94,
    ];

    var i = 0;
    while (i < disallowedParams.size()) {
        val param = disallowedParams.get(i);
        val before = contractDataHash(ctx.contract);

        val res = ctx
            .contract
            .sendAny(
                ADMIN_ADDRESS_FOR_CUSTOM_PARAMS,
                beginCell()
                    .storeUint(OP_SET_CUSTOM_PARAM, 32)
                    .storeUint(0, 64)
                    .storeInt(param, 32)
                    .storeAddress(ctx.deployer.address)
                    .storeRef(testCell)
                    .endCell(),
                { value: ton("10"), bounce: true },
            );

        expect(res).toHaveTx({
            from: ctx.contract.address,
            to: ctx.deployer.address,
            opcode: TAG_SET_CUSTOM_PARAM_REJECTED,
        });
        expect(contractDataHash(ctx.contract)).toEqual(before);

        i += 1;
    }
}

get fun `test custom params: should reject exotic cells for custom slots`() {
    val ctx = setupConfigTest();

    val plain = beginCell().storeSlice("Hop hey La La Ley".beginParse()).endCell();
    testing.registerLibrary(plain);

    val libraryRef = plain.toLibraryReference();

    val merkleProof = beginCell()
        .storeInt(ExoticCellType.MerkleProof as int, 8)
        .storeUint(plain.hashOfLevel(0), 256)
        .storeUint(plain.depthOfLevel(0), 16)
        .storeRef(plain)
        .endCellSpecial();

    val merkleUpdate = beginCell()
        .storeInt(ExoticCellType.MerkleUpdate as int, 8)
        .storeUint(merkleProof.hashOfLevel(0), 256)
        .storeUint(merkleProof.hashOfLevel(0), 256)
        .storeUint(merkleProof.depthOfLevel(0), 16)
        .storeUint(merkleProof.depthOfLevel(0), 16)
        .storeRef(merkleProof)
        .storeRef(merkleProof)
        .endCellSpecial();

    val slots = customSlots();
    val exoticPayloads = [libraryRef, merkleProof, merkleUpdate];
    var i = 0;
    while (i < slots.size()) {
        val slot = slots.get(i);

        var j = 0;
        while (j < exoticPayloads.size()) {
            val payload = exoticPayloads.get(j);
            val before = contractDataHash(ctx.contract);
            val res = ctx
                .contract
                .sendSetCustomParamRequest(
                    ADMIN_ADDRESS_FOR_CUSTOM_PARAMS,
                    0,
                    slot,
                    ctx.deployer.address,
                    payload,
                    { value: ton("10"), bounce: true },
                );

            expect(res).toHaveTx({
                from: ctx.contract.address,
                to: ctx.deployer.address,
                opcode: TAG_SET_CUSTOM_PARAM_REJECTED,
            });
            expect(contractDataHash(ctx.contract)).toEqual(before);

            j += 1;
        }

        i += 1;
    }
}

get fun `test custom params invariant: accepted updates should not mutate proposal dictionary`() {
    val ctx = setupConfigTest();

    val before = proposalCount(ctx.contract);

    val value = beginCell().storeSlice("Invariant payload".beginParse()).endCell();
    val res = ctx
        .contract
        .sendSetCustomParamRequest(
            ADMIN_ADDRESS_FOR_CUSTOM_PARAMS,
            1,
            CUSTOM_SLOT_1,
            ctx.deployer.address,
            value,
            { value: ton("10"), bounce: true },
        );

    expect(res).toHaveTx({
        from: ctx.contract.address,
        to: ctx.deployer.address,
        opcode: TAG_SET_CUSTOM_PARAM_ACCEPTED,
    });
    expect(proposalCount(ctx.contract)).toEqual(before);
}
