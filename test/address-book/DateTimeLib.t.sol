// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {DateTimeLib} from "../../src/address-book/libraries/DateTimeLib.sol";

contract DateTimeLibHarness {
    function isUtcMonthStart(uint256 timestamp) external pure returns (bool) {
        return DateTimeLib.isUtcMonthStart(timestamp);
    }

    function timestampToYearMonth(uint256 timestamp) external pure returns (uint256 year, uint256 month) {
        return DateTimeLib.timestampToYearMonth(timestamp);
    }

    function monthIndex(uint256 year, uint256 month) external pure returns (uint256) {
        return DateTimeLib.monthIndex(year, month);
    }

    function indexToYearMonth(uint256 index) external pure returns (uint256 year, uint256 month) {
        return DateTimeLib.indexToYearMonth(index);
    }

    function periodEndTimestamp(uint64 periodStartTimestamp, uint32 period) external pure returns (uint256) {
        return DateTimeLib.periodEndTimestamp(periodStartTimestamp, period);
    }
}

contract DateTimeLibTest is Test {
    uint64 internal constant JAN_2025 = 1_735_689_600; // 2025-01-01 00:00:00 UTC
    uint64 internal constant FEB_2025 = 1_738_368_000; // 2025-02-01 00:00:00 UTC
    uint64 internal constant MAR_2025 = 1_740_787_200; // 2025-03-01 00:00:00 UTC
    uint64 internal constant APR_2025 = 1_743_465_600; // 2025-04-01 00:00:00 UTC
    uint64 internal constant JAN_2026 = 1_767_225_600; // 2026-01-01 00:00:00 UTC

    DateTimeLibHarness internal harness;

    function setUp() public {
        harness = new DateTimeLibHarness();
    }

    function testIsUtcMonthStart() public view {
        assertTrue(harness.isUtcMonthStart(JAN_2025));
        assertTrue(harness.isUtcMonthStart(FEB_2025));
        assertFalse(harness.isUtcMonthStart(JAN_2025 + 1));
        assertFalse(harness.isUtcMonthStart(JAN_2025 + 1 days));
    }

    function testTimestampToYearMonthKnownValues() public view {
        (uint256 y1, uint256 m1) = harness.timestampToYearMonth(JAN_2025);
        assertEq(y1, 2025);
        assertEq(m1, 1);

        (uint256 y2, uint256 m2) = harness.timestampToYearMonth(MAR_2025);
        assertEq(y2, 2025);
        assertEq(m2, 3);
    }

    function testPeriodEndTimestampKnownValues() public view {
        assertEq(harness.periodEndTimestamp(JAN_2025, 0), FEB_2025);
        assertEq(harness.periodEndTimestamp(JAN_2025, 1), MAR_2025);
        assertEq(harness.periodEndTimestamp(JAN_2025, 2), APR_2025);
        assertEq(harness.periodEndTimestamp(JAN_2025, 11), JAN_2026);
    }

    function testFuzzMonthIndexRoundTrip(uint256 year, uint256 month) public view {
        year = bound(year, 1970, 1_000_000);
        month = bound(month, 1, 12);

        uint256 index = harness.monthIndex(year, month);
        (uint256 roundTripYear, uint256 roundTripMonth) = harness.indexToYearMonth(index);

        assertEq(roundTripYear, year);
        assertEq(roundTripMonth, month);
    }

    function testFuzzPeriodEndTimestampIsMonthStartAndMonotonic(uint32 period) public view {
        uint32 p = uint32(bound(uint256(period), 0, 2400)); // up to 200 years
        uint256 end = harness.periodEndTimestamp(JAN_2025, p);
        assertTrue(harness.isUtcMonthStart(end));

        if (p == 0) {
            assertEq(end, FEB_2025);
        } else {
            uint256 prev = harness.periodEndTimestamp(JAN_2025, p - 1);
            assertGt(end, prev);

            uint256 delta = end - prev;
            assertGe(delta, 28 days);
            assertLe(delta, 31 days);
        }
    }

    function testPeriodEndTimestampAtMaxPeriodDoesNotOverflow() public view {
        uint256 end = harness.periodEndTimestamp(JAN_2025, type(uint32).max);
        assertTrue(harness.isUtcMonthStart(end));
        assertGt(end, JAN_2025);
    }
}
