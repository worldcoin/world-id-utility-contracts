// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @title DateTimeLib
 * @notice Minimal UTC date/time helpers used for calendar-month period arithmetic.
 */
library DateTimeLib {
    uint256 internal constant SECONDS_PER_DAY = 24 * 60 * 60;
    int256 internal constant OFFSET19700101 = 2440588;

    /**
     * @notice Checks whether a timestamp is exactly at a UTC month boundary.
     * @param timestamp The timestamp to validate.
     * @return True if `timestamp` is `YYYY-MM-01 00:00:00 UTC`.
     */
    function isUtcMonthStart(uint256 timestamp) internal pure returns (bool) {
        if (timestamp % SECONDS_PER_DAY != 0) return false;

        (, , uint256 day) = daysToDate(timestamp / SECONDS_PER_DAY);
        return day == 1;
    }

    /**
     * @notice Converts a Unix timestamp to UTC year and month components.
     * @param timestamp The Unix timestamp in seconds.
     * @return year The UTC year.
     * @return month The UTC month in range [1..12].
     */
    function timestampToYearMonth(uint256 timestamp) internal pure returns (uint256 year, uint256 month) {
        (year, month,) = daysToDate(timestamp / SECONDS_PER_DAY);
    }

    /**
     * @notice Converts year-month to a monotonic month index.
     * @param year The UTC year.
     * @param month The UTC month in range [1..12].
     * @return The zero-based month index used for period arithmetic.
     */
    function monthIndex(uint256 year, uint256 month) internal pure returns (uint256) {
        return year * 12 + (month - 1);
    }

    /**
     * @notice Converts a monotonic month index back to year-month components.
     * @param index The zero-based month index.
     * @return year The UTC year.
     * @return month The UTC month in range [1..12].
     */
    function indexToYearMonth(uint256 index) internal pure returns (uint256 year, uint256 month) {
        year = index / 12;
        month = (index % 12) + 1;
    }

    /**
     * @notice Returns the exclusive end timestamp of a target period.
     * @dev End timestamp is the first second of the month after `period`.
     * @param periodStartTimestamp Period 0 start timestamp (must be UTC month start).
     * @param period The target period index.
     * @return The UTC timestamp for the period end boundary.
     */
    function periodEndTimestamp(uint64 periodStartTimestamp, uint32 period) internal pure returns (uint256) {
        (uint256 baseYear, uint256 baseMonth) = timestampToYearMonth(periodStartTimestamp);
        uint256 nextMonthIdx = monthIndex(baseYear, baseMonth) + uint256(period) + 1;
        (uint256 endYear, uint256 endMonth) = indexToYearMonth(nextMonthIdx);
        return daysFromDate(endYear, endMonth, 1) * SECONDS_PER_DAY;
    }

    /**
     * @notice Converts a UTC date to days since Unix epoch.
     * @dev Uses the Julian day conversion algorithm.
     * @param year The UTC year.
     * @param month The UTC month in range [1..12].
     * @param day The UTC day in range [1..31].
     * @return _days Number of days since 1970-01-01 UTC.
     */
    function daysFromDate(uint256 year, uint256 month, uint256 day) internal pure returns (uint256 _days) {
        int256 _year = int256(year);
        int256 _month = int256(month);
        int256 _day = int256(day);

        int256 __days = _day - 32075 + 1461 * (_year + 4800 + (_month - 14) / 12) / 4
            + 367 * (_month - 2 - ((_month - 14) / 12) * 12) / 12 - 3 * ((_year + 4900 + (_month - 14) / 12) / 100) / 4
            - OFFSET19700101;

        _days = uint256(__days);
    }

    /**
     * @notice Converts days since Unix epoch into a UTC date.
     * @dev Uses the Julian day conversion algorithm.
     * @param _days Number of days since 1970-01-01 UTC.
     * @return year The UTC year.
     * @return month The UTC month in range [1..12].
     * @return day The UTC day in range [1..31].
     */
    function daysToDate(uint256 _days) internal pure returns (uint256 year, uint256 month, uint256 day) {
        int256 __days = int256(_days);

        int256 L = __days + 68569 + OFFSET19700101;
        int256 N = 4 * L / 146097;
        L = L - (146097 * N + 3) / 4;
        int256 _year = 4000 * (L + 1) / 1461001;
        L = L - 1461 * _year / 4 + 31;
        int256 _month = 80 * L / 2447;
        int256 _day = L - 2447 * _month / 80;
        L = _month / 11;
        _month = _month + 2 - 12 * L;
        _year = 100 * (N - 49) + _year + L;

        year = uint256(_year);
        month = uint256(_month);
        day = uint256(_day);
    }
}
