// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {
    PointSellingController,
    IPointMinter,
    PointSaleRequest,
    ZeroAddressProvided,
    NotSafeOwner,
    Claim,
    ISafe,
    ArrayLengthMismatch,
    RequestInactive,
    TokenOutMismatch
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

    function swap(IERC20 tokenIn, IERC20 tokenOut, uint256 amountIn, uint256 minPrice)
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

contract PointMinterMock is IPointMinter {
    mapping(bytes32 => ERC20Mock) public pTokens;

    constructor() {
        pTokens[bytes32(uint256(1))] = new ERC20Mock("pToken1", "PTK1");
    }

    function claimPTokens(Claim calldata _claim, address, address _receiver) external {
        pTokens[_claim.pointsId].mint(_receiver, _claim.amountToClaim);
    }

    function trustReceiver(address _account, bool _isTrusted) external {}
}

contract RumpelWalletMock is ISafe {
    address public immutable owner;

    constructor(address _owner) {
        owner = _owner;
    }

    function isOwner(address _owner) external view returns (bool) {
        return owner == _owner;
    }
}

contract PointSellingControllerTest is Test {
    address admin = makeAddr("admin");
    address user = makeAddr("user");
    address user1 = makeAddr("user1");

    PointMinterMock public minter = new PointMinterMock();
    ERC20Mock public tokenOut = new ERC20Mock("token out", "TKNO");

    PointSellingControllerMock public pointSellingController;
    IERC20 pToken;

    function setUp() public {
        pointSellingController = new PointSellingControllerMock(admin);
        pToken = IERC20(minter.pTokens(bytes32(uint256(1))));

        tokenOut.mint(address(pointSellingController.amm()), 1e27);
        ERC20Mock(address(pToken)).mint(address(pointSellingController.amm()), 1e27);
    }

    function test_addRequest() public {
        vm.prank(user);
        vm.expectRevert(ZeroAddressProvided.selector);
        pointSellingController.updateRequest(
            user,
            IERC20(address(0)),
            PointSaleRequest({
                active: true,
                tokenOut: IERC20(address(1)),
                minPrice: 1000000000000000000,
                recipient: user
            })
        );

        vm.prank(user);
        vm.expectRevert(ZeroAddressProvided.selector);
        pointSellingController.updateRequest(
            user,
            IERC20(address(1)),
            PointSaleRequest({
                active: true,
                tokenOut: IERC20(address(0)),
                minPrice: 1000000000000000000,
                recipient: user
            })
        );

        address rumpelWallet = address(new RumpelWalletMock(makeAddr("random owner")));
        vm.prank(user);
        vm.expectRevert(NotSafeOwner.selector);
        pointSellingController.updateRequest(
            rumpelWallet,
            IERC20(address(1)),
            PointSaleRequest({
                active: true,
                tokenOut: IERC20(address(2)),
                minPrice: 1000000000000000000,
                recipient: user
            })
        );

        vm.prank(user);
        pointSellingController.updateRequest(
            user,
            IERC20(address(1)),
            PointSaleRequest({
                active: true,
                tokenOut: IERC20(address(2)),
                minPrice: 1000000000000000000,
                recipient: user
            })
        );

        (bool active, IERC20 _tokenOut, uint256 minPrice, address recipient) =
            pointSellingController.requests(user, IERC20(address(1)));
        assertTrue(active);
        assertEq(minPrice, 1000000000000000000);
        assertEq(recipient, user);
        assertEq(address(_tokenOut), address(2));
    }

    function test_executePointSale() public {
        address[] memory wallets = new address[](2);
        Claim[] memory claims = new Claim[](1);
        vm.prank(admin);
        vm.expectRevert(ArrayLengthMismatch.selector);
        pointSellingController.executePointSale(pToken, wallets, minter, claims);

        wallets = new address[](1);
        claims = new Claim[](1);
        wallets[0] = makeAddr("random user");
        vm.prank(admin);
        vm.expectRevert(RequestInactive.selector);
        pointSellingController.executePointSale(pToken, wallets, minter, claims);

        vm.prank(user);
        pointSellingController.updateRequest(
            user,
            pToken,
            PointSaleRequest({active: true, tokenOut: tokenOut, minPrice: 1000000000000000000, recipient: user})
        );

        vm.prank(user1);
        pointSellingController.updateRequest(
            user1,
            pToken,
            PointSaleRequest({
                active: true,
                tokenOut: IERC20(address(1234546)),
                minPrice: 1000000000000000000,
                recipient: user1
            })
        );
        wallets = new address[](2);
        claims = new Claim[](2);
        wallets[0] = user;
        wallets[1] = user1;
        claims[0] =
            Claim({pointsId: bytes32(uint256(1)), totalClaimable: 1e18, amountToClaim: 1e18, proof: new bytes32[](0)});
        vm.prank(admin);
        vm.expectRevert(TokenOutMismatch.selector);
        pointSellingController.executePointSale(pToken, wallets, minter, claims);

        vm.prank(user1);
        pointSellingController.updateRequest(
            user1,
            pToken,
            PointSaleRequest({active: true, tokenOut: tokenOut, minPrice: 1000000000000000000, recipient: user1})
        );
        claims[1] =
            Claim({pointsId: bytes32(uint256(1)), totalClaimable: 1e18, amountToClaim: 1e18, proof: new bytes32[](0)});

        vm.prank(admin);
        pointSellingController.executePointSale(pToken, wallets, minter, claims);

        assertEq(tokenOut.balanceOf(user), tokenOut.balanceOf(user1));
        assertEq(tokenOut.balanceOf(user), 999000000000000000);
        assertEq(tokenOut.balanceOf(admin), 2000000000000000);
    }
}
