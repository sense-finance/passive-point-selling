// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {
    PointSellingController,
    IPointTokenizationVault,
    UserPreferences,
    NotSafeOwner,
    Claim
} from "../src/PointSellingController.sol";
import {UniswapV3PointSellingController} from "../src/UniswapV3PointSelling.sol";

// tests:
// - multiple pTokens
// - multiple users
// - multiple wallets
// - multiple wallets with different preferences
// - multiple wallets with different pTokens
// - multiple wallets with different min prices
// - multiple wallets with different recipients

contract PointSellingControllerInstance is PointSellingController {
    constructor(address _owner) PointSellingController(_owner) {}

    function swap(ERC20 tokenIn, ERC20 tokenOut, uint256 amountIn, uint256 minReturn, bytes calldata additionalParams)
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
    ERC20 USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 ETHFI = ERC20(0xFe0c30065B384F05761f15d0CC899D4F9F9Cc0eB);
    IPointTokenizationVault pointTokenizationVault = IPointTokenizationVault(0xe47F9Dbbfe98d6930562017ee212C1A1Ae45ba61);

    PointSellingController public pointSellingController;
    UniswapV3PointSellingController public uniswapV3PointSellingController;

    function setUp() public {
        string memory MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
        uint256 forkId = vm.createFork(MAINNET_RPC_URL, 22_048_049); // Block mined at Mar-14-2025 10:17:59 PM +UTC
        vm.selectFork(forkId);

        pointSellingController = new PointSellingControllerInstance(admin);
        uniswapV3PointSellingController = new UniswapV3PointSellingController(admin);
    }

    function test_setUserPreferences() public {
        // Address passed in is not a safe
        vm.prank(rumpelUserSam);
        vm.expectRevert();
        ERC20[] memory pTokens = new ERC20[](1);
        pTokens[0] = ERC20(address(kpEF5));
        uint256[] memory minPrices = new uint256[](1);
        minPrices[0] = 1000000000000000000;
        pointSellingController.setUserPreferences(
            makeAddr("random wallet"), makeAddr("random wallet"), pTokens, minPrices
        );

        // Address passed in is a safe but Rumpel user is not an owner
        vm.prank(rumpelUserSam);
        vm.expectRevert(abi.encodeWithSelector(NotSafeOwner.selector, rumpelUserSam, randomRumpelWallet));
        pointSellingController.setUserPreferences(randomRumpelWallet, rumpelUserSam, pTokens, minPrices);

        // Rumpel user is owner of the rumpel wallet
        vm.prank(rumpelUserSam);
        pointSellingController.setUserPreferences(samRumpelWallet, rumpelUserSam, pTokens, minPrices);
    }

    function test_simpleExecutePointSale() public {
        vm.prank(rumpelUserSam);
        ERC20[] memory pTokens = new ERC20[](1);
        pTokens[0] = ERC20(address(kpEF5));
        uint256[] memory minPrices = new uint256[](1);
        minPrices[0] = 1000000000000000000;
        pointSellingController.setUserPreferences(samRumpelWallet, rumpelUserSam, pTokens, minPrices);

        // sam (via rumpel wallet) trust point selling controller
        vm.prank(samRumpelWallet);
        pointTokenizationVault.trustReceiver(address(pointSellingController), true);

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
        uint256 totalClaimable = 28267069140624997000;
        uint256 amountToClaim = totalClaimable - pointTokenizationVault.claimedPTokens(rumpelUserSam, pointsId);
        claims[0] = Claim({
            pointsId: pointsId,
            totalClaimable: 28267069140624997000,
            amountToClaim: amountToClaim,
            proof: proof
        });

        vm.prank(admin);
        pointSellingController.executePointSale(
            ERC20(address(kpEF5)), USDC, wallets, pointTokenizationVault, claims, 1000000000000000000, ""
        );
    }

    function test_executePointSale_UniswapV3() public {
        // --- Setup Preferences ---
        uint256 minPricePerPToken = 0; // Example: min 0 USDC per pToken means we accept any price
        vm.prank(rumpelUserSam);
        ERC20[] memory pTokens = new ERC20[](1);
        pTokens[0] = ERC20(address(kpEF5));
        uint256[] memory minPrices = new uint256[](1);
        minPrices[0] = minPricePerPToken;
        uniswapV3PointSellingController.setUserPreferences(samRumpelWallet, rumpelUserSam, pTokens, minPrices);

        // --- Trust Controller ---
        vm.prank(samRumpelWallet);
        pointTokenizationVault.trustReceiver(address(uniswapV3PointSellingController), true);

        // --- Prepare Claims ---
        address[] memory wallets = new address[](1);
        wallets[0] = samRumpelWallet;

        bytes32 pointsId = 0x1652756d70656c206b50743a2045544845524649205335066b7045462d350000;

        // Using the same proof as the simple test for simplicity
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
        uint256 totalClaimable = 28267069140624997000; // ~28.26 kpEF5
        uint256 amountToClaim = totalClaimable - pointTokenizationVault.claimedPTokens(samRumpelWallet, pointsId);
        claims[0] =
            Claim({pointsId: pointsId, totalClaimable: totalClaimable, amountToClaim: amountToClaim, proof: proof});

        // --- Prepare Uniswap V3 Swap Parameters ---
        // Path: kpEF5 -> WETH (0.3% fee) -> USDC (0.05% fee)
        // Note: This assumes a kpEF5/WETH pool exists with 0.3% fee, which might not be true on mainnet.
        // This path primarily tests the multi-hop swap encoding and execution logic.
        bytes memory path = abi.encodePacked(
            address(kpEF5), uint24(10000), address(ETHFI), uint24(3000), address(WETH), uint24(3000), address(USDC)
        );
        uint256 deadline = block.timestamp + 600; // 10 minutes from now
        bytes memory additionalParams = abi.encode(path, deadline);

        // --- Execute Sale ---
        uint256 usdcBalanceBeforeRecipient = USDC.balanceOf(rumpelUserSam);
        uint256 usdcBalanceBeforeAdmin = USDC.balanceOf(admin);
        uint256 contractPTokensBefore = ERC20(address(kpEF5)).balanceOf(address(uniswapV3PointSellingController));

        // The minPrice for executePointSale should aggregate the minimums from preferences.
        // Here, we use the single user's minPrice. If multiple users, it should be the minimum of all their required prices *per pToken*.
        uint256 executeMinPrice = minPricePerPToken;

        vm.prank(admin);
        uniswapV3PointSellingController.executePointSale(
            ERC20(address(kpEF5)), USDC, wallets, pointTokenizationVault, claims, executeMinPrice, additionalParams
        );

        // --- Assertions ---
        uint256 contractPTokensAfter = ERC20(address(kpEF5)).balanceOf(address(uniswapV3PointSellingController));
        uint256 usdcBalanceAfterRecipient = USDC.balanceOf(rumpelUserSam);
        uint256 usdcBalanceAfterAdmin = USDC.balanceOf(admin);

        // Check pTokens were claimed and spent
        assertEq(contractPTokensBefore, 0, "Contract should start with 0 pTokens");
        assertEq(contractPTokensAfter, 0, "Contract should end with 0 pTokens after swap");

        // Check USDC distribution
        assertTrue(usdcBalanceAfterRecipient > usdcBalanceBeforeRecipient, "Recipient USDC balance should increase");
        uint256 fee = uniswapV3PointSellingController.fee();
        if (fee > 0) {
            assertTrue(usdcBalanceAfterAdmin > usdcBalanceBeforeAdmin, "Admin USDC balance should increase if fee > 0");
            // We could add more precise checks on fee amount if needed, but fork state makes exact swap output variable.
        } else {
            assertEq(usdcBalanceAfterAdmin, usdcBalanceBeforeAdmin, "Admin USDC balance should not change if fee == 0");
        }

        // Check minPrice logic implicitly: if the transaction didn't revert,
        // the amountOutMinimum calculated in the swap was met or exceeded.
        console.log("Recipient USDC received:", usdcBalanceAfterRecipient - usdcBalanceBeforeRecipient);
        console.log("Admin Fee USDC received:", usdcBalanceAfterAdmin - usdcBalanceBeforeAdmin);
    }
}
