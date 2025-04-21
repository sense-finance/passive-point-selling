// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

/// @dev users and claims arrays do not have the same length
error ArrayLengthMismatch();

/// @dev min price for pToken sale is lower than one or more user provided values
error MinPriceTooLow();

/// @dev user is not a rumpel wallet owner
error NotSafeOwner(address sender, address wallet);

/// @dev provided fee percentage too large
error FeeTooLarge();

/// @dev rumpel wallet has multiple owners
error MultipleOwners();

event FeeUpdated(uint256 oldFee, uint256 newFee);

event UserPreferencesUpdated(address indexed user, address indexed recipient, ERC20[] pTokens, uint256[] minPrices);

event PointSaleExecuted(ERC20 indexed pToken, ERC20 indexed tokenOut, uint256 amountIn, uint256 amountOut, uint256 fee);

/// @notice User preferences for passive point selling
/// @param minPrice Minimum price user will accept for their points, scaled by tokenOut.decimals, expected per 1 unit tokenIn (pTokens always 18 decimals)
/// @param recipient Address that will receive proceeds (zero address = rumpel wallet owner)
struct UserPreferences {
    mapping(ERC20 pToken => uint256 minPrice) minPrices; // minPrice of 0 means any price is accepted.
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

    uint256 public constant MAX_FEE = 0.3e18; // 30%
    uint256 public constant FEE_PRECISION = 1e18;

    mapping(address wallet => UserPreferences preferences) public userPreferences;

    uint256 public fee = 1e15; // 0.01%

    constructor(address initialOwner) Ownable(initialOwner) {}

    /// @dev sets fee percentage. Reverts if fee is bigger than `MAX_FEE`
    /// @param newFee new fee percentage
    function setFeePercentage(uint256 newFee) external onlyOwner {
        require(newFee <= MAX_FEE, FeeTooLarge());
        emit FeeUpdated(fee, newFee);
        fee = newFee;
    }

    /// @notice Store or update a user's preferences
    /// @dev Caller must be the Safe itself or one of its owners (if there is only one owner)
    /// @param rumpelWallet  User's Safe (rumpel wallet)
    /// @param recipient     Address that should receive sale proceeds (0x00 = Safe owner)
    /// @param pTokens       Point tokens to set preferences for
    /// @param minPrices     Minimum acceptable prices, scaled to `tokenOut.decimals`
    ///                      It is on the operator to publicize what the tokenOut is, and announce/give a heads up to users when it changes
    function setUserPreferences(
        address rumpelWallet,
        address recipient,
        ERC20[] calldata pTokens,
        uint256[] calldata minPrices
    ) external {
        require(pTokens.length == minPrices.length, ArrayLengthMismatch());

        address[] memory walletOwners = ISafe(rumpelWallet).getOwners();
        // If the rumpel wallet has multiple owners, preferences can only be set by the wallet itself.
        if (walletOwners.length > 1) {
            if (rumpelWallet != msg.sender) {
                revert MultipleOwners();
            }
        } else {
            // If the rumpel wallet has only one owner, preferences can be set by that owner or the wallet itself.
            if (walletOwners[0] != msg.sender && rumpelWallet != msg.sender) {
                revert NotSafeOwner(msg.sender, rumpelWallet);
            }
        }

        userPreferences[rumpelWallet].recipient = recipient;
        for (uint256 i = 0; i < pTokens.length; i++) {
            userPreferences[rumpelWallet].minPrices[pTokens[i]] = minPrices[i]; // Based on the tokenOut publicized by the operator.
        }

        emit UserPreferencesUpdated(rumpelWallet, recipient, pTokens, minPrices);
    }

    /// @notice Returns the minimum price set by a user for a specific pToken
    /// @param rumpelWallet The user's wallet address
    /// @param pToken The pToken address
    /// @return The minimum price set, or 0 if not set
    function getMinPrice(address rumpelWallet, ERC20 pToken) external view returns (uint256) {
        return userPreferences[rumpelWallet].minPrices[pToken];
    }

