// SPDX-License-Identifier: unlicensed
pragma solidity =0.8.19;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {IPortalV2MultiAsset} from "./interfaces/IPortalV2MultiAsset.sol";
import {IAdapterV1, Account} from "./interfaces/IAdapterV1.sol";

contract DummyMigration is ERC721Holder {
    constructor(address _oldAdapter) {
        ADAPTER = IAdapterV1(_oldAdapter);
        PORTAL = IPortalV2MultiAsset(ADAPTER.PORTAL());
        PORTAL_NFT = PORTAL.portalNFT();
    }

    /////////////////////////////
    /////////////////////////////

    IAdapterV1 public immutable ADAPTER; // The migrating Adapter
    IPortalV2MultiAsset public immutable PORTAL; // The connected Portal contract
    address public immutable PORTAL_NFT; // Contract address of the related Portal Position NFT

    mapping(address => Account) public accounts; // Associate users with their stake position

    /////////////////////////////
    /////////////////////////////

    // Function to redeem the Position NFT and transfer its PE & stake balance to this contract
    // This redeems the value for all users
    function redeemNFT(uint256 _id) public {
        require(_id != 0, "Must set ID first");

        PORTAL.redeemNFTposition(_id);
    }

    function migrateStake(address _user) external {
        (
            uint256 lastUpdateTime,
            uint256 lastMaxLockDuration,
            uint256 stakedBalance,
            uint256 maxStakeDebt,
            uint256 portalEnergy
        ) = ADAPTER.migrateStake(_user);

        // Update the user account in this contract (examplary only, must consider existing stake)
        accounts[_user] = Account(
            lastUpdateTime,
            lastMaxLockDuration,
            stakedBalance,
            maxStakeDebt,
            portalEnergy
        );
    }
}
