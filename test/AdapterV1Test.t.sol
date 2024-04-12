// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {AdapterV1} from "../src/AdapterV1.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PortalV2MultiAsset} from "../src/Portal/PortalV2MultiAsset.sol";
import {VirtualLP} from "../src/Portal/VirtualLP.sol";
import {SwapDescription} from "./../src/interfaces/IOneInchV5AggregationRouter.sol";
import {Account} from "./../src/interfaces/IAdapterV1.sol";
import {EventsLib} from "./../src/libraries/EventsLib.sol";
import {ErrorsLib} from "./../src/libraries/ErrorsLib.sol";
import {IWETH} from "./../src/interfaces/IWETH.sol";
import {IRamsesFactory, IRamsesRouter, IRamsesPair} from "./../src/interfaces/IRamses.sol";

contract AdapterV1Test is Test {
    address constant PSM_TOKEN_ADDRESS =
        0x17A8541B82BF67e10B0874284b4Ae66858cb1fd5;
    address constant ONE_INCH_V5_AGGREGATION_ROUTER_CONTRACT_ADDRESS =
        0x1111111254EEB25477B68fb85Ed929f73A960582;
    address constant WETH_ADDRESS = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address constant RAMSES_FACTORY_ADDRESS =
        0xAAA20D08e59F6561f242b08513D36266C5A29415;
    address constant RAMSES_ROUTER_ADDRESS =
        0xAAA87963EFeB6f7E0a2711F397663105Acb1805e;
    uint256 constant WAD = 1e18;
    uint256 constant SECONDS_PER_YEAR = 31536000;
    uint256 constant MAX_UINT =
        115792089237316195423570985008687907853269984665640564039457584007913129639935;

    address constant WETH_TOKEN_ADDRESS =
        0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address constant USDC_TOKEN_ADDRESS =
        0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address constant USDCE_TOKEN_ADDRESS =
        0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address constant ARB_TOKEN_ADDRESS =
        0x912CE59144191C1204E64559FE8253a0e49E6548;
    address constant USDT_TOKEN_ADDRESS =
        0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;

    IERC20 constant _WETH_TOKEN = IERC20(WETH_TOKEN_ADDRESS);
    IERC20 constant _USDC_TOKEN = IERC20(USDC_TOKEN_ADDRESS);
    IERC20 constant _USDCE_TOKEN = IERC20(USDCE_TOKEN_ADDRESS);
    IERC20 constant _ARB_TOKEN = IERC20(ARB_TOKEN_ADDRESS);
    IERC20 constant _USDT_TOKEN = IERC20(USDT_TOKEN_ADDRESS);

    AdapterV1 public adapter_USDC;
    AdapterV1 public adapter_ETH;
    PortalV2MultiAsset public portal_USDC;
    PortalV2MultiAsset public portal_ETH;
    VirtualLP public virtualLP;
    IERC20 public portalEnergyToken_USDC;
    IERC20 public portalEnergyToken_ETH;
    IERC20 public principal_USDC;
    IERC20 public principal_ETH;

    IWETH public constant WETH = IWETH(WETH_ADDRESS); // Interface of WETH
    IRamsesFactory public RAMSES_FACTORY =
        IRamsesFactory(RAMSES_FACTORY_ADDRESS); // Interface of Ramses Factory
    IRamsesRouter public RAMSES_ROUTER = IRamsesRouter(RAMSES_ROUTER_ADDRESS); // Interface of Ramses Router
    IERC20 constant PSM = IERC20(PSM_TOKEN_ADDRESS);

    uint256 public denominator_USDC;
    uint256 public denominator_ETH;

    uint256 public startAmount = 1e24; // 1 million
    uint256 public usdc_precision = 1e6;
    address public usdcSender = 0x2Df1c51E09aECF9cacB7bc98cB1742757f163dF7;
    address public psmSender = 0xAb845D09933f52af5642FC87Dd8FBbf553fd7B33;

    // prank addresses
    address alice = address(uint160(uint256(keccak256("alice"))));
    address bob = address(uint160(uint256(keccak256("bob"))));
    address karen = address(uint160(uint256(keccak256("karen"))));

    function setUp() public {
        // vm.createSelectFork({
        //     urlOrAlias: "rpcURL"
        // });

        principal_USDC = _USDC_TOKEN;
        principal_ETH = IERC20(address(0));

        virtualLP = new VirtualLP(psmSender, 1e24, 259200, 1);

        portal_USDC = new PortalV2MultiAsset(
            address(virtualLP),
            1e55,
            address(principal_USDC),
            6,
            "USD COIN",
            "USDC",
            "abcd"
        );

        portal_ETH = new PortalV2MultiAsset(
            address(virtualLP),
            1e55,
            address(principal_ETH),
            6,
            "Ether",
            "ETH",
            "abcd"
        );

        help_setupVirtualLP();
        help_setupPortals();

        adapter_USDC = new AdapterV1(address(portal_USDC));
        adapter_ETH = new AdapterV1(address(portal_ETH));

        denominator_USDC = portal_USDC.DENOMINATOR();
        denominator_ETH = portal_ETH.DENOMINATOR();

        portalEnergyToken_USDC = portal_USDC.portalEnergyToken();
        portalEnergyToken_ETH = portal_ETH.portalEnergyToken();

        vm.startPrank(psmSender);
        PSM.transfer(alice, startAmount);
        PSM.transfer(bob, startAmount);
        PSM.transfer(karen, startAmount);
        vm.stopPrank();
        vm.startPrank(usdcSender);
        principal_USDC.transfer(alice, (startAmount * usdc_precision) / WAD);
        principal_USDC.transfer(bob, (startAmount * usdc_precision) / WAD);
        principal_USDC.transfer(karen, (startAmount * usdc_precision) / WAD);
        vm.stopPrank();
        vm.deal(alice, startAmount);
        vm.deal(bob, startAmount);
        vm.deal(karen, startAmount);
    }

    /////////////////////////////////////////////
    ////////////// HELPER FUNCTIONS /////////////
    /////////////////////////////////////////////
    function help_setupPortals() public {
        // create PE token
        portal_USDC.create_portalEnergyToken();
        portal_ETH.create_portalEnergyToken();
        // create NFT
        portal_USDC.create_portalNFT();
        portal_ETH.create_portalNFT();
    }

    function help_setupVirtualLP() public {
        // create bToken
        virtualLP.create_bToken();

        // fund LP
        vm.startPrank(psmSender);
        PSM.approve(address(virtualLP), 1e55);
        virtualLP.contributeFunding(5e26);

        // pass time
        uint256 activationTime = block.timestamp +
            virtualLP.FUNDING_PHASE_DURATION();
        vm.warp(activationTime);

        // activate LP
        virtualLP.activateLP();

        // register Portals in LP
        virtualLP.registerPortal(
            address(portal_USDC),
            address(principal_USDC),
            virtualLP.USDC_WATER()
        );
        virtualLP.registerPortal(
            address(portal_ETH),
            address(principal_ETH),
            virtualLP.WETH_WATER()
        );
        vm.stopPrank();
    }

    function help_setAllowances() internal {
        // increase token spending approvals for the Vault in LP
        virtualLP.increaseAllowanceVault(address(portal_USDC));
        virtualLP.increaseAllowanceVault(address(portal_ETH));

        /// increase token spending approvals for the Portals in Adapters
        adapter_USDC.increaseAllowances();
        adapter_ETH.increaseAllowances();
    }

    function help_stake_USDC() internal {
        vm.startPrank(alice);
        principal_USDC.approve(address(adapter_USDC), 1e10);
        adapter_USDC.stake(1e10);
        vm.stopPrank();
    }

    function help_stake_ETH() internal {
        vm.prank(alice);
        adapter_ETH.stake{value: 1e19}(1e19);
    }

    function help_mintPeTokens_ETH() internal {
        help_stake_ETH();

        adapter_ETH.mintPortalEnergyToken(msg.sender, 1e18);
    }

    function help_mintPeTokens_USDC() internal {
        help_stake_USDC();

        adapter_USDC.mintPortalEnergyToken(msg.sender, 1e9);
    }

    /////////////////////////////////////////////
    ///////////////// TEST CASES ////////////////
    /////////////////////////////////////////////

    // stake
    // success 1: ETH Portal
    function testStake_ETH() external {
        uint256 amount = 1e18;
        uint256 VaultBalance = IERC20(WETH_ADDRESS).balanceOf(
            virtualLP.WETH_WATER()
        );

        help_setAllowances();

        vm.prank(alice);
        adapter_ETH.stake{value: amount}(amount);

        assertEq(alice.balance, startAmount - amount);
        assertEq(
            _WETH_TOKEN.balanceOf(virtualLP.WETH_WATER()),
            VaultBalance + amount
        );
    }

    // success 2: ETH Portal
    function testStake_ETH_2() external {
        uint256 amount = 1e18;
        uint256 VaultBalance = IERC20(WETH_ADDRESS).balanceOf(
            virtualLP.WETH_WATER()
        );

        help_setAllowances();

        vm.prank(alice);
        adapter_ETH.stake{value: amount}(123);

        assertEq(alice.balance, startAmount - amount);
        assertEq(
            _WETH_TOKEN.balanceOf(virtualLP.WETH_WATER()),
            VaultBalance + amount
        );
    }

    // success 3: USDC Portal
    function testStake_USDC() external {
        uint256 amount = 1e9;
        uint256 VaultBalance = principal_USDC.balanceOf(virtualLP.USDC_WATER());

        help_setAllowances();

        vm.startPrank(alice);
        principal_USDC.approve(address(adapter_USDC), amount);
        adapter_USDC.stake(amount);
        vm.stopPrank();

        assertEq(
            principal_USDC.balanceOf(alice),
            (startAmount * usdc_precision) / WAD - amount
        );
        assertEq(
            principal_USDC.balanceOf(virtualLP.USDC_WATER()),
            VaultBalance + amount
        );
    }

    // revert 1: not enough ETH in wallet
    function testFailStake_ETH() external {
        uint256 amount = 1e36;

        help_setAllowances();

        vm.startPrank(alice);
        vm.expectRevert("OutOfFund");
        adapter_ETH.stake{value: amount}(amount);
        vm.stopPrank();
    }

    // revert 2: not enough USDC in wallet
    function testFailStake_USDC() external {
        uint256 amount = 1e36;

        help_setAllowances();

        vm.startPrank(alice);
        principal_USDC.approve(address(adapter_USDC), amount);
        vm.expectRevert("OutOfFund");
        adapter_USDC.stake{value: amount}(amount);
        vm.stopPrank();
    }

    // unstake
    // success 1: enough PE with ETH Portal
    // success 2: enough PE with USDC Portal
    // success 3: burning PE tokens ETH Portal
    // success 4: burning PE tokens with USDC Portal
    // revert 1: not enough staked balance ETH Portal
    // revert 2: not enough staked balance USDC Portal
    // revert 3: not enough PE / PE tokens ETH Portal
    // revert 4: not enough PE / PE tokens USDC Portal

    // buyPortalEnergy
    // success
    // revert 1: 0 amount
    // revert 2: recipient address 0
    // revert 3: more input than balance PSM

    // sellPortalEnergy
    // success 1: get PSM
    // success 2: get LP
    // success 3: get Other token
    // revert 1: 0 amount
    // revert 2: recipient address 0
    // revert 3: more input than balance PE

    // burnPortalEnergyToken
    // success
    // revert 1: 0 amount
    // revert 2: recipient address 0
    // revert 3: amount > balance PE token

    // MintPortalEnergyToken
    // success
    // revert 1: 0 amount
    // revert 2: recipient address 0
    // revert 3: amount > balance PE
}