    /// @notice Returns the recipient address set by a user for a specific rumpel wallet
    /// @param rumpelWallet The user's wallet address
    /// @return The recipient address, or the zero address if not set
    function getRecipient(address rumpelWallet) external view returns (address) {
        return userPreferences[rumpelWallet].recipient;
    }

    /// @notice Execute a bulk claim and swap of users' pTokens.
    /// @dev 1. Enforces each user's floor price
    ///      2. Claims tokens via `multicall`
    ///      3. Swaps to `tokenOut`, takes protocol fee, then distributes pro-rata
    /// @param pToken          the ERC-20 point token to sell (always 18 decimals)
    /// @param tokenOut        the ERC-20 users will receive
    /// @param wallets         each user's Rumpel Wallet address
    /// @param pointTokenizationVault  vault used to claim pTokens
    /// @param claims          pre-constructed proofs & amounts for each wallet
    /// @param minPrice        global floor price (18 decimals)
    /// @param additionalParams encoded path, slippage, etc.
    function executePointSale(
        ERC20 pToken,
        ERC20 tokenOut,
        address[] calldata wallets,
        IPointTokenizationVault pointTokenizationVault,
        Claim[] calldata claims,
        uint256 minPrice,
        bytes calldata additionalParams
    ) external onlyOwner {
        // Admin only. We assume the admin has already constructed the list of valid wallets and claims.
        uint256 numWallets = wallets.length;
        require(numWallets == claims.length, ArrayLengthMismatch());

        uint256 totalPTokens;

        bytes[] memory calls = new bytes[](numWallets);

        for (uint256 i = 0; i < numWallets; i++) {
            address wallet = wallets[i];

            // If the user has set a minimum price, it must be met. Default minimum price is 0.
            require(minPrice >= userPreferences[wallet].minPrices[pToken], MinPriceTooLow());

            // Can only be done for users that have added this contract as a trusted receiver.
            // We assume that if they have done this, they have opted into passive point selling.
            calls[i] = abi.encodeCall(pointTokenizationVault.claimPTokens, (claims[i], wallet, address(this)));

            unchecked {
                totalPTokens += claims[i].amountToClaim;
            }
        }

        // Claim all users' points in one multicall.
        pointTokenizationVault.multicall(calls);

        // Swap all pTokens for tokenOut.
        // We assume that the path passed in through additionalParams is the best path to swap pTokens for tokenOut.
        uint256 amountOut = swap(pToken, tokenOut, totalPTokens, minPrice, additionalParams);

        uint256 _fee = fee;
        uint256 feeAmount = amountOut * _fee / FEE_PRECISION;
        uint256 remainingAmount = amountOut - feeAmount;

        if (_fee > 0) {
            tokenOut.safeTransfer(msg.sender, feeAmount);
        }

        // Transfer tokenOut to users.
        for (uint256 i = 0; i < numWallets; i++) {
            // If the user has set a recipient, transfer the tokenOut to them.
            address recipient = userPreferences[wallets[i]].recipient;

            // If not set, transfer to the owner of the rumpel wallet existing in the first slot.
            if (recipient == address(0)) {
                address[] memory walletOwners = ISafe(wallets[i]).getOwners();
                // If the rumpel wallet has multiple owners, and a recipient is not set, revert.
                if (walletOwners.length > 1) {
                    revert MultipleOwners();
                }
                recipient = walletOwners[0];
            }

            // Calculate each user's share proportional to their contribution.
            uint256 walletShare = FixedPointMathLib.mulDivDown(remainingAmount, claims[i].amountToClaim, totalPTokens); // Dust is accepted.
            tokenOut.safeTransfer(recipient, walletShare);
        }

        emit PointSaleExecuted(pToken, tokenOut, totalPTokens, amountOut, _fee);
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
