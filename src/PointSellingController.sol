// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

error Unauthorized();
error ZeroAddressProvided();
error ArrayLengthMismatch();
error RequestInactive();
error PointTokenMismatch();
error TokenOutMismatch();

struct PointSaleRequest {
    address user;
    bool active;
    IERC20 pTokenIn;
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

abstract contract PointSellingController {
    uint256 public nextRequestId;

    mapping(uint256 requestId => PointSaleRequest request) public requests;

    uint256 public fee = 1e16;

    function addRequest(PointSaleRequest calldata request) external returns (uint256 requestId) {
        require(request.user == msg.sender, Unauthorized());
        require(address(request.tokenOut) != address(0), ZeroAddressProvided());
        require(address(request.pTokenIn) != address(0), ZeroAddressProvided());

        requestId = nextRequestId++;
        requests[requestId] = request;
    }

    function setRequestActive(uint256 requestId, bool isActive) external {
        require(requests[requestId].user == msg.sender, Unauthorized());
        requests[requestId].active = isActive;
    }

    /// @dev Executes batch point sale. Each user needs to register this contract as a trusted reciever.
    /// Reverts if @param claims and @param requestIds have different length
    /// Reverts if batch requests do not have the same pTokenIn and tokenOut
    /// Reverts if one of the requests is not active
    /// @param requestIds ids of user requests to be batched
    /// @param pointMinter address of the contract to mint points
    /// @param claims claims for each user's points
    function executePointSale(uint256[] calldata requestIds, IPointMinter pointMinter, Claim[] calldata claims)
        external
    {
        require(requestIds.length == claims.length, ArrayLengthMismatch());
        IERC20 pToken = requests[requestIds[0]].pTokenIn;
        IERC20 tokenOut = requests[requestIds[0]].tokenOut;

        PointSaleRequest[] memory requests_ = new PointSaleRequest[](requestIds.length);
        uint256 totalPoints;
        uint256 minPrice;

        for (uint256 i = 0; i < requestIds.length; i++) {
            requests_[i] = requests[requestIds[i]];
            require(requests_[i].active, RequestInactive());
            require(pToken == requests_[i].pTokenIn, PointTokenMismatch());
            require(tokenOut == requests_[i].tokenOut, TokenOutMismatch());

            pointMinter.claimPTokens(claims[i], requests_[i].user, address(this));
            totalPoints += claims[i].amountToClaim;

            // chose the best possible minPrice of the batch
            minPrice = requests_[i].minPrice > minPrice ? requests_[i].minPrice : minPrice;
        }

        uint256 tokenOutPrecision = 10 ** IERC20Metadata(address(tokenOut)).decimals();
        uint256 amountOut = swap(pToken, tokenOut, totalPoints, totalPoints * minPrice / tokenOutPrecision);

        /// To be discussed if fee should be paid in point token instead
        uint256 feeAmount = amountOut * fee / 1e18;
        tokenOut.transfer(msg.sender, feeAmount);

        for (uint256 i = 0; i < requestIds.length; i++) {
            tokenOut.transfer(requests[i].user, amountOut * claims[i].amountToClaim / totalPoints);
        }
    }

    function swap(IERC20 tokenIn, IERC20 tokenOut, uint256 amountIn, uint256 minReturn)
        internal
        virtual
        returns (uint256 amountOut);
}
