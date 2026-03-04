// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {RecoveryAgent} from "src/RecoveryAgent.sol";

contract RecoveryAgentTest is Test {
    RecoveryAgent internal agent;
    address internal owner;
    uint256 internal signerKey;
    address internal signer;

    bytes4 internal constant MAGIC_VALUE = 0x1626ba7e;
    bytes4 internal constant INVALID_VALUE = 0xffffffff;

    function setUp() public {
        owner = address(this);
        (signer, signerKey) = makeAddrAndKey("signer");

        RecoveryAgent impl = new RecoveryAgent();
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), abi.encodeCall(RecoveryAgent.initialize, ()));
        agent = RecoveryAgent(address(proxy));
    }

    ////////////////////////////////////////////////////////////
    //                     Initialization                     //
    ////////////////////////////////////////////////////////////

    function test_ownerIsDeployer() public view {
        assertEq(agent.owner(), owner);
    }

    function test_implementationCannotBeInitialized() public {
        RecoveryAgent impl = new RecoveryAgent();
        vm.expectRevert();
        impl.initialize();
    }

    ////////////////////////////////////////////////////////////
    //                      updateSigner                      //
    ////////////////////////////////////////////////////////////

    function test_addSigner() public {
        vm.expectEmit(true, false, false, false, address(agent));
        emit RecoveryAgent.SignerAuthorized(signer);
        agent.updateSigner(signer, true);
        assertTrue(agent.isAuthorizedSigner(signer));
    }

    function test_removeSigner() public {
        agent.updateSigner(signer, true);
        vm.expectEmit(true, false, false, false, address(agent));
        emit RecoveryAgent.SignerUnauthorized(signer);
        agent.updateSigner(signer, false);
        assertFalse(agent.isAuthorizedSigner(signer));
    }

    function test_updateSigner_revertsForNonOwner() public {
        address stranger = makeAddr("stranger");
        vm.prank(stranger);
        vm.expectRevert();
        agent.updateSigner(signer, true);
    }

    ////////////////////////////////////////////////////////////
    //               isValidSignature (ERC-1271)              //
    ////////////////////////////////////////////////////////////

    function test_isValidSignature_authorizedSigner() public {
        agent.updateSigner(signer, true);

        bytes32 hash = keccak256("test message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        assertEq(agent.isValidSignature(hash, signature), MAGIC_VALUE);
    }

    function test_isValidSignature_unauthorizedSigner() public view {
        bytes32 hash = keccak256("test message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        assertEq(agent.isValidSignature(hash, signature), INVALID_VALUE);
    }

    function test_isValidSignature_invalidSignature() public {
        agent.updateSigner(signer, true);

        bytes32 hash = keccak256("test message");
        bytes memory badSig = new bytes(65);

        assertEq(agent.isValidSignature(hash, badSig), INVALID_VALUE);
    }

    function test_isValidSignature_removedSigner() public {
        agent.updateSigner(signer, true);
        agent.updateSigner(signer, false);

        bytes32 hash = keccak256("test message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        assertEq(agent.isValidSignature(hash, signature), INVALID_VALUE);
    }

    ////////////////////////////////////////////////////////////
    //        ERC-1271 via OZ SignatureChecker library         //
    ////////////////////////////////////////////////////////////

    function test_signatureChecker_validatesAuthorizedSigner() public {
        agent.updateSigner(signer, true);

        bytes32 hash = keccak256("cross-contract call");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // OZ SignatureChecker sees address(agent) has code,
        // falls through to isValidERC1271SignatureNow which
        // calls isValidSignature and checks the magic value.
        assertTrue(SignatureChecker.isValidSignatureNow(address(agent), hash, signature));
    }

    function test_signatureChecker_rejectsUnauthorizedSigner() public view {
        bytes32 hash = keccak256("cross-contract call");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        assertFalse(SignatureChecker.isValidSignatureNow(address(agent), hash, signature));
    }

    ////////////////////////////////////////////////////////////
    //                   Multisig as owner                    //
    ////////////////////////////////////////////////////////////

    function test_multisigOwnerCanUpdateSigner() public {
        // Set up two multisig co-signers
        (address cosigner1, uint256 cosigner1Key) = makeAddrAndKey("cosigner1");
        (address cosigner2, uint256 cosigner2Key) = makeAddrAndKey("cosigner2");

        // Deploy 2-of-2 multisig
        Multisig2of2 multisig = new Multisig2of2(cosigner1, cosigner2);

        // Transfer ownership to the multisig (2-step)
        agent.transferOwnership(address(multisig));
        multisig.execute(address(agent), abi.encodeCall(Ownable2StepUpgradeable.acceptOwnership, ()));
        assertEq(agent.owner(), address(multisig));

        // Build the updateSigner call the multisig will execute
        address newSigner = makeAddr("newSigner");
        bytes memory innerCall = abi.encodeCall(RecoveryAgent.updateSigner, (newSigner, true));

        // Both co-signers sign the execution digest
        bytes32 digest = multisig.getDigest(address(agent), innerCall, multisig.nonce());
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(cosigner1Key, digest);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(cosigner2Key, digest);

        // Execute through multisig with both signatures
        multisig.executeWithSignatures(
            address(agent), innerCall, abi.encodePacked(r1, s1, v1), abi.encodePacked(r2, s2, v2)
        );

        assertTrue(agent.isAuthorizedSigner(newSigner));
    }

    function test_multisigOwner_singleSignatureReverts() public {
        (address cosigner1, uint256 cosigner1Key) = makeAddrAndKey("cosigner1");
        (address cosigner2,) = makeAddrAndKey("cosigner2");

        Multisig2of2 multisig = new Multisig2of2(cosigner1, cosigner2);

        agent.transferOwnership(address(multisig));
        multisig.execute(address(agent), abi.encodeCall(Ownable2StepUpgradeable.acceptOwnership, ()));

        address newSigner = makeAddr("newSigner");
        bytes memory innerCall = abi.encodeCall(RecoveryAgent.updateSigner, (newSigner, true));

        bytes32 digest = multisig.getDigest(address(agent), innerCall, multisig.nonce());
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(cosigner1Key, digest);

        // Second sig from cosigner1 again (not cosigner2)
        vm.expectRevert(Multisig2of2.InvalidSignature.selector);
        multisig.executeWithSignatures(
            address(agent), innerCall, abi.encodePacked(r1, s1, v1), abi.encodePacked(r1, s1, v1)
        );
    }
}

/// @dev Minimal 2-of-2 multisig for testing. Models the Safe flow:
/// co-signers sign off-chain, then signatures are submitted
/// in a single transaction that verifies and executes.
contract Multisig2of2 {
    error InvalidSignature();
    error CallFailed();

    address public immutable signer1;
    address public immutable signer2;
    uint256 public nonce;

    constructor(address _signer1, address _signer2) {
        signer1 = _signer1;
        signer2 = _signer2;
    }

    function getDigest(address target, bytes memory data, uint256 _nonce) public pure returns (bytes32) {
        return keccak256(abi.encode(target, data, _nonce));
    }

    /// @dev Execute without signature verification (for setup
    ///      calls like acceptOwnership during tests).
    function execute(address target, bytes memory data) external returns (bytes memory) {
        (bool ok, bytes memory ret) = target.call(data);
        if (!ok) revert CallFailed();
        return ret;
    }

    /// @dev Execute with 2-of-2 signature verification.
    function executeWithSignatures(address target, bytes memory data, bytes memory sig1, bytes memory sig2)
        external
        returns (bytes memory)
    {
        bytes32 digest = getDigest(target, data, nonce);

        address recovered1 = ECDSA.recover(digest, sig1);
        address recovered2 = ECDSA.recover(digest, sig2);

        bool valid =
            (recovered1 == signer1 && recovered2 == signer2) || (recovered1 == signer2 && recovered2 == signer1);
        if (!valid) revert InvalidSignature();

        nonce++;

        (bool ok, bytes memory ret) = target.call(data);
        if (!ok) revert CallFailed();
        return ret;
    }
}
