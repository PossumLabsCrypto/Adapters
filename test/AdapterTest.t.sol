// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.19;

// import {Test, console2} from "forge-std/Test.sol";
// import {AdapterV1} from "../src/AdapterV1.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import {IHlpPortal} from "./../src/interfaces/IHlpPortal.sol";
// import {SwapDescription} from "./../src/interfaces/IOneInchV5AggregationRouter.sol";
// import {Account} from "./../src/interfaces/IAdapterV1.sol";
// import {EventsLib} from "./../src/libraries/EventsLib.sol";
// import {ErrorsLib} from "./../src/libraries/ErrorsLib.sol";

// import {IWETH} from "./../src/interfaces/IWETH.sol";

// import {IRamsesFactory, IRamsesRouter, IRamsesPair} from "./../src/interfaces/IRamses.sol";

// import "./../src/libraries/ConstantsLib.sol";

// //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// //                                                Done by mahdiRostami
// //                              I have availability for smart contract security audits and testing.
// // Reach out to me on [Twitter](https://twitter.com/0xmahdirostami) or [GitHub](https://github.com/0xmahdirostami/audits).
// ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// contract AdapterTest is Test {
//     address constant WETH_TOKEN_ADDRESS =
//         0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
//     address constant USDC_TOKEN_ADDRESS =
//         0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
//     address constant USDCE_TOKEN_ADDRESS =
//         0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
//     address constant ARB_TOKEN_ADDRESS =
//         0x912CE59144191C1204E64559FE8253a0e49E6548;
//     address constant USDT_TOKEN_ADDRESS =
//         0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;

//     IERC20 constant _WETH_TOKEN = IERC20(WETH_TOKEN_ADDRESS);
//     IERC20 constant _USDC_TOKEN = IERC20(USDC_TOKEN_ADDRESS);
//     IERC20 constant _USDCE_TOKEN = IERC20(USDCE_TOKEN_ADDRESS);
//     IERC20 constant _ARB_TOKEN = IERC20(ARB_TOKEN_ADDRESS);
//     IERC20 constant _USDT_TOKEN = IERC20(USDT_TOKEN_ADDRESS);

//     IHlpPortal constant _HLP_PORTAL = IHlpPortal(HLP_PORTAL_ADDRESS);
//     IWETH constant _IWETH = IWETH(WETH_ADDRESS); // Interface of WETH
//     IRamsesFactory public _RAMSES_FACTORY =
//         IRamsesFactory(RAMSES_FACTORY_ADDRESS); // Interface of Ramses Factory
//     IRamsesRouter public _RAMSES_ROUTER = IRamsesRouter(RAMSES_ROUTER_ADDRESS); // Interface of Ramses Router

//     IERC20 constant _PSM_TOKEN = IERC20(PSM_TOKEN_ADDRESS);
//     IERC20 constant _ENERGY_TOKEN = IERC20(ENERGY_TOKEN_ADDRESS);
//     IERC20 constant _HLP_TOKEN = IERC20(HLP_TOKEN_ADDRESS);
//     address public adapterAddress;
//     Adapter public adapter;

//     // prank addresses
//     address alice = address(uint160(uint256(keccak256("alice"))));
//     address bob = address(uint160(uint256(keccak256("bob"))));
//     address karen = address(uint160(uint256(keccak256("karen"))));

//     function setUp() public {
//         vm.createSelectFork({
//             urlOrAlias: "arbitrum_infura_v4",
//             blockNumber: 173305634
//         });
//         adapter = new Adapter();
//         adapterAddress = address(adapter);
//         deal(PSM_TOKEN_ADDRESS, alice, 2e23);
//         deal(HLP_TOKEN_ADDRESS, alice, 2e23);
//         deal(PSM_TOKEN_ADDRESS, bob, 2e23);
//         deal(HLP_TOKEN_ADDRESS, bob, 2e23);
//         deal(PSM_TOKEN_ADDRESS, karen, 1e30);
//         deal(WETH_ADDRESS, karen, 1e30);
//         vm.deal(karen, 1e30);
//     }

//     /////////////////////////////////////////////////////////// helper
//     function help_stake() internal {
//         vm.startPrank(alice);
//         _HLP_TOKEN.approve(adapterAddress, 1e18);
//         adapter.stake(alice, 1e18);
//         vm.stopPrank();
//     }

//     function getmaxLockDuration() internal view returns (uint256) {
//         return _HLP_PORTAL.maxLockDuration();
//     }

//     // ---------------------------------------------------
//     // ---------------staking and unstaking---------------
//     // ---------------------------------------------------

//     // reverts
//     function testRevert_stake0Amount() external {
//         vm.startPrank(alice);
//         _HLP_TOKEN.approve(adapterAddress, 1e18);
//         vm.expectRevert(ErrorsLib.InvalidInput.selector);
//         adapter.stake(alice, 0);
//     }

//     function testRevert_stake0Address() external {
//         vm.startPrank(alice);
//         _HLP_TOKEN.approve(adapterAddress, 1e18);
//         vm.expectRevert(ErrorsLib.InvalidInput.selector);
//         adapter.stake(address(0), 1e18);
//     }

//     function testRevert_unStakeExistingAccount() external {
//         vm.expectRevert(ErrorsLib.AccountDoesNotExist.selector);
//         adapter.unstake(1e18);
//     }

//     function testRevert_unStake0Amount() external {
//         help_stake();
//         vm.startPrank(alice);
//         vm.expectRevert(ErrorsLib.InvalidInput.selector);
//         adapter.unstake(0);
//     }

//     function testRevert_unStakeMoreThanStaked() external {
//         help_stake();
//         vm.startPrank(alice);
//         vm.expectRevert(ErrorsLib.InsufficientToWithdraw.selector);
//         adapter.unstake(2e18);
//     }

//     function testRevert_forceunStakeExistingAccount() external {
//         vm.expectRevert(ErrorsLib.AccountDoesNotExist.selector);
//         adapter.forceUnstakeAll();
//     }

//     function testRevert_forceunStakeInsufficent() external {
//         help_stake();
//         vm.startPrank(alice);
//         adapter.mintPortalEnergyToken(bob, 10);
//         vm.expectRevert(ErrorsLib.InsufficientPEtokens.selector);
//         adapter.forceUnstakeAll();
//     }

