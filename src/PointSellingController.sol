// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

/// @dev Provided address for tokens iz zero
error ZeroAddressProvided();

/// @dev users and claims arrays do not have the same length
error ArrayLengthMismatch();

/// @dev min price for pToken sale is lower than one or more user provided values
error MinPriceTooLow();

/// @dev user is not a rumpel wallet owner
error NotSafeOwner(address sender, address wallet);

/// @dev provided fee percentage too large
error FeeTooLarge();

event FeeUpdated(uint256 oldFee, uint256 newFee);

event UserPreferencesUpdated(address indexed user, address recipient, ERC20[] indexed pTokens, uint256[] minPrices);

event PointSaleExecuted(ERC20 indexed pToken, uint256 amountOut, uint256 fee);

/// @notice User preferences for passive point selling
/// @param minPrice Minimum price user will accept for their points
/// @param recipient Address that will receive proceeds (zero address = rumpel wallet owner)
struct UserPreferences {
    mapping(ERC20 pToken => uint256 minPrice) minPrices;
    address recipient;
}

struct Claim {
    bytes32 pointsId;
    uint256 totalClaimable;
    uint256 amountToClaim;
    bytes32[] proof;
}

interface IPointTokenizationVault {
    function claimPTokens(Claim calldata _claim, address _account, address _receiver) external;
    function trustReceiver(address _account, bool _isTrusted) external;
    function claimedPTokens(address _account, bytes32 _pointsId) external view returns (uint256);
    function multicall(bytes[] calldata calls) external;
}

interface ISafe {
    function isOwner(address _owner) external view returns (bool);
    function getOwners() external view returns (address[] memory);
}

abstract contract PointSellingController is Ownable2Step {
    using SafeTransferLib for ERC20;

    uint256 public constant MAX_FEE = 1e17; // 10%
    uint256 public constant FEE_PRECISION = 1e18;

    mapping(address wallet => UserPreferences preferences) public userPreferences;

    uint256 public fee = 1e15;

    constructor(address initialOwner) Ownable(initialOwner) {}

    /// @dev sets fee percentage. Reverts if fee is bigger than `MAX_FEE`
    /// @param newFee new fee percentage
    function setFeePercentage(uint256 newFee) external onlyOwner {
        require(newFee <= MAX_FEE, FeeTooLarge());
        emit FeeUpdated(fee, newFee);
        fee = newFee;
    }

    /// @dev Adds, updates or deactivates user preferences
    /// Reverts if provided pToken address is zero address
    /// @param rumpelWallet address of the user's rumpel wallet
    /// @param recipient address of the recipient
    /// @param pTokens array of pToken addresses
    /// @param minPrices array of minimum prices for each pToken
    function setUserPreferences(
        address rumpelWallet,
        address recipient,
        ERC20[] calldata pTokens,
        uint256[] calldata minPrices
    ) external {
        require(pTokens.length == minPrices.length, ArrayLengthMismatch());
        // TODO: ensure it is a rumpel wallet?
        // TODO: safe transfer and approve

        if (rumpelWallet != msg.sender && !ISafe(rumpelWallet).isOwner(msg.sender)) {
            revert NotSafeOwner(msg.sender, rumpelWallet);
        }

        userPreferences[rumpelWallet].recipient = recipient;
        for (uint256 i = 0; i < pTokens.length; i++) {
            userPreferences[rumpelWallet].minPrices[pTokens[i]] = minPrices[i];
        }

        emit UserPreferencesUpdated(rumpelWallet, recipient, pTokens, minPrices);
    }

    /// @notice Returns the minimum price set by a user for a specific pToken
    /// @param wallet The user's wallet address
    /// @param pToken The pToken address
    /// @return The minimum price set, or 0 if not set
    function getUserMinPrice(address wallet, ERC20 pToken) external view returns (uint256) {
        return userPreferences[wallet].minPrices[pToken];
    }

    /// @notice Executes a point sale for multiple users
    /// @param pToken Address of the pToken being sold
    /// @param tokenOut Address of the token to receive
    /// @param wallets Array of user wallet addresses
    /// @param pointTokenizationVault The vault contract for claiming points
    /// @param claims Array of claim data for each wallet
    /// @param minPrice Minimum price floor for all transactions
    /// @param additionalParams Implementation-specific swap parameters
    function executePointSale(
        ERC20 pToken,
        ERC20 tokenOut,
        address[] calldata wallets,
        IPointTokenizationVault pointTokenizationVault,
        Claim[] calldata claims,
        uint256 minPrice,
        bytes calldata additionalParams
    ) external onlyOwner {
        uint256 numWallets = wallets.length;
        require(numWallets == claims.length, ArrayLengthMismatch());

        uint256 totalPTokens;

        bytes[] memory calls = new bytes[](numWallets);

        for (uint256 i = 0; i < numWallets; i++) {
            // If the user has set a minimum price, it must be met. Default minimum price is 0.
            require(minPrice >= userPreferences[wallets[i]].minPrices[pToken], MinPriceTooLow());

            // Can only be done for users that have added this contract as a trusted receiver.
            // We assume that if they have done this, they have opted into passive point selling.
            calls[i] = abi.encodeCall(pointTokenizationVault.claimPTokens, (claims[i], wallets[i], address(this)));

            unchecked {
                totalPTokens += claims[i].amountToClaim;
            }
        }

        // Claim all users' points in one multicall.
        pointTokenizationVault.multicall(calls);

        // Swap all pTokens for tokenOut.
        // We assume that the path passed in through additionalParams is the best path to swap pTokens for tokenOut.
        uint256 amountOut = swap(pToken, tokenOut, totalPTokens, minPrice, additionalParams);

        uint256 feeAmount = amountOut * fee / FEE_PRECISION;
        uint256 remainingAmount = amountOut - feeAmount;

        if (fee > 0) {
            tokenOut.safeTransfer(msg.sender, feeAmount);
        }

        // Transfer tokenOut to users.
        for (uint256 i = 0; i < wallets.length; i++) {
            // If the user has set a recipient, transfer the tokenOut to them.
            address recipient = userPreferences[wallets[i]].recipient;

            // If not set, transfer to the owner of the rumpel wallet existing in the first slot.
            if (recipient == address(0)) {
                address[] memory walletOwners = ISafe(wallets[i]).getOwners();
                recipient = walletOwners[0];
            }

            // Calculate each user's share proportional to their contribution
            uint256 walletShare = (remainingAmount * claims[i].amountToClaim) / totalPTokens;
            tokenOut.safeTransfer(recipient, walletShare);
        }

        emit PointSaleExecuted(pToken, amountOut, fee);
    }

    /// @dev Abstract function used to implement swaps from pToken to requested token out
    /// Derived contract should implement particular strategies for swaps
    /// @param tokenIn address of the token to be swapped
    /// @param tokenOut address of the token to be swapped for
    /// @param amountIn amount of @param tokenIn to be swapped
    /// @param minPrice minimal price in @param tokenOut precision for the swap
    /// @param additionalParams additional swap params, specific to concrete implementation
    function swap(ERC20 tokenIn, ERC20 tokenOut, uint256 amountIn, uint256 minPrice, bytes calldata additionalParams)
        internal
        virtual
        returns (uint256 amountOut);
}
