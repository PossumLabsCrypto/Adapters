// SPDX-License-Identifier: GPL-2.0-only
pragma solidity =0.8.19;

library ErrorsLib {
    /// @notice Thrown when zero amount is passed as input.
    string internal constant ZeroAmount = "zero amount";

    /// @notice Thrown when a zero address is passed as input.
    string internal constant ZeroAddress = "zero address";

    //
    string internal constant InsufficientToWithdraw = "insufficient to withdraw";
    string internal constant AccountDoesNotExist = "account doesn't exist";

    string internal constant InsufficientPEtokens = "insufficient energy tokens";

    string internal constant DeadlineExpired = "dead line expired";

    string internal constant TradeTimelockActive = "trade timelock active";

    string internal constant InsufficientBalance = "insufficient balance";

    string internal constant InvalidOutput = "invalid output";
}
