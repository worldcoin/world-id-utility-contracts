// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";

/// @title Deploy
/// @notice Base deployment script with CREATE2, config loading, and deployment artifacts.
/// @dev Concrete scripts inherit this and implement `_run` and `_serializeContracts`.
abstract contract Deploy is Script {
    /// @notice Deploy contracts for the given environment.
    /// @param env The environment name matching a file in script/config/ (e.g. "staging", "production").
    function run(string calldata env) public {
        string memory config = _loadConfig(env);

        vm.startBroadcast();
        _run(config);
        vm.stopBroadcast();

        _writeDeployment(env);
    }

    /// @notice Identifier for the deployment (e.g. "recovery-agent"). Used to build the output path.
    function _name() internal pure virtual returns (string memory);

    /// @notice Deploy all contracts for this script. Called between startBroadcast/stopBroadcast.
    function _run(string memory config) internal virtual;

    /// @notice Serialize contract-specific addresses into the root JSON key and return the final JSON.
    function _serializeContracts(string memory rootKey) internal virtual returns (string memory json);

    /// @notice Write deployment artifacts to deployments/{name}/{env}.json.
    function _writeDeployment(string memory env) internal {
        string memory root = "root";
        _serializeMetadata(root);
        string memory json = _serializeContracts(root);

        string memory dir = string.concat("deployments/", _name());
        vm.createDir(dir, true);
        string memory path = string.concat(dir, "/", env, ".json");
        vm.writeJson(json, path);
        console2.log("Deployment written to", path);
    }

    /// @notice Returns a salt, preferring the environment variable if set over the JSON config value.
    /// @param config The raw JSON config string.
    /// @param key The key under `.salts` in the config (e.g. "recoveryAgent").
    /// @param envVar The env var name to check first (e.g. "SALT_RECOVERY_AGENT").
    function _getSalt(string memory config, string memory key, string memory envVar) internal view returns (bytes32) {
        return vm.envOr(envVar, vm.parseJsonBytes32(config, string.concat(".salts.", key)));
    }

    /// @notice Loads a JSON config file for the given environment.
    function _loadConfig(string memory env) internal view returns (string memory json) {
        string memory path = string.concat("script/config/", env, ".json");
        json = vm.readFile(path);
    }

    /// @notice Serialize common deployment metadata into a JSON key and return the partial JSON.
    /// @param rootKey The serialization key for the root object.
    function _serializeMetadata(string memory rootKey) internal returns (string memory json) {
        vm.serializeUint(rootKey, "chainId", block.chainid);
        vm.serializeAddress(rootKey, "deployer", msg.sender);
        vm.serializeUint(rootKey, "timestamp", block.timestamp);
        json = vm.serializeString(rootKey, "commitSha", vm.envOr("GIT_COMMIT", string("")));
    }
}
