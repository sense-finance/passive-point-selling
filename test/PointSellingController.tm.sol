// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {
    PointSellingController,
    IPointMinter,
    PointSaleRequest,
    NotSafeOwner,
    Claim
} from "../src/PointSellingController.sol";

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

    // Mainnet addresses
    address kpEF5 = 0x4A4E500eC5dE798cc3D229C544223E65511A9A39;
    IERC20 USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IPointMinter pointMinter = IPointMinter(0xe47F9Dbbfe98d6930562017ee212C1A1Ae45ba61);

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
        vm.expectRevert(NotSafeOwner.selector);
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

    function test_simpleExecutePointSale() public {
        vm.prank(rumpelUserSam);
        pointSellingController.updateRequest(
            samRumpelWallet,
            IERC20(address(kpEF5)),
            PointSaleRequest({active: true, tokenOut: USDC, minPrice: 1000000000000000000, recipient: rumpelUserSam})
        );

        // sam (via rumpel wallet) trust point selling controller
        vm.prank(samRumpelWallet);
        pointMinter.trustReceiver(address(pointSellingController), true);

        address[] memory wallets = new address[](1);
        wallets[0] = samRumpelWallet;

        bytes32 pointsId = 0x1652756d70656c206b50743a2045544845524649205335066b7045462d350000;

        bytes32[] memory proof = new bytes32[](12);
        proof[0] = 0xb4a4cb9e989294ca4f084453dc18d584ce71cf980faef1c8a7a762d68c7036c4;
        proof[1] = 0x2d45d3b77c600aedd31be2517388b735632bc417d299e713e98e534b52f1b80a;
        proof[2] = 0x9989926ae24480dbeb2c6b521fcc5530c18f00a33e6239e5374f5056f3ef3cfd;
        proof[3] = 0xf0747cdadde3ef84dfc19012c0115ae6f4d0a782157287319291394236f89bdd;
        proof[4] = 0x7d99c324df573d95917724e3753530a02e84337bd74c2dd97b07b02f623bfaac;
        proof[5] = 0xfc1d07d6df3800219267a702d03bafea9ab9a4cf10f8142a4c48a5707523caa5;
        proof[6] = 0xe6d145b2e73e5802528493abff88922eb9e78333a4b87a1051305fa27a584424;
        proof[7] = 0x29a713465254b6932029c66a33caecf991a4b3cabd078835ae27fbe64e345e08;
        proof[8] = 0xbd5b81125566d6d6679d0dd186d51bb5ced9d15e13ea4cd9091900d43f3743e7;
        proof[9] = 0x91db6169431d89257356c0eddd4109cf6974b7a52b8da9ef3932a8e49ddb7cc0;
        proof[10] = 0x9e37c2b5a34e86fc22b5bce7743da21fda50fd6228592dc98b2a2a80431f74bf;
        proof[11] = 0xf5f8e4cd9c3927d63a5333a89bd4b129b4246eec0e645baffcbac388ed467c18;

        Claim[] memory claims = new Claim[](1);
        claims[0] = Claim({pointsId: pointsId, totalClaimable: 28267069140624997000, amountToClaim: 1, proof: proof});

        vm.prank(admin);
        pointSellingController.executePointSale(
            IERC20(address(kpEF5)), wallets, pointMinter, claims, 1000000000000000000
        );
    }
}
