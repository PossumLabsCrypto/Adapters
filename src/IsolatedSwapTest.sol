// SPDX-License-Identifier: GPL-2.0-only
pragma solidity =0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IWETH} from "./interfaces/IWETH.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAdapterV1, Account, SwapData} from "./interfaces/IAdapterV1.sol";
import {ErrorsLib} from "./libraries/ErrorsLib.sol";
import {IOneInchV5AggregationRouter, SwapDescription} from "./interfaces/IOneInchV5AggregationRouter.sol";
import {IRamsesFactory, IRamsesRouter, IRamsesPair} from "./interfaces/IRamses.sol";

contract IsolatedSwapTest {
    constructor() {}

    using SafeERC20 for IERC20;

    uint256 constant MAX_UINT =
        115792089237316195423570985008687907853269984665640564039457584007913129639935;
    address constant WETH_ADDRESS = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address constant PSM_TOKEN_ADDRESS =
        0x17A8541B82BF67e10B0874284b4Ae66858cb1fd5;
    address constant ONE_INCH_V5_AGGREGATION_ROUTER_CONTRACT_ADDRESS =
        0x1111111254EEB25477B68fb85Ed929f73A960582;
    address constant RAMSES_FACTORY_ADDRESS =
        0xAAA20D08e59F6561f242b08513D36266C5A29415;
    address constant RAMSES_ROUTER_ADDRESS =
        0xAAA87963EFeB6f7E0a2711F397663105Acb1805e;

    IERC20 PSM = IERC20(PSM_TOKEN_ADDRESS);
    IERC20 constant WETH = IERC20(WETH_ADDRESS);

    IOneInchV5AggregationRouter public constant ONE_INCH_V5_AGGREGATION_ROUTER =
        IOneInchV5AggregationRouter(
            ONE_INCH_V5_AGGREGATION_ROUTER_CONTRACT_ADDRESS
        ); // Interface of 1inchRouter
    IRamsesFactory public constant RAMSES_FACTORY =
        IRamsesFactory(RAMSES_FACTORY_ADDRESS); // Interface of Ramses Factory
    IRamsesRouter public constant RAMSES_ROUTER =
        IRamsesRouter(RAMSES_ROUTER_ADDRESS); // Interface of Ramses Router

    function resuceToken(address _token) external {
        uint256 balance = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(msg.sender, balance);
    }

    /////////////////////////
    /////////////////////////
    // This function takes PSM from caller, then triggers 1Inch swap or LP pooling
    // Amount of PSM taken is _amountInputPE
    function sellPortalEnergy(
        address payable _recipient,
        uint256 _amountInputPE,
        uint256 _minReceived,
        uint256 _deadline,
        uint256 _mode,
        bytes calldata _actionData
    ) external {
        if (_mode > 2) revert ErrorsLib.InvalidMode();

        /// @dev Assemble the swap data from API to use 1Inch Router
        SwapData memory swap = SwapData(
            _recipient,
            _amountInputPE,
            _actionData
        );

        // use the variables to avoid warning
        _minReceived = 1;
        _deadline = block.timestamp;

        // transfer PSM from caller to contract to then be used in swap
        PSM.safeTransferFrom(msg.sender, address(this), _amountInputPE);

        /// @dev Add liquidity, or exchange on 1Inch and transfer output token
        if (_mode == 1) {
            addLiquidity(swap);
        } else {
            swapOneInch(swap, false);
        }
    }

    /// @dev This internal function assembles the swap via the 1Inch router from API data
    function swapOneInch(SwapData memory _swap, bool _forLiquidity) internal {
        /// @dev decode the data for getting _executor, _description, _data.
        (
            address _executor,
            SwapDescription memory _description,
            bytes memory _data,
            ,

        ) = abi.decode(
                _swap.actionData,
                (address, SwapDescription, bytes, uint256, uint256)
            );

        /// @dev Swap via the 1Inch Router
        /// @dev Allowance is increased in separate function to save gas
        (, uint256 spentAmount_) = ONE_INCH_V5_AGGREGATION_ROUTER.swap(
            _executor,
            _description,
            "",
            _data
        );

        /// @dev Send remaining tokens back to user if not called from addLiquidity
        if (!_forLiquidity) {
            uint256 remainAmount = _swap.psmAmount - spentAmount_;
            if (remainAmount > 0) PSM.safeTransfer(msg.sender, remainAmount);
        }
    }

    /// @dev Given some amount of an asset and pair reserves, returns an equivalent amount of the other asset
    /// @dev This is used to determine how many assets must be supplied to a Pool2 LP
    function quoteLiquidity(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB
    ) internal pure returns (uint256 amountB) {
        if (amountA == 0) revert ErrorsLib.InvalidAmount();
        if (reserveA == 0 || reserveB == 0)
            revert ErrorsLib.InsufficientReserves();

        amountB = (amountA * reserveB) / reserveA;
    }

    /// @dev This function is called when mode = 1 in sellPortalEnergy
    /// @dev Sell some amount of PSM for WETH, then pair in Ramses Pool2
    function addLiquidity(SwapData memory _swap) internal {
        swapOneInch(_swap, true);

        /// @dev Decode the swap data for getting minPSM and minWETH.
        (, , , uint256 minPSM, uint256 minWeth) = abi.decode(
            _swap.actionData,
            (address, SwapDescription, bytes, uint256, uint256)
        );

        /// @dev This contract shouldn't hold any token, so we pass all tokens.
        uint256 PSMBalance = PSM.balanceOf(address(this));
        uint256 WETHBalance = WETH.balanceOf(address(this));

        /// @dev Get the correct amount of PSM and WETH to add to the Ramses Pool2
        (uint256 amountPSM, uint256 amountWETH) = _addLiquidity(
            PSMBalance,
            WETHBalance,
            minPSM,
            minWeth
        );

        /// @dev Get the pair address of the ETH/PSM Pool2 LP
        address pair = RAMSES_FACTORY.getPair(
            PSM_TOKEN_ADDRESS,
            WETH_ADDRESS,
            false
        );

        /// @dev Transfer tokens to the LP and mint LP shares to the user
        /// @dev Uses the low level mint function of the pair implementation
        /// @dev Assumes that the pair already exists which is the case
        PSM.safeTransfer(pair, amountPSM);
        WETH.safeTransfer(pair, amountWETH);
        IRamsesPair(pair).mint(_swap.recevier);
    }

    /// @dev Calculate the required token amounts of PSM and WETH to add liquidity
    function _addLiquidity(
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal view returns (uint256 amountA, uint256 amountB) {
        if (amountADesired < amountAMin) revert ErrorsLib.InvalidAmount();
        if (amountBDesired < amountBMin) revert ErrorsLib.InvalidAmount();

        /// @dev Get the pair address
        address pair = RAMSES_FACTORY.getPair(
            PSM_TOKEN_ADDRESS,
            WETH_ADDRESS,
            false
        );

        /// @dev Get the reserves of the pair
        (uint256 reserveA, uint256 reserveB, ) = IRamsesPair(pair)
            .getReserves();

        /// @dev Calculate how much PSM and WETH are required
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBOptimal = quoteLiquidity(
                amountADesired,
                reserveA,
                reserveB
            );
            if (amountBOptimal <= amountBDesired) {
                if (amountBOptimal < amountBMin)
                    revert ErrorsLib.InvalidAmount();
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = quoteLiquidity(
                    amountBDesired,
                    reserveB,
                    reserveA
                );
                if (amountAOptimal > amountADesired)
                    revert ErrorsLib.InvalidAmount();
                if (amountAOptimal < amountAMin)
                    revert ErrorsLib.InvalidAmount();
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    /// @dev Increase token spending allowances of Adapter holdings
    function increaseAllowances() external {
        PSM.approve(ONE_INCH_V5_AGGREGATION_ROUTER_CONTRACT_ADDRESS, MAX_UINT);
    }
}
