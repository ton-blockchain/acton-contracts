import "@acton/emulation/network"
import "@acton/testing/expect"
import "@acton/testing/transaction_expect"
import "test_utils"
import "../wrappers/HighloadWalletV3"

get fun `test timeout replay attack`() {
    val ctx = setupHighloadTest();
    val newDeployer = net.treasury("new_deployer");
    val attacker = net.treasury("attacker");

    val newWallet = HighloadWalletV3.fromConfig(ctx.keyPair.publicKey, SUBWALLET_ID, 1234);
    val deployRes = newWallet.deploy(newDeployer.address, { value: ton("1000"), bounce: false });
    expect(deployRes).toHaveSuccessfulDeploy({ to: newWallet.address });

    val queryId = queryIdZero().toInt();
    val legitOut = createMessage({
        bounce: false,
        value: ton("10"),
        dest: attacker.address,
    }).messageCell;

    val extBody = buildSignedExternalBody(
        ctx.wallet,
        ctx.keyPair,
        legitOut,
        SEND_MODE_PAY_FEES_SEPARATELY,
        queryId,
        1000,
        SUBWALLET_ID,
        DEFAULT_TIMEOUT,
    );

    val legitRes = ctx.wallet.sendRawExternalBody(extBody);
    expect(legitRes).toHaveSuccessfulTx({
        from: ctx.wallet.address,
        to: attacker.address,
        value: ton("10"),
    });

    val replay = newWallet.trySendRawExternalBodySingle(extBody);
    expect(replay).toBeNull();
}
