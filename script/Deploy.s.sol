// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

/// @title Create2Deployer
/// @notice Helper contract that deploys proxies via CREATE2 and transfers ownership to the caller.
contract Create2Deployer {
    /// @notice Deploys a contract using CREATE2 and initiates ownership transfer to msg.sender.
    /// @param salt The salt to use for the CREATE2 deployment.
    /// @param initCode The init code of the contract to deploy.
    /// @return addr The address of the deployed contract.
    function deploy(bytes32 salt, bytes memory initCode) external returns (address addr) {
        assembly {
            addr := create2(0, add(initCode, 0x20), mload(initCode), salt)
            if iszero(extcodesize(addr)) {
                mstore(0x00, 0x2f8f8019)
                revert(0x1c, 0x04)
            }
        }
        // The proxy's owner is this contract (msg.sender in initialize = address(this)).
        // Initiate 2-step transfer to the caller (the EOA).
        Ownable2StepUpgradeable(addr).transferOwnership(msg.sender);
    }
}

/// @title Deploy
/// @notice Base deployment script with CREATE2, config loading, and deployment artifacts.
/// @dev Concrete scripts inherit this and implement `_run`, `_acceptOwnership`, and `_writeDeployment`.
abstract contract Deploy is Script {
    Create2Deployer internal _deployer;

    /// @notice Deploy contracts for the given environment.
    /// @param env The environment name matching a file in script/config/ (e.g. "staging", "production").
    function run(string calldata env) public {
        string memory config = _loadConfig(env);

        vm.startBroadcast();

        _ensureDeployer();

        _run(config);
        _acceptOwnership();

        vm.stopBroadcast();

        _writeDeployment(env);
    }

    /// @notice Identifier for the deployment (e.g. "recovery-agent"). Used to build the output path.
    function _name() internal pure virtual returns (string memory);

    /// @notice Deploy all contracts for this script. Called between startBroadcast/stopBroadcast.
    function _run(string memory config) internal virtual;

    /// @notice Accept ownership on all deployed proxies, completing the 2-step transfer.
    function _acceptOwnership() internal virtual;

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

    /// @notice Reuses an existing Create2Deployer or deploys a new one.
    /// @dev Set CREATE2_DEPLOYER env var to reuse a previously deployed instance.
    function _ensureDeployer() internal {
        address existing = vm.envOr("CREATE2_DEPLOYER", address(0));

        if (existing != address(0)) {
            _deployer = Create2Deployer(existing);
            console2.log("Create2Deployer found at:", existing);
            return;
        }

        _deployer = new Create2Deployer{salt: bytes32(0)}();
        console2.log("Create2Deployer deployed:", address(_deployer));
    }

    /// @notice Deploy a contract via CREATE2 through the deployer helper.
    function deploy(bytes32 salt, bytes memory initCode) internal returns (address addr) {
        addr = _deployer.deploy(salt, initCode);
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
