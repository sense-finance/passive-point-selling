// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import {ERC20} from "solmate/tokens/ERC20.sol";

import {PointSellingController} from "./PointSellingController.sol";

struct ExactInputParams {
    bytes path;
    address recipient;
    uint256 deadline;
    uint256 amountIn;
    uint256 amountOutMinimum;
}

interface ISwapRouter {
    function exactInput(ExactInputParams memory params) external payable returns (uint256 amountOut);
}

contract UniswapV3PointSellingController is PointSellingController {
    ISwapRouter internal constant SWAP_ROUTER = ISwapRouter(address(0xE592427A0AEce92De3Edee1F18E0157C05861564));

    constructor(address initialOwner) PointSellingController(initialOwner) {}

    function swap(ERC20 tokenIn, ERC20 tokenOut, uint256 amountIn, uint256 minPrice, bytes calldata additionalParams)
        internal
        virtual
        override
        returns (uint256 amountOut)
    {
        if (tokenIn.allowance(address(this), address(SWAP_ROUTER)) < amountIn) {
            tokenIn.approve(address(SWAP_ROUTER), amountIn);
        }

        (bytes memory path, uint256 deadline) = abi.decode(additionalParams, (bytes, uint256));
        return SWAP_ROUTER.exactInput(
            ExactInputParams({
                path: path,
                recipient: address(this),
                deadline: deadline,
                amountIn: amountIn,
                amountOutMinimum: minPrice * amountIn / (10 ** tokenOut.decimals())
            })
        );
    }
}
