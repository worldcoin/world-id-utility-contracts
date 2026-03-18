// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console2} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {RecoveryAgent} from "src/recovery-agent/RecoveryAgent.sol";
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

        RecoveryAgent implementation = new RecoveryAgent();
        recoveryAgentImplAddress = address(implementation);
        console2.log("  implementation:   ", recoveryAgentImplAddress);

        bytes memory initData = abi.encodeCall(RecoveryAgent.initialize, (msg.sender));
        bytes memory initCode =
            abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(recoveryAgentImplAddress, initData));
        console2.log("  proxy init code hash:");
        console2.logBytes32(keccak256(initCode));

        ERC1967Proxy proxy = new ERC1967Proxy{salt: salt}(recoveryAgentImplAddress, initData);
        recoveryAgentAddress = address(proxy);
        console2.log("  proxy:            ", recoveryAgentAddress);
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
