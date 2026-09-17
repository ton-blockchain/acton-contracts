# W5

Original FunC: [ton-blockchain/wallet-contract-v5](https://github.com/ton-blockchain/wallet-contract-v5).

This package implements Wallet V5, including signed external execution, internal execution, extension support, and the get-method surface. Tests exercise external and internal message flows, extensions, get methods, and core wallet behavior.

Scripts in `scripts/` provide operational entry points for deployment, state inspection, transfer submission, and extension management: `deploy.tolk`, `info.tolk`, `send-transfer.tolk`, `add-extension.tolk`, `remove-extension.tolk`, and `set-signature.tolk`. Run them with `acton script w5.2/scripts/<name>.tolk`.

## Comparison Tolk vs FunC

A detailed table of transactions.

| # | Operation                       | WalletV5 Tolk | WalletV5 FunC | Diff              | Winner   | Tx Tolk                                                                                               | Tx FunC                                                                                               |
|---|---------------------------------|---------------|---------------|-------------------|----------|-------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------|
| 1 | TON transfer                    | 466,337       | 568,604       | −102,267 (−18.0%) | **Tolk** | [tx](https://testnet.tonscan.org/tx/b41bee8ebe6e07338148bd85849a1eb87bbab6013a3653ae872f9947ae1be864) | [tx](https://testnet.tonscan.org/tx/06bdcdfb219cfe309534c9cc823990c8108f72e93a524ae8e80b1a3b4bc2eb03) |
| 2 | USDT transfer                   | 1,101,745     | 1,208,880     | −107,135 (−8.9%)  | **Tolk** | [tx](https://testnet.tonscan.org/tx/b4a869a2edb2d074d0da883fd9655e7e38f90f83167c3296db66cec31d1fb713) | [tx](https://testnet.tonscan.org/tx/ae64924d545b07fa04eaee51124c0ae93cd3e5cf94ad2f8137e0462b03b0a55d) |
| 3 | First TON transfer              | 1,015,270     | 1,042,604     | −27,334 (−2.6%)   | **Tolk** | [tx](https://testnet.tonscan.org/tx/606fc40351e5b2e711f82b63972014152381ecb99b8654fbf1859c7259bfabd2) | [tx](https://testnet.tonscan.org/tx/250398e794cfefb9ba81e0553fdcf9de6a8d20b7e2d2d8220d99d062352ffb4b) |
| 4 | First USDT transfer             | 2,076,178     | 2,183,311     | −107,133 (−4.9%)  | **Tolk** | [tx](https://testnet.tonscan.org/tx/5ab69a471e785f82142b9b9bf21eff5861f86c8f1b6d49932639abd6c6584876) | [tx](https://testnet.tonscan.org/tx/909647815f15788c3de593e6e132fc346a9fbe9565ddc09baa69d61cab8df0f1) |
| 5 | Receive TON                     | 47,002        | 36,402        | +10,600 (+22.6%)  | **FunC** | [tx](https://testnet.tonscan.org/tx/462c0af4e7d995bedd9acd91edb655e84ee4b137ab0c71706674b259eae2595c) | [tx](https://testnet.tonscan.org/tx/2a2083bf35933e59ba88fc60a25c00898cd684631cff0da875d3429329087c11) |
| 6 | Gasless TON transfer            | 311,869       | 429,069       | −117,200 (−27.3%) | **Tolk** | [tx](https://testnet.tonscan.org/tx/1e778020384b134908bf31e000d919f13a8404a93be7e0b9fbe4be4060a336a3) | [tx](https://testnet.tonscan.org/tx/b74257cbbadfef59921a823106afb47d05d781b2b8fdfaa304adc38cd66a2e58) |
| 7 | Gasless USDT transfer         | 895,279       | 1,017,346     | −122,067 (−12.0%) | **Tolk** | [tx](https://testnet.tonscan.org/tx/076845723199e10f0ff9bed93b7dcfcce38d97096a7af1ae4b663fed02fa410d) | [tx](https://testnet.tonscan.org/tx/e7280cb8e75d8b38358d459cad9216a3f0853f56838f5153cf4d5d370b2e9fab) |
| 8 | Sponsored USDT transfer + reward  | 1,585,488     | 1,726,755     | −141,267 (−8.2%)  | **Tolk** | [tx](https://testnet.tonscan.org/tx/7901f15d072088c2941f0d8fb4967d85678491af95124cb3f5f8c7a33608bb36) | [tx](https://testnet.tonscan.org/tx/2e159683173c81278913b162bc0770d98cd1e0f1b371da7e562eee6c96e163bd) |

All values in nanograms. Negative diff = Tolk is cheaper.

Note that [tolk-bench](https://github.com/ton-blockchain/tolk-bench) repo indicates `-30%` gas reducing, whereas the table above shows smaller values.
This is not a mistake. When we measure gas only, we do get 30% less. But if we include blockchain message fees (importFee+fwdFee, which are equal to FunC and Tolk),
the percentage for the whole transaction smaller.
