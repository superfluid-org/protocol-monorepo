// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Script, console} from "forge-std/Script.sol";

interface IETHRegistrarController {
    struct Registration {
        string label;
        address owner;
        uint256 duration;
        bytes32 secret;
        address resolver;
        bytes[] data;
        uint8 reverseRecord;
        bytes32 referrer;
    }

    function available(string calldata name) external view returns (bool);
    function makeCommitment(Registration calldata registration) external pure returns (bytes32);
    function commit(bytes32 commitment) external;
    function register(Registration calldata registration) external payable;
    function rentPrice(string calldata name, uint256 duration) external view returns (uint256 base, uint256 premium);
    function minCommitmentAge() external view returns (uint256);
}

contract RegisterEnsSepolia is Script {
    address constant CONTROLLER = 0xfb3cE5D01e0f33f41DbB39035dB9745962F1f968;
    address constant PUBLIC_RESOLVER = 0xE99638b40E4Fff0129D56f03b55b6bbC4BBE49b5;
    uint256 constant DURATION = 365 days;

    function run() external {
        string memory label = vm.envOr("ENS_LABEL", string("sftest"));
        address owner = vm.envAddress("SENDER");

        IETHRegistrarController controller = IETHRegistrarController(CONTROLLER);

        if (!controller.available(label)) {
            revert(string.concat("ENS name ", label, ".eth is not available"));
        }

        (uint256 base, uint256 premium) = controller.rentPrice(label, DURATION);
        uint256 cost = base + premium;
        console.log("Cost:", cost, "wei");
        console.log("Owner:", owner);

        bytes32 secret;
        string memory step = vm.envOr("ENS_STEP", string("commit"));
        bool isCommit = keccak256(abi.encodePacked(step)) == keccak256(abi.encodePacked("commit"));
        secret = bytes32(vm.parseUint(vm.envOr("ENS_SECRET", string(""))));

        if (isCommit) {
            IETHRegistrarController.Registration memory reg = IETHRegistrarController.Registration({
                label: label,
                owner: owner,
                duration: DURATION,
                secret: secret,
                resolver: PUBLIC_RESOLVER,
                data: new bytes[](0),
                reverseRecord: 0,
                referrer: bytes32(0)
            });

            bytes32 commitment = controller.makeCommitment(reg);

            vm.startBroadcast();
            controller.commit(commitment);
            vm.stopBroadcast();

            console.log("Commitment submitted. Wait ~60s then run with ENS_STEP=register using the same ENS_SECRET");
        } else {
            IETHRegistrarController.Registration memory reg = IETHRegistrarController.Registration({
                label: label,
                owner: owner,
                duration: DURATION,
                secret: secret,
                resolver: PUBLIC_RESOLVER,
                data: new bytes[](0),
                reverseRecord: 0,
                referrer: bytes32(0)
            });

            vm.startBroadcast();
            controller.register{value: cost}(reg);
            vm.stopBroadcast();

            console.log("Registered", label, ".eth");
        }
    }
}
