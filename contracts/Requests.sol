// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

type RequestId is bytes32;
type SlotId is bytes32;

struct Request {
  address client;
  Ask ask;
  Content content;
  uint256 expiry; // amount of seconds since start of the request at which this request expires
  bytes32 nonce; // random nonce to differentiate between similar requests
  // Percentage of total time before expiry that all addresses are eligible to
  // reserve a slot. Total time is the duration between request creation and
  // expiry. Higher number means faster expansion. Valid range is [0, 100],
  // where 100 means all addresses will be eligible at request creation, and 0
  // indicates that all addresses will be eligible at the time of expiry.
  uint8 expansionRate;
}

struct Ask {
  uint64 slots; // the number of requested slots
  uint256 slotSize; // amount of storage per slot (in number of bytes)
  uint256 duration; // how long content should be stored (in seconds)
  uint256 proofProbability; // how often storage proofs are required
  uint256 reward; // amount of tokens paid per second per slot to hosts
  uint256 collateral; // amount of tokens required to be deposited by the hosts in order to fill the slot
  uint64 maxSlotLoss; // Max slots that can be lost without data considered to be lost
}

struct Content {
  string cid; // content id, used to download the dataset
  bytes32 merkleRoot; // merkle root of the dataset, used to verify storage proofs
}

enum RequestState {
  New, // [default] waiting to fill slots
  Started, // all slots filled, accepting regular proofs
  Cancelled, // not enough slots filled before expiry
  Finished, // successfully completed
  Failed // too many nodes have failed to provide proofs, data lost
}

enum SlotState {
  Free, // [default] not filled yet, or host has vacated the slot
  Filled, // host has filled slot
  Finished, // successfully completed
  Failed, // the request has failed
  Paid, // host has been paid
  Cancelled // when request was cancelled then slot is cancelled as well
}

library Requests {
  function id(Request memory request) internal pure returns (RequestId) {
    return RequestId.wrap(keccak256(abi.encode(request)));
  }

  function slotId(
    RequestId requestId,
    uint256 slotIndex
  ) internal pure returns (SlotId) {
    return SlotId.wrap(keccak256(abi.encode(requestId, slotIndex)));
  }

  function toRequestIds(
    bytes32[] memory ids
  ) internal pure returns (RequestId[] memory result) {
    // solhint-disable-next-line no-inline-assembly
    assembly {
      result := ids
    }
  }

  function toSlotIds(
    bytes32[] memory ids
  ) internal pure returns (SlotId[] memory result) {
    // solhint-disable-next-line no-inline-assembly
    assembly {
      result := ids
    }
  }

  function pricePerSlot(
    Request memory request
  ) internal pure returns (uint256) {
    return request.ask.duration * request.ask.reward;
  }

  function price(Request memory request) internal pure returns (uint256) {
    return request.ask.slots * pricePerSlot(request);
  }
}