//     function testRevert_forceunStakeTimeLock() external {
//         help_stake();
//         vm.startPrank(alice);
//         adapter.mintPortalEnergyToken(alice, 10);
//         vm.expectRevert(ErrorsLib.TradeTimelockActive.selector);
//         adapter.forceUnstakeAll();
//     }

//     // events
//     function testEvent_stake() external {
//         uint256 maxLockDuration = getmaxLockDuration();
//         vm.startPrank(alice);
//         _HLP_TOKEN.approve(adapterAddress, 1e5);
//         vm.expectEmit(adapterAddress);
//         emit EventsLib.StakePositionUpdated(
//             alice,
//             alice,
//             block.timestamp,
//             maxLockDuration,
//             1e5,
//             (1e5 * maxLockDuration) / SECONDS_PER_YEAR,
//             (1e5 * maxLockDuration) / SECONDS_PER_YEAR,
//             1e5
//         );
//         adapter.stake(alice, 1e5);
//     }

//     function testEvent_stakeForOther() external {
//         uint256 maxLockDuration = getmaxLockDuration();
//         vm.startPrank(alice);
//         _HLP_TOKEN.approve(adapterAddress, 1e5);
//         vm.expectEmit(adapterAddress);
//         emit EventsLib.StakePositionUpdated(
//             alice,
//             bob,
//             block.timestamp,
//             maxLockDuration,
//             1e5,
//             (1e5 * maxLockDuration) / SECONDS_PER_YEAR,
//             (1e5 * maxLockDuration) / SECONDS_PER_YEAR,
//             1e5
//         );
//         adapter.stake(bob, 1e5);
//     }

//     function testEvent_reStake() external {
//         uint256 maxLockDuration = getmaxLockDuration();
//         vm.startPrank(alice);
//         _HLP_TOKEN.approve(adapterAddress, 2e5);
//         adapter.stake(alice, 1e5);
//         vm.expectEmit(adapterAddress);
//         emit EventsLib.StakePositionUpdated(
//             alice,
//             alice,
//             block.timestamp,
//             maxLockDuration,
//             1e5 * 2,
//             (1e5 * 2 * maxLockDuration) / SECONDS_PER_YEAR,
//             (1e5 * 2 * maxLockDuration) / SECONDS_PER_YEAR - 1, // 2 times division
//             199995 // stake * portalenery / maxstakedebt
//         );
//         adapter.stake(alice, 1e5);
//     }

//     function testEvent_unStake() external {
//         uint256 maxLockDuration = getmaxLockDuration();
//         help_stake();
//         vm.startPrank(alice);
//         vm.expectEmit(adapterAddress);
//         emit EventsLib.StakePositionUpdated(
//             alice,
//             alice,
//             block.timestamp,
//             maxLockDuration,
//             0,
//             0,
//             0,
//             0
//         );
//         adapter.unstake(1e18);
//     }

//     function testEvent_unStakePartially() external {
//         uint256 maxLockDuration = getmaxLockDuration();
//         help_stake();
//         vm.startPrank(alice);
//         vm.expectEmit(adapterAddress);
//         emit EventsLib.StakePositionUpdated(
//             alice,
//             alice,
//             block.timestamp,
//             maxLockDuration,
//             5e17,
//             (5e17 * maxLockDuration) / SECONDS_PER_YEAR,
//             (5e17 * maxLockDuration) / SECONDS_PER_YEAR,
//             5e17
//         );
//         adapter.unstake(5e17);
//     }

//     function testEvent_forceunStake() external {
//         uint256 maxLockDuration = getmaxLockDuration();
//         help_stake();
//         vm.startPrank(alice);
//         vm.expectEmit(adapterAddress);
//         emit EventsLib.StakePositionUpdated(
//             alice,
//             alice,
//             block.timestamp,
//             maxLockDuration,
//             0,
//             0,
//             0,
//             0
//         );
//         adapter.forceUnstakeAll();
//     }

//     function testEvent_forceunStakeWithExtraEnergy() external {
//         uint256 maxLockDuration = getmaxLockDuration();
//         help_stake();
//         vm.warp(block.timestamp + 60);
//         vm.startPrank(alice);
//         vm.expectEmit(adapterAddress);
//         emit EventsLib.StakePositionUpdated(
//             alice,
//             alice,
//             block.timestamp,
//             maxLockDuration,
//             0,
//             0, //
//             1902587519025,
//             // 1902587519025 = 60 * 1e18 / 31536000
//             0
//         );
//         adapter.forceUnstakeAll();
//     }

//     // stake
//     function test_stake() external {
//         uint256 maxLockDuration = getmaxLockDuration();
//         vm.startPrank(alice);
//         _HLP_TOKEN.approve(adapterAddress, 1e5);
//         uint256 balanceBeforeAlice = _HLP_TOKEN.balanceOf(alice);
//         adapter.stake(alice, 1e5);
//         (
//             address user,
//             uint256 lastUpdateTime,
//             uint256 lastMaxLockDuration,
//             uint256 stakedBalance,
//             uint256 maxStakeDebt,
//             uint256 portalEnergy,
//             uint256 availableToWithdraw
//         ) = adapter.getUpdateAccount(alice, 0);
//         assertEq(user, alice);
//         assertEq(lastUpdateTime, block.timestamp);
//         assertEq(lastMaxLockDuration, maxLockDuration);
//         assertEq(stakedBalance, 1e5);
//         assertEq(
//             maxStakeDebt,
//             (1e5 * maxLockDuration * WAD) /
//                 (SECONDS_PER_YEAR * DECIMALS_ADJUSTMENT)
//         );
//         assertEq(
//             portalEnergy,
//             (1e5 * maxLockDuration * WAD) /
//                 (SECONDS_PER_YEAR * DECIMALS_ADJUSTMENT)
//         );
//         assertEq(availableToWithdraw, 1e5);

