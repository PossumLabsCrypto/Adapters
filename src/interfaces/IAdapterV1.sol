// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.19;

struct Account {
    uint256 lastUpdateTime;
    uint256 lastMaxLockDuration;
    uint256 stakedBalance;
    uint256 maxStakeDebt;
    uint256 portalEnergy;
}

struct SwapData {
    address recipient;
    uint256 psmAmount;
    bytes actionData;
}

interface IAdapterV1 {
    function PORTAL() external view returns (address PORTAL);

    function acceptMigrationDestination() external;

    function executeMigration() external;

    function migrateStake(address _user)
        external
        returns (
            uint256 lastUpdateTime,
            uint256 lastMaxLockDuration,
            uint256 stakedBalance,
            uint256 maxStakeDebt,
            uint256 portalEnergy
        );

    function getUpdateAccount(address _user, uint256 _amount, bool _isPositiveAmount)
        external
        view
        returns (
            uint256 lastUpdateTime,
            uint256 lastMaxLockDuration,
            uint256 stakedBalance,
            uint256 maxStakeDebt,
            uint256 portalEnergy,
            uint256 availableToWithdraw,
            uint256 portalEnergyTokensRequired
        );

    function stake(uint256 _amount) external;

    function unstake(uint256 _amount) external;

    function buyPortalEnergy(address _recipient, uint256 _amountInputPSM, uint256 _minReceived, uint256 _deadline)
        external;

    function sellPortalEnergy(
        address payable _recipient,
        uint256 _amountInputPE,
        uint256 _minReceived,
        uint256 _deadline,
        uint256 _mode,
        bytes calldata _actionData,
        uint256 _minPSMForLiquidiy,
        uint256 _minWethForLiquidiy
    ) external;

    function burnPortalEnergyToken(address _recipient, uint256 _amount) external;

    function mintPortalEnergyToken(address _recipient, uint256 _amount) external;

    function increaseAllowances() external;

    function salvageToken(address _token) external;
}
