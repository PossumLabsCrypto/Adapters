// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;

interface IRamsesPair {
    function burn(address to) external returns (uint256 amount0, uint256 amount1);

    function mint(address to) external returns (uint256 liquidity);

    function getReserves() external view returns (uint256 _reserve0, uint256 _reserve1, uint256 _blockTimestampLast);
}

interface IRamsesFactory {
    function getPair(address tokenA, address token, bool stable) external view returns (address);

    function createPair(address tokenA, address tokenB, bool stable) external returns (address pair);
}

interface IRamsesRouter {
    function addLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);

    function quoteAddLiquidity(
        address _tokenA,
        address _tokenB,
        bool _stable,
        uint256 _amountADesired,
        uint256 _amountBDesired
    ) external view returns (uint256 amountA, uint256 amountB, uint256 liquidity);

    function quoteRemoveLiquidity(address _tokenA, address _tokenB, bool _stable, uint256 _liquidity)
        external
        view
        returns (uint256 amountA, uint256 amountB);
}
