// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {RecoveryAgent} from "src/recovery-agent/RecoveryAgent.sol";

contract RecoveryAgentTest is Test {
    RecoveryAgent internal agent;
    address internal owner;
    uint256 internal signerKey;
    address internal signer;

    bytes4 internal constant MAGIC_VALUE = 0x1626ba7e;

    function setUp() public {
        owner = address(this);
        (signer, signerKey) = makeAddrAndKey("signer");

        RecoveryAgent impl = new RecoveryAgent();
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), abi.encodeCall(RecoveryAgent.initialize, (owner)));
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
        impl.initialize(owner);
    }

    ////////////////////////////////////////////////////////////
    //                       addSigner                        //
    ////////////////////////////////////////////////////////////

    function test_addSigner() public {
        vm.expectEmit(true, false, false, false, address(agent));
        emit RecoveryAgent.SignerAdded(signer);
        agent.addSigner(signer);
        assertTrue(agent.isAuthorizedSigner(signer));
    }

    function test_addSigner_revertsForNonOwner() public {
        address stranger = makeAddr("stranger");
        vm.prank(stranger);
        vm.expectRevert();
        agent.addSigner(signer);
    }

    function test_addSigner_revertsForZeroAddress() public {
        vm.expectRevert(RecoveryAgent.ZeroAddress.selector);
        agent.addSigner(address(0));
    }

    function test_addSigner_revertsIfAlreadyAuthorized() public {
        agent.addSigner(signer);
        vm.expectRevert(abi.encodeWithSelector(RecoveryAgent.SignerAlreadyAuthorized.selector, signer));
        agent.addSigner(signer);
    }

    ////////////////////////////////////////////////////////////
    //                      removeSigner                      //
    ////////////////////////////////////////////////////////////

    function test_removeSigner() public {
        agent.addSigner(signer);
        vm.expectEmit(true, false, false, false, address(agent));
        emit RecoveryAgent.SignerRemoved(signer);
        agent.removeSigner(signer);
        assertFalse(agent.isAuthorizedSigner(signer));
    }

    function test_removeSigner_revertsForNonOwner() public {
        agent.addSigner(signer);
        address stranger = makeAddr("stranger");
        vm.prank(stranger);
        vm.expectRevert();
        agent.removeSigner(signer);
    }

    function test_removeSigner_revertsIfNotAuthorized() public {
        vm.expectRevert(abi.encodeWithSelector(RecoveryAgent.SignerNotAuthorized.selector, signer));
        agent.removeSigner(signer);
    }

    ////////////////////////////////////////////////////////////
    //                   Signer Enumeration                   //
    ////////////////////////////////////////////////////////////

    function test_signerCount_incrementsOnAdd() public {
        assertEq(agent.signerCount(), 0);

        agent.addSigner(signer);
        assertEq(agent.signerCount(), 1);

        address signer2 = makeAddr("signer2");
        agent.addSigner(signer2);
        assertEq(agent.signerCount(), 2);
    }

    function test_signerCount_decrementsOnRemove() public {
        agent.addSigner(signer);
        agent.removeSigner(signer);
        assertEq(agent.signerCount(), 0);
    }

    function test_signerAt_returnsCorrectAddress() public {
        agent.addSigner(signer);
        assertEq(agent.signerAt(0), signer);
    }

    function test_signerAt_revertsOutOfBounds() public {
        vm.expectRevert();
        agent.signerAt(0);
    }

    function test_getSigners_returnsAllSigners() public {
        address signer2 = makeAddr("signer2");
        address signer3 = makeAddr("signer3");

        agent.addSigner(signer);
        agent.addSigner(signer2);
        agent.addSigner(signer3);

        address[] memory signers = agent.getSigners();
        assertEq(signers.length, 3);
    }

    ////////////////////////////////////////////////////////////
    //               isValidSignature (ERC-1271)              //
    ////////////////////////////////////////////////////////////

    function test_isValidSignature_authorizedSigner() public {
        agent.addSigner(signer);

        bytes32 hash = keccak256("test message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        assertEq(agent.isValidSignature(hash, signature), MAGIC_VALUE);
    }

    function test_isValidSignature_unauthorizedSigner() public {
        bytes32 hash = keccak256("test message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(abi.encodeWithSelector(RecoveryAgent.SignerNotAuthorized.selector, signer));
        agent.isValidSignature(hash, signature);
    }

    function test_isValidSignature_invalidSignature() public {
        agent.addSigner(signer);

        bytes32 hash = keccak256("test message");
        bytes memory badSig = new bytes(65);

        vm.expectRevert(abi.encodeWithSelector(ECDSA.ECDSAInvalidSignature.selector));
        agent.isValidSignature(hash, badSig);
    }

    function test_isValidSignature_removedSigner() public {
        agent.addSigner(signer);
        agent.removeSigner(signer);

        bytes32 hash = keccak256("test message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(abi.encodeWithSelector(RecoveryAgent.SignerNotAuthorized.selector, signer));
        agent.isValidSignature(hash, signature);
    }

    function test_isValidSignature_wrongHash() public {
        agent.addSigner(signer);

        bytes32 originalHash = keccak256("original message");
        bytes32 wrongHash = keccak256("different message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, originalHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        address recovered = ECDSA.recover(wrongHash, signature);

        vm.expectRevert(abi.encodeWithSelector(RecoveryAgent.SignerNotAuthorized.selector, recovered));
        agent.isValidSignature(wrongHash, signature);
    }

    function test_isValidSignatureFuzzy(uint256 privateKey, bytes32 hash) public {
        // bind the private key to valid secp256k1 range
        privateKey = bound(privateKey, 1, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364140);
        address fuzzSigner = vm.addr(privateKey);

        agent.addSigner(fuzzSigner);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        assertEq(agent.isValidSignature(hash, signature), MAGIC_VALUE);
    }

    ////////////////////////////////////////////////////////////
    //                   onlyProxy guard                      //
    ////////////////////////////////////////////////////////////

    function test_isValidSignature_revertsOnImplementation() public {
        RecoveryAgent impl = new RecoveryAgent();
        bytes32 hash = keccak256("test");
        bytes memory sig = new bytes(65);

        vm.expectRevert();
        impl.isValidSignature(hash, sig);
    }

    function test_isAuthorizedSigner_revertsOnImplementation() public {
        RecoveryAgent impl = new RecoveryAgent();
        vm.expectRevert();
        impl.isAuthorizedSigner(signer);
    }

    function test_addSigner_revertsOnImplementation() public {
        RecoveryAgent impl = new RecoveryAgent();
        vm.expectRevert();
        impl.addSigner(signer);
    }

    function test_removeSigner_revertsOnImplementation() public {
        RecoveryAgent impl = new RecoveryAgent();
        vm.expectRevert();
        impl.removeSigner(signer);
    }

    ////////////////////////////////////////////////////////////
    //                   Re-initialization                    //
    ////////////////////////////////////////////////////////////

    function test_proxyCannotBeReinitalized() public {
        vm.expectRevert();
        agent.initialize(owner);
    }

    ////////////////////////////////////////////////////////////
    //        ERC-1271 via OZ SignatureChecker library         //
    ////////////////////////////////////////////////////////////

    function test_signatureChecker_validatesAuthorizedSigner() public {
        agent.addSigner(signer);

        bytes32 hash = keccak256("cross-contract call");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

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

    function test_multisigOwnerCanAddSigner() public {
        (address cosigner1, uint256 cosigner1Key) = makeAddrAndKey("cosigner1");
        (address cosigner2, uint256 cosigner2Key) = makeAddrAndKey("cosigner2");

        Multisig2of2 multisig = new Multisig2of2(cosigner1, cosigner2);

        agent.transferOwnership(address(multisig));
        multisig.execute(address(agent), abi.encodeCall(Ownable2StepUpgradeable.acceptOwnership, ()));
        assertEq(agent.owner(), address(multisig));

        address newSigner = makeAddr("newSigner");
        bytes memory innerCall = abi.encodeCall(RecoveryAgent.addSigner, (newSigner));

        bytes32 digest = multisig.getDigest(address(agent), innerCall, multisig.nonce());
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(cosigner1Key, digest);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(cosigner2Key, digest);

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
        bytes memory innerCall = abi.encodeCall(RecoveryAgent.addSigner, (newSigner));

        bytes32 digest = multisig.getDigest(address(agent), innerCall, multisig.nonce());
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(cosigner1Key, digest);

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

    address public immutable SIGNER_1;
    address public immutable SIGNER_2;
    uint256 public nonce;

    constructor(address _signer1, address _signer2) {
        SIGNER_1 = _signer1;
        SIGNER_2 = _signer2;
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
            (recovered1 == SIGNER_1 && recovered2 == SIGNER_2) || (recovered1 == SIGNER_2 && recovered2 == SIGNER_1);
        if (!valid) revert InvalidSignature();

        nonce++;

        (bool ok, bytes memory ret) = target.call(data);
        if (!ok) revert CallFailed();
        return ret;
    }
}
