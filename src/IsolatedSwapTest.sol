// SPDX-License-Identifier: GPL-2.0-only
pragma solidity =0.8.19;

interface IRamsesFactory {
    function getPair(address tokenA, address token, bool stable) external view returns (address);
}

interface IRamsesPair {
    function mint(address to) external returns (uint256 liquidity);

    function getReserves() external view returns (uint256 _reserve0, uint256 _reserve1, uint256 _blockTimestampLast);
}

interface IAggregationExecutor {
    /// @notice propagates information about original msg.sender and executes arbitrary data
    function execute(address msgSender) external payable returns (uint256); // 0x4b64e492
}

struct SwapDescription {
    address srcToken;
    address dstToken;
    address payable srcReceiver;
    address payable dstReceiver;
    uint256 amount;
    uint256 minReturnAmount;
    uint256 flags;
}

interface IAggregationRouterV6 {
    /// @notice Performs a swap, delegating all calls encoded in `data` to `_executor`.
    /// @dev router keeps 1 wei of every token on the contract balance for gas optimisations reasons. This affects first swap of every token by leaving 1 wei on the contract.
    /// @param executor Aggregation executor that executes calls described in `data`
    /// @param desc Swap description
    /// @param data Encoded calls that `caller` should execute in between of swaps
    /// @return returnAmount_ Resulting token amount
    /// @return spentAmount_ Source token amount
    function swap(IAggregationExecutor executor, SwapDescription calldata desc, bytes calldata data)
        external
        payable
        returns (uint256 returnAmount_, uint256 spentAmount_);
}

interface IERC20 {
    function approve(address addr, uint256 amount) external;
    function transfer(address receiver, uint256 amount) external;
    function transferFrom(address sender, address receiver, uint256 amount) external;
    function balanceOf(address addr) external returns (uint256);
}

struct SwapData {
    address receiver;
    uint256 psmAmount;
    bytes actionData;
}

error InvalidAmount();
error InsufficientReserves();

