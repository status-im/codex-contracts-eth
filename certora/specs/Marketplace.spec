import "./shared.spec";

using ERC20A as Token;

methods {
    function Token.balanceOf(address) external returns (uint256) envfree;
    function Token.totalSupply() external returns (uint256) envfree;
    function publicPeriodEnd(Periods.Period) external returns (uint64) envfree;
    function generateSlotId(Marketplace.RequestId, uint64) external returns (Marketplace.SlotId) envfree;
}

/*--------------------------------------------
|              Ghosts and hooks              |
--------------------------------------------*/

ghost mathint sumOfBalances {
    init_state axiom sumOfBalances == 0;
}

hook Sload uint256 balance Token._balances[KEY address addr] {
    require sumOfBalances >= to_mathint(balance);
}

hook Sstore Token._balances[KEY address addr] uint256 newValue (uint256 oldValue) {
    sumOfBalances = sumOfBalances - oldValue + newValue;
}

ghost mathint totalReceived;

hook Sload uint256 defaultValue currentContract._marketplaceTotals.received {
    require totalReceived >= to_mathint(defaultValue);
}

hook Sstore currentContract._marketplaceTotals.received uint256 defaultValue (uint256 defaultValue_old) {
    totalReceived = totalReceived + defaultValue - defaultValue_old;
}

ghost mathint totalSent;

hook Sload uint256 defaultValue currentContract._marketplaceTotals.sent {
    require totalSent >= to_mathint(defaultValue);
}

hook Sstore currentContract._marketplaceTotals.sent uint256 defaultValue (uint256 defaultValue_old) {
    totalSent = totalSent + defaultValue - defaultValue_old;
}

ghost uint64 lastBlockTimestampGhost;

hook TIMESTAMP uint v {
    require lastBlockTimestampGhost <= assert_uint64(v);
    lastBlockTimestampGhost = assert_uint64(v);
}

ghost mapping(MarketplaceHarness.SlotId => mapping(Periods.Period => bool)) _missingMirror {
    init_state axiom forall MarketplaceHarness.SlotId a.
            forall Periods.Period b.
            _missingMirror[a][b] == false;
}

ghost mapping(MarketplaceHarness.SlotId => uint64) _missedMirror {
    init_state axiom forall MarketplaceHarness.SlotId a.
            _missedMirror[a] == 0;
}

ghost mapping(MarketplaceHarness.SlotId => mathint) _missedCalculated {
    init_state axiom forall MarketplaceHarness.SlotId a.
            _missedCalculated[a] == 0;
}

hook Sload bool defaultValue _missing[KEY MarketplaceHarness.SlotId slotId][KEY Periods.Period period] {
    require _missingMirror[slotId][period] == defaultValue;
}

hook Sstore _missing[KEY MarketplaceHarness.SlotId slotId][KEY Periods.Period period] bool defaultValue {
    _missingMirror[slotId][period] = defaultValue;
    if (defaultValue) {
        _missedCalculated[slotId] = _missedCalculated[slotId] + 1;
    }
}

hook Sload uint64 defaultValue _missed[KEY MarketplaceHarness.SlotId slotId] {
    require _missedMirror[slotId] == defaultValue;
}

hook Sstore _missed[KEY MarketplaceHarness.SlotId slotId] uint64 defaultValue {
    _missedMirror[slotId] = defaultValue;
    if (defaultValue == 0) {
        _missedCalculated[slotId] = 0;
    }
}

ghost mathint requestStateChangesCount {
    init_state axiom requestStateChangesCount == 0;
}

hook Sstore _requestContexts[KEY Marketplace.RequestId requestId].state Marketplace.RequestState newState (Marketplace.RequestState oldState) {
    if (oldState != newState) {
        requestStateChangesCount = requestStateChangesCount + 1;
    }
}

ghost mathint slotStateChangesCount {
    init_state axiom slotStateChangesCount == 0;
}

hook Sstore _slots[KEY Marketplace.SlotId slotId].state Marketplace.SlotState newState (Marketplace.SlotState oldState) {
    if (oldState != newState) {
        slotStateChangesCount = slotStateChangesCount + 1;
    }
}

ghost mapping(MarketplaceHarness.RequestId => uint64) slotsFilledGhost;

hook Sload uint64 defaultValue _requestContexts[KEY MarketplaceHarness.RequestId RequestId].slotsFilled {
    require slotsFilledGhost[RequestId] == defaultValue;
}

