// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {AddressBook} from "../../src/address-book/AddressBook.sol";
import {IAddressBook} from "../../src/address-book/interfaces/IAddressBook.sol";

contract MockWorldIDVerifier {
    error ProofInvalid();
    error SignalHashMismatch();
    error ActionMismatch();
    error RpIdMismatch();

    bool public shouldRevert;

    bool public enforceExpectedSignalHash;
    uint256 public expectedSignalHash;

    bool public enforceExpectedAction;
    uint256 public expectedAction;

    bool public enforceExpectedRpId;
    uint64 public expectedRpId;

    function setShouldRevert(bool value) external {
        shouldRevert = value;
    }

    function setExpectedSignalHash(uint256 value) external {
        expectedSignalHash = value;
        enforceExpectedSignalHash = true;
    }

    function setExpectedAction(uint256 value) external {
        expectedAction = value;
        enforceExpectedAction = true;
    }

    function setExpectedRpId(uint64 value) external {
        expectedRpId = value;
        enforceExpectedRpId = true;
    }

    function verify(
        uint256,
        uint256 action,
        uint64 rpId,
        uint256,
        uint256 signalHash,
        uint64,
        uint64,
        uint256,
        uint256[5] calldata
    ) external view {
        if (shouldRevert) revert ProofInvalid();

        if (enforceExpectedSignalHash && signalHash != expectedSignalHash) {
            revert SignalHashMismatch();
        }

        if (enforceExpectedAction && action != expectedAction) {
            revert ActionMismatch();
        }

        if (enforceExpectedRpId && rpId != expectedRpId) {
            revert RpIdMismatch();
        }
    }
}

