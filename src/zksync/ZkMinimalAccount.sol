//SPDX-License-Identifier:MIT

pragma solidity ^0.8.24;

import {
    IAccount,
    ACCOUNT_VALIDATION_SUCCESS_MAGIC
} from "lib/foundry-era-contracts/src/system-contracts/contracts/interfaces/IAccount.sol";
import {
    Transaction,
    MemoryTransactionHelper
} from "lib/foundry-era-contracts/src/system-contracts/contracts/libraries/MemoryTransactionHelper.sol";
import {
    SystemContractsCaller
} from "lib/foundry-era-contracts/src/system-contracts/contracts/libraries/SystemContractsCaller.sol";
import {
    NONCE_HOLDER_SYSTEM_CONTRACT,
    BOOTLOADER_FORMAL_ADDRESS,
    DEPLOYER_SYSTEM_CONTRACT
} from "lib/foundry-era-contracts/src/system-contracts/contracts/Constants.sol";
import {INonceHolder} from "lib/foundry-era-contracts/src/system-contracts/contracts/interfaces/INonceHolder.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {Utils} from "lib/foundry-era-contracts/src/system-contracts/contracts/libraries/Utils.sol";

contract ZkMinimalAccount is IAccount, Ownable {
    using MemoryTransactionHelper for Transaction;

    error ZkMinimalAccount__NotEnoughBalance();
    error ZkMinimalAccount__NotFromBootloader();
    error ZkMinimalAccount__NotFromBootloaderOrOwner();
    error ZkMinimalAccount__ExecutionFailed();
    error ZkMinimalAccount__InvalidSignature();
    error ZkMinimalAccount__FailedToPay();
    ///////Modifiers/////
    modifier onlyBootloader() {
        if (msg.sender != BOOTLOADER_FORMAL_ADDRESS) {
            revert ZkMinimalAccount__NotFromBootloader();
        }
        _;
    }

    modifier onlyBootloaderOrOwner() {
        if (msg.sender != BOOTLOADER_FORMAL_ADDRESS && msg.sender != owner()) {
            revert ZkMinimalAccount__NotFromBootloaderOrOwner();
        }
        _;
    }

    constructor() Ownable(msg.sender) {}

    ///////External Functions/////
    receive() external payable {}

    /**
     * @notice - Validation must increase the nonce and check the owner signed the transaction
     *         - Called by the bootloader to validate that an account agrees to process the transaction
     *         - Function also should check if there is enough balance to pay for the transaction
     *
     * @param _transaction The transaction itself
     */
    function validateTransaction(
        bytes32,
        /*_txHash*/
        bytes32,
        /*_suggestedSignedHash*/
        Transaction memory _transaction
    )
        external
        payable
        onlyBootloader
        returns (bytes4 magic)
    {
        return _validateTransaction(_transaction);
    }

    function executeTransaction(
        bytes32,
        /*_txHash*/
        bytes32,
        /*_suggestedSignedHash*/
        Transaction memory _transaction
    )
        external
        payable
        onlyBootloaderOrOwner
    {
        _executeTransaction(_transaction);
    }

    function executeTransactionFromOutside(Transaction calldata _transaction) external payable {
        bytes4 magic = _validateTransaction(_transaction);
        if (magic != ACCOUNT_VALIDATION_SUCCESS_MAGIC) {
            revert ZkMinimalAccount__InvalidSignature();
        }
        _executeTransaction(_transaction);
    }

    function payForTransaction(
        bytes32,
        /*_txHash*/
        bytes32,
        /*_suggestedSignedHash*/
        Transaction memory _transaction
    )
        external
        payable
    {
        bool success = _transaction.payToTheBootloader();
        if (!success) {
            revert ZkMinimalAccount__FailedToPay();
        }
    }

    function prepareForPaymaster(
        bytes32,
        /*_txHash*/
        bytes32,
        /*_possibleSignedHash*/
        Transaction memory _transaction
    )
        external
        payable {}

    ///////Internal Functions/////
    function _validateTransaction(Transaction memory _transaction) internal returns (bytes4 magic) {
        //increase the nonce
        SystemContractsCaller.systemCallWithPropagatedRevert(
            uint32(gasleft()),
            address(NONCE_HOLDER_SYSTEM_CONTRACT),
            0,
            abi.encodeCall(INonceHolder.incrementMinNonceIfEquals, (_transaction.nonce))
        );
        //check for enough balance to pay for the transaction
        uint256 totalRequiredBalance = MemoryTransactionHelper.totalRequiredBalance(_transaction);
        if (totalRequiredBalance > address(this).balance) {
            revert ZkMinimalAccount__NotEnoughBalance();
        }

        //check if the owner signed the transaction
        bytes32 txHash = _transaction.encodeHash();
        //bytes32 convertedHash = MessageHashUtils.toEthSignedMessageHash(txHash);
        address signer = ECDSA.recover(txHash, _transaction.signature);
        bool isValidSigner = signer == owner();
        if (isValidSigner) {
            magic = ACCOUNT_VALIDATION_SUCCESS_MAGIC;
        } else {
            magic = bytes4(0);
        }
        return magic;
    }

    function _executeTransaction(Transaction memory _transaction) internal {
        address to = address(uint160(_transaction.to));
        uint128 value = Utils.safeCastToU128(_transaction.value);
        bytes memory data = _transaction.data;

        if (to == address(DEPLOYER_SYSTEM_CONTRACT)) {
            uint32 gas = Utils.safeCastToU32(gasleft());
            SystemContractsCaller.systemCallWithPropagatedRevert(gas, to, value, data);
        } else {
            bool success;
            assembly {
                success := call(gas(), to, value, add(data, 0x20), mload(data), 0, 0)
            }
            if (!success) {
                revert ZkMinimalAccount__ExecutionFailed();
            }
        }
    }
}
