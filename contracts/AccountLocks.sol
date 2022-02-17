// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// Implements account locking. The main goal of this design is to allow
/// unlocking of multiple accounts in O(1). To achieve this we keep a list of
/// locks per account. Every time an account is locked or unlocked, this list is
/// checked for inactive locks, which are subsequently removed. To ensure that
/// this operation does not become too expensive in gas costs, a maximum amount
/// of active locks per account is enforced.
contract AccountLocks {
  uint256 public constant MAX_LOCKS_PER_ACCOUNT = 128;

  mapping(bytes32 => Lock) private locks;
  mapping(address => Account) private accounts;

  /// Creates a lock that can be used to lock accounts. The id needs to be
  /// unique and collision resistant. The expiry time is given in unix time.
  function _createLock(bytes32 id, uint256 expiry) internal {
    require(locks[id].owner == address(0), "Lock already exists");
    locks[id] = Lock(msg.sender, expiry, false);
  }

  /// Attaches a lock to an account. Only when the lock is unlocked or expires
  /// can the account be unlocked again.
  /// Calling this function triggers a cleanup of inactive locks, making this
  /// an O(N) operation, where N = MAX_LOCKS_PER_ACCOUNT.
  function _lock(address account, bytes32 lockId) internal {
    require(locks[lockId].owner != address(0), "Lock does not exist");
    bytes32[] storage accountLocks = accounts[account].locks;
    removeInactiveLocks(accountLocks);
    require(accountLocks.length < MAX_LOCKS_PER_ACCOUNT, "Max locks reached");
    accountLocks.push(lockId);
  }

  /// Unlocks a lock, thereby freeing any accounts that are attached to this
  /// lock. This is an O(1) operation. Only the party that created the lock is
  /// allowed to unlock it.
  function _unlock(bytes32 lockId) internal {
    Lock storage lock = locks[lockId];
    require(lock.owner != address(0), "Lock does not exist");
    require(lock.owner == msg.sender, "Only lock creator can unlock");
    lock.unlocked = true;
  }

  /// Unlocks an account. This will fail if there are any active locks attached
  /// to this account.
  /// Calling this function triggers a cleanup of inactive locks, making this
  /// an O(N) operation, where N = MAX_LOCKS_PER_ACCOUNT.
  function _unlockAccount() internal {
    bytes32[] storage accountLocks = accounts[msg.sender].locks;
    removeInactiveLocks(accountLocks);
    require(accountLocks.length == 0, "Account locked");
  }

  function removeInactiveLocks(bytes32[] storage lockIds) private {
    uint256 index = 0;
    while (true) {
      if (index >= lockIds.length) {
        return;
      }
      if (isInactive(locks[lockIds[index]])) {
        lockIds[index] = lockIds[lockIds.length - 1];
        lockIds.pop();
      } else {
        index++;
      }
    }
  }

  function isInactive(Lock storage lock) private view returns (bool) {
    // solhint-disable-next-line not-rely-on-time
    return lock.unlocked || lock.expiry <= block.timestamp;
  }

  struct Lock {
    address owner;
    uint256 expiry;
    bool unlocked;
  }

  struct Account {
    bytes32[] locks;
  }
}