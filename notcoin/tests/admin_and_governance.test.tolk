import "@acton/build/build"
import "@acton/emulation/network"
import "@acton/testing/expect"
import "@acton/testing/transaction_expect"
import "test_utils"
import "wrappers/JettonMinter"
import "wrappers/JettonWallet"
import "../contracts/errors"
import "../contracts/messages"
import "../contracts/storage"

get fun `test admin: deploy should create minter without bounce`() {
    val deployer = net.treasury("deployer_manual_deploy");

    val minter = JettonMinter.fromStorage(MinterStorage {
        totalSupply: 0,
        adminAddress: deployer.address,
        jettonWalletCode: build("notcoin_wallet"),
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

    val changeResult = minter.sendChangeMetadata(deployer.address, "https://new.meta");
    expect(changeResult).toHaveSuccessfulTx<ChangeMinterMetadataUri>({
        from: deployer.address,
        to: minter.address,
    });
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

    val withOwner = minter.sendDiscovery(deployer.address, deployer.address, true);
    expect(withOwner).toHaveSuccessfulTx<RequestWalletAddress>({
        from: deployer.address,
        to: minter.address,
    });
    expect(withOwner).toHaveSuccessfulTx<ResponseWalletAddress>({
        from: minter.address,
        to: deployer.address,
    });

    val withoutOwner = minter.sendDiscovery(deployer.address, notDeployer.address, false);
    expect(withoutOwner).toHaveSuccessfulTx<ResponseWalletAddress>({
        from: minter.address,
        to: deployer.address,
    });

    val invalidAddr = address.fromWorkchainAndHash(-1, 0);
    val invalid = minter.sendDiscovery(deployer.address, invalidAddr, true);
    expect(invalid).toHaveSuccessfulTx<ResponseWalletAddress>({
        from: minter.address,
        to: deployer.address,
    });
}

get fun `test admin: non-admin should not be able to upgrade minter`() {
    val (minter, deployer, notDeployer) = setupTest();
    val newData = MinterStorage {
        totalSupply: minter.getTotalSupply(),
        adminAddress: deployer.address,
        nextAdminAddress: null,
        jettonWalletCode: build("notcoin_wallet"),
        metadataUri: "meta",
    }.toCell();
    val newCode = build("notcoin_minter");

    val res = minter.sendUpgrade(notDeployer.address, newCode, newData);
    expect(res).toHaveFailedTx<UpgradeMinterCode>({
        from: notDeployer.address,
        to: minter.address,
        exitCode: ERROR_NOT_OWNER,
    });
}

get fun `test admin: admin should be able to upgrade minter`() {
    val (minter, deployer, _) = setupTest();
    val newData = MinterStorage {
        totalSupply: minter.getTotalSupply(),
        adminAddress: deployer.address,
        nextAdminAddress: null,
        jettonWalletCode: build("notcoin_wallet"),
        metadataUri: "meta2",
    }.toCell();
    val newCode = build("notcoin_minter");

    val res = minter.sendUpgrade(deployer.address, newCode, newData);
    expect(res).toHaveSuccessfulTx<UpgradeMinterCode>({
        from: deployer.address,
        to: minter.address,
    });
}
