// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {AddressBook} from "../../src/address-book/AddressBook.sol";
import {IAddressBook} from "../../src/address-book/interfaces/IAddressBook.sol";
import {DateTimeLib} from "../../src/address-book/libraries/DateTimeLib.sol";

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
    uint64 internal constant PERIOD_START_TIMESTAMP = 1_735_689_600; // 2025-01-01 00:00:00 UTC
    uint256 internal constant USER1_PRIVATE_KEY = 0xA11CE;
    uint256 internal constant USER2_PRIVATE_KEY = 0xB0B;

    AddressBook internal addressBook;
    MockWorldIDVerifier internal verifier;

    address internal user1;
    address internal user2;

    function setUp() public {
        vm.warp(PERIOD_START_TIMESTAMP);

        user1 = vm.addr(USER1_PRIVATE_KEY);
        user2 = vm.addr(USER2_PRIVATE_KEY);

        verifier = new MockWorldIDVerifier();
        AddressBook implementation = new AddressBook();

        bytes memory initData = abi.encodeWithSelector(
            AddressBook.initialize.selector, address(verifier), RP_ID, ISSUER_SCHEMA_ID, uint64(block.timestamp)
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
            nullifier: nullifier,
            nonce: 77,
            expiresAtMin: type(uint64).max,
            zeroKnowledgeProof: zkProof
        });
    }

    function _warpToNextPeriod() internal {
        uint32 period = addressBook.getCurrentPeriod();
        while (addressBook.getCurrentPeriod() == period) {
            vm.warp(block.timestamp + 1 days);
        }
    }

    function _expectedAction(uint32 period) internal view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(address(addressBook), period))) >> 8;
    }

    function _expectedSignalHash(address account) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(account))) >> 8;
    }

    function _expectVerifierInputsForPeriod(uint32 period, address account) internal {
        verifier.setExpectedRpId(RP_ID);
        verifier.setExpectedAction(addressBook.getActionForPeriod(period));
        verifier.setExpectedSignalHash(_expectedSignalHash(account));
    }

    function testInitializeAndGetters() public view {
        uint32 currentPeriod = addressBook.getCurrentPeriod();

        assertEq(addressBook.getWorldIDVerifier(), address(verifier));
        assertEq(addressBook.getRpId(), RP_ID);
        assertEq(addressBook.getIssuerSchemaId(), ISSUER_SCHEMA_ID);
        assertEq(addressBook.getPeriodStartTimestamp(), PERIOD_START_TIMESTAMP);
        assertEq(currentPeriod, 0);
        assertEq(addressBook.getCurrentAction(), addressBook.getActionForPeriod(currentPeriod));
    }

    function testInitializeRevertsWhenRpIdIsZero() public {
        MockWorldIDVerifier localVerifier = new MockWorldIDVerifier();
        AddressBook implementation = new AddressBook();

        bytes memory initData = abi.encodeWithSelector(
            AddressBook.initialize.selector, address(localVerifier), uint64(0), ISSUER_SCHEMA_ID, PERIOD_START_TIMESTAMP
        );

        vm.expectRevert(abi.encodeWithSelector(IAddressBook.InvalidRpId.selector));
        new ERC1967Proxy(address(implementation), initData);
    }

    function testInitializeRevertsWhenIssuerSchemaIdIsZero() public {
        MockWorldIDVerifier localVerifier = new MockWorldIDVerifier();
        AddressBook implementation = new AddressBook();

        bytes memory initData = abi.encodeWithSelector(
            AddressBook.initialize.selector, address(localVerifier), RP_ID, uint64(0), PERIOD_START_TIMESTAMP
        );

        vm.expectRevert(abi.encodeWithSelector(IAddressBook.InvalidIssuerSchemaId.selector));
        new ERC1967Proxy(address(implementation), initData);
    }

    function testInitializeRevertsWhenPeriodStartIsNotUtcMonthStart() public {
        MockWorldIDVerifier localVerifier = new MockWorldIDVerifier();
        AddressBook implementation = new AddressBook();

        uint64 invalidPeriodStartTimestamp = PERIOD_START_TIMESTAMP + 1;
        bytes memory initData = abi.encodeWithSelector(
            AddressBook.initialize.selector, address(localVerifier), RP_ID, ISSUER_SCHEMA_ID, invalidPeriodStartTimestamp
        );

        vm.expectRevert(
            abi.encodeWithSelector(IAddressBook.InvalidPeriodStartTimestamp.selector, invalidPeriodStartTimestamp)
        );
        new ERC1967Proxy(address(implementation), initData);
    }

    function testGetActionForPeriodMatchesDerivation() public {
        uint32 currentPeriod = addressBook.getCurrentPeriod();
        uint32 nextPeriod = currentPeriod + 1;

        uint256 currentAction = addressBook.getActionForPeriod(currentPeriod);
        uint256 nextAction = addressBook.getActionForPeriod(nextPeriod);

        assertEq(currentAction, _expectedAction(currentPeriod));
        assertEq(nextAction, _expectedAction(nextPeriod));
        assertEq(addressBook.getCurrentAction(), currentAction);
        assertTrue(currentAction != nextAction);

        _warpToNextPeriod();
        assertEq(addressBook.getCurrentAction(), nextAction);
    }

    function testRegisterAndVerifyCurrentPeriod() public {
        uint32 period = addressBook.getCurrentPeriod();

        _expectVerifierInputsForPeriod(period, user1);
        vm.prank(user1);
        addressBook.register(user1, _proof(111));

        assertTrue(addressBook.verify(user1));
        assertTrue(addressBook.isRegisteredForPeriod(period, user1));
    }

    function testVerifyIsPeriodScopedAfterPeriodRollover() public {
        uint32 period = addressBook.getCurrentPeriod();

        _expectVerifierInputsForPeriod(period, user1);
        vm.prank(user1);
        addressBook.register(user1, _proof(123));

        _warpToNextPeriod();

        assertFalse(addressBook.verify(user1));
        assertTrue(addressBook.isRegisteredForPeriod(period, user1));
    }

    function testRegisterNextPeriod() public {
        uint32 currentPeriod = addressBook.getCurrentPeriod();
        uint32 nextPeriod = currentPeriod + 1;

        _expectVerifierInputsForPeriod(nextPeriod, user1);
        vm.prank(user1);
        addressBook.registerNextPeriod(user1, _proof(222));

        assertFalse(addressBook.verify(user1));
        assertTrue(addressBook.isRegisteredForPeriod(nextPeriod, user1));

        _warpToNextPeriod();

        assertTrue(addressBook.verify(user1));
    }

    function testRegisterNextPeriodRevertsAtMaxPeriod() public {
        MockWorldIDVerifier localVerifier = new MockWorldIDVerifier();
        AddressBook implementation = new AddressBook();

        bytes memory initData = abi.encodeWithSelector(
            AddressBook.initialize.selector, address(localVerifier), RP_ID, ISSUER_SCHEMA_ID, uint64(0)
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        AddressBook localAddressBook = AddressBook(address(proxy));

        vm.warp(DateTimeLib.periodEndTimestamp(0, type(uint32).max - 1));
        assertEq(localAddressBook.getCurrentPeriod(), type(uint32).max);

        vm.expectRevert(abi.encodeWithSelector(IAddressBook.PeriodOutOfRange.selector));
        vm.prank(user1);
        localAddressBook.registerNextPeriod(user1, _proof(123456));
    }

    function testRegisterRevertsWhenExpiresBeforeCurrentPeriodEnd() public {
        uint32 currentPeriod = addressBook.getCurrentPeriod();
        uint256 periodEnd = DateTimeLib.periodEndTimestamp(addressBook.getPeriodStartTimestamp(), currentPeriod);

        IAddressBook.RegistrationProof memory proof = _proof(445);
        proof.expiresAtMin = uint64(addressBook.getPeriodStartTimestamp());

        vm.expectRevert(
            abi.encodeWithSelector(IAddressBook.ExpirationBeforePeriodEnd.selector, proof.expiresAtMin, periodEnd)
        );
        vm.prank(user1);
        addressBook.register(user1, proof);
    }

    function testRegisterNextPeriodRevertsWhenExpiresBeforeNextPeriodEnd() public {
        uint32 nextPeriod = addressBook.getCurrentPeriod() + 1;
        uint256 periodEnd = DateTimeLib.periodEndTimestamp(addressBook.getPeriodStartTimestamp(), nextPeriod);

        IAddressBook.RegistrationProof memory proof = _proof(446);
        proof.expiresAtMin =
            uint64(DateTimeLib.periodEndTimestamp(addressBook.getPeriodStartTimestamp(), nextPeriod - 1));

        vm.expectRevert(
            abi.encodeWithSelector(IAddressBook.ExpirationBeforePeriodEnd.selector, proof.expiresAtMin, periodEnd)
        );
        vm.prank(user1);
        addressBook.registerNextPeriod(user1, proof);
    }

    function testCannotReuseNullifierInSamePeriod() public {
        uint32 period = addressBook.getCurrentPeriod();

        _expectVerifierInputsForPeriod(period, user1);
        vm.prank(user1);
        addressBook.register(user1, _proof(555));

        _expectVerifierInputsForPeriod(period, user2);

        vm.expectRevert(abi.encodeWithSelector(IAddressBook.NullifierAlreadyUsed.selector, 555, period));
        vm.prank(user2);
        addressBook.register(user2, _proof(555));
    }

    function testCannotReuseAddressInSamePeriod() public {
        uint32 period = addressBook.getCurrentPeriod();

        _expectVerifierInputsForPeriod(period, user1);
        vm.prank(user1);
        addressBook.register(user1, _proof(666));

        vm.expectRevert(abi.encodeWithSelector(IAddressBook.AddressAlreadyRegistered.selector, user1, period));
        vm.prank(user1);
        addressBook.register(user1, _proof(667));
    }

    function testCannotRegisterZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IAddressBook.InvalidAccount.selector));
        addressBook.register(address(0), _proof(777));
    }

    function testSignalHashBindingIsEnforced() public {
        uint32 period = addressBook.getCurrentPeriod();

        verifier.setExpectedRpId(RP_ID);
        verifier.setExpectedAction(addressBook.getActionForPeriod(period));
        verifier.setExpectedSignalHash(_expectedSignalHash(user2));

        vm.expectRevert(abi.encodeWithSelector(MockWorldIDVerifier.SignalHashMismatch.selector));
        vm.prank(user1);
        addressBook.register(user1, _proof(888));
    }

    function testCannotRegisterDifferentAccountWithProofBoundToAnother() public {
        uint32 period = addressBook.getCurrentPeriod();

        verifier.setExpectedRpId(RP_ID);
        verifier.setExpectedAction(addressBook.getActionForPeriod(period));
        verifier.setExpectedSignalHash(_expectedSignalHash(user1));

        vm.expectRevert(abi.encodeWithSelector(MockWorldIDVerifier.SignalHashMismatch.selector));
        vm.prank(user2);
        addressBook.register(user2, _proof(889));
    }

    function testThirdPartyCanRegisterAnotherAccount() public {
        uint32 period = addressBook.getCurrentPeriod();

        _expectVerifierInputsForPeriod(period, user2);

        vm.prank(user1);
        addressBook.register(user2, _proof(892));
        assertTrue(addressBook.verify(user2));
    }

    function testVerifierRevertBubblesUp() public {
        uint32 period = addressBook.getCurrentPeriod();

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
}
