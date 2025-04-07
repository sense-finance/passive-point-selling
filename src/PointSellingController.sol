// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {console} from "forge-std/console.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @dev Provided address for tokens iz zero
error ZeroAddressProvided();

/// @dev users and claims arrays do not have the same length
error ArrayLengthMismatch();

/// @dev min price for pToken sale is lower than one or more user provided values
error MinPriceTooLow();

/// @dev user is not a rumpel wallet owner
error NotSafeOwner();

/// @dev provided fee percentage too large
error FeeTooLarge();

event FeeUpdated(uint256 oldFee, uint256 newFee);

event UserPreferencesUpdated(address indexed user, IERC20 indexed pToken, UserPreferences preferences);

event PointSaleExecuted(IERC20 indexed pToken, uint256 amountOut, uint256 fee);

struct UserPreferences {
    uint256 minPrice;
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

// NOTES
// - should we use uni v4
// make sure sale works with different ptokens
// add test for no explicity preferences

abstract contract PointSellingController is Ownable2Step {
    uint256 MAX_FEE = 1e17; // 10%
    uint256 FEE_PRECISION = 1e18;

    mapping(address user => mapping(IERC20 pToken => UserPreferences preferences)) public userPreferences;

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
    /// @param pToken address of the pToken
    /// @param preferences sale request data
    function setUserPreferences(address rumpelWallet, IERC20 pToken, UserPreferences calldata preferences) external {
        require(address(pToken) != address(0), ZeroAddressProvided());

        if (rumpelWallet != msg.sender && !ISafe(rumpelWallet).isOwner(msg.sender)) {
            revert NotSafeOwner();
        }

        userPreferences[rumpelWallet][pToken] = preferences;

        emit UserPreferencesUpdated(rumpelWallet, pToken, preferences);
    }

    /// @dev Executes batch point sale. Each user needs to add this contract as a trusted reciever via the Rumpel Point Tokenization Vault.
    /// Reverts if @param claims and @param users have different length
    /// Reverts if batch requests do not have the same pTokenIn and tokenOut
    /// Reverts if one of the requests is not active
    /// Assumes that provided pointId from @param claims will match actual @param pToken
    /// @param pToken address of the pToken being sold
    /// @param tokenOut address of the token to be swapped for
    /// @param wallets rumpel wallets of users selling pTokens
    /// @param pointTokenizationVault address of the contract to mint points
    /// @param claims claims for each user's points
    /// @param minPrice minimum price for selling pTokens
    /// @param additionalParams additional swap params, specific to concrete implementation
    function executePointSale(
        IERC20 pToken,
        IERC20 tokenOut,
        address[] calldata wallets,
        IPointTokenizationVault pointTokenizationVault,
        Claim[] calldata claims,
        uint256 minPrice,
        bytes calldata additionalParams
    ) external onlyOwner {
        require(wallets.length == claims.length, ArrayLengthMismatch());

        uint256 totalPTokens;

        bytes[] memory calls = new bytes[](wallets.length);

        for (uint256 i = 0; i < wallets.length; i++) {
            // If the user has set a minimum price, it must be met. Default minimum price is 0.
            require(minPrice >= userPreferences[wallets[i]][pToken].minPrice, MinPriceTooLow());

            // Can only be done for users that have added this contract as a trusted receiver.
            // We assume that if they have done this, they have opted into passive point selling.
            calls[i] = abi.encodeCall(pointTokenizationVault.claimPTokens, (claims[i], wallets[i], address(this)));

            totalPTokens += claims[i].amountToClaim;
        }

        // Claim all users' points in one multicall.
        pointTokenizationVault.multicall(calls);

        // Swap all pTokens for tokenOut.
        // We assume that the path passed in through additionalParams is the best path to swap pTokens for tokenOut.
        uint256 amountOut = swap(pToken, tokenOut, totalPTokens, minPrice, additionalParams);

        /// To be discussed if fee should be paid in point token instead.
        if (fee > 0) {
            tokenOut.transfer(msg.sender, amountOut * fee / FEE_PRECISION);
        }

        // Transfer tokenOut to users.
        for (uint256 i = 0; i < wallets.length; i++) {
            // If the user has set a recipient, transfer the tokenOut to them.
            address recipient = userPreferences[wallets[i]][pToken].recipient;

            // If not set, transfer to the owner of the rumpel wallet in the first owner slot.
            if (recipient == address(0)) {
                address[] memory walletOwners = ISafe(wallets[i]).getOwners();
                recipient = walletOwners[0];
            }

            tokenOut.transfer(
                recipient, (amountOut * (FEE_PRECISION - fee) / FEE_PRECISION) * claims[i].amountToClaim / totalPTokens
            );
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
    function swap(IERC20 tokenIn, IERC20 tokenOut, uint256 amountIn, uint256 minPrice, bytes calldata additionalParams)
        internal
        virtual
        returns (uint256 amountOut);
}
