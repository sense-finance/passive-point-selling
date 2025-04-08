// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

import {
    PointSellingController,
    IPointTokenizationVault,
    UserPreferences,
    ZeroAddressProvided,
    NotSafeOwner,
    Claim,
    ISafe,
    ArrayLengthMismatch,
    MinPriceTooLow,
    FeeTooLarge
} from "../src/PointSellingController.sol";

contract ERC20Mock is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        return _mint(to, amount);
    }
}

error Slippage();

contract UniversalPoolMock {
    uint256 public nextSwapRate = 1e18;

    function setNextSwapRate(uint256 rate) external {
        nextSwapRate = rate;
    }

    function swap(IERC20 tokenIn, IERC20 tokenOut, uint256 amountIn, uint256 minReturn)
        external
        returns (uint256 amountOut)
    {
        uint256 tokenOutPrecision = 10 ** IERC20Metadata(address(tokenOut)).decimals();
        amountOut = amountIn * nextSwapRate / tokenOutPrecision;
        require(amountOut >= minReturn, Slippage());

        tokenIn.transferFrom(msg.sender, address(this), amountIn);
        tokenOut.transfer(msg.sender, amountOut);
    }
}

contract PointSellingControllerMock is PointSellingController {
    UniversalPoolMock public immutable amm = new UniversalPoolMock();

    constructor(address _owner) PointSellingController(_owner) {}

    function swap(IERC20 tokenIn, IERC20 tokenOut, uint256 amountIn, uint256 minPrice, bytes calldata)
        internal
        override
        returns (uint256 amountOut)
    {
        tokenIn.approve(address(amm), amountIn);
        return amm.swap(
            tokenIn, tokenOut, amountIn, minPrice * amountIn / (10 ** IERC20Metadata(address(tokenOut)).decimals())
        );
    }
}

contract PointTokenizationVaultMock is IPointTokenizationVault {
    mapping(bytes32 => ERC20Mock) public pTokens;

    constructor() {
        pTokens[bytes32(uint256(1))] = new ERC20Mock("pToken1", "PTK1");
    }

    function claimPTokens(Claim calldata _claim, address, address _receiver) external {
        pTokens[_claim.pointsId].mint(_receiver, _claim.amountToClaim);
    }

    function trustReceiver(address _account, bool _isTrusted) external {}

    function claimedPTokens(address _account, bytes32 _pointsId) external view returns (uint256) {}

    function multicall(bytes[] calldata calls) external {
        for (uint256 i = 0; i < calls.length; i++) {
            (bool success,) = address(this).call(calls[i]);
            require(success, "Multicall failed");
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

    function getOwners() external view returns (address[] memory) {
        address[] memory owners = new address[](1);
        owners[0] = owner;
        return owners;
    }
}

contract PointSellingControllerTest is Test {
    address admin = makeAddr("admin");
    address user = makeAddr("user");
    address user1 = makeAddr("user1");

    PointTokenizationVaultMock public pointTokenizationVault = new PointTokenizationVaultMock();
    ERC20Mock public tokenOut = new ERC20Mock("token out", "TKNO");

    PointSellingControllerMock public pointSellingController;
    IERC20 pToken;

    function setUp() public {
        pointSellingController = new PointSellingControllerMock(admin);
        pToken = IERC20(pointTokenizationVault.pTokens(bytes32(uint256(1))));

        tokenOut.mint(address(pointSellingController.amm()), 1e27);
        ERC20Mock(address(pToken)).mint(address(pointSellingController.amm()), 1e27);
    }

    function test_accessControl() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        pointSellingController.setFeePercentage(1);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        pointSellingController.executePointSale(
            pToken, tokenOut, new address[](1), pointTokenizationVault, new Claim[](1), 1, ""
        );
    }

    function test_setFeePercentage(uint256 newFee) public {
        newFee %= 2e17;
        vm.prank(admin);
        if (newFee > 1e17) {
            vm.expectRevert(FeeTooLarge.selector);
            pointSellingController.setFeePercentage(newFee);
        } else {
            pointSellingController.setFeePercentage(newFee);
            assertEq(pointSellingController.fee(), newFee);
        }
    }

    function test_setUserPreferences() public {
        vm.prank(user);
        vm.expectRevert(ZeroAddressProvided.selector);
        pointSellingController.setUserPreferences(
            user, IERC20(address(0)), UserPreferences({minPrice: 1000000000000000000, recipient: user})
        );

        address rumpelWallet = address(new RumpelWalletMock(makeAddr("random owner")));
        vm.prank(user);
        vm.expectRevert(NotSafeOwner.selector);
        pointSellingController.setUserPreferences(
            rumpelWallet, IERC20(address(1)), UserPreferences({minPrice: 1000000000000000000, recipient: user})
        );

        vm.prank(user);
        pointSellingController.setUserPreferences(
            user, IERC20(address(1)), UserPreferences({minPrice: 1000000000000000000, recipient: user})
        );

        (uint256 minPrice, address recipient) = pointSellingController.userPreferences(user, IERC20(address(1)));
        assertEq(minPrice, 1000000000000000000);
        assertEq(recipient, user);
    }

    function test_executePointSale() public {
        address[] memory wallets = new address[](2);
        Claim[] memory claims = new Claim[](1);
        vm.prank(admin);
        vm.expectRevert(ArrayLengthMismatch.selector);
        pointSellingController.executePointSale(
            pToken, tokenOut, wallets, pointTokenizationVault, claims, 1000000000000000000, ""
        );

        vm.prank(user);
        pointSellingController.setUserPreferences(
            user, pToken, UserPreferences({minPrice: 1000000000000000000, recipient: user})
        );

        wallets = new address[](2);
        claims = new Claim[](2);
        wallets[0] = user;
        wallets[1] = user1;
        claims[0] =
            Claim({pointsId: bytes32(uint256(1)), totalClaimable: 1e18, amountToClaim: 1e18, proof: new bytes32[](0)});
        vm.prank(admin);
        vm.expectRevert(MinPriceTooLow.selector);
        pointSellingController.executePointSale(pToken, tokenOut, wallets, pointTokenizationVault, claims, 1e17, "");

        vm.prank(user1);
        pointSellingController.setUserPreferences(
            user1, pToken, UserPreferences({minPrice: 1000000000000000000, recipient: user1})
        );
        claims[1] =
            Claim({pointsId: bytes32(uint256(1)), totalClaimable: 1e18, amountToClaim: 1e18, proof: new bytes32[](0)});

        vm.prank(admin);
        pointSellingController.executePointSale(
            pToken, tokenOut, wallets, pointTokenizationVault, claims, 1000000000000000000, ""
        );

        assertEq(tokenOut.balanceOf(user), tokenOut.balanceOf(user1));
        assertEq(tokenOut.balanceOf(user), 999000000000000000);
        assertEq(tokenOut.balanceOf(admin), 2000000000000000);
    }
}
