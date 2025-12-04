//SPDX-License-Identifier:MIT

pragma solidity ^0.8.24;
import {Test, console} from "forge-std/Test.sol";
import {MinimalAccount} from "src/ethereum/MinimalAccount.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {DeployMinimalAccount} from "script/DeployMinimalAccount.s.sol";
import {ERC20Mock} from "openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {SendPackedUserOp} from "script/SendPackedUserOp.s.sol";

contract MinimalAccountTest is Test {
    MinimalAccount public minimalAccount;
    HelperConfig public helperConfig;
    SendPackedUserOp public sendPackedUserOp;
    ERC20Mock usdc;
    uint256 public constant USDC_AMOUNT = 1e18;
    address user = makeAddr("user");

    function setUp() public {
        DeployMinimalAccount deployer = new DeployMinimalAccount();
        (minimalAccount, helperConfig) = deployer.run();
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
        address dest = address(usdc);
        uint256 value = 0;
        bytes memory functionData =
            abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), USDC_AMOUNT);
        vm.prank(user);
        vm.expectRevert(MinimalAccount.MinimalAccount__NotEntryPointOrOwner.selector);
        minimalAccount.execute(dest, value, functionData);
    }

    // function testRecoverSignedOp() public {
    //     address dest = address(usdc);
    //     uint256 value = 0;
    //     bytes memory functionData = abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), USDC_AMOUNT);
    //     bytes memory executeCallData = abi.encodeWithSelector(MinimalAccount.execute.selector, dest, value, functionData);
    //     PackedUserOperation packedUserOp = sendPackedUserOp.generateSignedUserOperation(executeCallData, helperConfig.activeNetworkConfig());

    // }

    // function testValidateUserOp() public {}
}
