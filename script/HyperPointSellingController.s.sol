// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";

import {UniswapV3PointSellingController} from "../src/UniswapV3PointSelling.sol";

contract HyperPointSellingControllerScripts is Script {
    address public constant HYPER_RUMPEL_OPERATOR = 0x200F8df85C37268F39e3Fae332E91730A2d049d5;
    address public constant HYPER_SWAP_ROUTER = 0x4E2960a8cd19B467b82d26D83fAcb0fAE26b094D;

    function run() public returns (UniswapV3PointSellingController) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        UniswapV3PointSellingController uniswapV3PointSellingController =
            new UniswapV3PointSellingController(HYPER_RUMPEL_OPERATOR, HYPER_SWAP_ROUTER);

        vm.stopBroadcast();

        return uniswapV3PointSellingController;
    }
}
