// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Stakes {

  IERC20 private token;
  mapping(address=>uint) private stakes;
  mapping(address=>uint) private locks;

  constructor(IERC20 _token) {
    token = _token;
  }

  function stake(address account) public view returns (uint) {
    return stakes[account];
  }

  function increase(uint amount) public {
    token.transferFrom(msg.sender, address(this), amount);
    stakes[msg.sender] += amount;
  }

  function withdraw() public {
    require(locks[msg.sender] == 0, "Stake locked");
    token.transfer(msg.sender, stakes[msg.sender]);
  }

  function _lock(address account) internal {
    locks[account] += 1;
  }

  function _unlock(address account) internal {
    require(locks[account] > 0, "Stake already unlocked");
    locks[account] -= 1;
  }
}
