import "test_utils"
import "wrappers/JettonMinter"
import "@acton/build/build"
import "@acton/emulation/network"
import "@acton/testing/expect"
import "@acton/testing/transaction_expect"
import "@acton/tlb/maybe"
import "../contracts/errors"
import "../contracts/messages"
import "../contracts/sharding"
import "../contracts/storage"
import "../contracts/types"

fun extractUriString(contentCell: cell): string? {
    val metadata = OnchainMetadataReply.fromCell(contentCell);
    val uriCell = metadata.contentDict.get(stringSha256("uri"));
    if (!uriCell.isFound) {
        return null;
    }
    val uri = uriCell.loadValue().load();
    return uri.string;
}

fun assertSameShardPrefix(owner: address, wallet: address) {
    val (_, ownerHash) = owner.getWorkchainAndHash();
    val (_, walletHash) = wallet.getWorkchainAndHash();
    expect(ownerHash >> (256 - SHARD_DEPTH)).toEqual(walletHash >> (256 - SHARD_DEPTH));
}

get fun `test admin: deploy should create minter without bounce`() {
    val deployer = net.treasury("deployer_manual_deploy");

    val minter = JettonMinter.fromStorage(MinterStorage {
        totalSupply: 0,
        adminAddress: deployer.address,
        metadataUri: "link",
        nextAdminAddress: null,
    });

    val deployResult = minter.sendDeploy(deployer.address, { value: ton("10") });
    expect(deployResult).toHaveSuccessfulDeploy<TopUpTons>({
        from: deployer.address,
        to: minter.address,
    });
    expect(deployResult).toNotHaveTx({
        from: minter.address,
        to: deployer.address,
        bounced: true,
    });
}

get fun `test admin: minter admin should be able to mint jettons`() {
    val (minter, deployer, not_deployer) = setup_test();
    val supplyBefore = minter.getTotalSupply();
    val deployerMint = ton("25");
    val otherMint = ton("7");

    val deployerWallet = mintTo(minter, deployer, deployer.address, deployerMint);
    val otherWallet = mintTo(minter, deployer, not_deployer.address, otherMint);

    expect(deployerWallet.getJettonBalance()).toEqual(deployerMint);
    expect(otherWallet.getJettonBalance()).toEqual(otherMint);
    expect(minter.getTotalSupply()).toEqual(supplyBefore + deployerMint + otherMint);
    assertSameShardPrefix(not_deployer.address, otherWallet.address);
}

get fun `test admin: non-admin should not be able to mint jettons`() {
    val (minter, deployer, not_deployer) = setup_test();
    val supplyBefore = minter.getTotalSupply();

    val mintResult = minter.sendMint(
        not_deployer.address,
        deployer.address,
        ton("5"),
        ton("0.05"),
        ton("0.3")
    );
    expect(mintResult).toHaveFailedTx<MintNewJettons>({
        from: not_deployer.address,
        to: minter.address,
        exitCode: ERROR_NOT_OWNER,
    });

    val deployerWallet = userWallet(minter, deployer.address);
    expect(deployerWallet.getJettonBalance()).toEqual(0);
    expect(minter.getTotalSupply()).toEqual(supplyBefore);
}

get fun `test admin: change-admin flow should work and only next admin can claim`() {
    val (minter, deployer, not_deployer) = setup_test();
    expect(minter.getAdminAddress()).toEqual(deployer.address);

    val changeResult = minter.sendChangeAdmin(deployer.address, not_deployer.address);
    expect(changeResult).toHaveSuccessfulTx<ChangeMinterAdmin>({
        from: deployer.address,
        to: minter.address,
    });
    expect(minter.getAdminAddress()).toEqual(deployer.address);

    val badClaim = minter.sendClaimAdmin(deployer.address);
    expect(badClaim).toHaveFailedTx<ClaimMinterAdmin>({
        from: deployer.address,
        to: minter.address,
        exitCode: ERROR_NOT_OWNER,
    });

    val claimResult = minter.sendClaimAdmin(not_deployer.address);
    expect(claimResult).toHaveSuccessfulTx<ClaimMinterAdmin>({
        from: not_deployer.address,
        to: minter.address,
    });
    expect(minter.getAdminAddress()).toEqual(not_deployer.address);

    minter.sendChangeAdmin(not_deployer.address, deployer.address);
    minter.sendClaimAdmin(deployer.address);
    expect(minter.getAdminAddress()).toEqual(deployer.address);
}