hook Sstore _requestContexts[KEY MarketplaceHarness.RequestId RequestId].slotsFilled uint64 defaultValue {
    slotsFilledGhost[RequestId] = defaultValue;
}

ghost mapping(MarketplaceHarness.RequestId => uint64) endsAtGhost;

hook Sload uint64 defaultValue _requestContexts[KEY MarketplaceHarness.RequestId RequestId].endsAt {
    require endsAtGhost[RequestId] == defaultValue;
}

hook Sstore _requestContexts[KEY MarketplaceHarness.RequestId RequestId].endsAt uint64 defaultValue {
    endsAtGhost[RequestId] = defaultValue;
}

/*--------------------------------------------
|              Helper functions              |
--------------------------------------------*/

function canCancelRequest(method f) returns bool {
    return f.selector == sig:withdrawFunds(Marketplace.RequestId).selector;
}

function canStartRequest(method f) returns bool {
    return f.selector == sig:fillSlot(Marketplace.RequestId, uint64, Marketplace.Groth16Proof).selector;
}

function canFinishRequest(method f) returns bool {
    return f.selector == sig:freeSlot(Marketplace.SlotId, address, address).selector ||
        f.selector == sig:freeSlot(Marketplace.SlotId).selector;
}

function canFailRequest(method f) returns bool {
    return f.selector == sig:markProofAsMissing(Marketplace.SlotId, Periods.Period).selector ||
        f.selector == sig:freeSlot(Marketplace.SlotId, address, address).selector ||
        f.selector == sig:freeSlot(Marketplace.SlotId).selector;
}

function canMakeSlotPaid(method f) returns bool {
    return f.selector == sig:freeSlot(Marketplace.SlotId, address, address).selector ||
        f.selector == sig:freeSlot(Marketplace.SlotId).selector;
}

function canFillSlot(method f) returns bool {
    return f.selector == sig:fillSlot(Marketplace.RequestId, uint64, Marketplace.Groth16Proof).selector;
}

// The slot identified by `slotId` must have requestId and slotIndex set to 0,
// or to values that satisfied slotId == keccak(requestId, slotIndex)
function slotAttributesAreConsistent(env e, Marketplace.SlotId slotId) {
    require (currentContract.slots(e, slotId).requestId == to_bytes32(0) && currentContract.slots(e, slotId).slotIndex == 0) ||
        slotId == currentContract.generateSlotId(e, currentContract.slots(e, slotId).requestId, currentContract.slots(e, slotId).slotIndex);
}

/*--------------------------------------------
|                 Invariants                 |
--------------------------------------------*/

invariant totalSupplyIsSumOfBalances()
    to_mathint(Token.totalSupply()) == sumOfBalances;

invariant requestStartedWhenSlotsFilled(env e, Marketplace.RequestId requestId, Marketplace.SlotId slotId)
    currentContract.requestState(e, requestId) == Marketplace.RequestState.Started => to_mathint(currentContract.getRequest(e, requestId).ask.slots) - slotsFilledGhost[requestId] <= to_mathint(currentContract.getRequest(e, requestId).ask.maxSlotLoss);

// STATUS - verified
// https://prover.certora.com/output/6199/6e2383ea040347eabeeb1008bc257ae6?anonymousKey=e1a6a00310a44ed264b1f98b03fa29273e68fca9
invariant slotMissedShouldBeEqualToNumberOfMissedPeriods(env e, Marketplace.SlotId slotId)
    to_mathint(_missedMirror[slotId]) == _missedCalculated[slotId];

// STATUS - verified
// can set missing if period was passed
// https://prover.certora.com/output/3106/026b36c118e44ad0824a51c50647c497/?anonymousKey=29879706f3d343555bb6122d071c9409d4e9876d
invariant cantBeMissedIfInPeriod(MarketplaceHarness.SlotId slotId, Periods.Period period)
    lastBlockTimestampGhost <= publicPeriodEnd(period) => !_missingMirror[slotId][period];

// STATUS - verified
// cancelled request is always expired
// https://prover.certora.com/output/6199/36b12b897f3941faa00fb4ab6871be8e?anonymousKey=de98a02041b841fb2fa67af4222f29fac258249f
invariant cancelledRequestAlwaysExpired(env e, Marketplace.RequestId requestId)
    currentContract.requestState(e, requestId) == Marketplace.RequestState.Cancelled =>
        currentContract.requestExpiry(e, requestId) < lastBlockTimestampGhost;

