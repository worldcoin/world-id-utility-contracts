// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console2} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {RecoveryAgent} from "src/RecoveryAgent.sol";
import {Deploy} from "script/Deploy.s.sol";

/// @title DeployRecoveryAgent
/// @notice Deploys the RecoveryAgent proxy with atomic initialization via CREATE2.
/// @dev Usage: forge script script/DeployRecoveryAgent.s.sol --sig "run(string)" "staging" --broadcast --private-key $PK
contract DeployRecoveryAgent is Deploy {
    address public recoveryAgentAddress;
    address public recoveryAgentImplAddress;

    function _run(string memory config) internal override {
        bytes32 salt = _getSalt(config, "recoveryAgent", "SALT_RECOVERY_AGENT");

        console2.log("--- RecoveryAgent ---");
        console2.log("  proxy salt:       ");
        console2.logBytes32(salt);

        address existingImpl = vm.envOr("RECOVERY_AGENT_IMPL", address(0));

        if (existingImpl != address(0)) {
            recoveryAgentImplAddress = existingImpl;
            console2.log("  implementation:   ", existingImpl, "(existing)");
        } else {
            RecoveryAgent implementation = new RecoveryAgent{salt: bytes32(uint256(1))}();
            recoveryAgentImplAddress = address(implementation);
            console2.log("  implementation:   ", recoveryAgentImplAddress);
        }

        bytes memory initData = abi.encodeCall(RecoveryAgent.initialize, ());
        bytes memory initCode =
            abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(recoveryAgentImplAddress, initData));
        console2.log("  proxy init code hash:");
        console2.logBytes32(keccak256(initCode));

        recoveryAgentAddress = deploy(salt, initCode);
        console2.log("  proxy:            ", recoveryAgentAddress);
    }

    function _acceptOwnership() internal override {
        Ownable2StepUpgradeable(recoveryAgentAddress).acceptOwnership();
    }

    function _name() internal pure override returns (string memory) {
        return "recovery-agent";
    }

    function _serializeContracts(string memory rootKey) internal override returns (string memory json) {
        string memory ra = "recoveryAgent";
        vm.serializeAddress(ra, "implementation", recoveryAgentImplAddress);
        string memory raJson = vm.serializeAddress(ra, "proxy", recoveryAgentAddress);

        json = vm.serializeString(rootKey, "recoveryAgent", raJson);
    }
}
