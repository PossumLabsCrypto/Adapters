// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.19;

/// @title Adapter V1 contract for Portals V2
/// @author Possum Labs
/**
 * @notice This contract breaks the migration function of Adapters by being set as migration destination
 * This contract cannot receive ERC721 tokens.
 * Therefore, triggering the migration in the Adapter will fail because it tries to mint an ERC721 token to an address without receiver functio
 * WARNING: Using this contract for migration locks the Adapter in withdraw-only mode
 */
contract MigrationBreaker {
    constructor() {}

    function displayMessage() public pure returns (string memory message) {
        message =
            "This contract is empty and cannot handle or receive ERC721 tokens (NFTs). It was created to break the migration function in AdaptersV1 by defining an incompatible migration destination.";
    }
}
