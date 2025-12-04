// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {IAccount} from "lib/account-abstraction/contracts/interfaces/IAccount.sol";
import {PackedUserOperation} from "lib/account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {SIG_VALIDATION_FAILED, SIG_VALIDATION_SUCCESS} from "lib/account-abstraction/contracts/core/Helpers.sol";
import {IEntryPoint} from "lib/account-abstraction/contracts/interfaces/IEntryPoint.sol";

contract MinimalAccount is IAccount, Ownable {
    error MinimalAccount__NotEntryPoint();
    error MinimalAccount__NotEntryPointOrOwner();
    error MinimalAccount__CallFailed(bytes returnData);

    IEntryPoint private immutable I_ENTRY_POINT;

    modifier onlyEntryPoint() {
        if (msg.sender != address(I_ENTRY_POINT)) {
            revert MinimalAccount__NotEntryPoint();
        }
        _;
    }

    modifier onlyEntryPointOrOwner() {
        if (msg.sender != address(I_ENTRY_POINT) && msg.sender != owner()) {
            revert MinimalAccount__NotEntryPointOrOwner();
        }
        _;
    }

    constructor(address entryPoint) Ownable(msg.sender) {
        I_ENTRY_POINT = IEntryPoint(entryPoint);
    }

    ///////External Functions/////
    receive() external payable {}

    function execute(address dest, uint256 value, bytes calldata functionData) external onlyEntryPointOrOwner {
        (bool success, bytes memory returnData) = dest.call{value: value}(functionData);
        if (!success) {
            revert MinimalAccount__CallFailed(returnData);
        }
    }

    //Signature is valid if its account owner.
    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash, uint256 missingAccountFunds)
        external
        onlyEntryPoint
        returns (uint256 validationData)
    {
        validationData = _validateSignature(userOp, userOpHash);
        //_validateNonce()
        _payPrefund(missingAccountFunds);
    }

    ///////Internal Functions/////
    //EIP-191 version of signature validation.
    function _validateSignature(PackedUserOperation calldata userOp, bytes32 userOpHash)
        internal
        view
        returns (uint256 validationData)
    {
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(userOpHash);
        address signer = ECDSA.recover(ethSignedMessageHash, userOp.signature);
        //We can also return "0" or "1" directly instead of using the SIG_VALIDATION_FAILED and SIG_VALIDATION_SUCCESS constants.
        if (signer != owner()) {
            return SIG_VALIDATION_FAILED;
        }
        return SIG_VALIDATION_SUCCESS;
    }

    function _payPrefund(uint256 missingAccountFunds) internal {
        if (missingAccountFunds > 0) {
            //We use type(uint256).max to ensure that the call is executed with the maximum possible gas.
            //In account abstraction (ERC-4337), when this _payPrefund function is called, msg.sender is the EntryPoint contract, NOT a regular user address. so our Account will pay to EntryPointContract.
            (bool success,) = payable(msg.sender).call{value: missingAccountFunds, gas: type(uint256).max}("");
            (success);
        }
    }

    ///////Getters////
    function getEntryPoint() public view returns (address) {
        return address(I_ENTRY_POINT);
    }
}