//         // check portal
//         (
//             user,
//             lastUpdateTime,
//             lastMaxLockDuration,
//             stakedBalance,
//             maxStakeDebt,
//             portalEnergy,
//             availableToWithdraw
//         ) = _HLP_PORTAL.getUpdateAccount(adapterAddress, 0);
//         assertEq(user, adapterAddress);
//         assertEq(lastUpdateTime, block.timestamp);
//         assertEq(lastMaxLockDuration, maxLockDuration);
//         assertEq(stakedBalance, 1e5);
//         assertEq(
//             maxStakeDebt,
//             (1e5 * maxLockDuration * WAD) /
//                 (SECONDS_PER_YEAR * DECIMALS_ADJUSTMENT)
//         );
//         assertEq(
//             portalEnergy,
//             (1e5 * maxLockDuration * WAD) /
//                 (SECONDS_PER_YEAR * DECIMALS_ADJUSTMENT)
//         );
//         assertEq(availableToWithdraw, 1e5);
//         uint256 balanceAfterAlice = _HLP_TOKEN.balanceOf(alice);

//         // check alice balance
//         assertEq(balanceBeforeAlice - balanceAfterAlice, 1e5);
//         assertEq(adapter.totalPrincipalStaked(), 1e5);
//     }

//     function test_reStake() external {
//         uint256 maxLockDuration = getmaxLockDuration();
//         vm.startPrank(alice);
//         _HLP_TOKEN.approve(adapterAddress, 2e5);
//         uint256 balanceBeforeAlice = _HLP_TOKEN.balanceOf(alice);
//         adapter.stake(alice, 1e5);
//         adapter.stake(alice, 1e5);
//         (
//             address user,
//             uint256 lastUpdateTime,
//             uint256 lastMaxLockDuration,
//             uint256 stakedBalance,
//             uint256 maxStakeDebt,
//             uint256 portalEnergy,
//             uint256 availableToWithdraw
//         ) = adapter.getUpdateAccount(alice, 0);
//         assertEq(user, alice);
//         assertEq(lastUpdateTime, block.timestamp);
//         assertEq(lastMaxLockDuration, maxLockDuration);
//         assertEq(stakedBalance, 2 * 1e5);
//         assertEq(maxStakeDebt, (2 * 1e5 * maxLockDuration) / SECONDS_PER_YEAR);
//         assertEq(
//             portalEnergy,
//             ((2 * 1e5 * maxLockDuration) / SECONDS_PER_YEAR) - 1
//         ); // beacuse of there are two division for portal energy
//         assertEq(availableToWithdraw, 199995); // due to portalEnergy

//         // check alice balance
//         uint256 balanceAfterAlice = _HLP_TOKEN.balanceOf(alice);
//         assertEq(balanceBeforeAlice - balanceAfterAlice, 2e5);
//         assertEq(adapter.totalPrincipalStaked(), 2e5);
//     }

//     function test_unStake() external {
//         uint256 maxLockDuration = getmaxLockDuration();
//         vm.startPrank(alice);
//         _HLP_TOKEN.approve(adapterAddress, 1e5);
//         adapter.stake(alice, 1e5);
//         adapter.unstake(1e5);
//         (
//             bool isExist,
//             uint256 lastUpdateTime,
//             uint256 lastMaxLockDuration,
//             uint256 stakedBalance,
//             uint256 maxStakeDebt,
//             uint256 portalEnergy,
//             uint256 availableToWithdraw
//         ) = adapter.accounts(alice);
//         assertEq(isExist, true);
//         assertEq(lastUpdateTime, block.timestamp);
//         assertEq(lastMaxLockDuration, maxLockDuration);
//         assertEq(stakedBalance, 0);
//         assertEq(maxStakeDebt, 0);
//         assertEq(portalEnergy, 0);
//         assertEq(availableToWithdraw, 0);
//         assertEq(adapter.totalPrincipalStaked(), 0);
//     }

//     function test_unStakeReceiver() external {
//         uint256 maxLockDuration = getmaxLockDuration();
//         vm.startPrank(alice);
//         _HLP_TOKEN.approve(adapterAddress, 1e5);
//         adapter.stake(alice, 1e5);
//         uint256 balanceBeforeAlice = _HLP_TOKEN.balanceOf(alice);
//         adapter.unstake(1e5);
//         (
//             bool isExist,
//             uint256 lastUpdateTime,
//             uint256 lastMaxLockDuration,
//             uint256 stakedBalance,
//             uint256 maxStakeDebt,
//             uint256 portalEnergy,
//             uint256 availableToWithdraw
//         ) = adapter.accounts(alice);
//         assertEq(isExist, true);
//         assertEq(lastUpdateTime, block.timestamp);
//         assertEq(lastMaxLockDuration, maxLockDuration);
//         assertEq(stakedBalance, 0);
//         assertEq(maxStakeDebt, 0);
//         assertEq(portalEnergy, 0);
//         assertEq(availableToWithdraw, 0);

//         // check bob balance
//         uint256 balanceAfterAlice = _HLP_TOKEN.balanceOf(alice);
//         assertEq(balanceAfterAlice - balanceBeforeAlice, 1e5);
//     }

//     function test_unStakeAvailableToWithdraw() external {
//         uint256 maxLockDuration = getmaxLockDuration();
//         help_stake();
//         vm.startPrank(alice);
//         adapter.mintPortalEnergyToken(alice, 2902587519025);
//         vm.warp(block.timestamp + 60); // 1902587519025 = 60 * 1e18 / 31536000
//         (
//             address user,
//             uint256 lastUpdateTime,
//             uint256 lastMaxLockDuration,
//             uint256 stakedBalance,
//             uint256 maxStakeDebt,
//             uint256 portalEnergy,
//             uint256 availableToWithdraw
//         ) = adapter.getUpdateAccount(alice, 0);
//         uint256 _available = availableToWithdraw;
//         uint256 balanceBeforeAlice = _HLP_TOKEN.balanceOf(alice);
//         adapter.unstake(availableToWithdraw);
//         (
//             user,
//             lastUpdateTime,
//             lastMaxLockDuration,
//             stakedBalance,
//             maxStakeDebt,
//             portalEnergy,
//             availableToWithdraw
//         ) = adapter.getUpdateAccount(alice, 0);
//         assertEq(stakedBalance, 1e18 - _available);
//         assertEq(portalEnergy, 0);
//         assertEq(
//             (stakedBalance * maxLockDuration) / SECONDS_PER_YEAR,
//             maxStakeDebt
//         );
//         assertEq(availableToWithdraw, 0);

