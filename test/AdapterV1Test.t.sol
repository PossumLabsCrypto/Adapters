// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {AdapterV1} from "../src/AdapterV1.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PortalV2MultiAsset} from "../src/Portal/PortalV2MultiAsset.sol";
import {VirtualLP} from "../src/Portal/VirtualLP.sol";
import {Account} from "./../src/interfaces/IAdapterV1.sol";
import {EventsLib} from "./../src/libraries/EventsLib.sol";
import {ErrorsLib} from "./../src/libraries/ErrorsLib.sol";
import {IWETH} from "./../src/interfaces/IWETH.sol";
import {IRamsesPair} from "./../src/interfaces/IRamses.sol";

contract AdapterV1Test is Test {
    address constant PSM_TOKEN_ADDRESS = 0x17A8541B82BF67e10B0874284b4Ae66858cb1fd5;
    address constant ONE_INCH_V5_AGGREGATION_ROUTER_CONTRACT_ADDRESS = 0x1111111254EEB25477B68fb85Ed929f73A960582;
    address constant WETH_ADDRESS = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address constant RAMSES_FACTORY_ADDRESS = 0xAAA20D08e59F6561f242b08513D36266C5A29415;
    address constant RAMSES_ROUTER_ADDRESS = 0xAAA87963EFeB6f7E0a2711F397663105Acb1805e;
    uint256 constant WAD = 1e18;
    uint256 constant SECONDS_PER_YEAR = 31536000;
    uint256 constant MAX_UINT = 115792089237316195423570985008687907853269984665640564039457584007913129639935;

    address constant WETH_TOKEN_ADDRESS = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address constant USDC_TOKEN_ADDRESS = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address constant USDCE_TOKEN_ADDRESS = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address constant ARB_TOKEN_ADDRESS = 0x912CE59144191C1204E64559FE8253a0e49E6548;
    address constant USDT_TOKEN_ADDRESS = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;

    IERC20 constant _WETH_TOKEN = IERC20(WETH_TOKEN_ADDRESS);
    IERC20 constant _USDC_TOKEN = IERC20(USDC_TOKEN_ADDRESS);
    IERC20 constant _USDCE_TOKEN = IERC20(USDCE_TOKEN_ADDRESS);
    IERC20 constant _ARB_TOKEN = IERC20(ARB_TOKEN_ADDRESS);
    IERC20 constant _USDT_TOKEN = IERC20(USDT_TOKEN_ADDRESS);

    AdapterV1 public adapter_USDC;
    AdapterV1 public adapter_ETH;
    AdapterV1 public adapterNew;
    PortalV2MultiAsset public portal_USDC;
    PortalV2MultiAsset public portal_ETH;
    VirtualLP public virtualLP;
    IERC20 public portalEnergyToken_USDC;
    IERC20 public portalEnergyToken_ETH;
    IERC20 public principal_USDC;
    IERC20 public principal_ETH;

    IWETH public constant WETH = IWETH(WETH_ADDRESS); // Interface of WETH
    IERC20 constant PSM = IERC20(PSM_TOKEN_ADDRESS);

    uint256 public denominator_USDC;
    uint256 public denominator_ETH;

    uint256 public startAmount = 1e24; // 1 million
    uint256 public usdc_precision = 1e6;
    address public usdcSender = 0x2Df1c51E09aECF9cacB7bc98cB1742757f163dF7;
    address public psmSender = 0xAb845D09933f52af5642FC87Dd8FBbf553fd7B33;
    address public owner = 0xAb845D09933f52af5642FC87Dd8FBbf553fd7B33;
    address public newAdapterAddr = address(5);

    // prank addresses
    address alice = address(uint160(uint256(keccak256("alice"))));
    address bob = address(uint160(uint256(keccak256("bob"))));
    address karen = address(uint160(uint256(keccak256("karen"))));

    function setUp() public {
        vm.createSelectFork({urlOrAlias: "alchemy_arbitrum_api", blockNumber: 200000000});

        principal_USDC = _USDC_TOKEN;
        principal_ETH = IERC20(address(0));

        virtualLP = new VirtualLP(psmSender, 1e24, 259200, 1);

        portal_USDC =
            new PortalV2MultiAsset(address(virtualLP), 1e55, address(principal_USDC), 6, "USD COIN", "USDC", "abcd");

        portal_ETH =
            new PortalV2MultiAsset(address(virtualLP), 1e55, address(principal_ETH), 18, "Ether", "ETH", "abcd");

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
        uint256 activationTime = block.timestamp + virtualLP.FUNDING_PHASE_DURATION();
        vm.warp(activationTime);

        // activate LP
        virtualLP.activateLP();

        // register Portals in LP
        virtualLP.registerPortal(address(portal_USDC), address(principal_USDC), virtualLP.USDC_WATER());
        virtualLP.registerPortal(address(portal_ETH), address(principal_ETH), virtualLP.WETH_WATER());
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
        help_setAllowances();
        vm.startPrank(alice);
        principal_USDC.approve(address(adapter_USDC), 1e10);
        adapter_USDC.stake(1e10);
        vm.stopPrank();
    }

    function help_stake_ETH() internal {
        help_setAllowances();
        vm.prank(alice);
        adapter_ETH.stake{value: 1e19}(1e19);
    }

    function help_stake_ETH_Bob() internal {
        vm.prank(bob);
        adapter_ETH.stake{value: 1e19}(1e19);
    }

    function help_stake_ETH_Karen() internal {
        vm.prank(karen);
        adapter_ETH.stake{value: 1e19}(1e19);
    }

    function help_mintPeTokens_ETH() internal {
        help_stake_ETH();

        adapter_ETH.mintPortalEnergyToken(msg.sender, 1e18);
    }

    function help_mintPeTokens_USDC() internal {
        help_stake_USDC();

        adapter_USDC.mintPortalEnergyToken(msg.sender, 1e5);
    }

    /////////////////////////////////////////////
    ///////////////// TEST CASES ////////////////
    /////////////////////////////////////////////

    function testSetUp() external {
        adapterNew = new AdapterV1(address(portal_ETH));
        address PETAddr = address(adapterNew.portalEnergyToken());
        address PETAddr2 = address(portal_ETH.portalEnergyToken());
        assertEq(PETAddr, PETAddr2);
        console2.log(address(PSM));
        console2.log(address(adapter_ETH));
        console2.log(address(alice));
    }

    // stake
    function testStake_ETH() external {
        uint256 amount = 1e18;
        uint256 VaultBalance = IERC20(WETH_ADDRESS).balanceOf(virtualLP.WETH_WATER());

        help_setAllowances();

        vm.prank(alice);
        adapter_ETH.stake{value: amount}(amount);

        assertEq(alice.balance, startAmount - amount);
        assertEq(_WETH_TOKEN.balanceOf(virtualLP.WETH_WATER()), VaultBalance + amount);
    }

    function testStakeETH_totalPrincipalStakedIncreased() external {
        assertEq(adapter_ETH.totalPrincipalStaked(), 0);
        help_stake_ETH();
        help_stake_ETH_Bob();
        help_stake_ETH_Karen();
        assertEq(adapter_ETH.totalPrincipalStaked(), 1e19 * 3);
    }

    // success 2: ETH Portal
    function testStake_ETH_2() external {
        uint256 amount = 1e18;
        uint256 VaultBalance = IERC20(WETH_ADDRESS).balanceOf(virtualLP.WETH_WATER());

        help_setAllowances();

        vm.prank(alice);
        adapter_ETH.stake{value: amount}(123);

        assertEq(alice.balance, startAmount - amount);
        assertEq(_WETH_TOKEN.balanceOf(virtualLP.WETH_WATER()), VaultBalance + amount);
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

        assertEq(principal_USDC.balanceOf(alice), (startAmount * usdc_precision) / WAD - amount);
        assertEq(principal_USDC.balanceOf(virtualLP.USDC_WATER()), VaultBalance + amount);
    }

    function testStake_USDC_NativeTokenNotAllowed() external {
        uint256 amount = 1e9;
        help_setAllowances();

        vm.startPrank(alice);
        principal_USDC.approve(address(adapter_USDC), amount);
        vm.expectRevert(ErrorsLib.NativeTokenNotAllowed.selector);
        adapter_USDC.stake{value: amount}(amount);
        vm.stopPrank();
    }

    // revert 1: not enough ETH in wallet
    function testRevertsStake_ETH() external {
        uint256 amount = 1e36;

        help_setAllowances();

        vm.startPrank(alice);
        vm.expectRevert();
        adapter_ETH.stake{value: amount}(amount);
        vm.stopPrank();
    }

    // revert 2: not enough USDC in wallet
    function testRevertsStake_USDC() external {
        uint256 amount = 1e36;

        help_setAllowances();

        vm.startPrank(alice);
        principal_USDC.approve(address(adapter_USDC), amount);
        vm.expectRevert();
        adapter_USDC.stake{value: amount}(amount);
        vm.stopPrank();
    }

    // unstake
    function testUnstakeETH() external {
        help_stake_ETH();
        skip(30 days);
        uint256 balBefore = alice.balance;
        vm.prank(alice);
        adapter_ETH.unstake(1e19);
        assertGt(alice.balance, balBefore);
    }

    function testUnstakeETH_burnPE() external {
        help_stake_ETH();
        skip(30 days);
        vm.deal(alice, startAmount);

        vm.startPrank(alice);
        PSM.approve(address(adapter_ETH), startAmount);
        adapter_ETH.buyPortalEnergy(alice, startAmount, 1, block.timestamp);
        (,,,, uint256 portalEnergy) = adapter_ETH.accounts(alice);
        adapter_ETH.mintPortalEnergyToken(alice, portalEnergy);
        vm.stopPrank();

        uint256 PETbalBeforeBurn = portalEnergyToken_ETH.balanceOf(alice);
        uint256 balBefore = alice.balance;
        vm.startPrank(alice);
        portalEnergyToken_ETH.approve(address(adapter_ETH), portalEnergyToken_ETH.balanceOf(alice));
        adapter_ETH.unstake(1e19);
        uint256 PETbalAfterBurn = portalEnergyToken_ETH.balanceOf(alice);
        assertGt(alice.balance, balBefore);
        assertGt(PETbalBeforeBurn, PETbalAfterBurn);
        vm.stopPrank();
    }

    function testRevertsUnstakeETH_InsufficientStakeBalance() external {
        help_stake_ETH();
        skip(30 days);
        vm.prank(alice);
        vm.expectRevert(ErrorsLib.InsufficientStakeBalance.selector);
        adapter_ETH.unstake(1e20);
    }

    function testUnstakeETH_AfterVoting() external {
        help_stake_ETH();
        help_stake_ETH_Bob();
        help_stake_ETH_Karen();

        vm.prank(owner);
        adapter_ETH.proposeMigrationDestination(newAdapterAddr);
        assertEq(adapter_ETH.migrationDestination(), newAdapterAddr);
        assertEq(adapter_ETH.votesForMigration(), 0);

        skip(30 days);

        vm.prank(alice);
        adapter_ETH.acceptMigrationDestination();
        assertEq(adapter_ETH.voted(alice), 1e19);
        assertEq(adapter_ETH.votesForMigration(), 1e19);
        assertEq(adapter_ETH.successMigrated(), false);

        vm.prank(alice);
        adapter_ETH.unstake(1e9);
        assertEq(adapter_ETH.voted(alice), 0);
        assertEq(adapter_ETH.votesForMigration(), 0);
    }

    function testUnstakeUSDC() external {
        help_stake_USDC();
        skip(30 days);
        uint256 aliceBal = principal_USDC.balanceOf(alice);
        vm.prank(alice);
        adapter_USDC.unstake(1e10);
        assertGt(principal_USDC.balanceOf(alice), aliceBal);
    }

    function testRevertsUnstakeUSDC_InsufficientStakeBalance() external {
        help_stake_USDC();
        skip(30 days);
        vm.prank(alice);
        vm.expectRevert(ErrorsLib.InsufficientStakeBalance.selector);
        adapter_USDC.unstake(1e11);
    }

    function testUnstakeETH_totalPrincipalStakedDecreased() external {
        assertEq(adapter_ETH.totalPrincipalStaked(), 0);
        help_stake_ETH();
        assertEq(adapter_ETH.totalPrincipalStaked(), 1e19);
        skip(30 days);
        vm.prank(alice);
        adapter_ETH.unstake(1e19);
        assertEq(adapter_ETH.totalPrincipalStaked(), 0);
    }

    // Migration tests
    function testProposeMigrationDestination() external {
        assertEq(adapter_ETH.migrationDestination(), address(0));
        vm.startPrank(owner);
        adapter_ETH.proposeMigrationDestination(newAdapterAddr);
        vm.stopPrank();
        assertEq(adapter_ETH.migrationDestination(), newAdapterAddr);
    }

    function testReverts_ProposeMigrationDestination_notOwner() external {
        vm.startPrank(address(this));
        vm.expectRevert(ErrorsLib.notOwner.selector);
        adapter_ETH.proposeMigrationDestination(newAdapterAddr);
        vm.stopPrank();
    }

    function testacceptMigrationDestination() external {
        help_stake_ETH();

        vm.prank(owner);
        adapter_ETH.proposeMigrationDestination(newAdapterAddr);

        assertEq(adapter_ETH.migrationDestination(), newAdapterAddr);
        assertEq(adapter_ETH.votesForMigration(), 0);

        vm.prank(alice);
        adapter_ETH.acceptMigrationDestination();

        vm.warp(block.timestamp + 10 days);

        vm.prank(bob);
        adapter_ETH.executeMigration();
        assertEq(adapter_ETH.successMigrated(), true);
        assertEq(adapter_ETH.voted(alice), 1e19);
        assertEq(adapter_ETH.votesForMigration(), 1e19);
    }

    function testacceptMigrationDestination_ThreeUsersMajorityVotes() external {
        help_stake_ETH();
        help_stake_ETH_Bob();
        help_stake_ETH_Karen();

        vm.prank(owner);
        adapter_ETH.proposeMigrationDestination(newAdapterAddr);

        assertEq(adapter_ETH.migrationDestination(), newAdapterAddr);
        assertEq(adapter_ETH.votesForMigration(), 0);

        vm.prank(alice);
        adapter_ETH.acceptMigrationDestination();
        vm.prank(bob);
        adapter_ETH.acceptMigrationDestination();

        vm.warp(block.timestamp + 10 days);

        vm.prank(bob);
        adapter_ETH.executeMigration();
        assertEq(adapter_ETH.successMigrated(), true);
        assertEq(adapter_ETH.voted(alice), 1e19);
        assertEq(adapter_ETH.voted(bob), 1e19);
        assertEq(adapter_ETH.voted(karen), 0);
        assertEq(adapter_ETH.votesForMigration(), 1e19 * 2);
    }

    function testacceptMigrationDestination_ThreeUsersMinorityVote() external {
        help_stake_ETH();
        help_stake_ETH_Bob();
        help_stake_ETH_Karen();

        vm.prank(owner);
        adapter_ETH.proposeMigrationDestination(newAdapterAddr);

        assertEq(adapter_ETH.migrationDestination(), newAdapterAddr);
        assertEq(adapter_ETH.votesForMigration(), 0);

        vm.prank(alice);
        adapter_ETH.acceptMigrationDestination();

        assertEq(adapter_ETH.voted(alice), 1e19);
        assertEq(adapter_ETH.voted(bob), 0);
        assertEq(adapter_ETH.voted(karen), 0);
        assertEq(adapter_ETH.votesForMigration(), 1e19);
        assertEq(adapter_ETH.successMigrated(), false);
    }

    function testMigrateStake() external {
        help_stake_ETH();
        (,, uint256 stakedBalBefore,,) = adapter_ETH.accounts(alice);
        assertGt(stakedBalBefore, 0);

        vm.prank(owner);
        adapter_ETH.proposeMigrationDestination(newAdapterAddr);

        vm.prank(alice);
        adapter_ETH.acceptMigrationDestination();
        vm.warp(block.timestamp + 10 days);

        vm.prank(bob);
        adapter_ETH.executeMigration();
        assertEq(adapter_ETH.successMigrated(), true);

        vm.prank(newAdapterAddr);
        adapter_ETH.migrateStake(alice);

        (,, uint256 stakedBal,,) = adapter_ETH.accounts(alice);
        assertEq(stakedBal, 0);
    }

    function testReverts_migrateStake_notCalledByDestination() external {
        help_stake_ETH();
        vm.prank(owner);
        adapter_ETH.proposeMigrationDestination(newAdapterAddr);
        vm.prank(alice);
        adapter_ETH.acceptMigrationDestination();
        vm.warp(block.timestamp + 10 days);

        vm.prank(bob);
        adapter_ETH.executeMigration();
        assertEq(adapter_ETH.successMigrated(), true);

        vm.prank(karen);
        vm.expectRevert(ErrorsLib.notCalledByDestination.selector);
        adapter_ETH.migrateStake(alice);
    }

    function testReverts_migrateStake_migrationVotePending() external {
        help_stake_ETH();
        vm.prank(owner);
        adapter_ETH.proposeMigrationDestination(newAdapterAddr);

        vm.prank(newAdapterAddr);
        vm.expectRevert(ErrorsLib.migrationVotePending.selector);
        adapter_ETH.migrateStake(alice);
    }

    function testRevertsStake_whenMigrationStarted() external {
        uint256 amount = 1e10;

        help_setAllowances();

        assertEq(adapter_ETH.migrationDestination(), address(0));
        vm.startPrank(owner);
        adapter_ETH.proposeMigrationDestination(newAdapterAddr); //migration starts
        vm.stopPrank();
        assertEq(adapter_ETH.migrationDestination(), newAdapterAddr);

        vm.startPrank(alice);
        vm.expectRevert(ErrorsLib.isMigrating.selector);
        adapter_ETH.stake{value: amount}(amount);
        vm.stopPrank();
    }

    // buyPortalEnergy
    function testBuyPortalEnergy() external {
        adapter_ETH.increaseAllowances();
        vm.startPrank(alice);
        PSM.approve(address(adapter_ETH), startAmount);
        adapter_ETH.buyPortalEnergy(alice, startAmount, 1, block.timestamp);
        vm.stopPrank();
        (,,,, uint256 portalEnergyNew) = adapter_ETH.accounts(alice);
        assertGt(portalEnergyNew, 1);
    }

    function testBuyPortalEnergy_MultipleUsers() external {
        adapter_ETH.increaseAllowances();
        vm.startPrank(alice);
        PSM.approve(address(adapter_ETH), startAmount);
        adapter_ETH.buyPortalEnergy(alice, startAmount, 1, block.timestamp);
        vm.stopPrank();
        (,,,, uint256 portalEnergyAlice) = adapter_ETH.accounts(alice);
        assertGt(portalEnergyAlice, 1);

        vm.startPrank(bob);
        PSM.approve(address(adapter_ETH), startAmount);
        adapter_ETH.buyPortalEnergy(bob, startAmount, 5, block.timestamp);
        vm.stopPrank();
        (,,,, uint256 portalEnergyBob) = adapter_ETH.accounts(bob);
        assertGt(portalEnergyBob, 3);

        vm.startPrank(karen);
        PSM.approve(address(adapter_ETH), startAmount);
        adapter_ETH.buyPortalEnergy(karen, startAmount, 5, block.timestamp);
        vm.stopPrank();
        (,,,, uint256 portalEnergyKaren) = adapter_ETH.accounts(karen);
        assertGt(portalEnergyKaren, 5);
    }

    function testRevertsBuyPortalEnergy_zeroAmt() external {
        vm.startPrank(alice);
        PSM.approve(address(adapter_ETH), startAmount);
        vm.expectRevert(ErrorsLib.InvalidAmount.selector);
        adapter_ETH.buyPortalEnergy(alice, 0, 0, block.timestamp);
        vm.stopPrank();
    }

    function testFailBuyPortalEnergy_zeroAddr() external {
        vm.startPrank(alice);
        PSM.approve(address(adapter_ETH), startAmount);
        vm.expectRevert("InvalidAddress");
        adapter_ETH.buyPortalEnergy(address(0), startAmount, 1, block.timestamp);
        vm.stopPrank();
    }

    function testFailBuyPortalEnergy_NotEnoughBal() external {
        vm.startPrank(alice);
        PSM.approve(address(adapter_ETH), startAmount);
        vm.expectRevert("NotEnoughBal");
        adapter_ETH.buyPortalEnergy(address(0), startAmount + 5, 1, block.timestamp);
        vm.stopPrank();
    }

    // sellPortalEnergy
    function testSellPortalEnergy_ModeZero() external {
        adapter_ETH.increaseAllowances();
        vm.startPrank(alice);
        PSM.approve(address(adapter_ETH), startAmount);
        adapter_ETH.buyPortalEnergy(alice, startAmount, 1, block.timestamp);
        vm.stopPrank();

        (,,,, uint256 portalEnergy) = adapter_ETH.accounts(alice);
        assertEq(PSM.balanceOf(alice), 0);
        assertGt(portalEnergy, 1);

        uint256 MODE = 0;
        vm.startPrank(alice);
        adapter_ETH.sellPortalEnergy(payable(alice), portalEnergy, 1, block.timestamp, MODE, "", 1, 1);
        (,,,, uint256 portalEnergyNew) = adapter_ETH.accounts(alice);
        assertGt(PSM.balanceOf(alice), 0);
        assertEq(portalEnergyNew, 0);
        vm.stopPrank();
    }

    function testSellPortalEnergy_ModeOne() external { //TODO
            // adapter_ETH.increaseAllowances();
            // vm.startPrank(alice);
            // PSM.approve(address(adapter_ETH), startAmount);
            // adapter_ETH.buyPortalEnergy(alice, startAmount, 1, block.timestamp);
            // vm.stopPrank();

        // (,,,, uint256 portalEnergy) = adapter_ETH.accounts(alice);
        // assertEq(PSM.balanceOf(alice), 0);
        // assertGt(portalEnergy, 1);
        // uint256 MODE = 1;
        // bytes memory response = "0x07ed2379000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd0900000000000000000000000017a8541b82bf67e10b0874284b4ae66858cb1fd5000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000005dad7600c5d89fe3824ffa99ec1c3eb8bf3b0501000000000000000000000000000000000000000000000c94a9ffe5a6357d9746000000000000000000000000000000000000000000000000004025ee509227b600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000120000000000000000000000000000000000000000000000000000000000000019600000000000000000000000000000000000000017800015e0001480000fe00a007e5c0d20000000000000000000000000000000000000000000000da00009e00004f02a00000000000000000000000000000000000000000000000000000000003696c89ee63c1e501a137bed0b2dc07f0addc795b4dee3d2d47410fb917a8541b82bf67e10b0874284b4ae66858cb1fd502a0000000000000000000000000000000000000000000000000004025ee509227b6ee63c1e5007fcdc35463e3770c2fb992716cd070b63540b947af88d065e77c8cc2239327c5edb3a432268e5831410182af49447d8a07e3bd95bd0d56f35241523fbab100042e1a7d4d000000000000000000000000000000000000000000000000000000000000000000a0f2fa6b66eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0000000000000000000000000000000000000000000000000040cbcf1b14eca4000000000000000000059a97844d134ac061111111125421ca6dc452d289314280a0f8842a6500206b4be0b9111111125421ca6dc452d289314280a0f8842a65000000000000000000003a8db16d";
        // vm.startPrank(alice);
        // adapter_ETH.sellPortalEnergy(payable(alice), portalEnergy, 1, block.timestamp, MODE, response, 1, 1);
        // (,,,, uint256 portalEnergyNew) = adapter_ETH.accounts(alice);
        // assertGt(PSM.balanceOf(alice), 0);
        // assertEq(portalEnergyNew, 0);
        // vm.stopPrank();
    }

    function testSellPortalEnergy_ModeTwo() external { //TODO
            // vm.startPrank(alice);
            // PSM.approve(address(adapter_ETH), startAmount);
            // adapter_ETH.buyPortalEnergy(alice, startAmount, 1, block.timestamp);
            // vm.stopPrank();

        // (,,,, uint256 portalEnergy) = adapter_ETH.accounts(alice);
        // assertEq(PSM.balanceOf(alice), 0);
        // assertGt(portalEnergy, 1);

        // uint256 MODE = 2;
        // bytes memory response = '{ "dstAmount": "18933897941780920", "tx": { "from": "0xc7183455a4c133ae270771860664b6b7ec320bb1", "to": "0x111111125421ca6dc452d289314280a0f8842a65", "data": "0xe2c95c820000000000000000000000005dad7600c5d89fe3824ffa99ec1c3eb8bf3b050100000000000000000000000017a8541b82bf67e10b0874284b4ae66858cb1fd5000000000000000000000000000000000000000000000c94a9ffe5a6357d9746000000000000000000000000000000000000000000000000003c8a407aee158c388000000000000000000000a3cc74aacc1b91b7364a510222864d548c4f80383a8db16d", "value": "0", "gas": 0, "gasPrice": "21500000"}}';
        // vm.startPrank(alice);
        // adapter_ETH.sellPortalEnergy(payable(alice), portalEnergy, 1, block.timestamp, MODE, response);

        // (,,,, uint256 portalEnergyNew) = adapter_ETH.accounts(alice);
        // assertGt(PSM.balanceOf(alice), 0);
        // assertEq(portalEnergyNew, 0);
        // vm.stopPrank();
    }

    function testRevertsSellPortalEnergy_ModeInvalid() external {
        adapter_ETH.increaseAllowances();
        vm.startPrank(alice);
        PSM.approve(address(adapter_ETH), startAmount);
        adapter_ETH.buyPortalEnergy(alice, startAmount, 1, block.timestamp);
        vm.stopPrank();
        (,,,, uint256 portalEnergyNew) = adapter_ETH.accounts(alice);

        vm.startPrank(alice);
        vm.expectRevert(ErrorsLib.InvalidMode.selector);
        adapter_ETH.sellPortalEnergy(payable(alice), portalEnergyNew, 1, block.timestamp, 3, "", 1, 1);
    }

    function testFailSellPortalEnergy_ZeroAmt() external {
        vm.startPrank(alice);
        PSM.approve(address(adapter_ETH), startAmount);
        adapter_ETH.buyPortalEnergy(alice, startAmount, 1, block.timestamp);
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert("InvalidAmount");
        adapter_ETH.sellPortalEnergy(payable(alice), 0, 1, block.timestamp, 0, "", 1, 1);
    }

    function testFailSellPortalEnergy_ZeroAddr() external {
        vm.startPrank(alice);
        PSM.approve(address(adapter_ETH), startAmount);
        adapter_ETH.buyPortalEnergy(alice, startAmount, 1, block.timestamp);
        vm.stopPrank();
        (,,,, uint256 portalEnergyNew) = adapter_ETH.accounts(alice);

        vm.startPrank(alice);
        vm.expectRevert("InvalidAddress");
        adapter_ETH.sellPortalEnergy(payable(address(0)), portalEnergyNew, 1, block.timestamp, 0, "", 1, 1);
    }

    function testRevertsSellPortalEnergy_NotEnoughEnergy() external {
        adapter_ETH.increaseAllowances();
        vm.startPrank(alice);
        PSM.approve(address(adapter_ETH), startAmount);
        adapter_ETH.buyPortalEnergy(alice, startAmount, 1, block.timestamp);
        vm.stopPrank();
        (,,,, uint256 portalEnergyNew) = adapter_ETH.accounts(alice);

        vm.startPrank(alice);
        vm.expectRevert(ErrorsLib.InsufficientBalance.selector);
        adapter_ETH.sellPortalEnergy(payable(alice), portalEnergyNew + 5, 1, block.timestamp, 0, "", 1, 1);
    }

    function testFailSellPortalEnergy_DeadlineExpired() external {
        vm.startPrank(alice);
        PSM.approve(address(adapter_ETH), startAmount);
        adapter_ETH.buyPortalEnergy(alice, startAmount, 1, block.timestamp);
        vm.stopPrank();
        (,,,, uint256 portalEnergyNew) = adapter_ETH.accounts(alice);

        vm.startPrank(alice);
        vm.expectRevert("DeadlineExpired");
        adapter_ETH.sellPortalEnergy(payable(alice), portalEnergyNew, 1, 0, 3, "", 1, 1);
    }

    // MintPortalEnergyToken
    function testMintPortalEnergyToken() public {
        adapter_ETH.increaseAllowances();
        vm.startPrank(alice);
        PSM.approve(address(adapter_ETH), startAmount);
        adapter_ETH.buyPortalEnergy(alice, startAmount, 1, block.timestamp);
        (,,,, uint256 portalEnergy) = adapter_ETH.accounts(alice);
        assertGt(portalEnergy, 1);

        adapter_ETH.mintPortalEnergyToken(alice, portalEnergy);
        (,,,, uint256 portalEnergyLeft) = adapter_ETH.accounts(alice);
        assertEq(portalEnergyLeft, 0);
        assertGt(portalEnergyToken_ETH.balanceOf(alice), 0);
        vm.stopPrank();
    }

    function testRevertsMintPortalEnergyToken_InvalidAmt() external {
        adapter_ETH.increaseAllowances();
        vm.startPrank(alice);
        PSM.approve(address(adapter_ETH), startAmount);
        adapter_ETH.buyPortalEnergy(alice, startAmount, 1, block.timestamp);

        vm.expectRevert(ErrorsLib.InvalidAmount.selector);
        adapter_ETH.mintPortalEnergyToken(alice, 0);
    }

    function testRevertsMintPortalEnergyToken_InvalidAddr() external {
        adapter_ETH.increaseAllowances();
        vm.startPrank(alice);
        PSM.approve(address(adapter_ETH), startAmount);
        adapter_ETH.buyPortalEnergy(alice, startAmount, 1, block.timestamp);

        vm.expectRevert(ErrorsLib.InvalidAddress.selector);
        adapter_ETH.mintPortalEnergyToken(address(0), 55555);
    }

    function testMintPortalEnergyToken_NotEnoughEnergy() external {
        adapter_ETH.increaseAllowances();
        vm.startPrank(alice);
        PSM.approve(address(adapter_ETH), startAmount);
        adapter_ETH.buyPortalEnergy(alice, startAmount, 1, block.timestamp);
        (,,,, uint256 portalEnergy) = adapter_ETH.accounts(alice);

        vm.expectRevert(ErrorsLib.InsufficientBalance.selector);
        adapter_ETH.mintPortalEnergyToken(alice, portalEnergy + 55555);
    }

    // burnPortalEnergyToken
    function testBurnPortalEnergyToken() external {
        adapter_ETH.increaseAllowances();
        vm.startPrank(alice);
        PSM.approve(address(adapter_ETH), startAmount);
        adapter_ETH.buyPortalEnergy(alice, startAmount, 1, block.timestamp);
        (,,,, uint256 portalEnergy) = adapter_ETH.accounts(alice);
        assertGt(portalEnergy, 1);

        adapter_ETH.mintPortalEnergyToken(alice, portalEnergy);
        (,,,, uint256 portalEnergyLeft) = adapter_ETH.accounts(alice);
        assertEq(portalEnergyLeft, 0);
        assertGt(portalEnergyToken_ETH.balanceOf(alice), 1);

        portalEnergyToken_ETH.approve(address(adapter_ETH), portalEnergyToken_ETH.balanceOf(alice));
        adapter_ETH.burnPortalEnergyToken(alice, portalEnergyToken_ETH.balanceOf(alice));
        (,,,, uint256 portalEnergyNew) = adapter_ETH.accounts(alice);
        assertGt(portalEnergyNew, 1);
        assertEq(portalEnergyToken_ETH.balanceOf(alice), 0);
        vm.stopPrank();
    }

    function testRevertsBurnPortalEnergyToken_InvalidAmt() external {
        adapter_ETH.increaseAllowances();
        vm.startPrank(alice);
        PSM.approve(address(adapter_ETH), startAmount);
        adapter_ETH.buyPortalEnergy(alice, startAmount, 1, block.timestamp);
        (,,,, uint256 portalEnergy) = adapter_ETH.accounts(alice);
        assertGt(portalEnergy, 1);

        adapter_ETH.mintPortalEnergyToken(alice, portalEnergy);
        (,,,, uint256 portalEnergyLeft) = adapter_ETH.accounts(alice);
        assertEq(portalEnergyLeft, 0);
        assertGt(portalEnergyToken_ETH.balanceOf(alice), 1);

        portalEnergyToken_ETH.approve(address(adapter_ETH), portalEnergyToken_ETH.balanceOf(alice));
        vm.expectRevert(ErrorsLib.InvalidAmount.selector);
        adapter_ETH.burnPortalEnergyToken(alice, 0);
    }

    function testFailBurnPortalEnergyToken_InvalidAddr() external {
        adapter_ETH.increaseAllowances();
        vm.startPrank(alice);
        PSM.approve(address(adapter_ETH), startAmount);
        adapter_ETH.buyPortalEnergy(alice, startAmount, 1, block.timestamp);
        (,,,, uint256 portalEnergy) = adapter_ETH.accounts(alice);
        assertGt(portalEnergy, 1);

        adapter_ETH.mintPortalEnergyToken(alice, portalEnergy);
        (,,,, uint256 portalEnergyLeft) = adapter_ETH.accounts(alice);
        assertEq(portalEnergyLeft, 0);
        assertGt(portalEnergyToken_ETH.balanceOf(alice), 1);

        portalEnergyToken_ETH.approve(address(adapter_ETH), portalEnergyToken_ETH.balanceOf(alice));
        vm.expectRevert("InvalidAddress");
        adapter_ETH.burnPortalEnergyToken(address(0), portalEnergyToken_ETH.balanceOf(alice));
    }

    function testFailBurnPortalEnergyToken_NotEnoughTokens() external {
        adapter_ETH.increaseAllowances();
        vm.startPrank(alice);
        PSM.approve(address(adapter_ETH), startAmount);
        adapter_ETH.buyPortalEnergy(alice, startAmount, 1, block.timestamp);
        (,,,, uint256 portalEnergy) = adapter_ETH.accounts(alice);
        assertGt(portalEnergy, 1);

        adapter_ETH.mintPortalEnergyToken(alice, portalEnergy);
        (,,,, uint256 portalEnergyLeft) = adapter_ETH.accounts(alice);
        assertEq(portalEnergyLeft, 0);
        assertGt(portalEnergyToken_ETH.balanceOf(alice), 1);

        portalEnergyToken_ETH.approve(address(adapter_ETH), portalEnergyToken_ETH.balanceOf(alice));
        vm.expectRevert("NotEnoughTokens");
        adapter_ETH.burnPortalEnergyToken(alice, portalEnergyToken_ETH.balanceOf(alice) + 55555);
    }
}
