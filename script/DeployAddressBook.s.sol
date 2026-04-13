// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console2} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AddressBook} from "src/address-book/AddressBook.sol";
import {Deploy} from "script/Deploy.s.sol";

/// @title DeployAddressBook
/// @notice Deploys the AddressBook proxy with atomic initialization via CREATE2.
contract DeployAddressBook is Deploy {
    address public addressBookAddress;
    address public addressBookImplAddress;

    function _run(string memory config) internal override {
        bytes32 salt = _getSalt(config, "addressBook", "SALT_ADDRESS_BOOK");

        address worldIDVerifier = vm.parseJsonAddress(config, ".addressBook.worldIDVerifier");
        uint64 rpId = uint64(vm.parseJsonUint(config, ".addressBook.rpId"));
        uint64 issuerSchemaId = uint64(vm.parseJsonUint(config, ".addressBook.issuerSchemaId"));
        uint64 epochDuration = uint64(vm.parseJsonUint(config, ".addressBook.epochDuration"));

        console2.log("--- AddressBook ---");
        console2.log("  proxy salt:       ");
        console2.logBytes32(salt);

        AddressBook implementation = new AddressBook();
        addressBookImplAddress = address(implementation);
        console2.log("  implementation:   ", addressBookImplAddress);

        bytes memory initData =
            abi.encodeCall(AddressBook.initialize, (worldIDVerifier, rpId, issuerSchemaId, epochDuration));
        bytes memory initCode =
            abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(addressBookImplAddress, initData));
        console2.log("  proxy init code hash:");
        console2.logBytes32(keccak256(initCode));

        ERC1967Proxy proxy = new ERC1967Proxy{salt: salt}(addressBookImplAddress, initData);
        addressBookAddress = address(proxy);
        console2.log("  proxy:            ", addressBookAddress);
    }

    function _name() internal pure override returns (string memory) {
        return "address-book";
    }

    function _serializeContracts(string memory rootKey) internal override returns (string memory json) {
        string memory ab = "addressBook";
        vm.serializeAddress(ab, "implementation", addressBookImplAddress);
        string memory abJson = vm.serializeAddress(ab, "proxy", addressBookAddress);

        json = vm.serializeString(rootKey, "addressBook", abJson);
    }
}