contract IsolatedSwapTest {
    constructor() {}

    uint256 constant MAX_UINT = 115792089237316195423570985008687907853269984665640564039457584007913129639935;
    address constant WETH_ADDRESS = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address constant PSM_TOKEN_ADDRESS = 0x17A8541B82BF67e10B0874284b4Ae66858cb1fd5;
    address constant ONE_INCH_V6_AGGREGATION_ROUTER_CONTRACT_ADDRESS = 0x111111125421cA6dc452d289314280a0f8842A65;
    address constant RAMSES_FACTORY_ADDRESS = 0xAAA20D08e59F6561f242b08513D36266C5A29415;

    IERC20 PSM = IERC20(PSM_TOKEN_ADDRESS);
    IERC20 constant WETH = IERC20(WETH_ADDRESS);

    IAggregationRouterV6 public constant ONE_INCH_V6_AGGREGATION_ROUTER =
        IAggregationRouterV6(ONE_INCH_V6_AGGREGATION_ROUTER_CONTRACT_ADDRESS); // Interface of 1inchRouter
    IRamsesFactory public constant RAMSES_FACTORY = IRamsesFactory(RAMSES_FACTORY_ADDRESS); // Interface of Ramses Factory

    function resuceToken(address _token) external {
        uint256 balance = IERC20(_token).balanceOf(address(this));
        IERC20(_token).transfer(msg.sender, balance);
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
        bytes calldata _actionData,
        uint256 _minPSMForLiquidiy,
        uint256 _minWethForLiquidiy
    ) external {
        /// @dev Assemble the swap data from API to use 1Inch Router
        SwapData memory swap = SwapData(_recipient, _amountInputPE, _actionData);

        // use the variables to avoid warning
        _minReceived = 1;
        _deadline = block.timestamp;

        // transfer PSM from caller to contract to then be used in swap
        PSM.transferFrom(msg.sender, address(this), _amountInputPE);

        /// @dev Add liquidity, or exchange on 1Inch and transfer output token
        if (_mode == 1) {
            addLiquidity(swap, _minPSMForLiquidiy, _minWethForLiquidiy);
        } else {
            swapOneInch(swap, false);
        }
    }

    /// @dev This internal function assembles the swap via the 1Inch router from API data
    function swapOneInch(SwapData memory _swap, bool _forLiquidity) internal {
        /// @dev decode the data for getting _executor, _description, _data.
        (address _executor, SwapDescription memory _description, bytes memory _data) =
            abi.decode(_swap.actionData, (address, SwapDescription, bytes));

        /// @dev Swap via the 1Inch Router
        /// @dev Allowance is increased in separate function to save gas
        (, uint256 spentAmount_) =
            ONE_INCH_V6_AGGREGATION_ROUTER.swap(IAggregationExecutor(_executor), _description, _data);

        /// @dev Send remaining tokens back to user if not called from addLiquidity
        if (!_forLiquidity) {
            uint256 remainAmount = _swap.psmAmount - spentAmount_;
            if (remainAmount > 0) PSM.transfer(msg.sender, remainAmount);
        }
    }

    /// @dev Given some amount of an asset and pair reserves, returns an equivalent amount of the other asset
    /// @dev This is used to determine how many assets must be supplied to a Pool2 LP
    function quoteLiquidity(uint256 amountA, uint256 reserveA, uint256 reserveB)
        internal
        pure
        returns (uint256 amountB)
    {
        if (amountA == 0) revert InvalidAmount();
        if (reserveA == 0 || reserveB == 0) {
            revert InsufficientReserves();
        }

        amountB = (amountA * reserveB) / reserveA;
    }

    /// @dev This function is called when mode = 1 in sellPortalEnergy
    /// @dev Sell some amount of PSM for WETH, then pair in Ramses Pool2
    function addLiquidity(SwapData memory _swap, uint256 _minPSMForLiquidiy, uint256 _minWethForLiquidiy) internal {
        swapOneInch(_swap, true);

        /// @dev This contract shouldn't hold any token, so we pass all tokens.
        uint256 PSMBalance = PSM.balanceOf(address(this));
        uint256 WETHBalance = WETH.balanceOf(address(this));

        /// @dev Get the correct amount of PSM and WETH to add to the Ramses Pool2
        (uint256 amountPSM, uint256 amountWETH) =
            _addLiquidity(PSMBalance, WETHBalance, _minPSMForLiquidiy, _minWethForLiquidiy);

        /// @dev Get the pair address of the ETH/PSM Pool2 LP
        address pair = RAMSES_FACTORY.getPair(PSM_TOKEN_ADDRESS, WETH_ADDRESS, false);

        /// @dev Transfer tokens to the LP and mint LP shares to the user
        /// @dev Uses the low level mint function of the pair implementation
        /// @dev Assumes that the pair already exists which is the case
        PSM.transfer(pair, amountPSM);
        WETH.transfer(pair, amountWETH);
        IRamsesPair(pair).mint(_swap.receiver);
        if (PSM.balanceOf(address(this)) > 0) PSM.transfer(_swap.receiver, PSM.balanceOf(address(this)));
        if (WETH.balanceOf(address(this)) > 0) WETH.transfer(_swap.receiver, WETH.balanceOf(address(this)));
    }

    /// @dev Calculate the required token amounts of PSM and WETH to add liquidity
    function _addLiquidity(uint256 amountADesired, uint256 amountBDesired, uint256 amountAMin, uint256 amountBMin)
        internal
        view
        returns (uint256 amountA, uint256 amountB)
    {
        if (amountADesired < amountAMin) revert InvalidAmount();
        if (amountBDesired < amountBMin) revert InvalidAmount();

        /// @dev Get the pair address
        address pair = RAMSES_FACTORY.getPair(PSM_TOKEN_ADDRESS, WETH_ADDRESS, false);

        /// @dev Get the reserves of the pair
        (uint256 reserveA, uint256 reserveB,) = IRamsesPair(pair).getReserves();

        /// @dev Calculate how much PSM and WETH are required
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBOptimal = quoteLiquidity(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                if (amountBOptimal < amountBMin) {
                    revert InvalidAmount();
                }
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = quoteLiquidity(amountBDesired, reserveB, reserveA);
                if (amountAOptimal > amountADesired) {
                    revert InvalidAmount();
                }
                if (amountAOptimal < amountAMin) {
                    revert InvalidAmount();
                }
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    /// @dev Increase token spending allowances of Adapter holdings
    function increaseAllowances() external {
        PSM.approve(ONE_INCH_V6_AGGREGATION_ROUTER_CONTRACT_ADDRESS, MAX_UINT);
    }
}
