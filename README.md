# Passive Point Selling Contracts

This repository contains Solidity smart contracts designed to facilitate the automated, non-custodial batch selling of point tokens (pTokens) on behalf of users.

## Overview

The system allows users to delegate the selling process of their accrued pTokens. Users optionally configure their preferences, including minimum acceptable selling prices. A designated operator can then initiate batch sales, claiming pTokens for participating users, executing a swap for a desired output token (e.g., stablecoin), and distributing the proceeds back to the users proportionally. The operator is trusted to assemble the batch correctly, and telegraph actions and expectations to users out of band.

## Core Functionality

1.  **User Preference Management (`setUserPreferences`)**:
    *   Allows users (identified by their `rumpelWallet` Safe address) to register their preferences for automated selling.
    *   Users specify target pTokens and the minimum price they are willing to accept for each, denominated in the output token (which needs to be publicly specified by the operator).
    *   Users designate a recipient address for sale proceeds. If none is provided, proceeds are sent to the `rumpelWallet` owner, provided the wallet has only one owner.
    *   Requires the caller to be an owner of the `rumpelWallet` or the wallet itself.

2.  **Batch Point Sale Execution (`executePointSale`)**:
    *   An `onlyOwner` function callable by a trusted administrator/operator.
    *   Takes inputs including the pToken address, the desired output token address, lists of participating user wallets and corresponding claim data (for interaction with an external `IPointTokenizationVault`), a global minimum price floor for the batch, and implementation-specific swap parameters.
    *   Verifies that the batch minimum price meets or exceeds each participating user's pre-configured minimum price.
    *   Interacts with the provided `IPointTokenizationVault` via `multicall` to claim pTokens from all participating users directly to this contract.
    *   Executes a swap of the aggregated pTokens for the specified output token using the `swap` function (implemented by derived contracts).
    *   Applies a configurable percentage fee (`fee`) to the total output amount, transferring the fee to the contract owner/operator.
    *   Distributes the remaining output tokens to the users' designated recipients, calculated proportionally based on their individual pToken contribution to the batch total.

## Contract Architecture

*   **`PointSellingController.sol`**:
    *   An abstract base contract containing the core logic for user preference storage (`userPreferences`), fee management, permissioning (`Ownable2Step`), and the main `executePointSale` workflow.
    *   Defines external view functions (`getMinPrice`, `getRecipient`) to query user settings.
    *   Declares an internal abstract `swap` function that must be implemented by inheriting contracts to define the token swapping strategy.

*   **`UniswapV3PointSellingController.sol`**:
    *   A concrete implementation inheriting from `PointSellingController`.
    *   Implements the `swap` function using the Uniswap V3 Router (`ISwapRouter`).
    *   Requires `additionalParams` in `executePointSale` to be ABI-encoded `(bytes path, uint256 deadline)`.
    *   Handles approvals for the `tokenIn` to the Uniswap V3 Router.
    *   Calculates the minimum output amount for the Uniswap V3 swap based on the provided `minPrice` and the `amountIn`.

## Design Rationale

*   **Batch Processing**: Aggregates pToken claims and swaps into fewer transactions to reduce gas costs for users and potentially achieve better price execution on the swap due to larger volume.
*   **Admin-Controlled Execution**: Sales are initiated by a trusted owner role. This simplifies the management of off-chain claim data (like Merkle proofs required by the `PointTokenizationVault`) and mitigates potential MEV risks (e.g., front-running) associated with fully permissionless sale initiation.
*   **User Price Protection**: Ensures sales only occur if the achieved price meets or exceeds the user's specified minimum threshold. The `executePointSale` also enforces a batch-wide minimum price. If a user's minimum price cannot be met by the market, it won't be included in the batch.
*   **Non-Custodial**: The contract only holds tokens temporarily during the claim and swap process within a single transaction. Proceeds are distributed immediately.

## Security Considerations

*   **Minimum Price Enforcement**: User-defined and batch-wide minimum prices prevent sales below acceptable thresholds.
*   **Proportional Distribution**: Proceeds are distributed fairly based on each user's contribution.
*   **Access Control**: `setUserPreferences` requires wallet ownership, while `executePointSale` and fee configuration are restricted to the contract owner.
*   **External Dependencies**: Relies on a specified `IPointTokenizationVault` for claims and an implementation-specific swap venue (e.g., Uniswap V3 Router in `UniswapV3PointSellingController`). The security of these external components is critical.
*   **Single Owner Assumption**: If a user does not specify a recipient, the system assumes their `rumpelWallet` has a single owner. Multi-owner wallets must specify a recipient explicitly to avoid not being included in the batch.

## Chains

For now, the only chain slated for support is ethereum mainnet.