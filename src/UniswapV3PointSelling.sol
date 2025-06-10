// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

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
    using SafeTransferLib for ERC20;

    ISwapRouter internal SWAP_ROUTER;

    constructor(address initialOwner, address swapRouter) PointSellingController(initialOwner) {
        SWAP_ROUTER = ISwapRouter(swapRouter);
    }

    function swap(ERC20 tokenIn, ERC20, uint256 amountIn, uint256 minPrice, bytes calldata additionalParams)
        internal
        virtual
        override
        returns (uint256 amountOut)
    {
        if (tokenIn.allowance(address(this), address(SWAP_ROUTER)) != type(uint256).max) {
            // Approvals only ever happen here, so we can safely assume that tokenIn has zero allowance.
            tokenIn.safeApprove(address(SWAP_ROUTER), type(uint256).max);
        }

        (bytes memory path, uint256 deadline) = abi.decode(additionalParams, (bytes, uint256));
        return SWAP_ROUTER.exactInput(
            ExactInputParams({
                path: path,
                recipient: address(this),
                deadline: deadline,
                amountIn: amountIn,
                amountOutMinimum: FixedPointMathLib.mulDivUp(minPrice, amountIn, 10 ** tokenIn.decimals())
            })
        );
    }
}
