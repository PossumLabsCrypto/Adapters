// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {Adapter} from "../src/AdapterV1.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IHlpPortal} from "./../src/interfaces/IHlpPortal.sol";
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
    IHlpPortal constant _HLP_PORTAL = IHlpPortal(HLP_PORTAL_ADDRESS);
    IERC20 constant _PSM_TOKEN = IERC20(PSM_TOKEN_ADDRESS);
    IERC20 constant _ENERGY_TOKEN = IERC20(ENERGY_TOKEN_ADDRESS);
    IERC20 constant _HLP_TOKEN = IERC20(HLP_TOKEN_ADDRESS);
    address public adapterAddress;
    Adapter public adapter;

    // prank addresses
    address alice = address(0x01);
    address bob = address(0x02);

    function setUp() public {
        vm.createSelectFork({urlOrAlias: "arbitrum_infura_v4", blockNumber: 163908850});
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
        vm.expectRevert(bytes(ErrorsLib.ZeroAmount));
        adapter.stake(alice, 0);
    }

    function testRevert_stake0Address() external {
        vm.startPrank(alice);
        _HLP_TOKEN.approve(adapterAddress, 1e18);
        vm.expectRevert(bytes(ErrorsLib.ZeroAddress));
        adapter.stake(address(0), 1e18);
    }

    function testRevert_unStakeExistingAccount() external {
        vm.expectRevert(bytes(ErrorsLib.AccountDoesNotExist));
        adapter.unstake(alice, 1e18);
    }

    function testRevert_unStake0Amount() external {
        help_stake();
        vm.startPrank(alice);
        vm.expectRevert(bytes(ErrorsLib.ZeroAmount));
        adapter.unstake(alice, 0);
    }

    function testRevert_unStake0Address() external {
        help_stake();
        vm.startPrank(alice);
        vm.expectRevert(bytes(ErrorsLib.ZeroAddress));
        adapter.unstake(address(0), 1e18);
    }

    function testRevert_unStakeMoreThanStaked() external {
        help_stake();
        vm.startPrank(alice);
        vm.expectRevert(bytes(ErrorsLib.InsufficientToWithdraw));
        adapter.unstake(alice, 2e18);
    }

    function testRevert_forceunStakeExistingAccount() external {
        vm.expectRevert(bytes(ErrorsLib.AccountDoesNotExist));
        adapter.forceUnstakeAll(alice);
    }

    function testRevert_forceunStakeInsufficent() external {
        help_stake();
        vm.startPrank(alice);
        adapter.mintPortalEnergyToken(bob, 10);
        vm.expectRevert(bytes(ErrorsLib.InsufficientPEtokens));
        adapter.forceUnstakeAll(bob);
    }

    function testRevert_forceunStakeTimeLock() external {
        help_stake();
        vm.startPrank(alice);
        adapter.mintPortalEnergyToken(alice, 10);
        vm.expectRevert(bytes(ErrorsLib.TradeTimelockActive));
        adapter.forceUnstakeAll(alice);
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
        adapter.unstake(alice, 1e18);
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
        adapter.unstake(alice, 5e17);
    }

    function testEvent_forceunStake() external {
        uint256 maxLockDuration = getmaxLockDuration();
        help_stake();
        vm.startPrank(alice);
        vm.expectEmit(adapterAddress);
        emit EventsLib.StakePositionUpdated(alice, alice, block.timestamp, maxLockDuration, 0, 0, 0, 0);
        adapter.forceUnstakeAll(alice);
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
        adapter.forceUnstakeAll(alice);
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
        adapter.unstake(alice, 1e5);
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
        uint256 balanceBeforeBob = _HLP_TOKEN.balanceOf(bob);
        adapter.unstake(bob, 1e5);
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
        uint256 balanceAfterBob = _HLP_TOKEN.balanceOf(bob);
        assertEq(balanceAfterBob - balanceBeforeBob, 1e5);
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
        adapter.unstake(alice, availableToWithdraw);
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
        adapter.forceUnstakeAll(alice);
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
        adapter.forceUnstakeAll(alice);
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
        vm.expectRevert(bytes(ErrorsLib.ZeroAmount));
        adapter.mintPortalEnergyToken(alice, 0);
    }

    function testRevert_mintPortalEnergyTokenFor0Address() external {
        help_stake();
        vm.startPrank(alice);
        vm.expectRevert(bytes(ErrorsLib.ZeroAddress));
        adapter.mintPortalEnergyToken(address(0), 1);
    }

    function testRevert_mintPortalEnergyTokenAccountDoesNotExist() external {
        vm.expectRevert(bytes(ErrorsLib.AccountDoesNotExist));
        adapter.mintPortalEnergyToken(alice, 1);
    }

    function testRevert_mintPortalEnergyTokenInsufficientBalance() external {
        help_stake();
        vm.startPrank(alice);
        vm.expectRevert(bytes(ErrorsLib.InsufficientBalance));
        adapter.mintPortalEnergyToken(alice, 1e18);
    }

    function testRevert_mintPortalEnergyTokenTimeLock() external {
        help_stake();
        vm.startPrank(alice);
        adapter.mintPortalEnergyToken(alice, 10);
        vm.expectRevert(bytes(ErrorsLib.TradeTimelockActive));
        adapter.mintPortalEnergyToken(alice, 10);
    }

    function testRevert_burnPrtalEnergyToken0Amount() external {
        help_stake();
        vm.startPrank(alice);
        vm.expectRevert(bytes(ErrorsLib.ZeroAmount));
        adapter.burnPortalEnergyToken(alice, 0);
    }

    function testRevert_burnPortalEnergyTokenForAccountDoesNotExist() external {
        help_stake();
        vm.startPrank(alice);
        vm.expectRevert(bytes(ErrorsLib.AccountDoesNotExist));
        adapter.burnPortalEnergyToken(bob, 1);
    }

    function testRevert_burnPortalEnergyTokenInsufficientBalance() external {
        help_stake();
        vm.startPrank(alice);
        adapter.mintPortalEnergyToken(alice, 100);
        vm.warp(block.timestamp + 60);
        vm.expectRevert(bytes(ErrorsLib.InsufficientBalance));
        adapter.burnPortalEnergyToken(alice, 101);
    }

    function testRevert_mintBurnPortalEnergyTokenTimeLock() external {
        help_stake();
        vm.startPrank(alice);
        adapter.mintPortalEnergyToken(alice, 10);
        vm.expectRevert(bytes(ErrorsLib.TradeTimelockActive));
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
        vm.expectRevert(bytes(ErrorsLib.AccountDoesNotExist));
        adapter.buyPortalEnergy(alice, 0, 0, 0);
    }

    function testRevert_buyPortalEnergy0Amount() external {
        help_stake();
        vm.expectRevert(bytes(ErrorsLib.ZeroAmount));
        adapter.buyPortalEnergy(alice, 0, 0, 0);
    }

    function testRevert_buyPortalEnergy0MinReceived() external {
        help_stake();
        vm.expectRevert(bytes(ErrorsLib.ZeroAmount));
        adapter.buyPortalEnergy(alice, 1, 0, 0);
    }

    function testRevert_buyPortalEnergyAfterDeadline() external {
        help_stake();
        vm.expectRevert(bytes(ErrorsLib.DeadlineExpired));
        adapter.buyPortalEnergy(alice, 1, 1, block.timestamp - 1);
    }

    function testRevert_buyPortalEnergyTradeTimelockActive() external {
        help_stake();
        vm.startPrank(alice);
        _PSM_TOKEN.approve(adapterAddress, 2e10);
        adapter.buyPortalEnergy(alice, 1e10, 1, block.timestamp);
        vm.expectRevert(bytes(ErrorsLib.TradeTimelockActive));
        adapter.buyPortalEnergy(alice, 1e10, 1, block.timestamp);
    }

    function testRevert_buyPortalEnergyAmountReceived() external {
        help_stake();
        vm.startPrank(alice);
        _PSM_TOKEN.approve(adapterAddress, 2e10);
        vm.expectRevert(bytes(ErrorsLib.InvalidOutput));
        adapter.buyPortalEnergy(alice, 1e10, 1e18, block.timestamp);
    }

    // function testRevert_sellPortalEnergynotexitaccount() external {
    //     vm.expectRevert(bytes(ErrorsLib.AccountDoesNotExist));
    //     adapter.sellPortalEnergy(alice, 0, 0, 0, address(0));
    // }

    // function testRevert_sellPortalEnergy0Amount() external {
    //     help_stake();
    //     vm.startPrank(alice);
    //     vm.expectRevert(bytes(ErrorsLib.ZeroAmount));
    //     adapter.sellPortalEnergy(alice, 0, 0, 0, address(0));
    // }

    // function testRevert_sellPortalEnergy0MinReceived() external {
    //     help_stake();
    //     vm.startPrank(alice);
    //     vm.expectRevert(bytes(ErrorsLib.ZeroAmount));
    //     adapter.sellPortalEnergy(alice, 1, 0, 0, address(0));
    // }

    // function testRevert_sellPortalEnergyAfterDeadline() external {
    //     help_stake();
    //     vm.startPrank(alice);
    //     vm.expectRevert(bytes(ErrorsLib.DeadlineExpired));
    //     adapter.sellPortalEnergy(alice, 1, 1, block.timestamp - 1, address(0));
    // }

    // function testRevert_sellPortalEnergy0TokenAddress() external {
    //     help_stake();
    //     vm.startPrank(alice);
    //     vm.expectRevert(bytes(ErrorsLib.ZeroAddress));
    //     adapter.sellPortalEnergy(alice, 1, 1, block.timestamp, address(0));
    // }

    // function testRevert_sellPortalEnergyTradeTimelockActive() external {
    //     help_stake();
    //     vm.startPrank(alice);
    //     adapter.sellPortalEnergy(alice, 1, 1, block.timestamp, PSM_TOKEN_ADDRESS);
    //     vm.expectRevert(bytes(ErrorsLib.TradeTimelockActive));
    //     adapter.sellPortalEnergy(alice, 1, 1, block.timestamp, PSM_TOKEN_ADDRESS);
    // }

    // function testRevert_sellPortalEnergyInsufficientBalance() external {
    //     help_stake();
    //     vm.startPrank(alice);
    //     vm.expectRevert(bytes(ErrorsLib.InsufficientBalance));
    //     adapter.sellPortalEnergy(alice, 10e18, 1e18, block.timestamp, PSM_TOKEN_ADDRESS);
    // }

    // function testRevert_sellPortalEnergyAmountReceived() external {
    //     help_stake();
    //     vm.startPrank(alice);
    //     vm.expectRevert(bytes(ErrorsLib.InvalidOutput));
    //     adapter.sellPortalEnergy(alice, 10, 10e18, block.timestamp, PSM_TOKEN_ADDRESS);
    // }

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

    // function testEvent_sellPortalEnergy() external {
    //     help_stake();
    //     uint256 expect = _HLP_PORTAL.quoteSellPortalEnergy(1e15);
    //     vm.startPrank(alice);
    //     vm.expectEmit(adapterAddress);
    //     emit EventsLib.PortalEnergySellExecuted(alice, alice, expect);
    //     adapter.sellPortalEnergy(alice, 1e15, 1e5, block.timestamp, PSM_TOKEN_ADDRESS);
    // }

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

    // function testSuccess_sellPortalEnergy() external {
    //     uint256 maxLockDuration = getmaxLockDuration();

    //     help_stake();
    //     uint256 expect = _HLP_PORTAL.quoteSellPortalEnergy(1e10);
    //     (,,,, uint256 maxStakeDebt, uint256 portalEnergy, uint256 availableToWithdraw) = adapter.accounts(alice);
    //     uint256 portalEnergyBefore = portalEnergy;
    //     uint256 balancePSMBobBefore = _PSM_TOKEN.balanceOf(bob);
    //     uint256 balancePSMPortalBefore = _PSM_TOKEN.balanceOf(HLP_PORTAL_ADDRESS);
    //     vm.startPrank(alice);
    //     adapter.sellPortalEnergy(bob, 1e10, 1, block.timestamp, PSM_TOKEN_ADDRESS);
    //     (,,,, maxStakeDebt, portalEnergy, availableToWithdraw) = adapter.accounts(alice);
    //     uint256 balancePSMBobAfter = _PSM_TOKEN.balanceOf(bob);
    //     uint256 balancePSMPortalAfter = _PSM_TOKEN.balanceOf(HLP_PORTAL_ADDRESS);

    //     assertEq(maxStakeDebt, (1e18 * maxLockDuration * WAD) / (SECONDS_PER_YEAR * DECIMALS_ADJUSTMENT));
    //     assertEq(portalEnergyBefore - portalEnergy, 1e10);
    //     assertEq(balancePSMBobAfter - balancePSMBobBefore, expect);
    //     assertEq(balancePSMPortalBefore - balancePSMPortalAfter, expect);
    // }

    // function test_sellPortalEnergyOtherToken() external {
    //     help_stake();
    //     vm.startPrank(alice);
    //     adapter.sellPortalEnergy(alice, 1e15, 1e5, block.timestamp, address(0x222));
    //     assert(1 + 1 == 2);
    // }

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
