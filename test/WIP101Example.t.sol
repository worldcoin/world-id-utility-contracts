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
    bytes4 internal constant MAGICVALUE = 0x35dbc8de;
    bytes internal constant VALID_DATA = hex"03";

    function setUp() public {
        example = new WIP101Example();
        vm.warp(1_000_000);
    }

    function _validCreatedAt() internal view returns (uint64) {
        return uint64(block.timestamp - 1 minutes);
    }

    function _validExpiresAt() internal view returns (uint64) {
        return uint64(block.timestamp + 14 minutes);
    }

    function _actionFor(bytes memory data) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked("vote1", data))) >> 8;
    }

    function test_validRequest_returnsMagicValue() public view {
        bytes4 result = example.verifyRpRequest(
            VERSION, NONCE, _validCreatedAt(), _validExpiresAt(), _actionFor(VALID_DATA), VALID_DATA
        );
        assertEq(result, MAGICVALUE);
    }

    function testFuzz_revert_wrongVersion(uint8 version) public {
        vm.assume(version != VERSION);
        vm.expectRevert(abi.encodeWithSelector(IWIP101.RpInvalidRequest.selector, 100));
        example.verifyRpRequest(
            version, NONCE, _validCreatedAt(), _validExpiresAt(), _actionFor(VALID_DATA), VALID_DATA
        );
    }

    function test_revert_usedNonce() public {
        example.executeAction(NONCE);

        vm.expectRevert(abi.encodeWithSelector(IWIP101.RpInvalidRequest.selector, 101));
        example.verifyRpRequest(
            VERSION, NONCE, _validCreatedAt(), _validExpiresAt(), _actionFor(VALID_DATA), VALID_DATA
        );
    }

    function test_revert_createdAt_inFuture() public {
        uint64 futureCreatedAt = uint64(block.timestamp + 1);
        vm.expectRevert(abi.encodeWithSelector(IWIP101.RpInvalidRequest.selector, 102));
        example.verifyRpRequest(VERSION, NONCE, futureCreatedAt, _validExpiresAt(), _actionFor(VALID_DATA), VALID_DATA);
    }

    function test_revert_expiresAt_tooFarInFuture() public {
        uint64 farExpiry = uint64(block.timestamp + 16 minutes);
        vm.expectRevert(abi.encodeWithSelector(IWIP101.RpInvalidRequest.selector, 103));
        example.verifyRpRequest(VERSION, NONCE, _validCreatedAt(), farExpiry, _actionFor(VALID_DATA), VALID_DATA);
    }

    function test_revert_wrongAction() public {
        uint256 wrongAction = uint256(keccak256(abi.encodePacked("vote2", VALID_DATA))) >> 8;
        vm.expectRevert(abi.encodeWithSelector(IWIP101.RpInvalidRequest.selector, 105));
        example.verifyRpRequest(VERSION, NONCE, _validCreatedAt(), _validExpiresAt(), wrongAction, VALID_DATA);
    }

    function test_revert_actionMismatchesData() public {
        bytes memory otherData = hex"030102";
        uint256 actionFromOtherData = _actionFor(otherData);
        vm.expectRevert(abi.encodeWithSelector(IWIP101.RpInvalidRequest.selector, 105));
        example.verifyRpRequest(VERSION, NONCE, _validCreatedAt(), _validExpiresAt(), actionFromOtherData, VALID_DATA);
    }

    function test_magicValue_matchesFunctionSelector() public pure {
        assertEq(MAGICVALUE, bytes4(keccak256("verifyRpRequest(uint8,uint256,uint64,uint64,uint256,bytes)")));
    }

    function testFuzz_executeAction_blocksVerify(uint256 nonce) public {
        example.executeAction(nonce);
        vm.expectRevert(abi.encodeWithSelector(IWIP101.RpInvalidRequest.selector, 101));
        example.verifyRpRequest(
            VERSION, nonce, _validCreatedAt(), _validExpiresAt(), _actionFor(VALID_DATA), VALID_DATA
        );
    }
}
