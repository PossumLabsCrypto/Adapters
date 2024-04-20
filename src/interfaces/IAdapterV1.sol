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
    address recevier;
    uint256 psmAmount;
    bytes actionData;
}

interface IAdapterV1 {
    function PORTAL() external view returns (address PORTAL);

    function migrateStake(
        address _user
    )
        external
        returns (
            uint256 lastUpdateTime,
            uint256 lastMaxLockDuration,
            uint256 stakedBalance,
            uint256 maxStakeDebt,
            uint256 portalEnergy
        );

    function stake(address _receiver, uint256 _amount) external;

    function unstake(uint256 _amount) external;

    function mintPortalEnergyToken(
        address _recipient,
        uint256 _amount
    ) external;

    function burnPortalEnergyToken(
        address _recipient,
        uint256 _amount
    ) external;

    function buyPortalEnergy(
        address _user,
        uint256 _amount,
        uint256 _minReceived,
        uint256 _deadline
    ) external;

    function sellPortalEnergy(
        address payable _receiver,
        uint256 _amount,
        uint256 _minReceivedPSM,
        uint256 _deadline,
        uint256 _mode,
        bytes calldata _actionData
    ) external;

    function addLiquidity(
        address _receiver,
        uint256 amountPSMDesired,
        uint256 amountWETHDesired,
        uint256 amountPSMMin,
        uint256 amountWETHMin,
        uint256 _deadline
    )
        external
        returns (uint256 amountPSM, uint256 amountWETH, uint256 liquidity);

    function addLiquidityETH(
        address _receiver,
        uint256 _amountPSMDesired,
        uint256 _amountPSMMin,
        uint256 _amountETHMin,
        uint256 _deadline
    )
        external
        payable
        returns (uint256 amountPSM, uint256 amountETH, uint256 liquidity);

    function removeLiquidity(
        address _receiver,
        uint256 _liquidity,
        uint256 _amountPSMMin,
        uint256 _amountWETHMin,
        uint256 _deadline
    ) external returns (uint256 amountPSM, uint256 amountWETH);

    function removeLiquidityETH(
        address _receiver,
        uint256 _liquidity,
        uint256 _amountPSMMin,
        uint256 _amountETHMin,
        uint256 _deadline
    ) external returns (uint256 amountPSM, uint256 amountETH);

    function getUpdateAccount(
        address _user,
        uint256 _amount
    )
        external
        view
        returns (address, uint256, uint256, uint256, uint256, uint256, uint256);

    function quoteforceUnstakeAll(
        address _user
    ) external view returns (uint256 portalEnergyTokenToBurn);

    function quoteBuyPortalEnergy(
        uint256 _amountInput
    ) external view returns (uint256);

    function quoteSellPortalEnergy(
        uint256 _amountInput
    ) external view returns (uint256);

    function quoteAddLiquidity(
        uint256 _amountADesired,
        uint256 _amountBDesired
    )
        external
        view
        returns (
            uint256 _amountPSMDesired,
            uint256 _amountWETHDesired,
            uint256 liquidity
        );

    function quoteRemoveLiquidity(
        uint256 _liquidity
    ) external view returns (uint256 amountA, uint256 amountB);
}
