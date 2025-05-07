// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";

import {UniswapV3PointSellingController} from "../src/UniswapV3PointSelling.sol";

contract PointSellingControllerScripts is Script {
    address public constant RUMPEL_OPERATOR = 0x0c0264Ba7799dA7aF0fd141ba5Ba976E6DcC6C17;

    function run() public returns (UniswapV3PointSellingController) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        UniswapV3PointSellingController uniswapV3PointSellingController =
            new UniswapV3PointSellingController(RUMPEL_OPERATOR);

        vm.stopBroadcast();

        return uniswapV3PointSellingController;
    }
}