contract AddressBookTest is Test {
    uint64 internal constant RP_ID = 42;
    uint64 internal constant ISSUER_SCHEMA_ID = 8;
    uint64 internal constant EPOCH_DURATION = 30 days;
    uint64 internal constant UPDATED_EPOCH_DURATION = 7 days;
    uint64 internal constant INITIAL_PERIOD = 1_234;
    uint64 internal constant INITIAL_TIMESTAMP = INITIAL_PERIOD * EPOCH_DURATION;
    uint256 internal constant USER1_PRIVATE_KEY = 0xA11CE;
    uint256 internal constant USER2_PRIVATE_KEY = 0xB0B;

    AddressBook internal addressBook;
    MockWorldIDVerifier internal verifier;

    address internal user1;
    address internal user2;

    function setUp() public {
        vm.warp(INITIAL_TIMESTAMP);

        user1 = vm.addr(USER1_PRIVATE_KEY);
        user2 = vm.addr(USER2_PRIVATE_KEY);

        verifier = new MockWorldIDVerifier();
        AddressBook implementation = new AddressBook();

        bytes memory initData = abi.encodeWithSelector(
            AddressBook.initialize.selector, address(verifier), RP_ID, ISSUER_SCHEMA_ID, EPOCH_DURATION
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        addressBook = AddressBook(address(proxy));
    }

    function _proof(uint256 nullifier) internal pure returns (IAddressBook.RegistrationProof memory) {
        uint256[5] memory zkProof;
        zkProof[0] = 1;
        zkProof[1] = 2;
        zkProof[2] = 3;
        zkProof[3] = 4;
        zkProof[4] = 5;

        return IAddressBook.RegistrationProof({
            nullifier: nullifier, nonce: 77, expiresAtMin: type(uint64).max, zeroKnowledgeProof: zkProof
        });
    }

    function _warpToNextPeriod() internal {
        uint64 period = addressBook.getCurrentPeriod();
        uint256 nextPeriodStart = (uint256(period) + 1) * addressBook.getEpochDuration();
        vm.warp(nextPeriodStart);
    }

    function _periodEndTimestamp(uint64 period, uint64 epochDuration) internal pure returns (uint256) {
        return (uint256(period) + 1) * epochDuration;
    }

    function _expectedAction(uint64 period, uint64 epochDuration) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(uint256(period), epochDuration))) >> 8;
    }

    function _expectedSignalHash(address account) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(account))) >> 8;
    }

    function _expectVerifierInputsForPeriod(uint64 period, address account) internal {
        verifier.setExpectedRpId(RP_ID);
        verifier.setExpectedAction(addressBook.getActionForPeriod(period));
        verifier.setExpectedSignalHash(_expectedSignalHash(account));
    }

    function testInitializeAndGetters() public view {
        uint64 currentPeriod = addressBook.getCurrentPeriod();

        assertEq(addressBook.getWorldIDVerifier(), address(verifier));
        assertEq(addressBook.getRpId(), RP_ID);
        assertEq(addressBook.getIssuerSchemaId(), ISSUER_SCHEMA_ID);
        assertEq(addressBook.getEpochDuration(), EPOCH_DURATION);
        assertEq(currentPeriod, INITIAL_PERIOD);
        assertEq(addressBook.getCurrentAction(), addressBook.getActionForPeriod(currentPeriod));
    }

    function testInitializeRevertsWhenRpIdIsZero() public {
        MockWorldIDVerifier localVerifier = new MockWorldIDVerifier();
        AddressBook implementation = new AddressBook();

        bytes memory initData = abi.encodeWithSelector(
            AddressBook.initialize.selector, address(localVerifier), uint64(0), ISSUER_SCHEMA_ID, EPOCH_DURATION
        );

        vm.expectRevert(abi.encodeWithSelector(IAddressBook.InvalidRpId.selector));
        new ERC1967Proxy(address(implementation), initData);
    }

    function testInitializeRevertsWhenIssuerSchemaIdIsZero() public {
        MockWorldIDVerifier localVerifier = new MockWorldIDVerifier();
        AddressBook implementation = new AddressBook();

        bytes memory initData = abi.encodeWithSelector(
            AddressBook.initialize.selector, address(localVerifier), RP_ID, uint64(0), EPOCH_DURATION
        );

        vm.expectRevert(abi.encodeWithSelector(IAddressBook.InvalidIssuerSchemaId.selector));
        new ERC1967Proxy(address(implementation), initData);
    }

    function testInitializeRevertsWhenEpochDurationIsZero() public {
        MockWorldIDVerifier localVerifier = new MockWorldIDVerifier();
        AddressBook implementation = new AddressBook();

        bytes memory initData =
            abi.encodeWithSelector(AddressBook.initialize.selector, address(localVerifier), RP_ID, ISSUER_SCHEMA_ID, 0);

        vm.expectRevert(abi.encodeWithSelector(IAddressBook.InvalidEpochDuration.selector));
        new ERC1967Proxy(address(implementation), initData);
    }

    function testGetActionForPeriodMatchesDerivation() public {
        uint64 currentPeriod = addressBook.getCurrentPeriod();
        uint64 nextPeriod = currentPeriod + 1;

        uint256 currentAction = addressBook.getActionForPeriod(currentPeriod);
        uint256 nextAction = addressBook.getActionForPeriod(nextPeriod);

        assertEq(currentAction, _expectedAction(currentPeriod, EPOCH_DURATION));
        assertEq(nextAction, _expectedAction(nextPeriod, EPOCH_DURATION));
        assertEq(addressBook.getCurrentAction(), currentAction);
        assertTrue(currentAction != nextAction);

        _warpToNextPeriod();
        assertEq(addressBook.getCurrentAction(), nextAction);
    }

    function testRegisterAndIsVerifiedCurrentPeriod() public {
        uint64 period = addressBook.getCurrentPeriod();
        uint256 action = addressBook.getActionForPeriod(period);

        _expectVerifierInputsForPeriod(period, user1);
        vm.prank(user1);
        addressBook.register(user1, _proof(111));

        assertTrue(addressBook.isVerified(user1));
        assertTrue(addressBook.isRegisteredForAction(action, user1));
    }

    function testIsVerifiedIsPeriodScopedAfterPeriodRollover() public {
        uint64 period = addressBook.getCurrentPeriod();
        uint256 action = addressBook.getActionForPeriod(period);

        _expectVerifierInputsForPeriod(period, user1);
        vm.prank(user1);
        addressBook.register(user1, _proof(123));

        _warpToNextPeriod();

        assertFalse(addressBook.isVerified(user1));
        assertTrue(addressBook.isRegisteredForAction(action, user1));
    }

    function testRegisterNextPeriod() public {
        uint64 currentPeriod = addressBook.getCurrentPeriod();
        uint64 nextPeriod = currentPeriod + 1;
        uint256 nextAction = addressBook.getActionForPeriod(nextPeriod);

        _expectVerifierInputsForPeriod(nextPeriod, user1);
        vm.prank(user1);
        addressBook.registerNextPeriod(user1, _proof(222));

        assertFalse(addressBook.isVerified(user1));
        assertTrue(addressBook.isRegisteredForAction(nextAction, user1));

        _warpToNextPeriod();

        assertTrue(addressBook.isVerified(user1));
    }

    function testRegisterNextPeriodRevertsAtMaxPeriod() public {
        MockWorldIDVerifier localVerifier = new MockWorldIDVerifier();
        AddressBook implementation = new AddressBook();

        bytes memory initData =
            abi.encodeWithSelector(AddressBook.initialize.selector, address(localVerifier), RP_ID, ISSUER_SCHEMA_ID, 1);

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        AddressBook localAddressBook = AddressBook(address(proxy));

        vm.warp(type(uint64).max);
        assertEq(localAddressBook.getCurrentPeriod(), type(uint64).max);

        vm.expectRevert(abi.encodeWithSelector(IAddressBook.PeriodOutOfRange.selector));
        vm.prank(user1);
        localAddressBook.registerNextPeriod(user1, _proof(123456));
    }

    function testRegisterRevertsWhenExpiresBeforeCurrentPeriodEnd() public {
        uint64 currentPeriod = addressBook.getCurrentPeriod();
        uint256 periodEnd = _periodEndTimestamp(currentPeriod, addressBook.getEpochDuration());

        IAddressBook.RegistrationProof memory proof = _proof(445);
        proof.expiresAtMin = uint64(periodEnd - 1);

        vm.expectRevert(
            abi.encodeWithSelector(IAddressBook.ExpirationBeforePeriodEnd.selector, proof.expiresAtMin, periodEnd)
        );
        vm.prank(user1);
        addressBook.register(user1, proof);
    }

    function testRegisterNextPeriodRevertsWhenExpiresBeforeNextPeriodEnd() public {
        uint64 nextPeriod = addressBook.getCurrentPeriod() + 1;
        uint256 periodEnd = _periodEndTimestamp(nextPeriod, addressBook.getEpochDuration());

        IAddressBook.RegistrationProof memory proof = _proof(446);
        proof.expiresAtMin = uint64(_periodEndTimestamp(nextPeriod - 1, addressBook.getEpochDuration()));

        vm.expectRevert(
            abi.encodeWithSelector(IAddressBook.ExpirationBeforePeriodEnd.selector, proof.expiresAtMin, periodEnd)
        );
        vm.prank(user1);
        addressBook.registerNextPeriod(user1, proof);
    }

    function testCannotReuseNullifierInSamePeriod() public {
        uint64 period = addressBook.getCurrentPeriod();
        uint256 action = addressBook.getActionForPeriod(period);

        _expectVerifierInputsForPeriod(period, user1);
        vm.prank(user1);
        addressBook.register(user1, _proof(555));

        _expectVerifierInputsForPeriod(period, user2);

        vm.expectRevert(abi.encodeWithSelector(IAddressBook.NullifierAlreadyUsed.selector, 555, action));
        vm.prank(user2);
        addressBook.register(user2, _proof(555));
    }

    function testCannotReuseNullifierAcrossPeriods() public {
        uint64 period = addressBook.getCurrentPeriod();

        _expectVerifierInputsForPeriod(period, user1);
        vm.prank(user1);
        addressBook.register(user1, _proof(556));

        _warpToNextPeriod();

        uint64 nextPeriod = addressBook.getCurrentPeriod();
        uint256 nextAction = addressBook.getActionForPeriod(nextPeriod);

        _expectVerifierInputsForPeriod(nextPeriod, user2);

        vm.expectRevert(abi.encodeWithSelector(IAddressBook.NullifierAlreadyUsed.selector, 556, nextAction));
        vm.prank(user2);
        addressBook.register(user2, _proof(556));
    }

    function testCannotReuseAddressInSamePeriod() public {
        uint64 period = addressBook.getCurrentPeriod();
        uint256 action = addressBook.getActionForPeriod(period);

        _expectVerifierInputsForPeriod(period, user1);
        vm.prank(user1);
        addressBook.register(user1, _proof(666));

        vm.expectRevert(abi.encodeWithSelector(IAddressBook.AddressAlreadyRegistered.selector, user1, action));
        vm.prank(user1);
        addressBook.register(user1, _proof(667));
    }

    function testCannotRegisterZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IAddressBook.InvalidAccount.selector));
        addressBook.register(address(0), _proof(777));
    }

    function testSignalHashBindingIsEnforced() public {
        uint64 period = addressBook.getCurrentPeriod();

        verifier.setExpectedRpId(RP_ID);
        verifier.setExpectedAction(addressBook.getActionForPeriod(period));
        verifier.setExpectedSignalHash(_expectedSignalHash(user2));

        vm.expectRevert(abi.encodeWithSelector(MockWorldIDVerifier.SignalHashMismatch.selector));
        vm.prank(user1);
        addressBook.register(user1, _proof(888));
    }

    function testCannotRegisterDifferentAccountWithProofBoundToAnother() public {
        uint64 period = addressBook.getCurrentPeriod();

        verifier.setExpectedRpId(RP_ID);
        verifier.setExpectedAction(addressBook.getActionForPeriod(period));
        verifier.setExpectedSignalHash(_expectedSignalHash(user1));

        vm.expectRevert(abi.encodeWithSelector(MockWorldIDVerifier.SignalHashMismatch.selector));
        vm.prank(user2);
        addressBook.register(user2, _proof(889));
    }

    function testThirdPartyCanRegisterAnotherAccount() public {
        uint64 period = addressBook.getCurrentPeriod();

        _expectVerifierInputsForPeriod(period, user2);

        vm.prank(user1);
        addressBook.register(user2, _proof(892));
        assertTrue(addressBook.isVerified(user2));
    }

    function testVerifierRevertBubblesUp() public {
        uint64 period = addressBook.getCurrentPeriod();

        _expectVerifierInputsForPeriod(period, user1);
        verifier.setShouldRevert(true);

        vm.expectRevert(abi.encodeWithSelector(MockWorldIDVerifier.ProofInvalid.selector));
        vm.prank(user1);
        addressBook.register(user1, _proof(999));
    }

    function testOwnerOnlyAdminFunctions() public {
        address nonOwner = address(0xBEEF);
        MockWorldIDVerifier newVerifier = new MockWorldIDVerifier();

        vm.prank(nonOwner);
        vm.expectRevert();
        addressBook.updateWorldIDVerifier(address(newVerifier));

        addressBook.updateWorldIDVerifier(address(newVerifier));
        assertEq(addressBook.getWorldIDVerifier(), address(newVerifier));
    }

    function testUpdateIssuerSchemaId() public {
        uint64 newSchemaId = 99;

        addressBook.updateIssuerSchemaId(newSchemaId);
        assertEq(addressBook.getIssuerSchemaId(), newSchemaId);
    }

    function testUpdateIssuerSchemaIdRevertsWhenZero() public {
        vm.expectRevert(abi.encodeWithSelector(IAddressBook.InvalidIssuerSchemaId.selector));
        addressBook.updateIssuerSchemaId(0);
    }

    function testUpdateIssuerSchemaIdRevertsForNonOwner() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert();
        addressBook.updateIssuerSchemaId(99);
    }

    function testUpdateIssuerSchemaIdEmitsEvent() public {
        uint64 newSchemaId = 99;

        vm.expectEmit();
        emit IAddressBook.IssuerSchemaIdUpdated(ISSUER_SCHEMA_ID, newSchemaId);
        addressBook.updateIssuerSchemaId(newSchemaId);
    }

    function testUpdateEpochDuration() public {
        addressBook.updateEpochDuration(UPDATED_EPOCH_DURATION);
        assertEq(addressBook.getEpochDuration(), UPDATED_EPOCH_DURATION);
    }

    function testUpdateEpochDurationRevertsWhenZero() public {
        vm.expectRevert(abi.encodeWithSelector(IAddressBook.InvalidEpochDuration.selector));
        addressBook.updateEpochDuration(0);
    }

    function testUpdateEpochDurationRevertsForNonOwner() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert();
        addressBook.updateEpochDuration(UPDATED_EPOCH_DURATION);
    }

    function testUpdateEpochDurationEmitsEvent() public {
        vm.expectEmit();
        emit IAddressBook.EpochDurationUpdated(EPOCH_DURATION, UPDATED_EPOCH_DURATION);
        addressBook.updateEpochDuration(UPDATED_EPOCH_DURATION);
    }

    function testUpdateEpochDurationChangesCurrentActionAndVerificationScope() public {
        uint64 currentPeriod = addressBook.getCurrentPeriod();

        _expectVerifierInputsForPeriod(currentPeriod, user1);
        vm.prank(user1);
        addressBook.register(user1, _proof(1_001));

        assertTrue(addressBook.isVerified(user1));

        addressBook.updateEpochDuration(UPDATED_EPOCH_DURATION);

        uint64 updatedPeriod = uint64(block.timestamp / UPDATED_EPOCH_DURATION);
        uint256 updatedAction = _expectedAction(updatedPeriod, UPDATED_EPOCH_DURATION);

        assertEq(addressBook.getCurrentPeriod(), updatedPeriod);
        assertEq(addressBook.getCurrentAction(), updatedAction);
        assertFalse(addressBook.isVerified(user1));

        _expectVerifierInputsForPeriod(updatedPeriod, user1);
        vm.prank(user1);
        addressBook.register(user1, _proof(1_002));

        assertTrue(addressBook.isVerified(user1));
        assertTrue(addressBook.isRegisteredForAction(updatedAction, user1));
    }
}
