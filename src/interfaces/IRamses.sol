// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.19;

interface IRamsesPair {
    function mint(address to) external returns (uint256 liquidity);

    function getReserves() external view returns (uint256 _reserve0, uint256 _reserve1, uint256 _blockTimestampLast);
}
