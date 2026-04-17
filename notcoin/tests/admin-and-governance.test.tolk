import "@acton/build/build"
import "@acton/emulation/network"
import "@acton/testing/expect"
import "@acton/testing/transaction_expect"
import "@acton/tlb/maybe"
import "@acton/types/transaction"
import "test-utils"
import "../contracts/errors"
import "../contracts/messages"
import "../contracts/storage"
import "../wrappers/JettonMinter"
import "../wrappers/JettonWallet"

get fun `test admin: deploy should create minter without bounce`() {
    val deployer = net.treasury("deployer-manual-deploy");

    val minter = JettonMinter.fromStorage(MinterStorage {
        totalSupply: 0,
        adminAddress: deployer.address,
        jettonWalletCode: build("NotcoinWallet"),
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
    val (minter, deployer, _) = setupTest();
    val supplyBefore = minter.getTotalSupply();
    val minted = ton("25");

    val wallet = mintTo(minter, deployer, deployer.address, minted);

    expect(wallet.getJettonBalance()).toEqual(minted);
    expect(minter.getTotalSupply()).toEqual(supplyBefore + minted);
}

get fun `test admin: non-admin should not be able to mint jettons`() {
    val (minter, deployer, notDeployer) = setupTest();
    val supplyBefore = minter.getTotalSupply();

    val mintResult = minter.sendMint(
        notDeployer.address,
        deployer.address,
        ton("5"),
        ton("0.05"),
        ton("0.3"),
    );
    expect(mintResult).toHaveFailedTx<MintNewJettons>({
        from: notDeployer.address,
        to: minter.address,
        exitCode: ERROR_NOT_OWNER,
    });

    val deployerWallet = userWallet(minter, deployer.address);
    expect(deployerWallet.getJettonBalance()).toEqual(0);
    expect(minter.getTotalSupply()).toEqual(supplyBefore);
}

get fun `test admin: change-admin flow should work`() {
    val (minter, deployer, notDeployer) = setupTest();
    expect(minter.getAdminAddress()).toEqual(deployer.address);

    val changeResult = minter.sendChangeAdmin(deployer.address, notDeployer.address);
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

    val claimResult = minter.sendClaimAdmin(notDeployer.address);
    expect(claimResult).toHaveSuccessfulTx<ClaimMinterAdmin>({
        from: notDeployer.address,
        to: minter.address,
    });
    expect(minter.getAdminAddress()).toEqual(notDeployer.address);

    minter.sendChangeAdmin(notDeployer.address, deployer.address);
    minter.sendClaimAdmin(deployer.address);
    expect(minter.getAdminAddress()).toEqual(deployer.address);
}

get fun `test admin: non-admin cannot change admin`() {
    val (minter, deployer, notDeployer) = setupTest();

    val changeResult = minter.sendChangeAdmin(notDeployer.address, deployer.address);
    expect(changeResult).toHaveFailedTx<ChangeMinterAdmin>({
        from: notDeployer.address,
        to: minter.address,
        exitCode: ERROR_NOT_OWNER,
    });
    expect(minter.getAdminAddress()).toEqual(deployer.address);
}

get fun `test admin: admin can drop admin access`() {
    val (minter, deployer, _) = setupTest();
    expect(minter.getAdminAddress()).toEqual(deployer.address);

    val dropResult = minter.sendDropAdmin(deployer.address);
    expect(dropResult).toHaveSuccessfulTx<DropMinterAdmin>({
        from: deployer.address,
        to: minter.address,
    });
    expect(minter.getAdminAddress()).toEqual(null);
}

get fun `test admin: non-admin cannot drop admin access`() {
    val (minter, _, notDeployer) = setupTest();

    val dropResult = minter.sendDropAdmin(notDeployer.address);
    expect(dropResult).toHaveFailedTx<DropMinterAdmin>({
        from: notDeployer.address,
        to: minter.address,
        exitCode: ERROR_NOT_OWNER,
    });
}

get fun `test admin: admin can change metadata`() {
    val (minter, deployer, _) = setupTest();
    val oldContentHash = minter.getContent().hash();

    val changeResult = minter.sendChangeMetadata(deployer.address, "https://new.meta");
    expect(changeResult).toHaveSuccessfulTx<ChangeMinterMetadataUri>({
        from: deployer.address,
        to: minter.address,
    });
    expect(minter.getContent().hash() == oldContentHash).toEqual(false);
}

get fun `test admin: non-admin cannot change metadata`() {
    val (minter, _, notDeployer) = setupTest();
    val oldContentHash = minter.getContent().hash();

    val changeResult = minter.sendChangeMetadata(notDeployer.address, "https://evil.meta");
    expect(changeResult).toHaveFailedTx<ChangeMinterMetadataUri>({
        from: notDeployer.address,
        to: minter.address,
        exitCode: ERROR_NOT_OWNER,
    });
    expect(minter.getContent().hash()).toEqual(oldContentHash);
}

get fun `test admin: discovery should return wallet address with and without owner`() {
    val (minter, deployer, notDeployer) = setupTest();
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

    val expectedOtherWallet = userWallet(minter, notDeployer.address).address;
    val withoutOwnerRes = minter.sendDiscovery(deployer.address, notDeployer.address, false);
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
    val (minter, deployer, _) = setupTest();
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
    val (minter, deployer, notDeployer) = setupTest();
    val newData = MinterStorage {
        totalSupply: minter.getTotalSupply(),
        adminAddress: deployer.address,
        nextAdminAddress: null,
        jettonWalletCode: build("NotcoinWallet"),
        metadataUri: "meta",
    }.toCell();
    val newCode = build("NotcoinMinter");

    val res = minter.sendUpgrade(notDeployer.address, newCode, newData);
    expect(res).toHaveFailedTx<UpgradeMinterCode>({
        from: notDeployer.address,
        to: minter.address,
        exitCode: ERROR_NOT_OWNER,
    });
}

get fun `test admin: admin should be able to upgrade minter`() {
    val (minter, deployer, _) = setupTest();
    val oldContentHash = minter.getContent().hash();
    val newData = MinterStorage {
        totalSupply: ton("99"),
        adminAddress: deployer.address,
        nextAdminAddress: null,
        jettonWalletCode: build("NotcoinWallet"),
        metadataUri: "meta2",
    }.toCell();
    val newCode = build("NotcoinMinter");

    val res = minter.sendUpgrade(deployer.address, newCode, newData);
    expect(res).toHaveSuccessfulTx<UpgradeMinterCode>({
        from: deployer.address,
        to: minter.address,
    });
    expect(minter.getTotalSupply()).toEqual(ton("99"));
    expect(minter.getContent().hash() == oldContentHash).toEqual(false);
}
