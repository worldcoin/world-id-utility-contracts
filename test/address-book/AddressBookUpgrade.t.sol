// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {AddressBook} from "../../src/address-book/AddressBook.sol";
import {IAddressBook} from "../../src/address-book/interfaces/IAddressBook.sol";

contract MockWorldIDVerifierUpgrade {
    bool public shouldRevert;

    function setShouldRevert(bool value) external {
        shouldRevert = value;
    }

    function verify(uint256, uint256, uint64, uint256, uint256, uint64, uint64, uint256, uint256[5] calldata)
        external
        view
    {
        if (shouldRevert) {
            revert("proof-invalid");
        }
    }
}

contract AddressBookV2Mock is AddressBook {
    uint256 public newFeature;

    function version() external pure returns (string memory) {
        return "V2";
    }

    function setNewFeature(uint256 value) external {
        newFeature = value;
    }
}

contract AddressBookUpgradeTest is Test {
    uint64 internal constant RP_ID = 42;
    uint64 internal constant ISSUER_SCHEMA_ID = 8;
    uint64 internal constant EPOCH_DURATION = 30 days;
    uint64 internal constant INITIAL_TIMESTAMP = 1_234 * EPOCH_DURATION;

    AddressBook internal addressBook;
    MockWorldIDVerifierUpgrade internal verifier;

    address internal user1 = address(0x1001);

    function setUp() public {
        vm.warp(INITIAL_TIMESTAMP);

        verifier = new MockWorldIDVerifierUpgrade();
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

    function testUpgradePreservesState() public {
        uint64 currentPeriod = addressBook.getCurrentPeriod();
        uint256 currentAction = addressBook.getCurrentAction();

        vm.prank(user1);
        addressBook.register(user1, _proof(111));

        assertTrue(addressBook.verify(user1));
        assertTrue(addressBook.isRegisteredForAction(currentAction, user1));

        AddressBookV2Mock implementationV2 = new AddressBookV2Mock();
        addressBook.upgradeToAndCall(address(implementationV2), "");

        AddressBookV2Mock upgraded = AddressBookV2Mock(address(addressBook));

        assertTrue(upgraded.verify(user1));
        assertTrue(upgraded.isRegisteredForAction(currentAction, user1));
        assertEq(upgraded.getWorldIDVerifier(), address(verifier));
        assertEq(upgraded.getEpochDuration(), EPOCH_DURATION);
        assertEq(upgraded.getRpId(), RP_ID);
        assertEq(upgraded.getCurrentPeriod(), currentPeriod);
        assertEq(upgraded.getCurrentAction(), currentAction);
        assertEq(upgraded.getActionForPeriod(currentPeriod), currentAction);

        upgraded.setNewFeature(42);
        assertEq(upgraded.newFeature(), 42);
        assertEq(upgraded.version(), "V2");
    }

    function testUpgradeFailsForNonOwner() public {
        AddressBookV2Mock implementationV2 = new AddressBookV2Mock();

        vm.prank(address(0xBEEF));
        vm.expectRevert();
        addressBook.upgradeToAndCall(address(implementationV2), "");
    }
}