//         uint256 balanceAfterAlice = _HLP_TOKEN.balanceOf(alice);
//         assertEq(balanceAfterAlice - balanceBeforeAlice, _available);
//     }

//     function test_forceunStake() external {
//         uint256 maxLockDuration = getmaxLockDuration();
//         vm.startPrank(alice);
//         _HLP_TOKEN.approve(adapterAddress, 1e5);
//         adapter.stake(alice, 1e5);
//         adapter.forceUnstakeAll();
//         (
//             address user,
//             uint256 lastUpdateTime,
//             uint256 lastMaxLockDuration,
//             uint256 stakedBalance,
//             uint256 maxStakeDebt,
//             uint256 portalEnergy,
//             uint256 availableToWithdraw
//         ) = adapter.getUpdateAccount(alice, 0);
//         assertEq(user, alice);
//         assertEq(lastUpdateTime, block.timestamp);
//         assertEq(lastMaxLockDuration, maxLockDuration);
//         assertEq(stakedBalance, 0);
//         assertEq(maxStakeDebt, 0);
//         assertEq(portalEnergy, 0);
//         assertEq(availableToWithdraw, 0);
//         assertEq(adapter.totalPrincipalStaked(), 0);
//     }

//     function test_forceunStakeWithMintToken() external {
//         help_stake();
//         vm.startPrank(alice);
//         adapter.mintPortalEnergyToken(alice, 246575342465753424);
//         vm.warp(block.timestamp + 60);
//         _ENERGY_TOKEN.approve(
//             adapterAddress,
//             246575342465753424 - 1902587519025
//         ); // 1902587519025 = 60 * 1e18 / 31536000
//         adapter.forceUnstakeAll();
//         (
//             ,
//             ,
//             ,
//             uint256 stakedBalance,
//             uint256 maxStakeDebt,
//             uint256 portalEnergy,
//             uint256 availableToWithdraw
//         ) = adapter.getUpdateAccount(alice, 0);
//         assertEq(stakedBalance, 0);
//         assertEq(maxStakeDebt, 0);
//         assertEq(availableToWithdraw, 0);
//         assertEq(portalEnergy, 0);
//         assertEq(_ENERGY_TOKEN.balanceOf(alice), 1902587519025);
//     }

//     // ---------------------------------------------------
//     // ---------------PortalEnergyToken-------------------
//     // ---------------------------------------------------

//     // reverts
//     function testRevert_mintPortalEnergyToken0Amount() external {
//         help_stake();
//         vm.startPrank(alice);
//         vm.expectRevert(ErrorsLib.InvalidInput.selector);
//         adapter.mintPortalEnergyToken(alice, 0);
//     }

//     function testRevert_mintPortalEnergyTokenFor0Address() external {
//         help_stake();
//         vm.startPrank(alice);
//         vm.expectRevert(ErrorsLib.InvalidInput.selector);
//         adapter.mintPortalEnergyToken(address(0), 1);
//     }

//     function testRevert_mintPortalEnergyTokenAccountDoesNotExist() external {
//         vm.expectRevert(ErrorsLib.AccountDoesNotExist.selector);
//         adapter.mintPortalEnergyToken(alice, 1);
//     }

//     function testRevert_mintPortalEnergyTokenInsufficientBalance() external {
//         help_stake();
//         vm.startPrank(alice);
//         vm.expectRevert(ErrorsLib.InsufficientBalance.selector);
//         adapter.mintPortalEnergyToken(alice, 1e18);
//     }

//     function testRevert_mintPortalEnergyTokenTimeLock() external {
//         help_stake();
//         vm.startPrank(alice);
//         adapter.mintPortalEnergyToken(alice, 10);
//         vm.expectRevert(ErrorsLib.TradeTimelockActive.selector);
//         adapter.mintPortalEnergyToken(alice, 10);
//     }

//     function testRevert_burnPrtalEnergyToken0Amount() external {
//         help_stake();
//         vm.startPrank(alice);
//         vm.expectRevert(ErrorsLib.InvalidInput.selector);
//         adapter.burnPortalEnergyToken(alice, 0);
//     }

//     function testRevert_burnPortalEnergyTokenForAccountDoesNotExist() external {
//         help_stake();
//         vm.startPrank(alice);
//         vm.expectRevert(ErrorsLib.AccountDoesNotExist.selector);
//         adapter.burnPortalEnergyToken(bob, 1);
//     }

//     function testRevert_burnPortalEnergyTokenInsufficientBalance() external {
//         help_stake();
//         vm.startPrank(alice);
//         adapter.mintPortalEnergyToken(alice, 100);
//         vm.warp(block.timestamp + 60);
//         vm.expectRevert(ErrorsLib.InsufficientBalance.selector);
//         adapter.burnPortalEnergyToken(alice, 101);
//     }

//     function testRevert_mintBurnPortalEnergyTokenTimeLock() external {
//         help_stake();
//         vm.startPrank(alice);
//         adapter.mintPortalEnergyToken(alice, 10);
//         vm.expectRevert(ErrorsLib.TradeTimelockActive.selector);
//         adapter.burnPortalEnergyToken(alice, 10);
//     }

//     // events
//     function testEvent_mintPortalEnergyToken() external {
//         help_stake();
//         vm.startPrank(alice);
//         vm.expectEmit(adapterAddress);
//         emit EventsLib.PortalEnergyMinted(alice, bob, 246575342465753424); //1e18*maxlock/year = 246,575,342,465,753,424
//         adapter.mintPortalEnergyToken(bob, 246575342465753424);
//     }

//     function testEvent_burnPortalEnergyToken() external {
//         help_stake();
//         vm.startPrank(alice);
//         adapter.mintPortalEnergyToken(alice, 246575342465753424);
//         vm.warp(block.timestamp + 60);
//         _ENERGY_TOKEN.approve(adapterAddress, 246575342465753424);
//         vm.expectEmit(adapterAddress);
//         emit EventsLib.PortalEnergyBurned(alice, alice, 246575342465753424);
//         adapter.burnPortalEnergyToken(alice, 246575342465753424);
//     }