get fun `test admin: non-admin cannot change admin`() {
    val (minter, deployer, not_deployer) = setup_test();

    val changeResult = minter.sendChangeAdmin(not_deployer.address, deployer.address);
    expect(changeResult).toHaveFailedTx<ChangeMinterAdmin>({
        from: not_deployer.address,
        to: minter.address,
        exitCode: ERROR_NOT_OWNER,
    });
    expect(minter.getAdminAddress()).toEqual(deployer.address);
}

get fun `test admin: non-admin cannot drop admin access`() {
    val (minter, _, not_deployer) = setup_test();

    val dropResult = minter.sendDropAdmin(not_deployer.address);
    expect(dropResult).toHaveFailedTx<DropMinterAdmin>({
        from: not_deployer.address,
        to: minter.address,
        exitCode: ERROR_NOT_OWNER,
    });
}

get fun `test admin: admin can drop admin access`() {
    val (minter, deployer, _) = setup_test();
    expect(minter.getAdminAddress()).toEqual(deployer.address);

    val dropResult = minter.sendDropAdmin(deployer.address);
    expect(dropResult).toHaveSuccessfulTx<DropMinterAdmin>({
        from: deployer.address,
        to: minter.address,
    });
    expect(minter.getAdminAddress()).toEqual(null);
}

get fun `test admin: admin can change metadata uri`() {
    val (minter, deployer, _) = setup_test();
    val newUri = "https://new.meta.example/jetton.json";

    val oldUri = extractUriString(minter.getContent());
    expect(oldUri).toBeNotNull();

    val changeResult = minter.sendChangeMetadata(deployer.address, newUri);
    expect(changeResult).toHaveSuccessfulTx<ChangeMinterMetadataUri>({
        from: deployer.address,
        to: minter.address,
    });

    val updatedUri = extractUriString(minter.getContent());
    expect(updatedUri).toBeNotNull();
    if (updatedUri == null) {
        return;
    }
    expect(updatedUri).toEqual(newUri);
}

get fun `test admin: non-admin cannot change metadata uri`() {
    val (minter, _, not_deployer) = setup_test();
    val oldContentHash = minter.getContent().hash();

    val changeResult = minter.sendChangeMetadata(
        not_deployer.address,
        "https://evil.meta.example/jetton.json"
    );
    expect(changeResult).toHaveFailedTx<ChangeMinterMetadataUri>({
        from: not_deployer.address,
        to: minter.address,
        exitCode: ERROR_NOT_OWNER,
    });
    expect(minter.getContent().hash()).toEqual(oldContentHash);
}

get fun `test admin: discovery should return expected wallet and optional owner`() {
    val (minter, deployer, not_deployer) = setup_test();
    mintTo(minter, deployer, deployer.address, ton("1"));

    val expectedDeployerWallet = userWallet(minter, deployer.address).address;
    val withOwnerRes = minter.sendDiscovery(deployer.address, deployer.address, true);
    val withOwnerTx = withOwnerRes.findTransaction<ResponseWalletAddress>({
        from: minter.address,
        to: deployer.address,
        success: true,
        exitCode: 0,
    });
    expect(withOwnerTx).toBeDefined();
    if (withOwnerTx is None) {
        return;
    }

    val withOwnerBody = withOwnerTx.value.loadBody<ResponseWalletAddress>();
    expect(withOwnerBody.jettonWalletAddress).toEqual(expectedDeployerWallet);
    expect(withOwnerBody.ownerAddress).toBeNotNull();
    if (withOwnerBody.ownerAddress == null) {
        return;
    }
    expect(withOwnerBody.ownerAddress.load()).toEqual(deployer.address);

    val expectedOtherWallet = userWallet(minter, not_deployer.address).address;
    val withoutOwnerRes = minter.sendDiscovery(deployer.address, not_deployer.address, false);
    val withoutOwnerTx = withoutOwnerRes.findTransaction<ResponseWalletAddress>({
        from: minter.address,
        to: deployer.address,
        success: true,
        exitCode: 0,
    });
    expect(withoutOwnerTx).toBeDefined();
    if (withoutOwnerTx is None) {
        return;
    }

    val withoutOwnerBody = withoutOwnerTx.value.loadBody<ResponseWalletAddress>();
    expect(withoutOwnerBody.jettonWalletAddress).toEqual(expectedOtherWallet);
    expect(withoutOwnerBody.ownerAddress).toEqual(null);
}