// STATUS - verified
// failed request is always ended
// https://prover.certora.com/output/6199/3c5e57311e474f26aa7d9e9481c5880a?anonymousKey=36e39932ee488bb35fe23e38d8d4091190e047af
invariant failedRequestAlwaysEnded(env e, Marketplace.RequestId requestId)
    currentContract.requestState(e, requestId) == Marketplace.RequestState.Failed =>
        endsAtGhost[requestId] < lastBlockTimestampGhost;

// STATUS - verified
// paid slot always has finished or cancelled request
// https://prover.certora.com/output/6199/d0e165ed5d594f9fb477602af06cfeb1?anonymousKey=01ffaad46027786c38d78e5a41c03ce002032200
invariant paidSlotAlwaysHasFinishedOrCancelledRequest(env e, Marketplace.SlotId slotId)
     currentContract.slotState(e, slotId) == Marketplace.SlotState.Paid =>
         currentContract.requestState(e, slotIdToRequestId[slotId]) == Marketplace.RequestState.Finished || currentContract.requestState(e, slotIdToRequestId[slotId]) == Marketplace.RequestState.Cancelled
    { preserved {
        requireInvariant cancelledSlotAlwaysHasCancelledRequest(e, slotId);
      }
    }


/*--------------------------------------------
|                 Properties                 |
--------------------------------------------*/

rule sanity(env e, method f) {
    calldataarg args;
    f(e, args);
    assert true;
    satisfy true;
}

rule totalReceivedCannotDecrease(env e, method f) {
    mathint total_before = totalReceived;

    calldataarg args;
    f(e, args);

    mathint total_after = totalReceived;

    assert total_after >= total_before;
}

rule totalSentCannotDecrease(env e, method f) {
    mathint total_before = totalSent;

    calldataarg args;
    f(e, args);

    mathint total_after = totalSent;

    assert total_after >= total_before;
}

// https://prover.certora.com/output/6199/0b56a7cdb3f9466db08f2a4677eddaac?anonymousKey=351ce9d5561f6c2aff1b38942e307735428bb83f
rule slotIsFailedOrFreeIfRequestHasFailed(env e, method f) {
    calldataarg args;
    Marketplace.SlotId slotId;

    requireInvariant paidSlotAlwaysHasFinishedOrCancelledRequest(e, slotId);

    Marketplace.RequestState requestStateBefore = currentContract.requestState(e, slotIdToRequestId[slotId]);
    f(e, args);
    Marketplace.RequestState requestAfter = currentContract.requestState(e, slotIdToRequestId[slotId]);

    assert requestStateBefore != Marketplace.RequestState.Failed && requestAfter == Marketplace.RequestState.Failed => currentContract.slotState(e, slotId) == Marketplace.SlotState.Failed || currentContract.slotState(e, slotId) == Marketplace.SlotState.Free;
}



rule functionsCausingRequestStateChanges(env e, method f) {
    calldataarg args;
    Marketplace.RequestId requestId;

    Marketplace.RequestState requestStateBefore = currentContract.requestState(e, requestId);
    f(e, args);
    Marketplace.RequestState requestStateAfter = currentContract.requestState(e, requestId);

    // RequestState.New -> RequestState.Started
    assert requestStateBefore == Marketplace.RequestState.New && requestStateAfter == Marketplace.RequestState.Started => canStartRequest(f);

    // RequestState.New -> RequestState.Cancelled
    assert requestStateBefore == Marketplace.RequestState.New && requestStateAfter == Marketplace.RequestState.Cancelled => canCancelRequest(f);

    // RequestState.Started -> RequestState.Finished
    assert requestStateBefore == Marketplace.RequestState.Started && requestStateAfter == Marketplace.RequestState.Finished => canFinishRequest(f);

    // RequestState.Started -> RequestState.Failed
    assert requestStateBefore == Marketplace.RequestState.Started && requestStateAfter == Marketplace.RequestState.Failed => canFailRequest(f);
}

