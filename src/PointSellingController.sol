// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @dev Provided address for tokens iz zero
error ZeroAddressProvided();

/// @dev users and claims arrays do not have the same length
error ArrayLengthMismatch();

/// @dev one of the provided requests is inactive
error RequestInactive();

/// @dev one or more requests have different tokenOut
error TokenOutMismatch();

/// @dev min price for pToken sale is lower than one or more user provided values
error MinPriceTooLow();

/// @dev user is not a rumpel wallet owner
error NotSafeOwner();

/// @dev provided fee percentage too large
error FeeTooLarge();

struct PointSaleRequest {
    bool active;
    IERC20 tokenOut;
    uint256 minPrice;
    address recipient;
}

struct Claim {
    bytes32 pointsId;
    uint256 totalClaimable;
    uint256 amountToClaim;
    bytes32[] proof;
}

interface IPointMinter {
    function claimPTokens(Claim calldata _claim, address _account, address _receiver) external;
    function trustReceiver(address _account, bool _isTrusted) external;
}

interface ISafe {
    function isOwner(address _owner) external view returns (bool);
}

abstract contract PointSellingController is Ownable2Step {
    uint256 MAX_FEE = 1e17; // 10%
    uint256 FEE_PRECISION = 1e18;

    mapping(address user => mapping(IERC20 pToken => PointSaleRequest request)) public requests;

    uint256 public fee = 1e15;

    constructor(address initialOwner) Ownable(initialOwner) {}

    /// @dev sets fee percentage. Reverts if fee is bigger than `MAX_FEE`
    /// @param newFee new fee percentage
    function setFeePercentage(uint256 newFee) external onlyOwner {
        require(newFee <= MAX_FEE, FeeTooLarge());
        fee = newFee;
    }

    /// @dev Adds, updates or deactivates point selling request
    /// Reverts if provided pToken address is zero address
    /// Reverts if provided tokenOut is zero address
    /// @param rumpelWallet address of the user's rumpel wallet
    /// @param pToken address of the pToken
    /// @param request sale request data
    function updateRequest(address rumpelWallet, IERC20 pToken, PointSaleRequest calldata request) external {
        require(address(pToken) != address(0), ZeroAddressProvided());
        require(address(request.tokenOut) != address(0), ZeroAddressProvided());

        if (rumpelWallet != msg.sender && !ISafe(rumpelWallet).isOwner(msg.sender)) {
            revert NotSafeOwner();
        }

        requests[rumpelWallet][pToken] = request;
    }

    /// @dev Executes batch point sale. Each user needs to register this contract as a trusted reciever.
    /// Reverts if @param claims and @param users have different length
    /// Reverts if batch requests do not have the same pTokenIn and tokenOut
    /// Reverts if one of the requests is not active
    /// Assumes that provided pointId from @param claims will match actual @param pToken
    /// @param pToken address of the pToken being sold
    /// @param wallets rumpel wallets of users selling pTokens
    /// @param pointMinter address of the contract to mint points
    /// @param claims claims for each user's points
    /// @param minPrice minimum price for selling pTokens
    /// @param additionalParams additional swap params, specific to concrete implementation
    function executePointSale(
        IERC20 pToken,
        address[] calldata wallets,
        IPointMinter pointMinter,
        Claim[] calldata claims,
        uint256 minPrice,
        bytes calldata additionalParams
    ) external onlyOwner {
        require(wallets.length == claims.length, ArrayLengthMismatch());
        IERC20 tokenOut = requests[wallets[0]][pToken].tokenOut;

        PointSaleRequest[] memory requests_ = new PointSaleRequest[](wallets.length);
        uint256 totalPoints;

        for (uint256 i = 0; i < wallets.length; i++) {
            requests_[i] = requests[wallets[i]][pToken];
            require(requests_[i].active, RequestInactive());
            require(tokenOut == requests_[i].tokenOut, TokenOutMismatch());
            require(minPrice >= requests_[i].minPrice, MinPriceTooLow());

            pointMinter.claimPTokens(claims[i], wallets[i], address(this));
            totalPoints += claims[i].amountToClaim;
        }

        uint256 amountOut = swap(pToken, tokenOut, totalPoints, minPrice, additionalParams);

        /// To be discussed if fee should be paid in point token instead
        if (fee > 0) {
            tokenOut.transfer(msg.sender, amountOut * fee / FEE_PRECISION);
        }

        for (uint256 i = 0; i < wallets.length; i++) {
            tokenOut.transfer(
                requests[wallets[i]][pToken].recipient,
                (amountOut * (FEE_PRECISION - fee) / FEE_PRECISION) * claims[i].amountToClaim / totalPoints
            );
        }
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