get fun `test admin: discovery should return none for non-basechain owner`() {
    val (minter, deployer, _) = setup_test();
    val invalidOwner = address.fromWorkchainAndHash(-1, 0);

    val noOwnerRes = minter.sendDiscovery(deployer.address, invalidOwner, false);
    val noOwnerTx = noOwnerRes.findTransaction<ResponseWalletAddress>({
        from: minter.address,
        to: deployer.address,
        success: true,
        exitCode: 0,
    });
    expect(noOwnerTx).toBeDefined();
    if (noOwnerTx is None) {
        return;
    }
    val noOwnerBody = noOwnerTx.value.loadBody<ResponseWalletAddress>();
    expect(noOwnerBody.jettonWalletAddress).toEqual(null);
    expect(noOwnerBody.ownerAddress).toEqual(null);

    val withOwnerRes = minter.sendDiscovery(deployer.address, invalidOwner, true);
    val withOwnerTx = withOwnerRes.findTransaction<ResponseWalletAddress>({
        from: minter.address,
        to: deployer.address,
        success: true,
        exitCode: 0,
    });
    expect(withOwnerTx).toBeDefined();
    if (withOwnerTx is None) {
        return;
    }
    val withOwnerBody = withOwnerTx.value.loadBody<ResponseWalletAddress>();
    expect(withOwnerBody.jettonWalletAddress).toEqual(null);
    expect(withOwnerBody.ownerAddress).toBeNotNull();
    if (withOwnerBody.ownerAddress == null) {
        return;
    }
    expect(withOwnerBody.ownerAddress.load()).toEqual(invalidOwner);
}

get fun `test admin: non-admin should not be able to upgrade minter`() {
    val (minter, deployer, not_deployer) = setup_test();
    val newData = MinterStorage {
        totalSupply: ton("99"),
        adminAddress: deployer.address,
        nextAdminAddress: null,
        metadataUri: "meta-upgrade",
    }.toCell();
    val newCode = build("acton_jetton_minter");
    val oldContentHash = minter.getContent().hash();

    val res = minter.sendUpgrade(not_deployer.address, newCode, newData);
    expect(res).toHaveFailedTx<UpgradeMinterCode>({
        from: not_deployer.address,
        to: minter.address,
        exitCode: ERROR_NOT_OWNER,
    });
    expect(minter.getContent().hash()).toEqual(oldContentHash);
}

get fun `test admin: admin should be able to upgrade minter code and data`() {
    val (minter, deployer, _) = setup_test();
    val upgradedSupply = ton("42");
    val upgradedUri = "https://upgraded.meta.example/jetton.json";
    val newData = MinterStorage {
        totalSupply: upgradedSupply,
        adminAddress: deployer.address,
        nextAdminAddress: null,
        metadataUri: upgradedUri,
    }.toCell();
    val newCode = build("acton_jetton_minter");

    val res = minter.sendUpgrade(deployer.address, newCode, newData);
    expect(res).toHaveSuccessfulTx<UpgradeMinterCode>({
        from: deployer.address,
        to: minter.address,
    });

    expect(minter.getTotalSupply()).toEqual(upgradedSupply);
    expect(minter.getAdminAddress()).toEqual(deployer.address);

    val uri = extractUriString(minter.getContent());
    expect(uri).toBeNotNull();
    if (uri == null) {
        return;
    }
    expect(uri).toEqual(upgradedUri);
}

get fun `test shard: wallet address should keep owner shard prefix in get/discovery/transfer`() {
    val (minter, deployer, _) = setup_test();
    val senderWallet = mintTo(minter, deployer, deployer.address, ton("100"));

    var prefix = 0;
    while (prefix < 32) {
        val owner = address.fromWorkchainAndHash(0, prefix << 248);
        val expectedWalletAddress = minter.getWalletAddress(owner);
        assertSameShardPrefix(owner, expectedWalletAddress);

        val discovery = minter.sendDiscovery(deployer.address, owner, true);
        val discoveryTx = discovery.findTransaction<ResponseWalletAddress>({
            from: minter.address,
            to: deployer.address,
            success: true,
            exitCode: 0,
        });
        expect(discoveryTx).toBeDefined();
        if (discoveryTx is None) {
            return;
        }
        val discoveryBody = discoveryTx.value.loadBody<ResponseWalletAddress>();
        expect(discoveryBody.jettonWalletAddress).toEqual(expectedWalletAddress);

        val transfer = senderWallet.sendTransfer(
            deployer.address,
            DEFAULT_TRANSFER_MSG_VALUE,
            TEST_JETTON_UNIT,
            owner,
            deployer.address,
            null,
            0,
            null,
        );
        expect(transfer).toHaveSuccessfulTx<AskToTransfer>({
            from: deployer.address,
            to: senderWallet.address,
        });
        expect(transfer).toHaveSuccessfulTx<InternalTransferStep>({
            from: senderWallet.address,
            to: expectedWalletAddress,
        });

        prefix += 1;
    }
}
