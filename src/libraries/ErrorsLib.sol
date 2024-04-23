// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.19;

// ============================================
// ==          CUSTOM ERROR MESSAGES         ==
// ============================================
library ErrorsLib {
    error DeadlineExpired();
    error DurationLocked();
    error DurationTooLow();
    error EmptyAccount();
    error InsufficientBalance();
    error InsufficientReceived();
    error InsufficientStakeBalance();
    error InsufficientToWithdraw();
    error InvalidAddress();
    error InvalidAmount();
    error InvalidConstructor();
    error NativeTokenNotAllowed();
    error TokenExists();
    error FailedToSendNativeToken();

    error InvalidMode();
    error InsufficientReserves();
    error notOwner();
    error isTimeLocked();
    error isMigrating();
    error notMigrating();
    error hasMigrated();
    error migrationVotePending();
    error notCalledByDestination();
    error TokenNotSet();
}
