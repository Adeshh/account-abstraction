//SPDX-License-Identifier:MIT

pragma solidity ^0.8.24;
import {Test, console} from "forge-std/Test.sol";
import {MinimalAccount} from "src/ethereum/MinimalAccount.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {DeployMinimalAccount} from "script/DeployMinimalAccount.s.sol";
import {ERC20Mock} from "openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {SendPackedUserOp, PackedUserOperation, IEntryPoint} from "script/SendPackedUserOp.s.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/**
 * @title MinimalAccountTest
 * @notice Test suite for MinimalAccount ERC-4337 implementation
 * @dev Tests cover direct execution, access control, signature validation, and EntryPoint integration
 */
contract MinimalAccountTest is Test {
    using MessageHashUtils for bytes32;
    MinimalAccount public minimalAccount;
    HelperConfig public config;
    SendPackedUserOp public sendPackedUserOp;
    ERC20Mock usdc;
    uint256 public constant USDC_AMOUNT = 1e18;
    address user = makeAddr("randomUser");

    function setUp() public {
        DeployMinimalAccount deployer = new DeployMinimalAccount();
        (minimalAccount, config) = deployer.run();
        usdc = new ERC20Mock();
        sendPackedUserOp = new SendPackedUserOp();
    }

    function testOwnerCanExecute() public {
        assertEq(usdc.balanceOf(address(minimalAccount)), 0);
        address dest = address(usdc);
        uint256 value = 0;
        bytes memory functionData =
            abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), USDC_AMOUNT);
        vm.prank(minimalAccount.owner());
        minimalAccount.execute(dest, value, functionData);
    }

    function testNonOwnerCannotExecute() public {
        //arrange
        address dest = address(usdc);
        uint256 value = 0;
        bytes memory functionData =
            abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), USDC_AMOUNT);
        vm.prank(user);

        //act/assert
        vm.expectRevert(MinimalAccount.MinimalAccount__NotEntryPointOrOwner.selector);
        minimalAccount.execute(dest, value, functionData);
    }

    function testRecoverSignedOp() public view {
        //arrange
        address dest = address(usdc);
        uint256 value = 0;
        bytes memory functionData =
            abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), USDC_AMOUNT);
        bytes memory executeCallData =
            abi.encodeWithSelector(MinimalAccount.execute.selector, dest, value, functionData);
        PackedUserOperation memory packedUserOp = sendPackedUserOp.generateSignedUserOperation(
            executeCallData, config.getActiveNetworkConfig(), address(minimalAccount)
        );
        bytes32 userOperationHash = IEntryPoint(config.getActiveNetworkConfig().entryPoint).getUserOpHash(packedUserOp);

        //act
        address actualSigner = ECDSA.recover(userOperationHash.toEthSignedMessageHash(), packedUserOp.signature);

        //assert
        assertEq(actualSigner, minimalAccount.owner());
    }

    function testValidateUserOp() public {
        //arrange
        address dest = address(usdc);
        uint256 value = 0;
        bytes memory functionData =
            abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), USDC_AMOUNT);
        bytes memory executeCallData =
            abi.encodeWithSelector(MinimalAccount.execute.selector, dest, value, functionData);
        PackedUserOperation memory packedUserOp = sendPackedUserOp.generateSignedUserOperation(
            executeCallData, config.getActiveNetworkConfig(), address(minimalAccount)
        );
        bytes32 userOperationHash = IEntryPoint(config.getActiveNetworkConfig().entryPoint).getUserOpHash(packedUserOp);

        //act
        vm.prank(config.getActiveNetworkConfig().entryPoint);
        uint256 validationData = minimalAccount.validateUserOp(packedUserOp, userOperationHash, 1e18);

        //assert
        assertEq(validationData, 0); //0 means success
    }

    function testEntryPointCanExecute() public {
        //arrange
        address dest = address(usdc);
        uint256 value = 0;
        bytes memory functionData =
            abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), USDC_AMOUNT);
        bytes memory executeCallData =
            abi.encodeWithSelector(MinimalAccount.execute.selector, dest, value, functionData);
        PackedUserOperation memory packedUserOp = sendPackedUserOp.generateSignedUserOperation(
            executeCallData, config.getActiveNetworkConfig(), address(minimalAccount)
        );
        //bytes32 userOperationHash = IEntryPoint(config.getActiveNetworkConfig().entryPoint).getUserOpHash(packedUserOp);

        vm.deal(address(minimalAccount), 1e18);
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = packedUserOp;
        console.log("1");
        //act
        vm.prank(user);
        IEntryPoint(config.getActiveNetworkConfig().entryPoint).handleOps(ops, payable(user));
        console.log("2");
        //assert
        assertEq(usdc.balanceOf(address(minimalAccount)), USDC_AMOUNT);
        console.log("3");
    }
}
