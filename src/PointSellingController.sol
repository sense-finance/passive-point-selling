// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @dev Provided address for tokens iz zero
error ZeroAddressProvided();

/// @dev users and claims arrays do not have the same length
error ArrayLengthMismatch();

/// @dev one of the provided requests is inactive
error RequestInactive();

/// @dev one or more requests have different tokenOut
error TokenOutMismatch();

struct PointSaleRequest {
    bool active;
    IERC20 tokenOut;
    uint256 minPrice;
}

struct Claim {
    bytes32 pointsId;
    uint256 totalClaimable;
    uint256 amountToClaim;
    bytes32[] proof;
}

interface IPointMinter {
    function claimPTokens(Claim calldata _claim, address _account, address _receiver) external;
}

abstract contract PointSellingController is Ownable2Step {
    mapping(address user => mapping(IERC20 pToken => PointSaleRequest request)) public requests;

    uint256 public fee = 1e15;

    /// @dev Adds, updates or deactivates point selling request
    /// Reverts if provided pToken address is zero address
    /// Reverts if provided tokenOut is zero address
    /// @param pToken address of the pToken
    /// @param request sale request data
    function updateRequest(IERC20 pToken, PointSaleRequest calldata request) external {
        require(address(pToken) != address(0), ZeroAddressProvided());
        require(address(request.tokenOut) != address(0), ZeroAddressProvided());

        requests[msg.sender][pToken] = request;
    }

    /// @dev Executes batch point sale. Each user needs to register this contract as a trusted reciever.
    /// Reverts if @param claims and @param users have different length
    /// Reverts if batch requests do not have the same pTokenIn and tokenOut
    /// Reverts if one of the requests is not active
    /// Assumes that provided pointId from @param claims will match actual @param pToken
    /// @param pToken address of the pToken being sold
    /// @param users addresses of users selling pTokens
    /// @param pointMinter address of the contract to mint points
    /// @param claims claims for each user's points
    function executePointSale(
        IERC20 pToken,
        address[] calldata users,
        IPointMinter pointMinter,
        Claim[] calldata claims
    ) external onlyOwner {
        require(users.length == claims.length, ArrayLengthMismatch());
        IERC20 tokenOut = requests[users[0]][pToken].tokenOut;

        PointSaleRequest[] memory requests_ = new PointSaleRequest[](users.length);
        uint256 totalPoints;
        uint256 minPrice;

        for (uint256 i = 0; i < users.length; i++) {
            requests_[i] = requests[users[i]][pToken];
            require(requests_[i].active, RequestInactive());
            require(tokenOut == requests_[i].tokenOut, TokenOutMismatch());

            pointMinter.claimPTokens(claims[i], users[i], address(this));
            totalPoints += claims[i].amountToClaim;

            // chose the best possible minPrice of the batch
            minPrice = requests_[i].minPrice > minPrice ? requests_[i].minPrice : minPrice;
        }

        uint256 tokenOutPrecision = 10 ** IERC20Metadata(address(tokenOut)).decimals();
        uint256 amountOut = swap(pToken, tokenOut, totalPoints, totalPoints * minPrice / tokenOutPrecision);

        /// To be discussed if fee should be paid in point token instead
        uint256 feeAmount = amountOut * fee / 1e18;
        tokenOut.transfer(msg.sender, feeAmount);

        for (uint256 i = 0; i < users.length; i++) {
            tokenOut.transfer(users[i], amountOut * claims[i].amountToClaim / totalPoints);
        }
    }

    /// @dev Abstract function used to implement swaps from pToken to requested token out
    /// Derived contract should implement particular strategies for swaps
    /// @param tokenIn address of the token to be swapped
    /// @param tokenOut address of the token to be swapped for
    /// @param amountIn amount of @param tokenIn to be swapped
    /// @param minReturn minimal amount of @param tokenOut to be received
    function swap(IERC20 tokenIn, IERC20 tokenOut, uint256 amountIn, uint256 minReturn)
        internal
        virtual
        returns (uint256 amountOut);
}