//     // mintPortalEnergyToken
//     function test_mintPortalEnergyToken() external {
//         help_stake();
//         vm.startPrank(alice);
//         adapter.mintPortalEnergyToken(bob, 246575342465753424);
//         assertEq(_ENERGY_TOKEN.balanceOf(bob), 246575342465753424);
//         (, , , , , uint256 portalEnergy, ) = adapter.getUpdateAccount(alice, 0);
//         assertEq(portalEnergy, 0);
//     }

//     // burnPortalEnergyToken
//     function test_burnPortalEnergyToken() external {
//         help_stake();
//         vm.startPrank(alice);
//         adapter.mintPortalEnergyToken(bob, 246575342465753424);
//         vm.startPrank(bob);
//         vm.warp(block.timestamp + 60);
//         _ENERGY_TOKEN.approve(adapterAddress, 246575342465753424);
//         adapter.burnPortalEnergyToken(alice, 246575342465753424);
//         assertEq(_ENERGY_TOKEN.balanceOf(bob), 0);
//         (, , , , , uint256 portalEnergy, ) = adapter.getUpdateAccount(alice, 0);
//         assertEq(portalEnergy, 246575342465753424 + 1902587519025); // 1902587519025 = 60 * 1e18 / 31536000
//     }

//     // ---------------------------------------------------
//     // ---------------buy and sell energy token-----------
//     // ---------------------------------------------------

//     // revert
//     function testRevert_buyPortalEnergynotexitAccount() external {
//         vm.expectRevert(ErrorsLib.AccountDoesNotExist.selector);
//         adapter.buyPortalEnergy(alice, 0, 0, block.timestamp);
//     }

//     function testRevert_buyPortalEnergy0Amount() external {
//         help_stake();
//         vm.expectRevert(ErrorsLib.InvalidInput.selector);
//         adapter.buyPortalEnergy(alice, 0, 0, block.timestamp);
//     }

//     function testRevert_buyPortalEnergy0MinReceived() external {
//         help_stake();
//         vm.expectRevert(ErrorsLib.InvalidInput.selector);
//         adapter.buyPortalEnergy(alice, 1, 0, block.timestamp);
//     }

//     function testRevert_buyPortalEnergyAfterDeadline() external {
//         help_stake();
//         vm.expectRevert(ErrorsLib.DeadlineExpired.selector);
//         adapter.buyPortalEnergy(alice, 1, 1, block.timestamp - 1);
//     }

//     function testRevert_buyPortalEnergyTradeTimelockActive() external {
//         help_stake();
//         vm.startPrank(alice);
//         _PSM_TOKEN.approve(adapterAddress, 2e10);
//         adapter.buyPortalEnergy(alice, 1e10, 1, block.timestamp);
//         vm.expectRevert(ErrorsLib.TradeTimelockActive.selector);
//         adapter.buyPortalEnergy(alice, 1e10, 1, block.timestamp);
//     }

//     function testRevert_buyPortalEnergyAmountReceived() external {
//         help_stake();
//         vm.startPrank(alice);
//         _PSM_TOKEN.approve(adapterAddress, 2e10);
//         vm.expectRevert(ErrorsLib.InvalidOutput.selector);
//         adapter.buyPortalEnergy(alice, 1e10, 1e18, block.timestamp);
//     }

//     function testRevert_sellPortalEnergynotexitaccount() external {
//         vm.expectRevert(ErrorsLib.AccountDoesNotExist.selector);
//         adapter.sellPortalEnergy(payable(alice), 0, 0, block.timestamp, 0, "");
//     }

//     function testRevert_sellPortalEnergy0Amount() external {
//         help_stake();
//         vm.startPrank(alice);
//         vm.expectRevert(ErrorsLib.InvalidInput.selector);
//         adapter.sellPortalEnergy(payable(alice), 0, 0, block.timestamp, 0, "");
//     }

//     function testRevert_sellPortalEnergy0MinReceived() external {
//         help_stake();
//         vm.startPrank(alice);
//         vm.expectRevert(ErrorsLib.InvalidInput.selector);
//         adapter.sellPortalEnergy(payable(alice), 1, 0, block.timestamp, 0, "");
//     }

//     function testRevert_sellPortalEnergyAfterDeadline() external {
//         help_stake();
//         vm.startPrank(alice);
//         vm.expectRevert(ErrorsLib.DeadlineExpired.selector);
//         adapter.sellPortalEnergy(
//             payable(alice),
//             1,
//             1,
//             block.timestamp - 1,
//             0,
//             ""
//         );
//     }

//     function testRevert_sellPortalEnergyAfterInvalidMode() external {
//         help_stake();
//         vm.startPrank(alice);
//         vm.expectRevert(ErrorsLib.InvalidInput.selector);
//         adapter.sellPortalEnergy(payable(alice), 1, 1, block.timestamp, 3, "");
//     }

//     function testRevert_sellPortalEnergyTradeTimelockActive() external {
//         help_stake();
//         vm.startPrank(alice);
//         adapter.sellPortalEnergy(payable(alice), 1, 1, block.timestamp, 0, "");
//         vm.expectRevert(ErrorsLib.TradeTimelockActive.selector);
//         adapter.sellPortalEnergy(payable(alice), 1, 1, block.timestamp, 0, "");
//     }

//     function testRevert_sellPortalEnergyInsufficientBalance() external {
//         help_stake();
//         vm.startPrank(alice);
//         vm.expectRevert(ErrorsLib.InsufficientBalance.selector);
//         adapter.sellPortalEnergy(
//             payable(alice),
//             10e18,
//             1e18,
//             block.timestamp,
//             0,
//             ""
//         );
//     }

//     function testRevert_sellPortalEnergyAmountReceived() external {
//         help_stake();
//         vm.startPrank(alice);
//         vm.expectRevert(ErrorsLib.InvalidOutput.selector);
//         adapter.sellPortalEnergy(
//             payable(alice),
//             10,
//             10e18,
//             block.timestamp,
//             0,
//             ""
//         );
//     }

//     // event
//     function testEvent_buyPortalEnergy() external {
//         help_stake();
//         uint256 expect = _HLP_PORTAL.quoteBuyPortalEnergy(1e15);
//         vm.startPrank(alice);
//         _PSM_TOKEN.approve(adapterAddress, 1e15);
//         vm.expectEmit(adapterAddress);
//         emit EventsLib.PortalEnergyBuyExecuted(alice, alice, expect);
//         adapter.buyPortalEnergy(alice, 1e15, 1e5, block.timestamp);
//     }

