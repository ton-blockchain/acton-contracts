import "test_utils"
import "wrappers/JettonMinter"
import "@acton/build/build"
import "@acton/emulation/network"
import "@acton/testing/expect"
import "@acton/testing/transaction_expect"
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
    val (minter, deployer, _) = setup_test();
    val supplyBefore = minter.getTotalSupply();
    val minted = ton("25");

    val wallet = mintTo(minter, deployer, deployer.address, minted);

    expect(wallet.getJettonBalance()).toEqual(minted);
    expect(minter.getTotalSupply()).toEqual(supplyBefore + minted);
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

get fun `test admin: change-admin flow should work`() {
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

get fun `test admin: non-admin cannot drop admin access`() {
    val (minter, _, not_deployer) = setup_test();

    val dropResult = minter.sendDropAdmin(not_deployer.address);
    expect(dropResult).toHaveFailedTx<DropMinterAdmin>({
        from: not_deployer.address,
        to: minter.address,
        exitCode: ERROR_NOT_OWNER,
    });
}

get fun `test admin: admin can change metadata`() {
    val (minter, deployer, _) = setup_test();

    val changeResult = minter.sendChangeMetadata(
        deployer.address,
        "https://new.meta"
    );
    expect(changeResult).toHaveSuccessfulTx<ChangeMinterMetadataUri>({
        from: deployer.address,
        to: minter.address,
    });
}

get fun `test admin: non-admin cannot change metadata`() {
    val (minter, _, not_deployer) = setup_test();
    val oldContentHash = minter.getContent().hash();

    val changeResult = minter.sendChangeMetadata(
        not_deployer.address,
        "https://evil.meta"
    );
    expect(changeResult).toHaveFailedTx<ChangeMinterMetadataUri>({
        from: not_deployer.address,
        to: minter.address,
        exitCode: ERROR_NOT_OWNER,
    });
    expect(minter.getContent().hash()).toEqual(oldContentHash);
}

get fun `test admin: discovery should return wallet address with and without owner`() {
    val (minter, deployer, not_deployer) = setup_test();
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

    val withoutOwner = minter.sendDiscovery(deployer.address, not_deployer.address, false);
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
    val (minter, deployer, not_deployer) = setup_test();
    val newData = MinterStorage {
        totalSupply: minter.getTotalSupply(),
        adminAddress: deployer.address,
        nextAdminAddress: null,
        jettonWalletCode: build("notcoin_wallet"),
        metadataUri: "meta",
    }.toCell();
    val newCode = build("notcoin_minter");

    val res = minter.sendUpgrade(not_deployer.address, newCode, newData);
    expect(res).toHaveFailedTx<UpgradeMinterCode>({
        from: not_deployer.address,
        to: minter.address,
        exitCode: ERROR_NOT_OWNER,
    });
}

get fun `test admin: admin should be able to upgrade minter`() {
    val (minter, deployer, _) = setup_test();
    val newData = MinterStorage {
        totalSupply: minter.getTotalSupply(),
        adminAddress: deployer.address,
        nextAdminAddress: null,
        jettonWalletCode: build("notcoin_wallet"),
        metadataUri: "meta2",
    }.toCell();
    val newCode = build("notcoin_minter");

    val res = minter.sendUpgrade(deployer.address, newCode, newData);
    expect(res).toHaveSuccessfulTx<UpgradeMinterCode>({ from: deployer.address, to: minter.address });
}
