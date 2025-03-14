// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

error Unauthorized();
error ZeroAddressProvided();
error ArrayLengthMismatch();
error RequestInactive();
error PointTokenMismatch();
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

    function updateRequest(IERC20 pToken, PointSaleRequest calldata request) external {
        require(address(pToken) != address(0), ZeroAddressProvided());
        require(address(request.tokenOut) != address(0), ZeroAddressProvided());

        requests[msg.sender][pToken] = request;
    }

    /// @dev Executes batch point sale. Each user needs to register this contract as a trusted reciever.
    /// Reverts if @param claims and @param users have different length
    /// Reverts if batch requests do not have the same pTokenIn and tokenOut
    /// Reverts if one of the requests is not active
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

    function swap(IERC20 tokenIn, IERC20 tokenOut, uint256 amountIn, uint256 minReturn)
        internal
        virtual
        returns (uint256 amountOut);
}