//     function testEvent_sellPortalEnergy() external {
//         help_stake();
//         uint256 expect = _HLP_PORTAL.quoteSellPortalEnergy(1e15);
//         vm.startPrank(alice);
//         vm.expectEmit(adapterAddress);
//         emit EventsLib.PortalEnergySellExecuted(alice, alice, expect);
//         adapter.sellPortalEnergy(
//             payable(alice),
//             1e15,
//             1e5,
//             block.timestamp,
//             0,
//             ""
//         );
//     }

//     function test_buyPortalEnergy() external {
//         uint256 maxLockDuration = getmaxLockDuration();

//         help_stake();
//         uint256 expect = _HLP_PORTAL.quoteBuyPortalEnergy(2e18);
//         (
//             ,
//             ,
//             ,
//             uint256 stakedBalance,
//             uint256 maxStakeDebt,
//             uint256 portalEnergy,
//             uint256 availableToWithdraw
//         ) = adapter.accounts(alice);
//         uint256 portalEnergyBefore = portalEnergy;
//         uint256 balancePSMAliceBefore = _PSM_TOKEN.balanceOf(alice);
//         uint256 balancePSMPortalBefore = _PSM_TOKEN.balanceOf(
//             HLP_PORTAL_ADDRESS
//         );
//         vm.startPrank(alice);
//         _PSM_TOKEN.approve(adapterAddress, 2e18);
//         adapter.buyPortalEnergy(alice, 2e18, 1, block.timestamp);
//         (
//             ,
//             ,
//             ,
//             stakedBalance,
//             maxStakeDebt,
//             portalEnergy,
//             availableToWithdraw
//         ) = adapter.accounts(alice);
//         uint256 balancePSMAliceAfter = _PSM_TOKEN.balanceOf(alice);
//         uint256 balancePSMPortalAfter = _PSM_TOKEN.balanceOf(
//             HLP_PORTAL_ADDRESS
//         );

//         assertEq(stakedBalance, 1e18);
//         assertEq(
//             maxStakeDebt,
//             (1e18 * maxLockDuration * WAD) /
//                 (SECONDS_PER_YEAR * DECIMALS_ADJUSTMENT)
//         );
//         assertEq(availableToWithdraw, 1e18);
//         assertEq(portalEnergy - portalEnergyBefore, expect);
//         assertEq(balancePSMAliceBefore - balancePSMAliceAfter, 2e18);
//         assertEq(balancePSMPortalAfter - balancePSMPortalBefore, 2e18);
//     }

//     function test_sellPortalEnergy() external {
//         uint256 maxLockDuration = getmaxLockDuration();

//         help_stake();
//         uint256 expect = _HLP_PORTAL.quoteSellPortalEnergy(1e10);
//         (
//             ,
//             ,
//             ,
//             ,
//             uint256 maxStakeDebt,
//             uint256 portalEnergy,
//             uint256 availableToWithdraw
//         ) = adapter.accounts(alice);
//         uint256 portalEnergyBefore = portalEnergy;
//         uint256 balancePSMBobBefore = _PSM_TOKEN.balanceOf(bob);
//         uint256 balancePSMPortalBefore = _PSM_TOKEN.balanceOf(
//             HLP_PORTAL_ADDRESS
//         );
//         vm.startPrank(alice);
//         uint256 expectPSM = adapter.quoteSellPortalEnergy(1e10);
//         adapter.sellPortalEnergy(
//             payable(bob),
//             1e10,
//             expect,
//             block.timestamp,
//             0,
//             ""
//         );
//         (, , , , maxStakeDebt, portalEnergy, availableToWithdraw) = adapter
//             .accounts(alice);
//         uint256 balancePSMBobAfter = _PSM_TOKEN.balanceOf(bob);
//         uint256 balancePSMPortalAfter = _PSM_TOKEN.balanceOf(
//             HLP_PORTAL_ADDRESS
//         );

//         assertEq(
//             maxStakeDebt,
//             (1e18 * maxLockDuration * WAD) /
//                 (SECONDS_PER_YEAR * DECIMALS_ADJUSTMENT)
//         );
//         assertEq(portalEnergyBefore - portalEnergy, 1e10);
//         assertEq(balancePSMBobAfter - balancePSMBobBefore, expect);
//         assertEq(balancePSMBobAfter - balancePSMBobBefore, expectPSM);
//         assertEq(balancePSMPortalBefore - balancePSMPortalAfter, expect);
//     }

//     //////////////////////////////////////////////////////////////////////////////////////////////// OneInch
//     // _actionData = executer + srcToken + dstToken + srcReceiver + dstReceiver + amount + minReturnAmount + flags + permit + _data
//     function test_sellPortalEnergyOtherToken() external {
//         vm.startPrank(alice);
//         _HLP_TOKEN.approve(adapterAddress, 5e20);
//         adapter.stake(alice, 5e20);
//         (, , , , , uint256 portalEnergy, ) = adapter.accounts(alice);
//         uint256 expectPSM = _HLP_PORTAL.quoteSellPortalEnergy(portalEnergy);
//         console2.log("expecet", expectPSM);
//         uint256 balancePSMPortalBefore = _PSM_TOKEN.balanceOf(
//             HLP_PORTAL_ADDRESS
//         );

//         // for this test dstToken is WETH
//         bytes
//             memory actionData = hex"000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd0900000000000000000000000017a8541b82bf67e10b0874284b4ae66858cb1fd500000000000000000000000082af49447d8a07e3bd95bd0d56f35241523fbab1000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000003440326f551b8a7ee198cee35cb5d517f2d296a2000000000000000000000000000000000000000000000c94a9ffe5a6357d9746000000000000000000000000000000000000000000000000005c21a242cf4ad80000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000014000000000000000000000000000000000000000000000000000000000000001600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010e0000000000000000000000000000000000000000000000000000f000001a0020d6bdbf7817a8541b82bf67e10b0874284b4ae66858cb1fd500a007e5c0d20000000000000000000000000000000000000000000000000000b200004f02a00000000000000000000000000000000000000000000000000000000000000001ee63c1e501a137bed0b2dc07f0addc795b4dee3d2d47410fb917a8541b82bf67e10b0874284b4ae66858cb1fd502a00000000000000000000000000000000000000000000000000000000000000001ee63c1e580c6962004f452be9203591991d15f6b388e09e8d0af88d065e77c8cc2239327c5edb3a432268e58311111111254eeb25477b68fb85ed929f73a9605820000000000000000000000000000000000008b1ccac8";
//         uint256 expectToken = adapter.quoteSellPortalEnergy(portalEnergy);
//         adapter.sellPortalEnergy(
//             payable(bob),
//             portalEnergy,
//             expectPSM,
//             block.timestamp,
//             1,
//             actionData
//         );

