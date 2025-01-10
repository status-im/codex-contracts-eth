// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./Requests.sol";
import "./Configuration.sol";

abstract contract SlotReservations {
  using EnumerableSet for EnumerableSet.AddressSet;
  error SlotReservations_ReservationNotAllowed();

  mapping(SlotId => EnumerableSet.AddressSet) internal _reservations;
  SlotReservationsConfig private _config;

  constructor(SlotReservationsConfig memory config) {
    _config = config;
  }

  function _slotIsFree(SlotId slotId) internal view virtual returns (bool);

  function reserveSlot(RequestId requestId, uint64 slotIndex) public {
    if (!canReserveSlot(requestId, slotIndex))
      revert SlotReservations_ReservationNotAllowed();

    SlotId slotId = Requests.slotId(requestId, slotIndex);
    _reservations[slotId].add(msg.sender);

    if (_reservations[slotId].length() == _config.maxReservations) {
      emit SlotReservationsFull(requestId, slotIndex);
    }
  }

  function canReserveSlot(
    RequestId requestId,
    uint64 slotIndex
  ) public view returns (bool) {
    address host = msg.sender;
    SlotId slotId = Requests.slotId(requestId, slotIndex);
    return
      // TODO: add in check for address inside of expanding window
      _slotIsFree(slotId) &&
      (_reservations[slotId].length() < _config.maxReservations) &&
      (!_reservations[slotId].contains(host));
  }

  event SlotReservationsFull(RequestId indexed requestId, uint64 slotIndex);
}
