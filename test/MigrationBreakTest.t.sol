// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MigrationBreaker} from "./../src/MigrationBreaker.sol";
import {IPortalV2MultiAsset} from "../src/interfaces/IPortalV2MultiAsset.sol";
import {Account} from "./../src/interfaces/IAdapterV1.sol";
import {EventsLib} from "./../src/libraries/EventsLib.sol";
import {ErrorsLib} from "./../src/libraries/ErrorsLib.sol";

interface IAdapterV1 {
    function proposeMigrationDestination(address _adapter) external;
    function acceptMigrationDestination() external;
    function executeMigration() external;

    function migrationDestination() external view returns (address);

    function stake(uint256 _amount) external;
}

// irreversibly break the Adapter migration capability to make current settings immutable
contract MigrationBreakTest is Test {
    address constant USDC_TOKEN_ADDRESS = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    IERC20 constant _USDC_TOKEN = IERC20(USDC_TOKEN_ADDRESS);
    IAdapterV1 public adapter_USDC = IAdapterV1(0x44d583Ee73B6D9B4c8B830049DbCc0FA2c9580C0);
    MigrationBreaker public migrationBreaker;

    // prank addresses
    address public Alice = address(uint160(uint256(keccak256("alice"))));
    address public Bob = address(uint160(uint256(keccak256("bob"))));
    address public psmSender = 0xAb845D09933f52af5642FC87Dd8FBbf553fd7B33;
    address public usdcWhale = 0xB38e8c17e38363aF6EbdCb3dAE12e0243582891D;

    function setUp() public {
        // Create main net fork
        vm.createSelectFork({urlOrAlias: "alchemy_arbitrum_api", blockNumber: 260000000});

        // Create contract instances
        migrationBreaker = new MigrationBreaker();
    }

    /////////////////////////////////////////////
    //////////////      TESTS       /////////////
    /////////////////////////////////////////////
    function testSuccess_breakMigration() public {
        // Simulate a 10M USDC stake from the usdc whale to become the majority holder of principal in the Adapter
        vm.startPrank(usdcWhale);
        _USDC_TOKEN.approve(address(adapter_USDC), 1e55);
        adapter_USDC.stake(1e13); // stake 10M USDC
        vm.stopPrank();

        // Call the proposeMigration in the Adapter from the multi-sig, set the MigrationBreaker as destination
        vm.prank(psmSender);
        adapter_USDC.proposeMigrationDestination(address(migrationBreaker));

        vm.startPrank(usdcWhale);
        // Accept the migration as the simulated staker
        adapter_USDC.acceptMigrationDestination();

        // Wait >7 days to pass timelock
        vm.warp(block.timestamp + 604801);

        // Try to execute the migration. Expect revert (ERC721 Error)
        vm.expectRevert("ERC721: transfer to non ERC721Receiver implementer");
        adapter_USDC.executeMigration();
        vm.stopPrank();

        assertEq(adapter_USDC.migrationDestination(), address(migrationBreaker));
    }

    function testSuccess_displayMessage() public {
        string memory message = migrationBreaker.displayMessage();

        assertEq(
            message,
            "This contract is empty and cannot handle or receive ERC721 tokens (NFTs). It was created to break the migration function in AdaptersV1 by defining an incompatible migration destination."
        );
    }
}
