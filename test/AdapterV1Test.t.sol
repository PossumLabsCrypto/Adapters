// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {Adapter} from "../src/AdapterV1.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IHlpPortal} from "./../src/interfaces/IHlpPortal.sol";
import {SwapDescription} from "./../src/interfaces/IOneInchV5AggregationRouter.sol";
import {Account} from "./../src/interfaces/IAdapter.sol";
import {EventsLib} from "./../src/libraries/EventsLib.sol";
import {ErrorsLib} from "./../src/libraries/ErrorsLib.sol";
import "./../src/libraries/ConstantsLib.sol";

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//                                                Done by mahdiRostami
//                              I have availability for smart contract security audits and testing.
// Reach out to me on [Twitter](https://twitter.com/0xmahdirostami) or [GitHub](https://github.com/0xmahdirostami/audits).
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

contract AdapterTest is Test {
    address constant WETH_TOKEN_ADDRESS = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address constant USDC_TOKEN_ADDRESS = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address constant USDCE_TOKEN_ADDRESS = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8; 
    address constant ARB_TOKEN_ADDRESS = 0x912CE59144191C1204E64559FE8253a0e49E6548;
     
    IERC20 constant _WETH_TOKEN = IERC20(WETH_TOKEN_ADDRESS);
    IERC20 constant _USDC_TOKEN = IERC20(USDC_TOKEN_ADDRESS);
    IERC20 constant _USDCE_TOKEN = IERC20(USDCE_TOKEN_ADDRESS);
    IERC20 constant _ARB_TOKEN = IERC20(ARB_TOKEN_ADDRESS);

    IHlpPortal constant _HLP_PORTAL = IHlpPortal(HLP_PORTAL_ADDRESS);
    IERC20 constant _PSM_TOKEN = IERC20(PSM_TOKEN_ADDRESS);
    IERC20 constant _ENERGY_TOKEN = IERC20(ENERGY_TOKEN_ADDRESS);
    IERC20 constant _HLP_TOKEN = IERC20(HLP_TOKEN_ADDRESS);
    address public adapterAddress;
    Adapter public adapter;

    // prank addresses
    address alice = address(uint160(uint256(keccak256('alice'))));
    address bob = address(uint160(uint256(keccak256('bob'))));

    function setUp() public {
        vm.createSelectFork({urlOrAlias: "arbitrum_infura_v4", blockNumber: 173305634});  
        adapter = new Adapter();
        adapterAddress = address(adapter);
        deal(PSM_TOKEN_ADDRESS, alice, 2e23);
        deal(HLP_TOKEN_ADDRESS, alice, 2e23);
        deal(PSM_TOKEN_ADDRESS, bob, 2e23);
        deal(HLP_TOKEN_ADDRESS, bob, 2e23);
    }

    /////////////////////////////////////////////////////////// helper
    function help_stake() internal {
        vm.startPrank(alice);
        _HLP_TOKEN.approve(adapterAddress, 1e18);
        adapter.stake(alice, 1e18);
        vm.stopPrank();
    }

    function getmaxLockDuration() internal view returns (uint256) {
        return _HLP_PORTAL.maxLockDuration();
    }

    // ---------------------------------------------------
    // ---------------staking and unstaking---------------
    // ---------------------------------------------------

    // reverts
    function testRevert_stake0Amount() external {
        vm.startPrank(alice);
        _HLP_TOKEN.approve(adapterAddress, 1e18);
        vm.expectRevert(ErrorsLib.InvalidInput.selector);
        adapter.stake(alice, 0);
        console2.log("address", address(this));
    }

    function testRevert_stake0Address() external {
        vm.startPrank(alice);
        _HLP_TOKEN.approve(adapterAddress, 1e18);
        vm.expectRevert(ErrorsLib.InvalidInput.selector);
        adapter.stake(address(0), 1e18);
    }

    function testRevert_unStakeExistingAccount() external {
        vm.expectRevert(ErrorsLib.AccountDoesNotExist.selector);
        adapter.unstake(1e18);
    }

    function testRevert_unStake0Amount() external {
        help_stake();
        vm.startPrank(alice);
        vm.expectRevert(ErrorsLib.InvalidInput.selector);
        adapter.unstake(0);
    }

    function testRevert_unStakeMoreThanStaked() external {
        help_stake();
        vm.startPrank(alice);
        vm.expectRevert(ErrorsLib.InsufficientToWithdraw.selector);
        adapter.unstake(2e18);
    }

    function testRevert_forceunStakeExistingAccount() external {
        vm.expectRevert(ErrorsLib.AccountDoesNotExist.selector);
        adapter.forceUnstakeAll();
    }

    function testRevert_forceunStakeInsufficent() external {
        help_stake();
        vm.startPrank(alice);
        adapter.mintPortalEnergyToken(bob, 10);
        vm.expectRevert(ErrorsLib.InsufficientPEtokens.selector);
        adapter.forceUnstakeAll();
    }

    function testRevert_forceunStakeTimeLock() external {
        help_stake();
        vm.startPrank(alice);
        adapter.mintPortalEnergyToken(alice, 10);
        vm.expectRevert(ErrorsLib.TradeTimelockActive.selector);
        adapter.forceUnstakeAll();
    }

    // events
    function testEvent_stake() external {
        uint256 maxLockDuration = getmaxLockDuration();
        vm.startPrank(alice);
        _HLP_TOKEN.approve(adapterAddress, 1e5);
        vm.expectEmit(adapterAddress);
        emit EventsLib.StakePositionUpdated(
            alice,
            alice,
            block.timestamp,
            maxLockDuration,
            1e5,
            1e5 * maxLockDuration / SECONDS_PER_YEAR,
            1e5 * maxLockDuration / SECONDS_PER_YEAR,
            1e5
        );
        adapter.stake(alice, 1e5);
    }

    function testEvent_stakeForOther() external {
        uint256 maxLockDuration = getmaxLockDuration();
        vm.startPrank(alice);
        _HLP_TOKEN.approve(adapterAddress, 1e5);
        vm.expectEmit(adapterAddress);
        emit EventsLib.StakePositionUpdated(
            alice,
            bob,
            block.timestamp,
            maxLockDuration,
            1e5,
            1e5 * maxLockDuration / SECONDS_PER_YEAR,
            1e5 * maxLockDuration / SECONDS_PER_YEAR,
            1e5
        );
        adapter.stake(bob, 1e5);
    }

    function testEvent_reStake() external {
        uint256 maxLockDuration = getmaxLockDuration();
        vm.startPrank(alice);
        _HLP_TOKEN.approve(adapterAddress, 2e5);
        adapter.stake(alice, 1e5);
        vm.expectEmit(adapterAddress);
        emit EventsLib.StakePositionUpdated(
            alice,
            alice,
            block.timestamp,
            maxLockDuration,
            1e5 * 2,
            1e5 * 2 * maxLockDuration / SECONDS_PER_YEAR,
            1e5 * 2 * maxLockDuration / SECONDS_PER_YEAR - 1, // 2 times division
            199995 // stake * portalenery / maxstakedebt
        );
        adapter.stake(alice, 1e5);
    }

    function testEvent_unStake() external {
        uint256 maxLockDuration = getmaxLockDuration();
        help_stake();
        vm.startPrank(alice);
        vm.expectEmit(adapterAddress);
        emit EventsLib.StakePositionUpdated(alice, alice, block.timestamp, maxLockDuration, 0, 0, 0, 0);
        adapter.unstake(1e18);
    }

    function testEvent_unStakePartially() external {
        uint256 maxLockDuration = getmaxLockDuration();
        help_stake();
        vm.startPrank(alice);
        vm.expectEmit(adapterAddress);
        emit EventsLib.StakePositionUpdated(
            alice,
            alice,
            block.timestamp,
            maxLockDuration,
            5e17,
            5e17 * maxLockDuration / SECONDS_PER_YEAR,
            5e17 * maxLockDuration / SECONDS_PER_YEAR,
            5e17
        );
        adapter.unstake(5e17);
    }

    function testEvent_forceunStake() external {
        uint256 maxLockDuration = getmaxLockDuration();
        help_stake();
        vm.startPrank(alice);
        vm.expectEmit(adapterAddress);
        emit EventsLib.StakePositionUpdated(alice, alice, block.timestamp, maxLockDuration, 0, 0, 0, 0);
        adapter.forceUnstakeAll();
    }

    function testEvent_forceunStakeWithExtraEnergy() external {
        uint256 maxLockDuration = getmaxLockDuration();
        help_stake();
        vm.warp(block.timestamp + 60);
        vm.startPrank(alice);
        vm.expectEmit(adapterAddress);
        emit EventsLib.StakePositionUpdated(
            alice,
            alice,
            block.timestamp,
            maxLockDuration,
            0,
            0, //
            1902587519025,
            // 1902587519025 = 60 * 1e18 / 31536000
            0
        );
        adapter.forceUnstakeAll();
    }

    // stake
    function test_stake() external {
        uint256 maxLockDuration = getmaxLockDuration();
        vm.startPrank(alice);
        _HLP_TOKEN.approve(adapterAddress, 1e5);
        uint256 balanceBeforeAlice = _HLP_TOKEN.balanceOf(alice);
        adapter.stake(alice, 1e5);
        (
            address user,
            uint256 lastUpdateTime,
            uint256 lastMaxLockDuration,
            uint256 stakedBalance,
            uint256 maxStakeDebt,
            uint256 portalEnergy,
            uint256 availableToWithdraw
        ) = adapter.getUpdateAccount(alice, 0);
        assertEq(user, alice);
        assertEq(lastUpdateTime, block.timestamp);
        assertEq(lastMaxLockDuration, maxLockDuration);
        assertEq(stakedBalance, 1e5);
        assertEq(maxStakeDebt, 1e5 * maxLockDuration * WAD / (SECONDS_PER_YEAR * DECIMALS_ADJUSTMENT));
        assertEq(portalEnergy, 1e5 * maxLockDuration * WAD / (SECONDS_PER_YEAR * DECIMALS_ADJUSTMENT));
        assertEq(availableToWithdraw, 1e5);

        // check portal
        (user, lastUpdateTime, lastMaxLockDuration, stakedBalance, maxStakeDebt, portalEnergy, availableToWithdraw) =
            _HLP_PORTAL.getUpdateAccount(adapterAddress, 0);
        assertEq(user, adapterAddress);
        assertEq(lastUpdateTime, block.timestamp);
        assertEq(lastMaxLockDuration, maxLockDuration);
        assertEq(stakedBalance, 1e5);
        assertEq(maxStakeDebt, 1e5 * maxLockDuration * WAD / (SECONDS_PER_YEAR * DECIMALS_ADJUSTMENT));
        assertEq(portalEnergy, 1e5 * maxLockDuration * WAD / (SECONDS_PER_YEAR * DECIMALS_ADJUSTMENT));
        assertEq(availableToWithdraw, 1e5);
        uint256 balanceAfterAlice = _HLP_TOKEN.balanceOf(alice);

        // check alice balance
        assertEq(balanceBeforeAlice - balanceAfterAlice, 1e5);
        assertEq(adapter.totalPrincipalStaked(), 1e5);
    }

    function test_reStake() external {
        uint256 maxLockDuration = getmaxLockDuration();
        vm.startPrank(alice);
        _HLP_TOKEN.approve(adapterAddress, 2e5);
        uint256 balanceBeforeAlice = _HLP_TOKEN.balanceOf(alice);
        adapter.stake(alice, 1e5);
        adapter.stake(alice, 1e5);
        (
            address user,
            uint256 lastUpdateTime,
            uint256 lastMaxLockDuration,
            uint256 stakedBalance,
            uint256 maxStakeDebt,
            uint256 portalEnergy,
            uint256 availableToWithdraw
        ) = adapter.getUpdateAccount(alice, 0);
        assertEq(user, alice);
        assertEq(lastUpdateTime, block.timestamp);
        assertEq(lastMaxLockDuration, maxLockDuration);
        assertEq(stakedBalance, 2 * 1e5);
        assertEq(maxStakeDebt, 2 * 1e5 * maxLockDuration / SECONDS_PER_YEAR);
        assertEq(portalEnergy, (2 * 1e5 * maxLockDuration / SECONDS_PER_YEAR) - 1); // beacuse of there are two division for portal energy
        assertEq(availableToWithdraw, 199995); // due to portalEnergy

        // check alice balance
        uint256 balanceAfterAlice = _HLP_TOKEN.balanceOf(alice);
        assertEq(balanceBeforeAlice - balanceAfterAlice, 2e5);
        assertEq(adapter.totalPrincipalStaked(), 2e5);
    }

    function test_unStake() external {
        uint256 maxLockDuration = getmaxLockDuration();
        vm.startPrank(alice);
        _HLP_TOKEN.approve(adapterAddress, 1e5);
        adapter.stake(alice, 1e5);
        adapter.unstake(1e5);
        (
            bool isExist,
            uint256 lastUpdateTime,
            uint256 lastMaxLockDuration,
            uint256 stakedBalance,
            uint256 maxStakeDebt,
            uint256 portalEnergy,
            uint256 availableToWithdraw
        ) = adapter.accounts(alice);
        assertEq(isExist, true);
        assertEq(lastUpdateTime, block.timestamp);
        assertEq(lastMaxLockDuration, maxLockDuration);
        assertEq(stakedBalance, 0);
        assertEq(maxStakeDebt, 0);
        assertEq(portalEnergy, 0);
        assertEq(availableToWithdraw, 0);
        assertEq(adapter.totalPrincipalStaked(), 0);
    }

    function test_unStakeReceiver() external {
        uint256 maxLockDuration = getmaxLockDuration();
        vm.startPrank(alice);
        _HLP_TOKEN.approve(adapterAddress, 1e5);
        adapter.stake(alice, 1e5);
        uint256 balanceBeforeAlice = _HLP_TOKEN.balanceOf(alice);
        adapter.unstake(1e5);
        (
            bool isExist,
            uint256 lastUpdateTime,
            uint256 lastMaxLockDuration,
            uint256 stakedBalance,
            uint256 maxStakeDebt,
            uint256 portalEnergy,
            uint256 availableToWithdraw
        ) = adapter.accounts(alice);
        assertEq(isExist, true);
        assertEq(lastUpdateTime, block.timestamp);
        assertEq(lastMaxLockDuration, maxLockDuration);
        assertEq(stakedBalance, 0);
        assertEq(maxStakeDebt, 0);
        assertEq(portalEnergy, 0);
        assertEq(availableToWithdraw, 0);

        // check bob balance
        uint256 balanceAfterAlice = _HLP_TOKEN.balanceOf(alice);
        assertEq(balanceAfterAlice - balanceBeforeAlice, 1e5);
    }

    function test_unStakeAvailableToWithdraw() external {
        uint256 maxLockDuration = getmaxLockDuration();
        help_stake();
        vm.startPrank(alice);
        adapter.mintPortalEnergyToken(alice, 2902587519025);
        vm.warp(block.timestamp + 60); // 1902587519025 = 60 * 1e18 / 31536000
        (
            address user,
            uint256 lastUpdateTime,
            uint256 lastMaxLockDuration,
            uint256 stakedBalance,
            uint256 maxStakeDebt,
            uint256 portalEnergy,
            uint256 availableToWithdraw
        ) = adapter.getUpdateAccount(alice, 0);
        uint256 _available = availableToWithdraw;
        uint256 balanceBeforeAlice = _HLP_TOKEN.balanceOf(alice);
        adapter.unstake(availableToWithdraw);
        (user, lastUpdateTime, lastMaxLockDuration, stakedBalance, maxStakeDebt, portalEnergy, availableToWithdraw) =
            adapter.getUpdateAccount(alice, 0);
        assertEq(stakedBalance, 1e18 - _available);
        assertEq(portalEnergy, 0);
        assertEq(stakedBalance * maxLockDuration / SECONDS_PER_YEAR, maxStakeDebt);
        assertEq(availableToWithdraw, 0);

        uint256 balanceAfterAlice = _HLP_TOKEN.balanceOf(alice);
        assertEq(balanceAfterAlice - balanceBeforeAlice, _available);
    }

    function test_forceunStake() external {
        uint256 maxLockDuration = getmaxLockDuration();
        vm.startPrank(alice);
        _HLP_TOKEN.approve(adapterAddress, 1e5);
        adapter.stake(alice, 1e5);
        adapter.forceUnstakeAll();
        (
            address user,
            uint256 lastUpdateTime,
            uint256 lastMaxLockDuration,
            uint256 stakedBalance,
            uint256 maxStakeDebt,
            uint256 portalEnergy,
            uint256 availableToWithdraw
        ) = adapter.getUpdateAccount(alice, 0);
        assertEq(user, alice);
        assertEq(lastUpdateTime, block.timestamp);
        assertEq(lastMaxLockDuration, maxLockDuration);
        assertEq(stakedBalance, 0);
        assertEq(maxStakeDebt, 0);
        assertEq(portalEnergy, 0);
        assertEq(availableToWithdraw, 0);
        assertEq(adapter.totalPrincipalStaked(), 0);
    }

    function test_forceunStakeWithMintToken() external {
        help_stake();
        vm.startPrank(alice);
        adapter.mintPortalEnergyToken(alice, 246575342465753424);
        vm.warp(block.timestamp + 60);
        _ENERGY_TOKEN.approve(adapterAddress, 246575342465753424 - 1902587519025); // 1902587519025 = 60 * 1e18 / 31536000
        adapter.forceUnstakeAll();
        (,,, uint256 stakedBalance, uint256 maxStakeDebt, uint256 portalEnergy, uint256 availableToWithdraw) =
            adapter.getUpdateAccount(alice, 0);
        assertEq(stakedBalance, 0);
        assertEq(maxStakeDebt, 0);
        assertEq(availableToWithdraw, 0);
        assertEq(portalEnergy, 0);
        assertEq(_ENERGY_TOKEN.balanceOf(alice), 1902587519025);
    }

    // ---------------------------------------------------
    // ---------------PortalEnergyToken-------------------
    // ---------------------------------------------------

    // reverts
    function testRevert_mintPortalEnergyToken0Amount() external {
        help_stake();
        vm.startPrank(alice);
        vm.expectRevert(ErrorsLib.InvalidInput.selector);
        adapter.mintPortalEnergyToken(alice, 0);
    }

    function testRevert_mintPortalEnergyTokenFor0Address() external {
        help_stake();
        vm.startPrank(alice);
        vm.expectRevert(ErrorsLib.InvalidInput.selector);
        adapter.mintPortalEnergyToken(address(0), 1);
    }

    function testRevert_mintPortalEnergyTokenAccountDoesNotExist() external {
        vm.expectRevert(ErrorsLib.AccountDoesNotExist.selector);
        adapter.mintPortalEnergyToken(alice, 1);
    }

    function testRevert_mintPortalEnergyTokenInsufficientBalance() external {
        help_stake();
        vm.startPrank(alice);
        vm.expectRevert(ErrorsLib.InsufficientBalance.selector);
        adapter.mintPortalEnergyToken(alice, 1e18);
    }

    function testRevert_mintPortalEnergyTokenTimeLock() external {
        help_stake();
        vm.startPrank(alice);
        adapter.mintPortalEnergyToken(alice, 10);
        vm.expectRevert(ErrorsLib.TradeTimelockActive.selector);
        adapter.mintPortalEnergyToken(alice, 10);
    }

    function testRevert_burnPrtalEnergyToken0Amount() external {
        help_stake();
        vm.startPrank(alice);
        vm.expectRevert(ErrorsLib.InvalidInput.selector);
        adapter.burnPortalEnergyToken(alice, 0);
    }

    function testRevert_burnPortalEnergyTokenForAccountDoesNotExist() external {
        help_stake();
        vm.startPrank(alice);
        vm.expectRevert(ErrorsLib.AccountDoesNotExist.selector);
        adapter.burnPortalEnergyToken(bob, 1);
    }

    function testRevert_burnPortalEnergyTokenInsufficientBalance() external {
        help_stake();
        vm.startPrank(alice);
        adapter.mintPortalEnergyToken(alice, 100);
        vm.warp(block.timestamp + 60);
        vm.expectRevert(ErrorsLib.InsufficientBalance.selector);
        adapter.burnPortalEnergyToken(alice, 101);
    }

    function testRevert_mintBurnPortalEnergyTokenTimeLock() external {
        help_stake();
        vm.startPrank(alice);
        adapter.mintPortalEnergyToken(alice, 10);
        vm.expectRevert(ErrorsLib.TradeTimelockActive.selector);
        adapter.burnPortalEnergyToken(alice, 10);
    }

    // events
    function testEvent_mintPortalEnergyToken() external {
        help_stake();
        vm.startPrank(alice);
        vm.expectEmit(adapterAddress);
        emit EventsLib.PortalEnergyMinted(alice, bob, 246575342465753424); //1e18*maxlock/year = 246,575,342,465,753,424
        adapter.mintPortalEnergyToken(bob, 246575342465753424);
    }

    function testEvent_burnPortalEnergyToken() external {
        help_stake();
        vm.startPrank(alice);
        adapter.mintPortalEnergyToken(alice, 246575342465753424);
        vm.warp(block.timestamp + 60);
        _ENERGY_TOKEN.approve(adapterAddress, 246575342465753424);
        vm.expectEmit(adapterAddress);
        emit EventsLib.PortalEnergyBurned(alice, alice, 246575342465753424);
        adapter.burnPortalEnergyToken(alice, 246575342465753424);
    }

    // mintPortalEnergyToken
    function test_mintPortalEnergyToken() external {
        help_stake();
        vm.startPrank(alice);
        adapter.mintPortalEnergyToken(bob, 246575342465753424);
        assertEq(_ENERGY_TOKEN.balanceOf(bob), 246575342465753424);
        (,,,,, uint256 portalEnergy,) = adapter.getUpdateAccount(alice, 0);
        assertEq(portalEnergy, 0);
    }

    // burnPortalEnergyToken
    function test_burnPortalEnergyToken() external {
        help_stake();
        vm.startPrank(alice);
        adapter.mintPortalEnergyToken(bob, 246575342465753424);
        vm.startPrank(bob);
        vm.warp(block.timestamp + 60);
        _ENERGY_TOKEN.approve(adapterAddress, 246575342465753424);
        adapter.burnPortalEnergyToken(alice, 246575342465753424);
        assertEq(_ENERGY_TOKEN.balanceOf(bob), 0);
        (,,,,, uint256 portalEnergy,) = adapter.getUpdateAccount(alice, 0);
        assertEq(portalEnergy, 246575342465753424 + 1902587519025); // 1902587519025 = 60 * 1e18 / 31536000
    }

    // ---------------------------------------------------
    // ---------------buy and sell energy token-----------
    // ---------------------------------------------------

    // revert
    function testRevert_buyPortalEnergynotexitAccount() external {
        vm.expectRevert(ErrorsLib.AccountDoesNotExist.selector);
        adapter.buyPortalEnergy(alice, 0, 0, 0);
    }

    function testRevert_buyPortalEnergy0Amount() external {
        help_stake();
        vm.expectRevert(ErrorsLib.InvalidInput.selector);
        adapter.buyPortalEnergy(alice, 0, 0, 0);
    }

    function testRevert_buyPortalEnergy0MinReceived() external {
        help_stake();
        vm.expectRevert(ErrorsLib.InvalidInput.selector);
        adapter.buyPortalEnergy(alice, 1, 0, 0);
    }

    function testRevert_buyPortalEnergyAfterDeadline() external {
        help_stake();
        vm.expectRevert(ErrorsLib.DeadlineExpired.selector);
        adapter.buyPortalEnergy(alice, 1, 1, block.timestamp - 1);
    }

    function testRevert_buyPortalEnergyTradeTimelockActive() external {
        help_stake();
        vm.startPrank(alice);
        _PSM_TOKEN.approve(adapterAddress, 2e10);
        adapter.buyPortalEnergy(alice, 1e10, 1, block.timestamp);
        vm.expectRevert(ErrorsLib.TradeTimelockActive.selector);
        adapter.buyPortalEnergy(alice, 1e10, 1, block.timestamp);
    }

    function testRevert_buyPortalEnergyAmountReceived() external {
        help_stake();
        vm.startPrank(alice);
        _PSM_TOKEN.approve(adapterAddress, 2e10);
        vm.expectRevert(ErrorsLib.InvalidOutput.selector);
        adapter.buyPortalEnergy(alice, 1e10, 1e18, block.timestamp);
    }

    function testRevert_sellPortalEnergynotexitaccount() external {
        vm.expectRevert(ErrorsLib.AccountDoesNotExist.selector);
        adapter.sellPortalEnergy(payable(alice), 0, 0, 0, true, "");
    }

    function testRevert_sellPortalEnergy0Amount() external {
        help_stake();
        vm.startPrank(alice);
        vm.expectRevert(ErrorsLib.InvalidInput.selector);
        adapter.sellPortalEnergy(payable(alice), 0, 0, 0, true, "");
    }

    function testRevert_sellPortalEnergy0MinReceived() external {
        help_stake();
        vm.startPrank(alice);
        vm.expectRevert(ErrorsLib.InvalidInput.selector);
        adapter.sellPortalEnergy(payable(alice), 1, 0, 0, true, "");
    }

    function testRevert_sellPortalEnergyAfterDeadline() external {
        help_stake();
        vm.startPrank(alice);
        vm.expectRevert(ErrorsLib.DeadlineExpired.selector);
        adapter.sellPortalEnergy(payable(alice), 1, 1, block.timestamp - 1, true, "");
    }

    function testRevert_sellPortalEnergyTradeTimelockActive() external {
        help_stake();
        vm.startPrank(alice);
        adapter.sellPortalEnergy(payable(alice), 1, 1, block.timestamp, true, "");
        vm.expectRevert(ErrorsLib.TradeTimelockActive.selector);
        adapter.sellPortalEnergy(payable(alice), 1, 1, block.timestamp, true, "");
    }

    function testRevert_sellPortalEnergyInsufficientBalance() external {
        help_stake();
        vm.startPrank(alice);
        vm.expectRevert(ErrorsLib.InsufficientBalance.selector);
        adapter.sellPortalEnergy(payable(alice), 10e18, 1e18, block.timestamp, true, "");
    }

    function testRevert_sellPortalEnergyAmountReceived() external {
        help_stake();
        vm.startPrank(alice);
        vm.expectRevert(ErrorsLib.InvalidOutput.selector);
        adapter.sellPortalEnergy(payable(alice), 10, 10e18, block.timestamp, true, "");
    }

    // event
    function testEvent_buyPortalEnergy() external {
        help_stake();
        uint256 expect = _HLP_PORTAL.quoteBuyPortalEnergy(1e15);
        vm.startPrank(alice);
        _PSM_TOKEN.approve(adapterAddress, 1e15);
        vm.expectEmit(adapterAddress);
        emit EventsLib.PortalEnergyBuyExecuted(alice, alice, expect);
        adapter.buyPortalEnergy(alice, 1e15, 1e5, block.timestamp);
    }

    function testEvent_sellPortalEnergy() external {
        help_stake();
        uint256 expect = _HLP_PORTAL.quoteSellPortalEnergy(1e15);
        vm.startPrank(alice);
        vm.expectEmit(adapterAddress);
        emit EventsLib.PortalEnergySellExecuted(alice, alice, expect);
        adapter.sellPortalEnergy(payable(alice), 1e15, 1e5, block.timestamp, true, "");
    }

    function test_buyPortalEnergy() external {
        uint256 maxLockDuration = getmaxLockDuration();

        help_stake();
        uint256 expect = _HLP_PORTAL.quoteBuyPortalEnergy(2e18);
        (,,, uint256 stakedBalance, uint256 maxStakeDebt, uint256 portalEnergy, uint256 availableToWithdraw) =
            adapter.accounts(alice);
        uint256 portalEnergyBefore = portalEnergy;
        uint256 balancePSMAliceBefore = _PSM_TOKEN.balanceOf(alice);
        uint256 balancePSMPortalBefore = _PSM_TOKEN.balanceOf(HLP_PORTAL_ADDRESS);
        vm.startPrank(alice);
        _PSM_TOKEN.approve(adapterAddress, 2e18);
        adapter.buyPortalEnergy(alice, 2e18, 1, block.timestamp);
        (,,, stakedBalance, maxStakeDebt, portalEnergy, availableToWithdraw) = adapter.accounts(alice);
        uint256 balancePSMAliceAfter = _PSM_TOKEN.balanceOf(alice);
        uint256 balancePSMPortalAfter = _PSM_TOKEN.balanceOf(HLP_PORTAL_ADDRESS);

        assertEq(stakedBalance, 1e18);
        assertEq(maxStakeDebt, (1e18 * maxLockDuration * WAD) / (SECONDS_PER_YEAR * DECIMALS_ADJUSTMENT));
        assertEq(availableToWithdraw, 1e18);
        assertEq(portalEnergy - portalEnergyBefore, expect);
        assertEq(balancePSMAliceBefore - balancePSMAliceAfter, 2e18);
        assertEq(balancePSMPortalAfter - balancePSMPortalBefore, 2e18);
    }

    function test_sellPortalEnergy() external {
        uint256 maxLockDuration = getmaxLockDuration();

        help_stake();
        uint256 expect = _HLP_PORTAL.quoteSellPortalEnergy(1e10);
        (,,,, uint256 maxStakeDebt, uint256 portalEnergy, uint256 availableToWithdraw) = adapter.accounts(alice);
        uint256 portalEnergyBefore = portalEnergy;
        uint256 balancePSMBobBefore = _PSM_TOKEN.balanceOf(bob);
        uint256 balancePSMPortalBefore = _PSM_TOKEN.balanceOf(HLP_PORTAL_ADDRESS);
        vm.startPrank(alice);
        uint256 expectPSM = adapter.sellPortalEnergy(payable(bob), 1e10, expect, block.timestamp, true, "");
        (,,,, maxStakeDebt, portalEnergy, availableToWithdraw) = adapter.accounts(alice);
        uint256 balancePSMBobAfter = _PSM_TOKEN.balanceOf(bob);
        uint256 balancePSMPortalAfter = _PSM_TOKEN.balanceOf(HLP_PORTAL_ADDRESS);

        assertEq(maxStakeDebt, (1e18 * maxLockDuration * WAD) / (SECONDS_PER_YEAR * DECIMALS_ADJUSTMENT));
        assertEq(portalEnergyBefore - portalEnergy, 1e10);
        assertEq(balancePSMBobAfter - balancePSMBobBefore, expect);
        assertEq(balancePSMBobAfter - balancePSMBobBefore, expectPSM);
        assertEq(balancePSMPortalBefore - balancePSMPortalAfter, expect);
    }

    //////////////////////////////////////////////////////////////////////////////////////////////// OneInch
    // _actionData = executer + srcToken + dstToken + srcReceiver + dstReceiver + amount + minReturnAmount + flags + permit + _data
    // executer
    // srcReceiver
    // dstReceiver = bob
    // amount = expectPSM = 11183540650115058084565553
    // minReturnAmount(based on slippage) = 5 percent
    // flags
    // _data

    // for 1inch api -> srcToken, dstToken, amount, from(adapter(0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f)), slippage, receiver(bob(0x3440326f551B8A7ee198cEE35cb5D517f2d296a2)), disableEstimate=True
    function test_oneInch() external {
        deal(USDCE_TOKEN_ADDRESS, alice, 100000000000000000000);
        vm.startPrank(alice);
        _USDCE_TOKEN.transfer(adapterAddress, 100000000000000000000);
        console2.log("adapter", adapterAddress);
        console2.log("bob", bob);

        // IF test revert, generate new actionData (for this test srtToken is UDCE dstToken is WETH)
        bytes memory actionData = hex"000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd09000000000000000000000000ff970a61a04b1ca14834a43f5de4533ebddb5cc800000000000000000000000082af49447d8a07e3bd95bd0d56f35241523fbab1000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000003440326f551b8a7ee198cee35cb5d517f2d296a20000000000000000000000000000000000000000000000056bc75e2d631000000000000000000000000000000000000000000000000000f9599e8c2c86f3a45e00000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000140000000000000000000000000000000000000000000000000000000000000016000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002c66000000000000000000000000002c48002c1a002c00002bd2002b88002b6e00a0c9e75c4800000000000000000604000000000000000000000000000000000000000000000000002b4000181700a007e5c0d20000000000000000000000000000000000000000000017f30012b300129900a0c9e75c480000000000000000290900000000000000000000000000000000000000000000000000126b000ace00a0c9e75c4800010101010101010101000000000aa00008f20007a20005f40005790004290003ae0002fe0001505106f26515d5482e2c2fd237149bf6a653da4794b3d0ff970a61a04b1ca14834a43f5de4533ebddb5cc80004f41766d80000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007939f62d00000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000000000000000000000000000000000000065b771230000000000000000000000000000000000000000000000000000000000000001000000000000000000000000ff970a61a04b1ca14834a43f5de4533ebddb5cc8000000000000000000000000fd086bc7cd5c481dcc9c85ebe478a1c0b69fcbb9000000000000000000000000000000000000000000000000000000000000000100a007e5c0d200000000000000000000000000000000000000000000000000018a0000d0512074c764d41b77dbbb4fe771dab1939b00b146894aff970a61a04b1ca14834a43f5de4533ebddb5cc8006402b9446c000000000000000000000000ff970a61a04b1ca14834a43f5de4533ebddb5cc8000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd09000000000000000000000000f4f0a3aaab0b348c075c0a35cf835c8a311914e4000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004020f4f0a3aaab0b348c075c0a35cf835c8a311914e4627dd56a00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000060000000000000000000000000ff970a61a04b1ca14834a43f5de4533ebddb5cc8000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd0900000000000000000000000000000000000000000000000000000000000000015100e97af01c48c0a332c06a92df36b77b2a680ab54bff970a61a04b1ca14834a43f5de4533ebddb5cc800445b41b9080000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002e5c90cdad0c20ff970a61a04b1ca14834a43f5de4533ebddb5cc8106ae154e4c24b6e11e70cfee7e075b14a1822446ae4071118002dc6c0106ae154e4c24b6e11e70cfee7e075b14a1822440000000000000000000000000000000000000000000000000000000028e3a499ff970a61a04b1ca14834a43f5de4533ebddb5cc85106e708aa9e887980750c040a6a2cb901c37aa34f3bff970a61a04b1ca14834a43f5de4533ebddb5cc80004f41766d8000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000bb6e8a1c00000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000000000000000000000000000000000000065b771230000000000000000000000000000000000000000000000000000000000000001000000000000000000000000ff970a61a04b1ca14834a43f5de4533ebddb5cc8000000000000000000000000fd086bc7cd5c481dcc9c85ebe478a1c0b69fcbb900000000000000000000000000000000000000000000000000000000000000010c20ff970a61a04b1ca14834a43f5de4533ebddb5cc8d082d6e0af69f74f283b90c3cda9c35615bce3676ae4071118002625a0d082d6e0af69f74f283b90c3cda9c35615bce36700000000000000000000000000000000000000000000000000000000009a3846ff970a61a04b1ca14834a43f5de4533ebddb5cc800a007e5c0d200000000000000000000000000000000000000000000000000018a0000d0512074c764d41b77dbbb4fe771dab1939b00b146894aff970a61a04b1ca14834a43f5de4533ebddb5cc8006402b9446c000000000000000000000000ff970a61a04b1ca14834a43f5de4533ebddb5cc8000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd0900000000000000000000000079bf7147ebcd0d55e83cb42ed3ba1bb2bb23ef2000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000402079bf7147ebcd0d55e83cb42ed3ba1bb2bb23ef20627dd56a00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000060000000000000000000000000ff970a61a04b1ca14834a43f5de4533ebddb5cc8000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd0900000000000000000000000000000000000000000000000000000000000000015106f26515d5482e2c2fd237149bf6a653da4794b3d0ff970a61a04b1ca14834a43f5de4533ebddb5cc80004f41766d8000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008c331300000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000000000000000000000000000000000000065b771230000000000000000000000000000000000000000000000000000000000000001000000000000000000000000ff970a61a04b1ca14834a43f5de4533ebddb5cc8000000000000000000000000fd086bc7cd5c481dcc9c85ebe478a1c0b69fcbb9000000000000000000000000000000000000000000000000000000000000000000a007e5c0d200000000000000000000000000000000000000000000000000018a0000d0512074c764d41b77dbbb4fe771dab1939b00b146894aff970a61a04b1ca14834a43f5de4533ebddb5cc8006402b9446c000000000000000000000000ff970a61a04b1ca14834a43f5de4533ebddb5cc8000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd09000000000000000000000000a59032a50ffc05ac4af40a15113a00a44e21b4bb000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004020a59032a50ffc05ac4af40a15113a00a44e21b4bb627dd56a00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000060000000000000000000000000ff970a61a04b1ca14834a43f5de4533ebddb5cc8000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd09000000000000000000000000000000000000000000000000000000000000000100a0c9e75c4800130a0502010101010100000000076f0006f40006790005fe00054e00047e0002d00001800000b05100a43e0c9e8755d4c8b42e837d74e2888b8184ea93ff970a61a04b1ca14834a43f5de4533ebddb5cc800441943c9cd000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000151000db3fe3b770c95a0b99d1ed6f2627933466c0dd8ff970a61a04b1ca14834a43f5de4533ebddb5cc800449169558600000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000024d61ba6360000000000000000000000000000000000000000000000000000000065b771235106aaa87963efeb6f7e0a2711f397663105acb1805eff970a61a04b1ca14834a43f5de4533ebddb5cc80004f41766d80000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002835f8e900000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000000000000000000000000000000000000065b771230000000000000000000000000000000000000000000000000000000000000001000000000000000000000000ff970a61a04b1ca14834a43f5de4533ebddb5cc8000000000000000000000000fd086bc7cd5c481dcc9c85ebe478a1c0b69fcbb9000000000000000000000000000000000000000000000000000000000000000100a007e5c0d200000000000000000000000000000000000000000000000000018a0000d0512074c764d41b77dbbb4fe771dab1939b00b146894aff970a61a04b1ca14834a43f5de4533ebddb5cc8006402b9446c000000000000000000000000ff970a61a04b1ca14834a43f5de4533ebddb5cc8000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd09000000000000000000000000cb4ef1f6b028358f89430e828219d3d5538c115c000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004020cb4ef1f6b028358f89430e828219d3d5538c115c627dd56a00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000060000000000000000000000000ff970a61a04b1ca14834a43f5de4533ebddb5cc8000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd0900000000000000000000000000000000000000000000000000000000000000015100969f7699fbb9c79d8b61315630cdeed95977cfb8ff970a61a04b1ca14834a43f5de4533ebddb5cc800449169558600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000346c938e0000000000000000000000000000000000000000000000000000000065b7712351007f90122bf0700f9e7e1f688fe926940e8839f353ff970a61a04b1ca14834a43f5de4533ebddb5cc800443df021240000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000125f7e03ab2d0c20ff970a61a04b1ca14834a43f5de4533ebddb5cc817f74f88d2283c7c6ddb0f7cc6cf581e134812a56ae4071118002dc6c017f74f88d2283c7c6ddb0f7cc6cf581e134812a5000000000000000000000000000000000000000000000000000000006831cc46ff970a61a04b1ca14834a43f5de4533ebddb5cc80c20ff970a61a04b1ca14834a43f5de4533ebddb5cc88165c70b01b7807351ef0c5ffd3ef010cabc16fb6ae4071118002dc6c08165c70b01b7807351ef0c5ffd3ef010cabc16fb00000000000000000000000000000000000000000000000000000000e213918eff970a61a04b1ca14834a43f5de4533ebddb5cc80c20ff970a61a04b1ca14834a43f5de4533ebddb5cc8ed4de839da369ee4c7077b0358e21d9100506d716ae4071118002625a0ed4de839da369ee4c7077b0358e21d9100506d7100000000000000000000000000000000000000000000000000000001b472ae38ff970a61a04b1ca14834a43f5de4533ebddb5cc80020d6bdbf78fd086bc7cd5c481dcc9c85ebe478a1c0b69fcbb900a0c9e75c48000016100502020101010000000000000005120004970004480003780003290002390001cb0001505106e708aa9e887980750c040a6a2cb901c37aa34f3bfd086bc7cd5c481dcc9c85ebe478a1c0b69fcbb90004f41766d800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000390dfe9616475e900000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000000000000000000000000000000000000065b771230000000000000000000000000000000000000000000000000000000000000001000000000000000000000000fd086bc7cd5c481dcc9c85ebe478a1c0b69fcbb900000000000000000000000082af49447d8a07e3bd95bd0d56f35241523fbab100000000000000000000000000000000000000000000000000000000000000000c20fd086bc7cd5c481dcc9c85ebe478a1c0b69fcbb9a2d807f22a35e3c05a1ae096c719bf9eaf5e71e66ae4071118002dc6c0a2d807f22a35e3c05a1ae096c719bf9eaf5e71e6000000000000000000000000000000000000000000000000099132a1897a79dafd086bc7cd5c481dcc9c85ebe478a1c0b69fcbb94801d387c40a72703b38a5181573724bcaf2ce6038a5fd086bc7cd5c481dcc9c85ebe478a1c0b69fcbb953c059a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd0951009aed3a8896a85fe9a8cac52c9b402d092b629a30fd086bc7cd5c481dcc9c85ebe478a1c0b69fcbb900447dc20382000000000000000000000000fd086bc7cd5c481dcc9c85ebe478a1c0b69fcbb900000000000000000000000082af49447d8a07e3bd95bd0d56f35241523fbab10000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000013e244df62b3e8972f000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd0900000000000000000000000042f527f50f16a103b6ccab48bccca214500c102102a0000000000000000000000000000000000000000000000004f84cc22156b18f71ee63c1e500c82819f72a9e77e2c0c3a69b3196478f44303cf4fd086bc7cd5c481dcc9c85ebe478a1c0b69fcbb95100960ea3e3c7fb317332d990873d354e18d7645590fd086bc7cd5c481dcc9c85ebe478a1c0b69fcbb90044394747c500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a185a3921a4838eac000000000000000000000000000000000000000000000000000000000000000002a0000000000000000000000000000000000000000000000086a4d523a9d8ba15bbee63c1e500641c00a822e8b671738d32a431a4fb6074e5c79dfd086bc7cd5c481dcc9c85ebe478a1c0b69fcbb90c20fd086bc7cd5c481dcc9c85ebe478a1c0b69fcbb9cb0e5bfa72bbb4d16ab5aa0c60601c438f04b4ad6ae4071118002dc6c0cb0e5bfa72bbb4d16ab5aa0c60601c438f04b4ad0000000000000000000000000000000000000000000000070e6bce46e021383ffd086bc7cd5c481dcc9c85ebe478a1c0b69fcbb900a0c9e75c4800000000000000002b070000000000000000000000000000000000000000000000000012fb0008ce00a0c9e75c48000000010101010101010000000000000000000008a00007500005a20003f40003790002fe0001505106f26515d5482e2c2fd237149bf6a653da4794b3d0ff970a61a04b1ca14834a43f5de4533ebddb5cc80004f41766d800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003ffe2bef737c051600000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000000000000000000000000000000000000065b771230000000000000000000000000000000000000000000000000000000000000001000000000000000000000000ff970a61a04b1ca14834a43f5de4533ebddb5cc800000000000000000000000082af49447d8a07e3bd95bd0d56f35241523fbab1000000000000000000000000000000000000000000000000000000000000000000a007e5c0d200000000000000000000000000000000000000000000000000018a0000d0512074c764d41b77dbbb4fe771dab1939b00b146894aff970a61a04b1ca14834a43f5de4533ebddb5cc8006402b9446c000000000000000000000000ff970a61a04b1ca14834a43f5de4533ebddb5cc8000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd09000000000000000000000000d4f4ffe0915c3eed7420a1b30550815b7a5d3d4a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004020d4f4ffe0915c3eed7420a1b30550815b7a5d3d4a627dd56a00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000060000000000000000000000000ff970a61a04b1ca14834a43f5de4533ebddb5cc8000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd0900000000000000000000000000000000000000000000000000000000000000010c20ff970a61a04b1ca14834a43f5de4533ebddb5cc8403b1405d8caffc1cc5032cc82aa135d2481d0cf6ae4071118002625a0403b1405d8caffc1cc5032cc82aa135d2481d0cf0000000000000000000000000000000000000000000000002e3d470c3e59cdb8ff970a61a04b1ca14834a43f5de4533ebddb5cc80c20ff970a61a04b1ca14834a43f5de4533ebddb5cc88b8149dd385955dc1ce77a4be7700ccd6a212e656ae4071118002625a08b8149dd385955dc1ce77a4be7700ccd6a212e6500000000000000000000000000000000000000000000000038c133efc1ab37a6ff970a61a04b1ca14834a43f5de4533ebddb5cc800a007e5c0d200000000000000000000000000000000000000000000000000018a0000d0512074c764d41b77dbbb4fe771dab1939b00b146894aff970a61a04b1ca14834a43f5de4533ebddb5cc8006402b9446c000000000000000000000000ff970a61a04b1ca14834a43f5de4533ebddb5cc8000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd09000000000000000000000000b75c77ff1dde7394ae743a21d19fba4e9367e0e7000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004020b75c77ff1dde7394ae743a21d19fba4e9367e0e7627dd56a00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000060000000000000000000000000ff970a61a04b1ca14834a43f5de4533ebddb5cc8000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd09000000000000000000000000000000000000000000000000000000000000000100a007e5c0d200000000000000000000000000000000000000000000000000018a0000d0512074c764d41b77dbbb4fe771dab1939b00b146894aff970a61a04b1ca14834a43f5de4533ebddb5cc8006402b9446c000000000000000000000000ff970a61a04b1ca14834a43f5de4533ebddb5cc8000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd09000000000000000000000000ecbe4776dc830cfc2a14109329747feaf3e57c8f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004020ecbe4776dc830cfc2a14109329747feaf3e57c8f627dd56a00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000060000000000000000000000000ff970a61a04b1ca14834a43f5de4533ebddb5cc8000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd0900000000000000000000000000000000000000000000000000000000000000015106e708aa9e887980750c040a6a2cb901c37aa34f3bff970a61a04b1ca14834a43f5de4533ebddb5cc80004f41766d800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002add9e3ca660465e00000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000000000000000000000000000000000000065b771230000000000000000000000000000000000000000000000000000000000000001000000000000000000000000ff970a61a04b1ca14834a43f5de4533ebddb5cc800000000000000000000000082af49447d8a07e3bd95bd0d56f35241523fbab1000000000000000000000000000000000000000000000000000000000000000000a0c9e75c480000130b0504010101010000000000000009ff0009840005f40004a40004290002d900012b00007b0c20ff970a61a04b1ca14834a43f5de4533ebddb5cc88bc2cd9dab840231a0dab5b747b8a6085c4ea4596ae4071118002dc6c08bc2cd9dab840231a0dab5b747b8a6085c4ea45900000000000000000000000000000000000000000000000005b251f0daf3cb1cff970a61a04b1ca14834a43f5de4533ebddb5cc85100a43e0c9e8755d4c8b42e837d74e2888b8184ea93ff970a61a04b1ca14834a43f5de4533ebddb5cc800441943c9cd000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100a007e5c0d200000000000000000000000000000000000000000000000000018a0000d0512074c764d41b77dbbb4fe771dab1939b00b146894aff970a61a04b1ca14834a43f5de4533ebddb5cc8006402b9446c000000000000000000000000ff970a61a04b1ca14834a43f5de4533ebddb5cc8000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000002a79320c1a917722394774166ef85b33cdc977580000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000040202a79320c1a917722394774166ef85b33cdc97758627dd56a00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000060000000000000000000000000ff970a61a04b1ca14834a43f5de4533ebddb5cc8000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd0900000000000000000000000000000000000000000000000000000000000000015106aaa87963efeb6f7e0a2711f397663105acb1805eff970a61a04b1ca14834a43f5de4533ebddb5cc80004f41766d800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000d5e2ba0da37554700000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000000000000000000000000000000000000065b771230000000000000000000000000000000000000000000000000000000000000001000000000000000000000000ff970a61a04b1ca14834a43f5de4533ebddb5cc800000000000000000000000082af49447d8a07e3bd95bd0d56f35241523fbab100000000000000000000000000000000000000000000000000000000000000000c20ff970a61a04b1ca14834a43f5de4533ebddb5cc86e8aee8ed658fdcbbb7447743fdd98152b3453a06ae4071118002dc6c06e8aee8ed658fdcbbb7447743fdd98152b3453a00000000000000000000000000000000000000000000000099648ad6021f54fb9ff970a61a04b1ca14834a43f5de4533ebddb5cc85100c873fecbd354f5a56e00e710b90ef4201db2448dff970a61a04b1ca14834a43f5de4533ebddb5cc80004ac3893ba000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000b7582c81156c1bbb500000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd0900000000000000000000000042f527f50f16a103b6ccab48bccca214500c10210000000000000000000000000000000000000000000000000000000065b771230000000000000000000000000000000000000000000000000000000000000002000000000000000000000000ff970a61a04b1ca14834a43f5de4533ebddb5cc800000000000000000000000082af49447d8a07e3bd95bd0d56f35241523fbab151001111111254eeb25477b68fb85ed929f73a960582ff970a61a04b1ca14834a43f5de4533ebddb5cc8008462e238bb00000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000002e000000000000000000000000000000000000000000000000000000000000003400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000e3413a27030f8f00000000000000000000000000000000000000000000000000000031213e3e8a00000000000000000000000082af49447d8a07e3bd95bd0d56f35241523fbab1000000000000000000000000ff970a61a04b1ca14834a43f5de4533ebddb5cc8000000000000000000000000f4fc41900cd05159ac66801b78929226fafc0a2c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000f1902ec8dba000000000000000000000000000000000000000000000000000b8fc0d5f29deb160000000a4000000a4000000a4000000a400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000014000000000000000000000000000000000000000000000000000000000000000a4bf15fcd8000000000000000000000000d7936052d1e096d48c81ef3918f9fd6384108480000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000242cc2878d00757cddd400000000000000f4fc41900cd05159ac66801b78929226fafc0a2c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004042ae6d574bb20f275fd0baac5a7f1ee41d3b515d70a2179982afe14a96cb05b52f0bf479a4313bb7e502eb421614d8fc23a683997d9b06b823d260894173585e00000000000000000000000000000000000000000000000000000000000000000c20ff970a61a04b1ca14834a43f5de4533ebddb5cc8905dfcd5649217c42684f23958568e533c711aa36ae4071118002dc6c0905dfcd5649217c42684f23958568e533c711aa300000000000000000000000000000000000000000000002990ea7c9c6d88f9c1ff970a61a04b1ca14834a43f5de4533ebddb5cc80020d6bdbf7882af49447d8a07e3bd95bd0d56f35241523fbab100a0f2fa6b6682af49447d8a07e3bd95bd0d56f35241523fbab10000000000000000000000000000000000000000000001067948938d2fbd18cf00000000000000000007ef38320f571280a06c4eca2782af49447d8a07e3bd95bd0d56f35241523fbab11111111254eeb25477b68fb85ed929f73a9605820020d6bdbf78ff970a61a04b1ca14834a43f5de4533ebddb5cc880a06c4eca27ff970a61a04b1ca14834a43f5de4533ebddb5cc83440326f551b8a7ee198cee35cb5d517f2d296a200000000000000000000000000000000000000000000000000008b1ccac8";
        
        uint256 expectToken = adapter.swapOneInch(actionData);

        assertEq(_USDCE_TOKEN.balanceOf(adapterAddress), 0);
        assertEq(_WETH_TOKEN.balanceOf(adapterAddress), 0);
        assertEq(_WETH_TOKEN.balanceOf(bob), expectToken);
    }

    function test_sellPortalEnergyOtherToken() external {
        vm.startPrank(alice);
        _HLP_TOKEN.approve(adapterAddress, 1e23);
        adapter.stake(alice, 1e23);
        (,,,,, uint256 portalEnergy,) = adapter.accounts(alice);
        uint256 expectPSM = _HLP_PORTAL.quoteSellPortalEnergy(portalEnergy);
        uint256 balancePSMPortalBefore = _PSM_TOKEN.balanceOf(HLP_PORTAL_ADDRESS); 

        // IF test revert, generate new actionData (for this test dstToken is USDC)
        bytes memory actionData = hex"000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd0900000000000000000000000017a8541b82bf67e10b0874284b4ae66858cb1fd5000000000000000000000000912ce59144191c1204e64559fe8253a0e49e6548000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000003440326f551b8a7ee198cee35cb5d517f2d296a2000000000000000000000000000000000000000000086c72d84648e2f1935231000000000000000000000000000000000000000000000136cd1adeba7e8c8516000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000160000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003420000000000000000000000000000000000000000000003240002f60002ac00a0c9e75c480000000000000000060400000000000000000000000000000000000000000000000000027e00013f00a007e5c0d200000000000000000000000000000000000000000000000000011b00004f02a000000000000000000000000000000000000000000000000017bcdaa93930c6a2ee63c1e501a3cc74aacc1b91b7364a510222864d548c4f803817a8541b82bf67e10b0874284b4ae66858cb1fd500a0c9e75c480000000000000000280a00000000000000000000000000000000000000000000000000009e00004f02a0000000000000000000000000000000000000000000000018fe3ed32faa1aa6c8ee63c1e501c6f780497a95e246eb9449f5e4770916dcd6396a82af49447d8a07e3bd95bd0d56f35241523fbab102a0000000000000000000000000000000000000000000000063fb2b21c96191e01eee63c1e5016ce9bc2d8093d32adde4695a4530b96558388f7e82af49447d8a07e3bd95bd0d56f35241523fbab100a007e5c0d200000000000000000000000000000000000000000000000000011b00004f02a0000000000000000000000000000000000000000000000000000000014c64ee0cee63c1e501a137bed0b2dc07f0addc795b4dee3d2d47410fb917a8541b82bf67e10b0874284b4ae66858cb1fd500a0c9e75c480000000000000000240e00000000000000000000000000000000000000000000000000009e00004f02a00000000000000000000000000000000000000000000000340673c8ac005efaffee63c1e500ee5f2e39d8abf28e449327bfd44317fc500eb4d8af88d065e77c8cc2239327c5edb3a432268e583102a0000000000000000000000000000000000000000000000085cd3d21157281032fee63c1e500b0f6ca40411360c03d41c5ffc5f179b8403cdcf8af88d065e77c8cc2239327c5edb3a432268e583100a0f2fa6b66912ce59144191c1204e64559fe8253a0e49e654800000000000000000000000000000000000000000000014728bdf7ecbb1aa70a00000000000000002a9ed04bf6cbdedc80a06c4eca27912ce59144191c1204e64559fe8253a0e49e65481111111254eeb25477b68fb85ed929f73a9605820000000000000000000000000000000000000000000000000000000000008b1ccac8";
        uint256 expectToken = adapter.sellPortalEnergy(payable(bob), portalEnergy, expectPSM, block.timestamp, false, actionData);

        assertEq(balancePSMPortalBefore - _PSM_TOKEN.balanceOf(HLP_PORTAL_ADDRESS), expectPSM);
        assertEq(_PSM_TOKEN.balanceOf(adapterAddress), 0);
        assertEq(_USDC_TOKEN.balanceOf(bob), expectToken);
        assertEq(_USDC_TOKEN.balanceOf(adapterAddress), 0);
    }

    function test_sellPortalEnergyETH() external {
        vm.startPrank(alice);
        _HLP_TOKEN.approve(adapterAddress, 1e23);
        adapter.stake(alice, 1e23);
        (,,,,, uint256 portalEnergy,) = adapter.accounts(alice);
        uint256 expectPSM = _HLP_PORTAL.quoteSellPortalEnergy(portalEnergy);
        uint256 balancePSMPortalBefore = _PSM_TOKEN.balanceOf(HLP_PORTAL_ADDRESS); 

        // IF test revert, generate new actionData, dstToken is 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
        bytes memory actionData = hex"000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd0900000000000000000000000017a8541b82bf67e10b0874284b4ae66858cb1fd5000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000003440326f551b8a7ee198cee35cb5d517f2d296a2000000000000000000000000000000000000000000086c72d84648e2f19352310000000000000000000000000000000000000000000000003ae40a30c0186b510000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000014000000000000000000000000000000000000000000000000000000000000001600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000038200000000000000000000000000000000000000000000036400034e00030400a0c9e75c48000000000000000005050000000000000000000000000000000000000000000000000002d600022700a007e5c0d20000000000000000000000000000000002030001c70000d70000bd00006302a000000000000000000000000000000000000000000000000000000001187b0417ee63c1e581a137bed0b2dc07f0addc795b4dee3d2d47410fb917a8541b82bf67e10b0874284b4ae66858cb1fd5fc43aaf89a71acaa644842ee4219e8eb776574274021fc43aaf89a71acaa644842ee4219e8eb7765742753c059a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090020d6bdbf78fd086bc7cd5c481dcc9c85ebe478a1c0b69fcbb951209aed3a8896a85fe9a8cac52c9b402d092b629a30fd086bc7cd5c481dcc9c85ebe478a1c0b69fcbb900447dc20382000000000000000000000000fd086bc7cd5c481dcc9c85ebe478a1c0b69fcbb900000000000000000000000082af49447d8a07e3bd95bd0d56f35241523fbab100000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000001da8c2279e73abed000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd0900000000000000000000000042f527f50f16a103b6ccab48bccca214500c1021410182af49447d8a07e3bd95bd0d56f35241523fbab100042e1a7d4d000000000000000000000000000000000000000000000000000000000000000000a007e5c0d200000000000000000000000000000000000000000000000000008b00004f02a00000000000000000000000000000000000000000000000001d3b480921a4bf63ee63c1e501a3cc74aacc1b91b7364a510222864d548c4f803817a8541b82bf67e10b0874284b4ae66858cb1fd5410182af49447d8a07e3bd95bd0d56f35241523fbab100042e1a7d4d000000000000000000000000000000000000000000000000000000000000000000a0f2fa6b66eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0000000000000000000000000000000000000000000000003dfd83fd6be3cf480000000000000000000812b7066c0820c0611111111254eeb25477b68fb85ed929f73a9605820000000000000000000000000000000000000000000000000000000000008b1ccac8";
        
        uint256 expectToken = adapter.sellPortalEnergy(payable(bob), portalEnergy, expectPSM, block.timestamp, false, actionData);

        assertEq(balancePSMPortalBefore - _PSM_TOKEN.balanceOf(HLP_PORTAL_ADDRESS), expectPSM);
        assertEq(_PSM_TOKEN.balanceOf(adapterAddress), 0);
        assertEq(bob.balance, expectToken);
        assertEq(adapterAddress.balance, 0);
    }
    // ---------------------------------------------------
    // ---------------------Liquidity---------------------
    // ---------------------------------------------------

    // function test_addLiquidity() external {
    // }
    // ---------------------------------------------------
    // ---------------------accept ETH--------------------
    // ---------------------------------------------------

    // function test_acceptETH() external {
    //     assertEq(adapterAddress.balance, 0);
    //     payable(adapterAddress).transfer(1 ether);
    //     assertEq(adapterAddress.balance, 1 ether);
    // }

    // function test_acceptETHwithData() external {
    //     assertEq(adapterAddress.balance, 0);
    //     (bool sent,) = adapterAddress.call{value: 1 ether}("0xPortal");
    //     require(sent);
    //     assertEq(adapterAddress.balance, 1 ether);
    // }
    // ---------------------------------------------------
    // ---------------------view--------------------------
    // ---------------------------------------------------

    function test_getUpdateAccount() external {
        uint256 maxLockDuration = getmaxLockDuration();
        help_stake();
        vm.startPrank(alice); //246575342465753424
        (
            address user,
            uint256 lastUpdateTime,
            uint256 lastMaxLockDuration,
            uint256 stakedBalance,
            uint256 maxStakeDebt,
            uint256 portalEnergy,
            uint256 availableToWithdraw
        ) = adapter.getUpdateAccount(alice, 0);
        assertEq(user, alice);
        assertEq(lastUpdateTime, block.timestamp);
        assertEq(lastMaxLockDuration, maxLockDuration);
        assertEq(stakedBalance, 1e18);
        assertEq(maxStakeDebt, 1e18 * maxLockDuration / SECONDS_PER_YEAR);
        assertEq(portalEnergy, 246575342465753424);
        assertEq(availableToWithdraw, 1e18);
    }

    function test_quoteforceUnstakeAll() external {
        help_stake();
        vm.startPrank(alice); //246575342465753424
        adapter.mintPortalEnergyToken(alice, 123287671232876712); //123287671232876712
        uint256 amount = adapter.quoteforceUnstakeAll(alice);
        assertEq(amount, 123287671232876712);
    }

    function test_quoteBuyPortalEnergy() external {
        assertEq(adapter.quoteBuyPortalEnergy(1e15), _HLP_PORTAL.quoteBuyPortalEnergy(1e15));
    }

    function test_quoteSellPortalEnergy() external {
        assertEq(adapter.quoteSellPortalEnergy(1e15), _HLP_PORTAL.quoteSellPortalEnergy(1e15));
    }
}
