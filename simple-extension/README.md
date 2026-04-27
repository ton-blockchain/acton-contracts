# Simple Extension W5 Console

This project contains a Simple Extension contract for Wallet V5, generated
TypeScript wrappers under `wrappers/`, and a Vite-based React app in `app/`
for inspecting Wallet V5 extensions and sending supported external extension
messages through Toncenter.

## Layout

- `contracts/src` contains the Simple Extension contract and shared Tolk types.
- `contracts/tests` contains integration tests.
- `contracts/wrappers` contains Tolk wrappers used by tests and scripts.
- `contracts/scripts` contains deployment and extension-management scripts.
- `wrappers/WalletV5.gen.ts` and `wrappers/SimpleExtension.gen.ts` are the generated
  TypeScript wrappers consumed by the app.
- `app/` contains the React + Vite frontend.
- `package.json`, `tsconfig.json`, and `vite.config.ts` configure the app
  toolchain.
- `package-lock.json` pins the npm dependency tree for reproducible installs.

## Install

```bash
npm ci
```

## Commands

```bash
acton build
npm run gen:wrappers
acton test
npm run build
npm run typecheck
npm run fmt:check
npm run dev
```

## Notes

- `npm run build:contracts` compiles contracts and regenerates TypeScript
  wrappers with Acton.
- `npm run build` runs the contract build, wrapper generation, and the frontend
  build.
- `npm run test` delegates to `acton test`.
- The app reads blockchain data through Toncenter. Set
  `TONCENTER_TESTNET_API_KEY` and/or `TONCENTER_MAINNET_API_KEY` in `.env` if
  you need higher rate limits. A legacy `TONCENTER_API_KEY` or
  `VITE_TONCENTER_API_KEY` value is also accepted.
