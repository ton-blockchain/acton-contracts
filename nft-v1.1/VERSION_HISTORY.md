## nft-1.1 - 11.05.2026

Rewrote contract in Tolk. Ported tests to Acton toolchain.

## nft-1.03 - 07.12.2022

nft-item:

Added additional check for transfer message correctness: `throw_unless(708, slice_bits(in_msg_body) >= 1);`.

Previously, it was possible to send a transfer without `either_forward_payload` bit, which formally does not comply with the standard.

## nft-getgems-v2 - 08.05.2023

https://github.com/getgems-io/nft-contracts/blob/main/packages/contracts/sources/nft-item-v2.fc

Differences with nft-item-1.02:

* Can send `ownership_assigned` on `init` if `forward_ton_amount` is specified.

https://github.com/getgems-io/nft-contracts/blob/main/packages/contracts/sources/nft-collection-editable-v2.fc

Differences with collection-editable-1.02:

* Optional `second_owner` added, `get_second_owner_address()` get-method, `change_second_owner` message.

* Auto-increment option for batch deploy.

* Return collection Toncoin balance (op = 5) message.

## nft-1.02 - 23.11.2022

nft-item:

Improved calculation of the required TON amount for gas for transfer: `fwd_fee = in_msg.fwd_fee` -> `fwd_fee = muldiv(in_msg.fwd_fee, 3, 2)`.

Previously, it was required to attach **less** TONs than necessary.

## dns-1.0 - 30.07.2022

https://github.com/ton-blockchain/dns-contract

Based on nft-1.01.

## nft-1.01 - 03.04.2022

Cosmetic

## nft-getgems-v1 - 11.07.2022

https://github.com/getgems-io/nft-contracts/blob/main/packages/contracts/sources/nft-item.fc
Identical with nft-item-1.00

https://github.com/getgems-io/nft-contracts/blob/main/packages/contracts/sources/nft-collection-editable.fc
Identical with nft-collection-editable-1.00.

## nft-1.00 - 31.03.2022

First Release: https://t.me/tonblockchain/112.

