// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

type RequestId is bytes32;
type SlotId is bytes32;

struct Request {
  address client;
  Ask ask;
  Content content;
  uint64 expiry; // amount of seconds since start of the request at which this request expires
  bytes32 nonce; // random nonce to differentiate between similar requests
}

struct Ask {
  uint256 proofProbability; // how often storage proofs are required
  uint256 reward; // amount of tokens paid per second per slot to hosts
  uint256 collateral; // amount of tokens required to be deposited by the hosts in order to fill the slot
  uint64 slots; // the number of requested slots
  uint64 slotSize; // amount of storage per slot (in number of bytes)
  uint64 duration; // how long content should be stored (in seconds)
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
  Free, // [default] not filled yet
  Filled, // host has filled slot
  Finished, // successfully completed
  Failed, // the request has failed
  Paid, // host has been paid
  Cancelled, // when request was cancelled then slot is cancelled as well
  Repair // when slot slot was forcible freed (host was kicked out from hosting the slot because of too many missed proofs) and needs to be repaired
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

  function maxPrice(Request memory request) internal pure returns (uint256) {
    return request.ask.slots * request.ask.duration * request.ask.reward;
  }
}
