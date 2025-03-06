// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

struct PointSaleRequest {
    address user;
    address pTokenIn;
    address tokenOut;
    uint256 minPrice;
}

contract PointSellingController {
    mapping(uint256 requestId => PointSaleRequest request) public requests;

    function executePointSale(uint256 requestId) {}
}
