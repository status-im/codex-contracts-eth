// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "./Configuration.sol";
import "./Requests.sol";
import "./Periods.sol";
import "./Groth16.sol";

/**
 * @title Proofs
 * @notice Abstract contract that handles proofs tracking, validation and reporting functionality
 */
abstract contract Proofs is Periods {
  error Proofs_InsufficientBlockHeight();
  error Proofs_InvalidProof();
  error Proofs_ProofAlreadySubmitted();
  error Proofs_PeriodNotEnded();
  error Proofs_ValidationTimedOut();
  error Proofs_ProofNotMissing();
  error Proofs_ProofNotRequired();
  error Proofs_ProofAlreadyMarkedMissing();

  ProofConfig private _config;
  IGroth16Verifier private _verifier;

  /**
   * Creation of the contract requires at least 256 mined blocks!
   * @param config Proving configuration
   */
  constructor(
    ProofConfig memory config,
    IGroth16Verifier verifier
  ) Periods(config.period) {
    if (block.number <= 256) {
      revert Proofs_InsufficientBlockHeight();
    }

    _config = config;
    _verifier = verifier;
  }

  mapping(SlotId => uint64) private _slotStarts;
  mapping(SlotId => uint64) private _missed;
  mapping(SlotId => uint256) private _probabilities;
  mapping(SlotId => mapping(Period => bool)) private _received;
  mapping(SlotId => mapping(Period => bool)) private _missing;

  function slotState(SlotId id) public view virtual returns (SlotState);

  /**
   * @return Number of missed proofs since Slot was Filled
   */
  function missingProofs(SlotId slotId) public view returns (uint64) {
    return _missed[slotId];
  }

  /**
   * @param slotId Slot's ID for which the proofs should be reset
   * @notice Resets the missing proofs counter to zero
   */
  function _resetMissingProofs(SlotId slotId) internal {
    _missed[slotId] = 0;
  }

  /**
   * @param id Slot's ID for which the proofs should be started to require
   * @param probability Integer which specifies the probability of how often the proofs will be required. Lower number means higher probability.
   * @notice Notes down the block's timestamp as Slot's starting time for requiring proofs
   *     and saves the required probability.
   */
  function _startRequiringProofs(SlotId id, uint256 probability) internal {
    _slotStarts[id] = uint64(block.timestamp);
    _probabilities[id] = probability;
  }

  /**
   * @param id Slot's ID for which the pointer should be calculated
   * @param period Period for which the pointer should be calculated
   * @return Uint8 pointer that is stable over current Period, ie an integer offset [0-255] of the last 256 blocks, pointing to a block that remains constant for the entire Period's duration.
   * @dev For more information see [timing of storage proofs](https://github.com/codex-storage/codex-research/blob/41c4b4409d2092d0a5475aca0f28995034e58d14/design/storage-proof-timing.md)
   */
  function _getPointer(SlotId id, Period period) internal view returns (uint8) {
    uint256 blockNumber = block.number % 256;
    uint256 periodNumber = (Period.unwrap(period) * _config.downtimeProduct) %
      256;
    uint256 idOffset = uint256(SlotId.unwrap(id)) % 256;
    uint256 pointer = (blockNumber + periodNumber + idOffset) % 256;
    return uint8(pointer);
  }

  /**
   * @param id Slot's ID for which the pointer should be calculated
   * @return Uint8 pointer that is stable over current Period, ie an integer offset [0-255] of the last 256 blocks, pointing to a block that remains constant for the entire Period's duration.
   * @dev For more information see [timing of storage proofs](https://github.com/codex-storage/codex-research/blob/41c4b4409d2092d0a5475aca0f28995034e58d14/design/storage-proof-timing.md)
   */
  function getPointer(SlotId id) public view returns (uint8) {
    return _getPointer(id, _blockPeriod());
  }

  /**
   * @param pointer Integer [0-255] that indicates an offset of the last 256 blocks, pointing to a block that remains constant for the entire Period's duration.
   * @return Challenge that should be used for generation of proofs
   */
  function _getChallenge(uint8 pointer) internal view returns (bytes32) {
    bytes32 hash = blockhash(block.number - 1 - pointer);
    assert(uint256(hash) != 0);
    return keccak256(abi.encode(hash));
  }

  /**
   * @param id Slot's ID for which the challenge should be calculated
   * @param period Period for which the challenge should be calculated
   * @return Challenge that should be used for generation of proofs
   */
  function _getChallenge(
    SlotId id,
    Period period
  ) internal view returns (bytes32) {
    return _getChallenge(_getPointer(id, period));
  }

  /**
   * @param id Slot's ID for which the challenge should be calculated
   * @return Challenge for current Period that should be used for generation of proofs
   */
  function getChallenge(SlotId id) public view returns (bytes32) {
    return _getChallenge(id, _blockPeriod());
  }

  /**
   * @param id Slot's ID for which the requirements are gathered. If the Slot's state is other than Filled, `false` is always returned.
   * @param period Period for which the requirements are gathered.
   */
  function _getProofRequirement(
    SlotId id,
    Period period
  ) internal view returns (bool isRequired, uint8 pointer) {
    SlotState state = slotState(id);
    Period start = _periodOf(_slotStarts[id]);
    if (state != SlotState.Filled || !_isAfter(period, start)) {
      return (false, 0);
    }
    pointer = _getPointer(id, period);
    bytes32 challenge = _getChallenge(pointer);

    /// Scaling of the probability according the downtime configuration
    /// See: https://github.com/codex-storage/codex-research/blob/41c4b4409d2092d0a5475aca0f28995034e58d14/design/storage-proof-timing.md#pointer-downtime
    uint256 probability = (_probabilities[id] * (256 - _config.downtime)) / 256;
    isRequired = probability == 0 || uint256(challenge) % probability == 0;
  }

  /**
   * See isProofRequired
   */
  function _isProofRequired(
    SlotId id,
    Period period
  ) internal view returns (bool) {
    bool isRequired;
    uint8 pointer;
    (isRequired, pointer) = _getProofRequirement(id, period);
    return isRequired && pointer >= _config.downtime;
  }

  /**
   * @param id Slot's ID for which the proof requirements should be checked. If the Slot's state is other than Filled, `false` is always returned.
   * @return bool indicating if proof is required for current period
   */
  function isProofRequired(SlotId id) public view returns (bool) {
    return _isProofRequired(id, _blockPeriod());
  }

  /**
   * Proof Downtime specifies part of the Period when the proof is not required even
   * if the proof should be required. This function returns true if the pointer is
   * in downtime (hence no proof required now) and at the same time the proof
   * will be required later on in the Period.
   *
   * @dev for more info about downtime see [timing of storage proofs](https://github.com/codex-storage/codex-research/blob/41c4b4409d2092d0a5475aca0f28995034e58d14/design/storage-proof-timing.md#pointer-downtime)
   * @param id SlotId for which the proof requirements should be checked. If the Slot's state is other than Filled, `false` is always returned.
   * @return bool
   */
  function willProofBeRequired(SlotId id) public view returns (bool) {
    bool isRequired;
    uint8 pointer;
    (isRequired, pointer) = _getProofRequirement(id, _blockPeriod());
    return isRequired && pointer < _config.downtime;
  }

  /**
   * Function used for submitting and verification of the proofs.
   *
   * @dev Reverts when proof is invalid or had been already submitted.
   * @dev Emits ProofSubmitted event.
   * @param id Slot's ID for which the proof requirements should be checked
   * @param proof Groth16 proof
   * @param pubSignals Proofs public input
   */
  function _proofReceived(
    SlotId id,
    Groth16Proof calldata proof,
    uint[] memory pubSignals
  ) internal {
    if (_received[id][_blockPeriod()]) revert Proofs_ProofAlreadySubmitted();
    if (!_verifier.verify(proof, pubSignals)) revert Proofs_InvalidProof();

    _received[id][_blockPeriod()] = true;
    emit ProofSubmitted(id);
  }

  /**
   * Function used to mark proof as missing.
   *
   * @param id Slot's ID for which the proof is missing
   * @param missedPeriod Period for which the proof was missed
   * @dev Reverts when:
   *    - missedPeriod has not ended yet ended
   *    - missing proof was time-barred
   *    - proof was submitted
   *    - proof was not required for missedPeriod period
   *    - proof was already marked as missing
   */
  function _markProofAsMissing(SlotId id, Period missedPeriod) internal {
    uint256 end = _periodEnd(missedPeriod);
    if (end >= block.timestamp) revert Proofs_PeriodNotEnded();
    if (block.timestamp >= end + _config.timeout)
      revert Proofs_ValidationTimedOut();
    if (_received[id][missedPeriod]) revert Proofs_ProofNotMissing();
    if (!_isProofRequired(id, missedPeriod)) revert Proofs_ProofNotRequired();
    if (_missing[id][missedPeriod]) revert Proofs_ProofAlreadyMarkedMissing();

    _missing[id][missedPeriod] = true;
    _missed[id] += 1;
  }

  event ProofSubmitted(SlotId id);
}
