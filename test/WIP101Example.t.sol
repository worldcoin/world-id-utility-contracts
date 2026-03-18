// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {WIP101Example} from "src/wip-101/WIP101Example.sol";
import {IWIP101} from "src/wip-101/interfaces/IWIP101.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

contract WIP101ExampleTest is Test {
    WIP101Example internal example;

    uint8 internal constant VERSION = 1;
    uint256 internal constant NONCE = 42;
    uint256 internal constant EXPECTED_ACTION = uint256(keccak256(abi.encodePacked("vote1", uint64(3)))) >> 8;
    bytes4 internal constant MAGICVALUE = 0xc97c0bca;

    function setUp() public {
        example = new WIP101Example();
        vm.warp(1_000_000);
    }

    function _validCreatedAt() internal view returns (uint64) {
        return uint64(block.timestamp - 16 minutes);
    }

    function _validExpiresAt() internal view returns (uint64) {
        return uint64(block.timestamp + 14 minutes);
    }

    function test_validRequest_returnsMagicValue() public view {
        bytes4 result = example.verifyRpRequest(VERSION, NONCE, _validCreatedAt(), _validExpiresAt(), EXPECTED_ACTION);
        assertEq(result, MAGICVALUE);
    }

    function testFuzz_revert_wrongVersion(uint8 version) public {
        vm.assume(version != VERSION);
        vm.expectRevert(IWIP101.InvalidRequest.selector);
        example.verifyRpRequest(version, NONCE, _validCreatedAt(), _validExpiresAt(), EXPECTED_ACTION);
    }

    function test_revert_usedNonce() public {
        example.executeAction(NONCE);

        vm.expectRevert(IWIP101.InvalidRequest.selector);
        example.verifyRpRequest(VERSION, NONCE, _validCreatedAt(), _validExpiresAt(), EXPECTED_ACTION);
    }

    function test_revert_createdAt_inFuture() public {
        uint64 futureCreatedAt = uint64(block.timestamp + 1);
        vm.expectRevert(IWIP101.InvalidRequest.selector);
        example.verifyRpRequest(VERSION, NONCE, futureCreatedAt, _validExpiresAt(), EXPECTED_ACTION);
    }

    function test_revert_expiresAt_tooFarInFuture() public {
        uint64 farExpiry = uint64(block.timestamp + 16 minutes);
        vm.expectRevert(IWIP101.InvalidRequest.selector);
        example.verifyRpRequest(VERSION, NONCE, _validCreatedAt(), farExpiry, EXPECTED_ACTION);
    }

    function test_revert_wrongAction() public {
        uint256 wrongAction = uint256(keccak256(abi.encodePacked("vote2", uint64(3)))) >> 8;
        vm.expectRevert(IWIP101.InvalidRequest.selector);
        example.verifyRpRequest(VERSION, NONCE, _validCreatedAt(), _validExpiresAt(), wrongAction);
    }

    function test_magicValue_matchesFunctionSelector() public pure {
        assertEq(MAGICVALUE, bytes4(keccak256("verifyRpRequest(uint8,uint256,uint64,uint64,uint256)")));
    }

    function testFuzz_executeAction_blocksVerify(uint256 nonce) public {
        example.executeAction(nonce);
        vm.expectRevert(IWIP101.InvalidRequest.selector);
        example.verifyRpRequest(VERSION, nonce, _validCreatedAt(), _validExpiresAt(), EXPECTED_ACTION);
    }
}
