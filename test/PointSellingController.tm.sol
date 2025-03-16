// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {PointSellingController, PointSaleRequest} from "../src/PointSellingController.sol";

contract PointSellingControllerInstance is PointSellingController {
    constructor(address _owner) PointSellingController(_owner) {}

    function swap(IERC20 tokenIn, IERC20 tokenOut, uint256 amountIn, uint256 minReturn)
        internal
        override
        returns (uint256 amountOut)
    {}
}

contract PointSellingControllerMainnetTest is Test {
    address admin = makeAddr("admin");

    address rumpelUserSam = 0x4D202b88f9762d8B399512c78E76B8854De08BA6;
    address samRumpelWallet = 0x092c6543efAda7b22E3351ED4e5C842A3069F3a2;

    address randomRumpelWallet = 0x0A30ff1a7Dcb1E98138E9Fd620C553919ccB7720;

    address kpEF5 = 0x4A4E500eC5dE798cc3D229C544223E65511A9A39;
    IERC20 USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    PointSellingController public pointSellingController;

    function setUp() public {
        string memory MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
        uint256 forkId = vm.createFork(MAINNET_RPC_URL, 22_048_049); // Block mined at Mar-14-2025 10:17:59 PM +UTC
        vm.selectFork(forkId);

        pointSellingController = new PointSellingControllerInstance(admin);
    }

    function test_addRequest() public {
        // Address passed in is not a safe
        vm.prank(rumpelUserSam);
        vm.expectRevert();
        pointSellingController.updateRequest(
            makeAddr("random wallet"),
            IERC20(address(kpEF5)),
            PointSaleRequest({active: true, tokenOut: USDC, minPrice: 1000000000000000000, recipient: rumpelUserSam})
        );

        // Address passed in is a safe but Rumpel user is not an owner
        vm.prank(rumpelUserSam);
        vm.expectRevert(PointSellingController.NotSafeOwner.selector);
        pointSellingController.updateRequest(
            randomRumpelWallet,
            IERC20(address(kpEF5)),
            PointSaleRequest({active: true, tokenOut: USDC, minPrice: 1000000000000000000, recipient: rumpelUserSam})
        );

        // Rumpel user is owner of the rumpel wallet
        vm.prank(rumpelUserSam);
        pointSellingController.updateRequest(
            samRumpelWallet,
            IERC20(address(kpEF5)),
            PointSaleRequest({active: true, tokenOut: USDC, minPrice: 1000000000000000000, recipient: rumpelUserSam})
        );
    }
}
