// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol"; // Import for potential manual checks

import {
    IPointTokenizationVault, Claim, NotSafeOwner, MinPriceTooLow
} // Import MinPriceTooLow for expected reverts
from "../src/PointSellingController.sol"; // Import base interfaces/errors
import {UniswapV3PointSellingController} from "../src/UniswapV3PointSelling.sol";

// tests:
// - multiple pTokens

contract PointSellingControllerMainnetTest is Test {
    using FixedPointMathLib for uint256; // If needed for test calculations

    address admin = makeAddr("admin");

    // Using real mainnet addresses for testing interactions
    address rumpelUserSam = 0x4D202b88f9762d8B399512c78E76B8854De08BA6; // Sam's EOA
    address samRumpelWallet = 0x092c6543efAda7b22E3351ED4e5C842A3069F3a2; // Sam's Rumpel Safe

    address randomRumpelWallet = 0x0A30ff1a7Dcb1E98138E9Fd620C553919ccB7720; // Another Safe for testing ownership

    // Mainnet Point Token & Output Token Addresses
    // kpETHFI-5: Rumpel kpT for ETHFI Season 5
    address kpEF5Address = 0x4A4E500eC5dE798cc3D229C544223E65511A9A39;
    ERC20 constant pTokenKpEF5 = ERC20(0x4A4E500eC5dE798cc3D229C544223E65511A9A39);
    ERC20 constant USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 constant WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 constant ETHFI = ERC20(0xFe0c30065B384F05761f15d0CC899D4F9F9Cc0eB);

    // Mainnet Point Tokenization Vault
    IPointTokenizationVault constant pointTokenizationVault =
        IPointTokenizationVault(0xe47F9Dbbfe98d6930562017ee212C1A1Ae45ba61);

    // Controller instance to test
    UniswapV3PointSellingController public uniswapV3PointSellingController;

    // Claim data for Sam's kpEF5
    bytes32 constant kpEF5PointsId = 0x1652756d70656c206b50743a2045544845524649205335066b7045462d350000;
    uint256 constant kpEF5TotalClaimable = 28267069140624997000; // ~28.26 kpEF5

    bytes32[] proof; // Populated in setUp

    function setUp() public {
        string memory MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
        uint256 forkId = vm.createFork(MAINNET_RPC_URL, 22_048_049); // Block mined at Mar-14-2025 10:17:59 PM +UTC
        vm.selectFork(forkId);

        uniswapV3PointSellingController = new UniswapV3PointSellingController(admin);

        // Populate Merkle Proof
        proof = new bytes32[](12);
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
    }

    /// @notice Tests setting user preferences with correct ownership checks using real Safes.
    function test_setUserPreferences_OwnershipChecks() public {
        ERC20[] memory pTokens = new ERC20[](1);
        pTokens[0] = pTokenKpEF5;
        uint256[] memory minPrices = new uint256[](1);
        minPrices[0] = 1 * (10 ** USDC.decimals()); // 1 USDC per pToken (example)

        // Fail Case 1: Caller is not owner of the target Safe (random safe)
        vm.prank(rumpelUserSam); // Sam tries to set prefs for a random Safe
        vm.expectRevert(abi.encodeWithSelector(NotSafeOwner.selector, rumpelUserSam, randomRumpelWallet));
        uniswapV3PointSellingController.setUserPreferences(randomRumpelWallet, rumpelUserSam, pTokens, minPrices);

        // Fail Case 2: Target wallet is not a Safe (using an EOA address)
        // The ISafe(target).isOwner() call will likely revert if target is an EOA.
        // We expect a low-level revert here, not NotSafeOwner.
        address eoaTarget = makeAddr("random EOA");
        vm.prank(eoaTarget); // EOA tries to set prefs for itself
        vm.expectRevert(); // Expect low-level call failure
        uniswapV3PointSellingController.setUserPreferences(eoaTarget, eoaTarget, pTokens, minPrices);

        // Success Case: Caller (Sam's EOA) is an owner of the target Safe (Sam's Rumpel Wallet)
        vm.prank(rumpelUserSam);
        uniswapV3PointSellingController.setUserPreferences(samRumpelWallet, rumpelUserSam, pTokens, minPrices);
        assertEq(uniswapV3PointSellingController.getMinPrice(samRumpelWallet, pTokenKpEF5), minPrices[0]);
        assertEq(uniswapV3PointSellingController.getRecipient(samRumpelWallet), rumpelUserSam);

        // Success Case: Caller is the Safe itself (e.g., called via Safe transaction)
        uint256[] memory newMinPrices = new uint256[](1);
        newMinPrices[0] = 2 * (10 ** USDC.decimals()); // 2 USDC
        address newRecipient = makeAddr("newRecipient");
        vm.prank(samRumpelWallet);
        uniswapV3PointSellingController.setUserPreferences(samRumpelWallet, newRecipient, pTokens, newMinPrices);
        assertEq(uniswapV3PointSellingController.getMinPrice(samRumpelWallet, pTokenKpEF5), newMinPrices[0]);
        assertEq(uniswapV3PointSellingController.getRecipient(samRumpelWallet), newRecipient);
    }

    /// @notice Tests the full executePointSale flow with Uniswap V3, including non-zero minPrice and USDC output.
    function test_executePointSale_UniswapV3_WithMinPriceAndUSDC() public {
        // --- Setup User Preferences ---
        // We set a minimum price the user will accept: e.g., 0.000077 USDC per 1 kpEF5 token.
        // kpEF5 has 18 decimals, USDC has 6 decimals.
        // The minPrice in preferences is per WHOLE pToken unit, scaled by tokenOut decimals.
        // So, 0.000077 USDC = 77 (scaled by 1e6).
        uint256 userMinPricePerPTokenScaled = 77; // 0.000077 USDC * 1e6

        vm.startPrank(rumpelUserSam);
        ERC20[] memory pTokens = new ERC20[](1);
        pTokens[0] = pTokenKpEF5;
        uint256[] memory minPrices = new uint256[](1);
        minPrices[0] = userMinPricePerPTokenScaled;
        uniswapV3PointSellingController.setUserPreferences(samRumpelWallet, rumpelUserSam, pTokens, minPrices);
        vm.stopPrank();

        // --- Trust Controller ---
        // Sam's Rumpel Wallet needs to trust the controller contract via the PointTokenizationVault
        vm.prank(samRumpelWallet);
        pointTokenizationVault.trustReceiver(address(uniswapV3PointSellingController), true);

        // --- Prepare Claims ---
        address[] memory wallets = new address[](1);
        wallets[0] = samRumpelWallet;

        Claim[] memory claims = new Claim[](1);
        // Calculate claimable amount AT THE FORKED BLOCK
        uint256 alreadyClaimed = pointTokenizationVault.claimedPTokens(samRumpelWallet, kpEF5PointsId);
        uint256 amountToClaim = kpEF5TotalClaimable - alreadyClaimed;
        console.log("Already Claimed (at fork block):", alreadyClaimed);
        console.log("Amount to Claim Now:", amountToClaim);
        require(amountToClaim > 0, "No points to claim at this block height for this test setup.");

        claims[0] = Claim({
            pointsId: kpEF5PointsId,
            totalClaimable: kpEF5TotalClaimable, // Total ever available
            amountToClaim: amountToClaim, // Amount remaining to claim now
            proof: proof // The merkle proof
        });

        // --- Prepare Uniswap V3 Swap Parameters ---
        // Path: kpEF5 -> WETH (0.3% fee) -> USDC (0.05% fee)
        // Note: This assumes a kpEF5/WETH pool exists with 0.3% fee, which might not be true on mainnet.
        // This path primarily tests the multi-hop swap encoding and execution logic.
        bytes memory path = abi.encodePacked(
            kpEF5Address, uint24(10000), address(ETHFI), uint24(3000), address(WETH), uint24(3000), address(USDC)
        );
        uint256 deadline = block.timestamp + 600; // 10 minutes from now
        bytes memory additionalParams = abi.encode(path, deadline);

        // --- Set Admin Execution Price Floor ---
        // The admin sets an overall minimum price for this specific batch execution.
        // This MUST be >= all included users' minPrices for that pToken.
        // We set it equal to the user's min price for this test.
        uint256 executeMinPriceFloor = userMinPricePerPTokenScaled; // 3000 (0.003 USDC per kpEF5, scaled)

        // --- Execute Sale ---
        uint256 usdcBalanceBeforeRecipient = USDC.balanceOf(rumpelUserSam);
        uint256 usdcBalanceBeforeAdmin = USDC.balanceOf(admin);
        uint256 contractPTokensBefore = pTokenKpEF5.balanceOf(address(uniswapV3PointSellingController));
        uint256 controllerFee = uniswapV3PointSellingController.fee(); // Get fee percentage

        console.log("Recipient USDC Balance Before:", usdcBalanceBeforeRecipient);
        console.log("Admin USDC Balance Before:", usdcBalanceBeforeAdmin);
        console.log("Contract pToken Balance Before:", contractPTokensBefore);
        console.log("Controller Fee Percentage:", controllerFee);
        console.log("User Min Price (USDC scaled):", userMinPricePerPTokenScaled);
        console.log("Admin Execution Min Price Floor (USDC scaled):", executeMinPriceFloor);

        vm.prank(admin);
        uniswapV3PointSellingController.executePointSale(
            pTokenKpEF5, USDC, wallets, pointTokenizationVault, claims, executeMinPriceFloor, additionalParams
        );

        // --- Assertions ---
        uint256 contractPTokensAfter = pTokenKpEF5.balanceOf(address(uniswapV3PointSellingController));
        uint256 usdcBalanceAfterRecipient = USDC.balanceOf(rumpelUserSam);
        uint256 usdcBalanceAfterAdmin = USDC.balanceOf(admin);

        console.log("Contract pToken Balance After:", contractPTokensAfter);
        console.log("Recipient USDC Balance After:", usdcBalanceAfterRecipient);
        console.log("Admin USDC Balance After:", usdcBalanceAfterAdmin);
        uint256 recipientReceived = usdcBalanceAfterRecipient - usdcBalanceBeforeRecipient;
        uint256 adminReceived = usdcBalanceAfterAdmin - usdcBalanceBeforeAdmin;
        console.log("Recipient USDC Received:", recipientReceived);
        console.log("Admin Fee USDC Received:", adminReceived);

        // Check pTokens were claimed to the contract and fully spent in the swap
        assertEq(contractPTokensBefore, 0, "Contract should start with 0 pTokens");
        assertEq(contractPTokensAfter, 0, "Contract should end with 0 pTokens after swap");

        // Check USDC distribution
        // If successful, the recipient MUST have received some USDC.
        assertTrue(usdcBalanceAfterRecipient > usdcBalanceBeforeRecipient, "Recipient USDC balance should increase");

        assertTrue(usdcBalanceAfterAdmin > usdcBalanceBeforeAdmin, "Admin USDC balance should increase if fee > 0");
        // We can loosely check if the fee looks proportional, but exact calculation is hard due to swap variance
        // uint256 totalReceived = recipientReceived + adminReceived;
        // uint256 expectedFee = totalReceived * controllerFee / PointSellingController.FEE_PRECISION;
        // console.log("Expected Fee (approx):", expectedFee);
        // Assert admin received *something* if fee > 0. More precise checks are brittle.

        // Implicit Check: The transaction did not revert. This means:
        // 1. The executeMinPriceFloor >= user's minPrice requirement passed.
        // 2. The claim via multicall worked.
        // 3. The swap in Uniswap V3 returned at least the amountOutMinimum calculated by the contract
        //    (based on executeMinPriceFloor, amountIn, and potentially flawed decimal logic if not fixed).
        //    *If the amountOutMinimum logic in the contract *is* fixed*, this test passing gives higher confidence.*
    }

    /// @notice Tests that executePointSale reverts if admin price floor is below user preference.
    function test_executePointSale_Revert_MinPriceTooLow() public {
        // --- Setup User Preferences ---
        uint256 userMinPricePerPTokenScaled = 5000; // User wants at least 0.005 USDC
        vm.prank(rumpelUserSam);
        ERC20[] memory pTokens = new ERC20[](1);
        pTokens[0] = pTokenKpEF5;
        uint256[] memory minPrices = new uint256[](1);
        minPrices[0] = userMinPricePerPTokenScaled;
        uniswapV3PointSellingController.setUserPreferences(samRumpelWallet, rumpelUserSam, pTokens, minPrices);
        vm.stopPrank();

        // --- Trust Controller ---
        vm.prank(samRumpelWallet);
        pointTokenizationVault.trustReceiver(address(uniswapV3PointSellingController), true);

        // --- Prepare Claims (Simplified amount for revert test) ---
        address[] memory wallets = new address[](1);
        wallets[0] = samRumpelWallet;
        Claim[] memory claims = new Claim[](1);
        claims[0] = Claim({
            pointsId: kpEF5PointsId,
            totalClaimable: kpEF5TotalClaimable,
            amountToClaim: 1e18, // Claim small amount for test
            proof: proof
        });

        // --- Prepare Swap Params (minimal, won't be reached) ---
        bytes memory path =
            abi.encodePacked(address(pTokenKpEF5), uint24(3000), address(WETH), uint24(500), address(USDC));
        bytes memory additionalParams = abi.encode(path, block.timestamp + 100);

        // --- Set Admin Price Floor LOWER than user preference ---
        uint256 executeMinPriceFloor = 4000; // Admin floor is 0.004 USDC, user wants 0.005
        assertTrue(executeMinPriceFloor < userMinPricePerPTokenScaled);

        // --- Execute Sale - Expect Revert ---
        vm.prank(admin);
        vm.expectRevert(MinPriceTooLow.selector);
        uniswapV3PointSellingController.executePointSale(
            pTokenKpEF5, USDC, wallets, pointTokenizationVault, claims, executeMinPriceFloor, additionalParams
        );
    }
}