//         assertEq(
//             balancePSMPortalBefore - _PSM_TOKEN.balanceOf(HLP_PORTAL_ADDRESS),
//             expectPSM
//         );
//         assertEq(_PSM_TOKEN.balanceOf(adapterAddress), 0);
//         assertEq(_WETH_TOKEN.balanceOf(bob), expectToken);
//         assertEq(_WETH_TOKEN.balanceOf(adapterAddress), 0);
//     }

//     function test_sellPortalEnergyETH() external {
//         vm.startPrank(alice);
//         _HLP_TOKEN.approve(adapterAddress, 5e20);
//         adapter.stake(alice, 5e20);
//         (, , , , , uint256 portalEnergy, ) = adapter.accounts(alice);
//         uint256 expectPSM = _HLP_PORTAL.quoteSellPortalEnergy(portalEnergy);
//         uint256 balancePSMPortalBefore = _PSM_TOKEN.balanceOf(
//             HLP_PORTAL_ADDRESS
//         );

//         // for this test dstToken is ETH 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
//         bytes
//             memory actionData = hex"000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd0900000000000000000000000017a8541b82bf67e10b0874284b4ae66858cb1fd5000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000003440326f551b8a7ee198cee35cb5d517f2d296a2000000000000000000000000000000000000000000000c94a9ffe5a6357d9746000000000000000000000000000000000000000000000000005b4db6245e7202000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000160000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000d90000000000000000000000000000000000000000bb0000a500006900001a0020d6bdbf7817a8541b82bf67e10b0874284b4ae66858cb1fd502a00000000000000000000000000000000000000000000000000000000000000001ee63c1e501a3cc74aacc1b91b7364a510222864d548c4f803817a8541b82bf67e10b0874284b4ae66858cb1fd5410182af49447d8a07e3bd95bd0d56f35241523fbab100042e1a7d4d0000000000000000000000000000000000000000000000000000000000000000c0611111111254eeb25477b68fb85ed929f73a960582000000000000008b1ccac8";
//         uint256 expectToken = adapter.quoteSellPortalEnergy(portalEnergy);

//         adapter.sellPortalEnergy(
//             payable(bob),
//             portalEnergy,
//             expectPSM,
//             block.timestamp,
//             1,
//             actionData
//         );

//         assertEq(
//             balancePSMPortalBefore - _PSM_TOKEN.balanceOf(HLP_PORTAL_ADDRESS),
//             expectPSM
//         );
//         assertEq(_PSM_TOKEN.balanceOf(adapterAddress), 0);
//         assertEq(bob.balance, expectToken);
//         assertEq(adapterAddress.balance, 0);
//     }

//     function test_sellPortalEnergyAddLiquidity() external {
//         vm.startPrank(alice);
//         _HLP_TOKEN.approve(adapterAddress, 5e20);
//         adapter.stake(alice, 5e20);
//         (, , , , , uint256 portalEnergy, ) = adapter.accounts(alice);
//         uint256 expectPSM = _HLP_PORTAL.quoteSellPortalEnergy(portalEnergy);
//         uint256 balancePSMPortalBefore = _PSM_TOKEN.balanceOf(
//             HLP_PORTAL_ADDRESS
//         );

//         // for this test dstToken is weth 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
//         bytes
//             memory actionData = hex"000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd0900000000000000000000000017a8541b82bf67e10b0874284b4ae66858cb1fd5000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000003440326f551b8a7ee198cee35cb5d517f2d296a2000000000000000000000000000000000000000000000c94a9ffe5a6357d9746000000000000000000000000000000000000000000000000005b4db6245e7202000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000160000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000d90000000000000000000000000000000000000000bb0000a500006900001a0020d6bdbf7817a8541b82bf67e10b0874284b4ae66858cb1fd502a00000000000000000000000000000000000000000000000000000000000000001ee63c1e501a3cc74aacc1b91b7364a510222864d548c4f803817a8541b82bf67e10b0874284b4ae66858cb1fd5410182af49447d8a07e3bd95bd0d56f35241523fbab100042e1a7d4d0000000000000000000000000000000000000000000000000000000000000000c0611111111254eeb25477b68fb85ed929f73a960582000000000000008b1ccac8";
//         uint256 expectToken = adapter.quoteSellPortalEnergy(portalEnergy);

//         adapter.sellPortalEnergy(
//             payable(bob),
//             portalEnergy,
//             expectPSM,
//             block.timestamp,
//             2,
//             actionData
//         );

//         assertEq(
//             balancePSMPortalBefore - _PSM_TOKEN.balanceOf(HLP_PORTAL_ADDRESS),
//             expectPSM
//         );
//         assertEq(_PSM_TOKEN.balanceOf(adapterAddress), 0);
//         assertEq(bob.balance, expectToken);
//         assertEq(adapterAddress.balance, 0);
//     }

//     // ---------------------------------------------------
//     // ---------------------Liquidity---------------------
//     // ---------------------------------------------------

//     // Helper
//     function AddLiquidity(
//         uint256 amountADesired,
//         uint256 amountBDesired,
//         uint256 amountAMin,
//         uint256 amountBMin
//     ) public {
//         vm.startPrank(karen);
//         _PSM_TOKEN.approve(adapterAddress, type(uint256).max);
//         _WETH_TOKEN.approve(adapterAddress, type(uint256).max);
//         adapter.addLiquidityWETH(
//             karen,
//             amountADesired,
//             amountBDesired,
//             amountAMin,
//             amountBMin,
//             block.timestamp + 200
//         );
//         vm.stopPrank();
//     }

