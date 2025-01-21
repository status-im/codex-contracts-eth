// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

contract Periods {
  type Period is uint64;

  uint64 internal immutable _secondsPerPeriod;

  constructor(uint64 secondsPerPeriod) {
    _secondsPerPeriod = secondsPerPeriod;
  }

  function _periodOf(uint64 timestamp) internal view returns (Period) {
    return Period.wrap(timestamp / _secondsPerPeriod);
  }

  function _blockPeriod() internal view returns (Period) {
    return _periodOf(uint64(block.timestamp));
  }

  function _nextPeriod(Period period) internal pure returns (Period) {
    return Period.wrap(Period.unwrap(period) + 1);
  }

  function _periodStart(Period period) internal view returns (uint64) {
    return Period.unwrap(period) * _secondsPerPeriod;
  }

  function _periodEnd(Period period) internal view returns (uint64) {
    return _periodStart(_nextPeriod(period));
  }

  function _isBefore(Period a, Period b) internal pure returns (bool) {
    return Period.unwrap(a) < Period.unwrap(b);
  }

  function _isAfter(Period a, Period b) internal pure returns (bool) {
    return _isBefore(b, a);
  }
}
