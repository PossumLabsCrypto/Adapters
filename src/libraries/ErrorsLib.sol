// SPDX-License-Identifier: GPL-2.0-only
pragma solidity =0.8.19;

// ============================================
// ==          CUSTOM ERROR MESSAGES         ==
// ============================================
library ErrorsLib {
    error DeadlineExpired();
    error AccountDoesNotExist();
    error InsufficientToWithdraw();
    error InsufficientPEtokens();
    error InsufficientBalance();
    error InvalidOutput();
    error InvalidInput();
    error TradeTimelockActive();
}
