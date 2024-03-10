// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.19;

interface IWETH {
    function deposit() external payable;

    function withdrawTo(address, uint256) external;
}