//     function test_AddLiquidity() public {
//         uint256 balance0before = _PSM_TOKEN.balanceOf(karen);
//         uint256 balance1before = _WETH_TOKEN.balanceOf(karen);
//         (uint256 amountA, uint256 amountB, uint256 liquidity) = adapter
//             .quoteAddLiquidity(10000000e18, 4e18);
//         AddLiquidity(10000000e18, 4e18, 10000000e18 / 2, 4e18 / 2);
//         address pair = _RAMSES_FACTORY.getPair(
//             PSM_TOKEN_ADDRESS,
//             WETH_ADDRESS,
//             false
//         );
//         assertEq(IERC20(pair).balanceOf(karen), liquidity); // 6223938189866138537600
//         assertEq(balance0before - amountA, _PSM_TOKEN.balanceOf(karen));
//         assertEq(balance1before - amountB, _WETH_TOKEN.balanceOf(karen));
//     }

//     function test_AddLiquidityETH() public {
//         (uint256 amountA, uint256 amountB, ) = adapter.quoteAddLiquidity(
//             10000000e18,
//             4e18
//         );
//         vm.startPrank(karen);
//         _PSM_TOKEN.approve(adapterAddress, type(uint256).max);
//         (bool success, bytes memory result) = address(adapterAddress).call{
//             value: 4 ether
//         }(
//             abi.encodeWithSignature(
//                 "addLiquidityETH(address,uint256,uint256,uint256,uint256)",
//                 karen,
//                 10000000e18,
//                 0,
//                 0,
//                 block.timestamp + 200
//             )
//         );
//         vm.stopPrank();
//         assertEq(success, true);
//         (uint256 amountToken, uint256 amountETH, uint256 liquidity) = abi
//             .decode(result, (uint256, uint256, uint256));
//         assertEq(amountToken, amountA);
//         assertEq(amountETH, amountB);
//         assertEq(liquidity, 6223938189866138537600);
//     }

//     function test_RemoveLiquidity() public {
//         AddLiquidity(10000000e18, 4e18, 0, 0);
//         address pair = _RAMSES_FACTORY.getPair(
//             PSM_TOKEN_ADDRESS,
//             WETH_ADDRESS,
//             false
//         );
//         (uint256 amountA, uint256 amountB) = adapter.quoteRemoveLiquidity(
//             6223938189866138537600
//         );
//         uint256 balance0before = _PSM_TOKEN.balanceOf(karen);
//         uint256 balance1before = _WETH_TOKEN.balanceOf(karen);
//         vm.startPrank(karen);
//         IERC20(pair).approve(adapterAddress, type(uint256).max);
//         adapter.removeLiquidityWETH(
//             karen,
//             6223938189866138537600,
//             0,
//             0,
//             block.timestamp + 200
//         );
//         assertEq(IERC20(pair).balanceOf(karen), 0);
//         assertEq(balance0before + amountA, _PSM_TOKEN.balanceOf(karen));
//         assertEq(balance1before + amountB, _WETH_TOKEN.balanceOf(karen));
//     }

//     function test_RemoveLiquidityETH() public {
//         AddLiquidity(10000000e18, 4e18, 0, 0);
//         address pair = _RAMSES_FACTORY.getPair(
//             PSM_TOKEN_ADDRESS,
//             WETH_ADDRESS,
//             false
//         );
//         (uint256 amountA, uint256 amountB) = adapter.quoteRemoveLiquidity(
//             6223938189866138537600
//         );
//         uint256 balance0before = _PSM_TOKEN.balanceOf(karen);
//         uint256 balance1before = karen.balance;
//         vm.startPrank(karen);
//         IERC20(pair).approve(adapterAddress, type(uint256).max);
//         adapter.removeLiquidityETH(
//             karen,
//             6223938189866138537600,
//             0,
//             0,
//             block.timestamp + 200
//         );
//         assertEq(IERC20(pair).balanceOf(karen), 0);
//         assertEq(balance0before + amountA, _PSM_TOKEN.balanceOf(karen));
//         assertEq(balance1before + amountB, karen.balance);
//     }

//     // ---------------------------------------------------
//     // ---------------------accept ETH--------------------
//     // ---------------------------------------------------

//     function test_RevertacceptETH() external {
//         vm.expectRevert(ErrorsLib.JustWeth.selector);
//         payable(adapterAddress).transfer(1 ether);
//     }

//     // ---------------------------------------------------
//     // ---------------------view--------------------------
//     // ---------------------------------------------------

//     function test_getUpdateAccount() external {
//         uint256 maxLockDuration = getmaxLockDuration();
//         help_stake();
//         vm.startPrank(alice); //246575342465753424
//         (
//             address user,
//             uint256 lastUpdateTime,
//             uint256 lastMaxLockDuration,
//             uint256 stakedBalance,
//             uint256 maxStakeDebt,
//             uint256 portalEnergy,
//             uint256 availableToWithdraw
//         ) = adapter.getUpdateAccount(alice, 0);
//         assertEq(user, alice);
//         assertEq(lastUpdateTime, block.timestamp);
//         assertEq(lastMaxLockDuration, maxLockDuration);
//         assertEq(stakedBalance, 1e18);
//         assertEq(maxStakeDebt, (1e18 * maxLockDuration) / SECONDS_PER_YEAR);
//         assertEq(portalEnergy, 246575342465753424);
//         assertEq(availableToWithdraw, 1e18);
//     }

//     function test_quoteforceUnstakeAll() external {
//         help_stake();
//         vm.startPrank(alice); //246575342465753424
//         adapter.mintPortalEnergyToken(alice, 123287671232876712); //123287671232876712
//         uint256 amount = adapter.quoteforceUnstakeAll(alice);
//         assertEq(amount, 123287671232876712);
//     }

//     function test_quoteBuyPortalEnergy() external {
//         assertEq(
//             adapter.quoteBuyPortalEnergy(1e15),
//             _HLP_PORTAL.quoteBuyPortalEnergy(1e15)
//         );
//     }

//     function test_quoteSellPortalEnergy() external {
//         assertEq(
//             adapter.quoteSellPortalEnergy(1e15),
//             _HLP_PORTAL.quoteSellPortalEnergy(1e15)
//         );
//     }
// }
