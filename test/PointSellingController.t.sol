// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import {Test} from "forge-std/Test.sol";
import {MockERC20, ERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

import {
    PointSellingController,
    IPointTokenizationVault,
    NotSafeOwner,
    Claim,
    ISafe,
    ArrayLengthMismatch,
    MinPriceTooLow,
    FeeTooLarge,
    MultipleOwners
} from "../src/PointSellingController.sol";

error Slippage();

contract UniversalPoolMock {
    uint256 public nextSwapRate = 1e18;

    function setNextSwapRate(uint256 rate) external {
        nextSwapRate = rate;
    }

    function swap(ERC20 tokenIn, ERC20 tokenOut, uint256 amountIn, uint256 minReturn)
        external
        returns (uint256 amountOut)
    {
        uint256 precision = 10 ** ERC20(address(tokenOut)).decimals();
        amountOut = amountIn * nextSwapRate / precision;
        require(amountOut >= minReturn, Slippage());

        tokenIn.transferFrom(msg.sender, address(this), amountIn);
        tokenOut.transfer(msg.sender, amountOut);
    }
}

contract PointSellingControllerMock is PointSellingController {
    UniversalPoolMock public immutable amm = new UniversalPoolMock();

    constructor(address _owner) PointSellingController(_owner) {}

    function swap(ERC20 tokenIn, ERC20 tokenOut, uint256 amountIn, uint256 minPrice, bytes calldata)
        internal
        override
        returns (uint256 amountOut)
    {
        tokenIn.approve(address(amm), amountIn);
        return amm.swap(tokenIn, tokenOut, amountIn, minPrice * amountIn / (10 ** tokenOut.decimals()));
    }
}

contract PointTokenizationVaultMock is IPointTokenizationVault {
    mapping(bytes32 => MockERC20) public pTokens;

    constructor() {
        pTokens[bytes32(uint256(1))] = new MockERC20("pToken1", "PTK1", 18);
    }

    function claimPTokens(Claim calldata c, address, address r) external {
        pTokens[c.pointsId].mint(r, c.amountToClaim);
    }

    function trustReceiver(address, bool) external {}

    function claimedPTokens(address, bytes32) external view returns (uint256) {}

    function multicall(bytes[] calldata calls) external {
        for (uint256 i; i < calls.length; i++) {
            (bool ok,) = address(this).call(calls[i]);
            require(ok, "Multicall failed");
        }
    }
}

contract RumpelWalletMock is ISafe {
    address public immutable owner;

    constructor(address _owner) {
        owner = _owner;
    }

    function isOwner(address _owner) external view returns (bool) {
        return owner == _owner;
    }

    function getOwners() external view returns (address[] memory owners) {
        owners = new address[](1);
        owners[0] = owner;
    }
}

contract MultiOwnerRumpelWalletMock is ISafe {
    address[] public owners;

    constructor(address[] memory _owners) {
        require(_owners.length > 1, "Must provide multiple owners");
        owners = _owners;
    }

    function isOwner(address _owner) external view returns (bool) {
        for (uint256 i = 0; i < owners.length; i++) {
            if (owners[i] == _owner) {
                return true;
            }
        }
        return false;
    }

    function getOwners() external view returns (address[] memory) {
        return owners;
    }
}

contract PointSellingControllerTest is Test {
    address admin = makeAddr("admin");
    address user = makeAddr("user");
    address user1 = makeAddr("user1");

    PointTokenizationVaultMock public vault = new PointTokenizationVaultMock();
    MockERC20 public tokenOut = new MockERC20("token out", "TKNO", 18);
    MockERC20 public tokenOut2 = new MockERC20("token out 2", "TKNO2", 6);

    PointSellingControllerMock public controller;
    ERC20 pToken;

    function setUp() public {
        controller = new PointSellingControllerMock(admin);
        pToken = ERC20(vault.pTokens(bytes32(uint256(1))));

        tokenOut.mint(address(controller.amm()), 1e27);
        MockERC20(address(pToken)).mint(address(controller.amm()), 1e27);
    }

    function test_accessControl() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        controller.setFeePercentage(1);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        controller.executePointSale(pToken, tokenOut, new address[](1), vault, new Claim[](1), 1, "");
    }

    function test_setFeePercentage(uint256 newFee) public {
        newFee %= 5e17;
        vm.prank(admin);
        if (newFee > 3e17) {
            vm.expectRevert(FeeTooLarge.selector);
            controller.setFeePercentage(newFee);
        } else {
            controller.setFeePercentage(newFee);
            assertEq(controller.fee(), newFee);
        }
    }

    function test_setUserPreferences() public {
        address wallet = address(new RumpelWalletMock(user));
        vm.expectRevert(abi.encodeWithSelector(NotSafeOwner.selector, address(this), wallet));
        ERC20[] memory tokens = new ERC20[](1);
        tokens[0] = ERC20(address(1));
        uint256[] memory minPrices = new uint256[](1);
        minPrices[0] = 1e18;
        controller.setUserPreferences(wallet, address(0), tokens, minPrices);

        // evm revert if setting preferences for non-safe user EOA
        vm.expectRevert();
        controller.setUserPreferences(user, user, tokens, minPrices);

        vm.prank(user);
        tokens[0] = ERC20(address(1));
        minPrices[0] = 1e18;
        controller.setUserPreferences(wallet, user, tokens, minPrices);

        assertEq(controller.getRecipient(wallet), user);
        assertEq(controller.getMinPrice(wallet, tokens[0]), 1e18);
    }

    function test_executePointSale() public {
        address wallet0 = address(new RumpelWalletMock(user));
        address wallet1 = address(new RumpelWalletMock(user1));

        address[] memory wallets = new address[](2);
        Claim[] memory claims = new Claim[](1);
        vm.prank(admin);
        vm.expectRevert(ArrayLengthMismatch.selector);
        controller.executePointSale(pToken, tokenOut, wallets, vault, claims, 1e18, "");

        vm.prank(user);
        ERC20[] memory tokens = new ERC20[](1);
        tokens[0] = ERC20(address(pToken));
        uint256[] memory minPrices = new uint256[](1);
        minPrices[0] = 1e18;
        controller.setUserPreferences(wallet0, user, tokens, minPrices);

        wallets = new address[](2);
        claims = new Claim[](2);
        wallets[0] = wallet0;
        wallets[1] = wallet1;
        claims[0] =
            Claim({pointsId: bytes32(uint256(1)), totalClaimable: 1e18, amountToClaim: 1e18, proof: new bytes32[](0)});

        vm.prank(admin);
        vm.expectRevert(MinPriceTooLow.selector);
        controller.executePointSale(pToken, tokenOut, wallets, vault, claims, 1e17, "");

        vm.prank(user1);
        controller.setUserPreferences(wallet1, user1, tokens, minPrices);
        claims[1] =
            Claim({pointsId: bytes32(uint256(1)), totalClaimable: 1e18, amountToClaim: 1e18, proof: new bytes32[](0)});

        vm.prank(admin);
        controller.executePointSale(pToken, tokenOut, wallets, vault, claims, 1e18, "");

        assertEq(tokenOut.balanceOf(user), tokenOut.balanceOf(user1));
        assertEq(tokenOut.balanceOf(user), 999000000000000000);
        assertEq(tokenOut.balanceOf(admin), 2000000000000000);
    }

    function test_executePointSale6DecimalTokenOut() public {
        address wallet0 = address(new RumpelWalletMock(user));
        address wallet1 = address(new RumpelWalletMock(user1));

        tokenOut2.mint(address(controller.amm()), 1e27);

        uint256 minPrice = 1e6;
        vm.prank(user);
        ERC20[] memory tokens = new ERC20[](1);
        tokens[0] = ERC20(address(pToken));
        uint256[] memory minPrices = new uint256[](1);
        minPrices[0] = minPrice;
        controller.setUserPreferences(wallet0, user, tokens, minPrices);

        vm.prank(user1);
        controller.setUserPreferences(wallet1, user1, tokens, minPrices);

        address[] memory wallets = new address[](2);
        Claim[] memory claims = new Claim[](2);
        wallets[0] = wallet0;
        wallets[1] = wallet1;
        claims[0] =
            Claim({pointsId: bytes32(uint256(1)), totalClaimable: 1e18, amountToClaim: 1e18, proof: new bytes32[](0)});
        claims[1] =
            Claim({pointsId: bytes32(uint256(1)), totalClaimable: 1e18, amountToClaim: 1e18, proof: new bytes32[](0)});

        uint256 swapRate = minPrice;
        controller.amm().setNextSwapRate(swapRate);

        vm.prank(admin);
        vm.expectRevert(MinPriceTooLow.selector);
        controller.executePointSale(pToken, tokenOut2, wallets, vault, claims, minPrice - 1, "");

        vm.prank(admin);
        controller.executePointSale(pToken, tokenOut2, wallets, vault, claims, minPrice, "");

        uint256 totalPTokens = 2e18;
        uint256 amountOut = totalPTokens * swapRate / (10 ** tokenOut2.decimals());

        uint256 fee = controller.fee();
        uint256 feeAmt = amountOut * fee / controller.FEE_PRECISION();
        uint256 remaining = amountOut - feeAmt;

        uint256 userShare = FixedPointMathLib.mulDivDown(remaining, claims[0].amountToClaim, totalPTokens);

        assertEq(tokenOut2.balanceOf(user), userShare, "User balance mismatch");
        assertEq(tokenOut2.balanceOf(user1), userShare, "User1 balance mismatch");
        assertEq(tokenOut2.balanceOf(admin), feeAmt, "Admin fee mismatch");
    }

    function testFuzz_executePointSale_proportional(
        uint8 rawWallets,
        uint256 rawFee,
        uint256 rawMinPrice,
        uint256 rawSwapRate,
        uint256 seed // used as entropy for amounts / addrs
    ) public {
        /* ---------- set‑up & bounds ---------- */
        uint8 n = uint8(bound(rawWallets, 1, 10));

        uint256 fee_ = bound(rawFee, 0, controller.MAX_FEE());
        vm.prank(admin);
        controller.setFeePercentage(fee_);

        uint256 minPrice = bound(rawMinPrice, 1, 1e18); // 18‑dec tokenOut
        uint256 swapRate = bound(rawSwapRate, minPrice, minPrice * 10); // keep swap ≥ minPrice
        controller.amm().setNextSwapRate(swapRate);

        // ensure AMM owns more than enough tokenOut
        tokenOut.mint(address(controller.amm()), 1e30);

        /* ---------- prepare prefs, wallets, claims ---------- */
        ERC20[] memory tokens = new ERC20[](1);
        tokens[0] = pToken;
        uint256[] memory prices = new uint256[](1);
        prices[0] = minPrice;

        address[] memory wallets = new address[](n);
        Claim[] memory claims = new Claim[](n);

        uint256 totalPTokens;
        for (uint8 i; i < n; ++i) {
            // pseudo‑random user / wallet addresses
            address u = address(uint160(uint256(keccak256(abi.encode(seed, i)))));
            address w = address(new RumpelWalletMock(u));
            wallets[i] = w;

            // each user sets identical prefs (price = minPrice, recipient = owner)
            vm.prank(u);
            controller.setUserPreferences(w, u, tokens, prices);

            // random amountToClaim in range [1, 1e18]
            uint256 amt = (uint256(keccak256(abi.encode(seed, i, "amt"))) % 1e18) + 1;
            claims[i] =
                Claim({pointsId: bytes32(uint256(1)), totalClaimable: amt, amountToClaim: amt, proof: new bytes32[](0)});
            totalPTokens += amt;
        }

        /* ---------- run sale ---------- */
        vm.prank(admin);
        controller.executePointSale(pToken, tokenOut, wallets, vault, claims, minPrice, "");

        /* ---------- invariants ---------- */
        uint256 amountOut = totalPTokens * swapRate / 1e18;
        uint256 feeAmt = amountOut * fee_ / controller.FEE_PRECISION();
        uint256 remainingOut = amountOut - feeAmt;

        // 1. fee correctness
        assertEq(tokenOut.balanceOf(admin), feeAmt, "admin fee mismatch");

        // 2. pro‑rata distribution
        uint256 distributed;
        for (uint8 i; i < n; ++i) {
            address u = RumpelWalletMock(payable(wallets[i])).owner(); // helper getter in mock
            uint256 expected = FixedPointMathLib.mulDivDown(remainingOut, claims[i].amountToClaim, totalPTokens);
            assertEq(tokenOut.balanceOf(u), expected, "user share mismatch");
            distributed += expected;
        }

        // at most `n` wei of dust due to mulDivDown rounding
        assertLe(remainingOut - distributed, n);
    }

    function test_MultiOwnerWalletScenarios() public {
        // Setup multi-owner wallet
        address otherOwner = makeAddr("otherOwner");
        address[] memory multiOwners = new address[](2);
        multiOwners[0] = user;
        multiOwners[1] = otherOwner;
        address multiOwnerWallet = address(new MultiOwnerRumpelWalletMock(multiOwners));

        // Prepare preferences data
        ERC20[] memory tokens = new ERC20[](1);
        tokens[0] = pToken;
        uint256[] memory minPrices = new uint256[](1);
        minPrices[0] = 1e18;
        address recipient = makeAddr("recipient");

        // === Test setUserPreferences ===
        // 1. Revert if called by an owner (not the wallet itself)
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(MultipleOwners.selector));
        controller.setUserPreferences(multiOwnerWallet, recipient, tokens, minPrices);

        // 2. Success if called *by* the wallet itself (requires wallet to be able to call)
        vm.prank(multiOwnerWallet);
        controller.setUserPreferences(multiOwnerWallet, recipient, tokens, minPrices);

        assertEq(controller.getRecipient(multiOwnerWallet), recipient, "Recipient setup failed");
        assertEq(controller.getMinPrice(multiOwnerWallet, pToken), minPrices[0], "MinPrice setup failed");

        // === Test executePointSale ===
        // Setup claims for the multi-owner wallet
        address[] memory wallets = new address[](1);
        wallets[0] = multiOwnerWallet;
        Claim[] memory claims = new Claim[](1);
        claims[0] =
            Claim({pointsId: bytes32(uint256(1)), totalClaimable: 1e18, amountToClaim: 1e18, proof: new bytes32[](0)});
        uint256 minPriceSale = 1e18;

        // 1. Revert if recipient is NOT set (0x0) and wallet has multiple owners
        vm.prank(multiOwnerWallet);
        controller.setUserPreferences(multiOwnerWallet, address(0), tokens, minPrices);
        assertEq(controller.getRecipient(multiOwnerWallet), address(0), "Recipient clear failed");
        // --- Execute and expect revert
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(MultipleOwners.selector));
        controller.executePointSale(pToken, tokenOut, wallets, vault, claims, minPriceSale, "");

        // 2. Success if recipient IS set
        vm.prank(multiOwnerWallet);
        controller.setUserPreferences(multiOwnerWallet, recipient, tokens, minPrices);
        assertEq(controller.getRecipient(multiOwnerWallet), recipient, "Recipient restore failed");
        // --- Execute sale
        uint256 swapRate = 1e18;
        controller.amm().setNextSwapRate(swapRate);
        vm.prank(admin);
        controller.executePointSale(pToken, tokenOut, wallets, vault, claims, minPriceSale, "");
        // --- Check balances
        uint256 totalPTokens = claims[0].amountToClaim;
        uint256 amountOut = totalPTokens * swapRate / 1e18;
        uint256 feeAmt = amountOut * controller.fee() / controller.FEE_PRECISION();
        uint256 expectedRecipientAmt = amountOut - feeAmt;

        assertEq(tokenOut.balanceOf(recipient), expectedRecipientAmt, "Recipient balance mismatch");
        assertEq(tokenOut.balanceOf(admin), feeAmt, "Admin fee mismatch");
        assertEq(tokenOut.balanceOf(user), 0, "Owner user should have 0");
        assertEq(tokenOut.balanceOf(otherOwner), 0, "Owner otherOwner should have 0");
    }
}
