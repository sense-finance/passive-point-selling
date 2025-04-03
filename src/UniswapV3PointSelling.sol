// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import {IERC20, PointSellingController} from "./PointSellingController.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

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
    IERC20 internal constant kpef5 = IERC20(0x4A4E500eC5dE798cc3D229C544223E65511A9A39);
    ISwapRouter internal constant SWAP_ROUTER = ISwapRouter(address(0xE592427A0AEce92De3Edee1F18E0157C05861564));

    constructor(address initialOwner) PointSellingController(initialOwner) {}

    function swap(IERC20, IERC20 tokenOut, uint256 amountIn, uint256 minPrice, bytes calldata additionalParams)
        internal
        virtual
        override
        returns (uint256 amountOut)
    {
        kpef5.approve(address(SWAP_ROUTER), amountIn);
        (bytes memory path, uint256 deadline) = abi.decode(additionalParams, (bytes, uint256));
        return SWAP_ROUTER.exactInput(
            ExactInputParams({
                path: path,
                recipient: address(this),
                deadline: deadline,
                amountIn: amountIn,
                amountOutMinimum: minPrice * amountIn / (10 ** IERC20Metadata(address(tokenOut)).decimals())
            })
        );
    }
}