rule functionsCausingSlotStateChanges(env e, method f) {
    calldataarg args;
    Marketplace.SlotId slotId;

    slotAttributesAreConsistent(e, slotId);

    Marketplace.Slot slot = currentContract.slots(e, slotId);
    Marketplace.SlotState slotStateBefore = currentContract.slotState(e, slotId);
    f(e, args);
    Marketplace.SlotState slotStateAfter = currentContract.slotState(e, slotId);

    // SlotState.Finished -> SlotState.Paid
    assert slotStateBefore == Marketplace.SlotState.Finished && slotStateAfter == Marketplace.SlotState.Paid => canMakeSlotPaid(f);

    // SlotState.Free -> SlotState.Filled
    assert (slotStateBefore == Marketplace.SlotState.Free || slotStateBefore == Marketplace.SlotState.Repair) && slotStateAfter == Marketplace.SlotState.Filled => canFillSlot(f);
}

rule allowedSlotStateChanges(env e, method f) {
    calldataarg args;
    Marketplace.SlotId slotId;

    slotAttributesAreConsistent(e, slotId);

    Marketplace.Slot slot = currentContract.slots(e, slotId);
    Marketplace.SlotState slotStateBefore = currentContract.slotState(e, slotId);
    f(e, args);
    Marketplace.SlotState slotStateAfter = currentContract.slotState(e, slotId);

    // Cannot change from Paid
    assert slotStateBefore == Marketplace.SlotState.Paid => slotStateAfter == Marketplace.SlotState.Paid;

    // SlotState.Cancelled -> SlotState.Cancelled || SlotState.Failed || Finished || Paid
    assert slotStateBefore == Marketplace.SlotState.Cancelled => (
            slotStateAfter == Marketplace.SlotState.Cancelled ||
            slotStateAfter == Marketplace.SlotState.Failed ||
            slotStateAfter == Marketplace.SlotState.Finished ||
            slotStateAfter == Marketplace.SlotState.Paid
            );

    // SlotState.Filled only from Free or Repair
    assert slotStateBefore != Marketplace.SlotState.Filled && slotStateAfter == Marketplace.SlotState.Filled => (slotStateBefore == Marketplace.SlotState.Free || slotStateBefore == Marketplace.SlotState.Repair);
}

rule cancelledRequestsStayCancelled(env e, method f) {

    calldataarg args;
    Marketplace.RequestId requestId;

    Marketplace.RequestState requestStateBefore = currentContract.requestState(e, requestId);

    require requestStateBefore == Marketplace.RequestState.Cancelled;
    requireInvariant cancelledRequestAlwaysExpired(e, requestId);

    ensureValidRequestId(requestId);

    f(e, args);
    Marketplace.RequestState requestStateAfter = currentContract.requestState(e, requestId);

    assert requestStateAfter == requestStateBefore;
}

rule finishedRequestsStayFinished(env e, method f) {

    calldataarg args;
    Marketplace.RequestId requestId;

    ensureValidRequestId(requestId);

    Marketplace.RequestState requestStateBefore = currentContract.requestState(e, requestId);
    require requestStateBefore == Marketplace.RequestState.Finished;
    f(e, args);
    Marketplace.RequestState requestStateAfter = currentContract.requestState(e, requestId);

    assert requestStateBefore == requestStateAfter;
}

rule requestStateChangesOnlyOncePerFunctionCall(env e, method f) {
    calldataarg args;
    Marketplace.RequestId requestId;

    mathint requestStateChangesCountBefore = requestStateChangesCount;
    f(e, args);
    mathint requestStateChangesCountAfter = requestStateChangesCount;

    assert requestStateChangesCountAfter <= requestStateChangesCountBefore + 1;
}

rule slotStateChangesOnlyOncePerFunctionCall(env e, method f) {
    calldataarg args;
    Marketplace.SlotId slotId;

    mathint slotStateChangesCountBefore = slotStateChangesCount;
    f(e, args);
    mathint slotStateChangesCountAfter =slotStateChangesCount;

    assert slotStateChangesCountAfter <= slotStateChangesCountBefore + 1;
}

rule slotCanBeFreedAndPaidOnce {
  env e;
  Marketplace.SlotId slotId;
  address rewardRecipient;
  address collateralRecipient;

  Marketplace.SlotState slotStateBefore = currentContract.slotState(e, slotId);
  require slotStateBefore != Marketplace.SlotState.Paid;
  freeSlot(e, slotId, rewardRecipient, collateralRecipient);

  Marketplace.SlotState slotStateAfter = currentContract.slotState(e, slotId);
  require slotStateAfter == Marketplace.SlotState.Paid;

  freeSlot@withrevert(e, slotId, rewardRecipient, collateralRecipient);

  assert lastReverted;
}
