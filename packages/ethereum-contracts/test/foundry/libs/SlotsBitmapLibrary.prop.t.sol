// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import { ERC1820RegistryCompiled } from "../../../contracts/libs/ERC1820RegistryCompiled.sol";
import { SlotsBitmapLibrary } from "../../../contracts/libs/SlotsBitmapLibrary.sol";
import { ISuperToken } from "../../../contracts/interfaces/superfluid/ISuperToken.sol";
import { ISuperfluidToken } from "../../../contracts/interfaces/superfluid/ISuperfluidToken.sol";
import { SuperTokenFactory, ISuperTokenFactory } from "../../../contracts/superfluid/SuperTokenFactory.sol";
import {
    SuperfluidFrameworkDeployer,
    TestToken,
    SuperToken
} from "../../../contracts/utils/SuperfluidFrameworkDeployer.t.sol";

contract SlotsBitmapLibraryPropertyTest is Test {
    SuperfluidFrameworkDeployer internal immutable sfDeployer;
    TestToken private token;
    ISuperToken private immutable superToken;
    address constant subscriber = address(1);
    bytes32 constant fakeId = keccak256(abi.encodePacked("subscriber", subscriber));

    uint32 internal constant _MAX_NUM_SLOTS = 256;
    /// @dev Subscriber state slot id for storing subs bitmap
    uint256 private constant _SUBSCRIBER_SUBS_BITMAP_STATE_SLOT_ID = 0;
    /// @dev Subscriber state slot id starting point for subscription data
    uint256 private constant _SUBSCRIBER_SUB_DATA_STATE_SLOT_ID_START = 1 << 128;

    constructor() {
        vm.etch(ERC1820RegistryCompiled.at, ERC1820RegistryCompiled.bin);
        vm.startPrank(subscriber);
        sfDeployer = new SuperfluidFrameworkDeployer();
        sfDeployer.deployTestFramework();
        vm.stopPrank();

        vm.startPrank(subscriber);
        (token, superToken) = sfDeployer.deployWrapperSuperToken("Test Token", "TST", 18, type(uint256).max, address(0));
        vm.stopPrank();
    }

    function _listData(ISuperToken _superToken, address _subscriber)
        private
        view
        returns (uint32[] memory slotIds, bytes32[] memory dataList)
    {
        (slotIds, dataList) = SlotsBitmapLibrary.listData(
            _superToken, _subscriber, _SUBSCRIBER_SUBS_BITMAP_STATE_SLOT_ID, _SUBSCRIBER_SUB_DATA_STATE_SLOT_ID_START
        );
    }

    /**
     * @dev Test the assertion below after the function is run once or n times
     *
     * ASSERTION: There should be one more slotId than before (use _listData to check)
     */
    function _findEmptySlotAndFill(ISuperToken _superToken, address _subscriber, bytes32 _subId)
        private
        returns (uint32 slotId)
    {
        slotId = SlotsBitmapLibrary.findEmptySlotAndFill(
            _superToken,
            _subscriber,
            _SUBSCRIBER_SUBS_BITMAP_STATE_SLOT_ID,
            _SUBSCRIBER_SUB_DATA_STATE_SLOT_ID_START,
            _subId
        );

        // NOTE: it is good to assert there is one more slot after each fill OR
        // n more slots after n fills
        // [ASSERT]: ONE_MORE_SLOT_AFTER_FILL | N_MORE_SLOTS_AFTER_FILLS
        // (uint32[] memory newSlotIds, ) = _listData(_superToken, _subscriber);
        // assertEq(_previousSlotIdsLength + 1, newSlotIds.length);
    }

    /**
     * @dev Test the assertions below after the function is run once or n times
     *
     * ASSERTION A: There should be one less slotId than before (use _listData to check)
     * ASSERTION B: The cleared slot should no longer exist (use _slotExists to check)
     */
    function _clearSlot(ISuperToken _superToken, address _subscriber, uint32 _slotId) private {
        SlotsBitmapLibrary.clearSlot(_superToken, _subscriber, _SUBSCRIBER_SUBS_BITMAP_STATE_SLOT_ID, _slotId);

        // NOTE: it is good to assert there is one less slot after each clear OR
        // n fewer slots after n clears

        // [ASSERT]: ONE_LESS_SLOT_AFTER_CLEAR | N_LESS_SLOTS_AFTER_CLEARS
        // (uint32[] memory newSlotIds, ) = _listData(_superToken, _subscriber);
        // assertEq(_previousSlotIdsLength - 1, newSlotIds.length);

        // [ASSERT]: SLOT_NO_LONGER_EXISTS_AFTER_CLEAR
        // bool slotExists = _slotExists(newSlotIds, uint8(_slotId));
        // assert(!slotExists);
    }

    function testCreateConsequtiveSlotsAndRemoveOneSlot(uint8 _numSlots, uint8 _subIdToRemove) public {
        vm.assume(_numSlots > 0);

        (uint32[] memory slotIds,) = _listData(superToken, subscriber);
        assertEq(slotIds.length, 0);

        // add _numSlots elements
        for (uint8 i = 0; i < _numSlots; ++i) {
            _findEmptySlotAndFill(superToken, subscriber, fakeId);
        }

        (uint32[] memory newSlotIds,) = _listData(superToken, subscriber);
        // [ASSERT]: N_MORE_SLOTS_AFTER_FILLS
        assertEq(newSlotIds.length, _numSlots);

        // remove an arbitary slot id between 0 and _numSlots - 1
        _subIdToRemove = uint8(bound(uint256(_subIdToRemove), 0, _numSlots - 1));
        _clearSlot(superToken, subscriber, _subIdToRemove);

        (slotIds,) = _listData(superToken, subscriber);
        // [ASSERT]: ONE_LESS_SLOT_AFTER_CLEAR
        assertEq(slotIds.length, newSlotIds.length - 1);

        bool slotExists = _slotExists(slotIds, _subIdToRemove);
        // [ASSERT]: SLOT_NO_LONGER_EXISTS_AFTER_CLEAR
        assert(!slotExists);
    }

    function testCreateConsequtiveSlotsAndClearAll(uint16 _numSlots) public {
        vm.assume(_numSlots < _MAX_NUM_SLOTS);
        _createConsequtiveSlotsAndClearAll(_numSlots);
    }

    function testCreateRandomSlotsThenCreateConsequtiveSlotsAndClearAll(int256[] memory _instructions) public {
        vm.assume(_instructions.length > 0);
        _createRandomSlots(_instructions);

        (uint32[] memory slotIds,) = _listData(superToken, subscriber);
        uint32 remainingSlots = _MAX_NUM_SLOTS - uint32(slotIds.length);
        _createConsequtiveSlotsAndClearAll(uint8(remainingSlots));
    }

    function testCreateRandomSlotsThenCreateTooMany(int256[] memory _instructions) public {
        vm.assume(_instructions.length > 0);
        _createRandomSlots(_instructions);

        _createNSlots(uint16(_MAX_NUM_SLOTS) + 1);
    }

    function _createNSlots(uint16 _slots) private {
        (uint32[] memory slotIds,) = _listData(superToken, subscriber);
        uint256 currentSlotIdsLength = slotIds.length;
        for (uint16 i = 0; i < _slots; ++i) {
            if (currentSlotIdsLength < uint16(_MAX_NUM_SLOTS)) {
                currentSlotIdsLength++;
                _findEmptySlotAndFill(superToken, subscriber, fakeId);
            } else {
                vm.expectRevert("SlotBitmap out of bound");
                _findEmptySlotAndFill(superToken, subscriber, fakeId);
            }
        }
    }

    function _createConsequtiveSlotsAndClearAll(uint16 _numSlots) private {
        vm.assume(_numSlots > 0 && _numSlots < _MAX_NUM_SLOTS);
        // fill _numSlots slots
        (uint32[] memory slotIds,) = _listData(superToken, subscriber);
        uint256 originalSlotIdsLength = slotIds.length;
        _createNSlots(_numSlots);
        (slotIds,) = _listData(superToken, subscriber);
        // [ASSERT]: N_MORE_SLOTS_AFTER_FILLS
        assertEq(slotIds.length, originalSlotIdsLength + _numSlots);

        // clear all slots
        for (uint32 i = 0; i < slotIds.length; ++i) {
            _clearSlot(superToken, subscriber, slotIds[i]);
        }

        (slotIds,) = _listData(superToken, subscriber);
        // [ASSERT]: N_LESS_SLOTS_AFTER_CLEARS
        assertEq(slotIds.length, 0);
    }

    // randomize the sequence of the two instructions (findEmptySlotAndFill and clearSlot)
    // IF < 0 TRY_CLEAR_SLOT; ELSE TRY_FILL_SLOT
    function _createRandomSlots(int256[] memory _instructions) private {
        vm.assume(_instructions.length > 0);
        vm.assume(_instructions.length < 42);
        uint256 numSlotIds;
        (uint32[] memory slotIds,) = _listData(superToken, subscriber);
        assertEq(slotIds.length, 0);

        // _instructions is a random array of int256 numbers
        for (int256 i = 0; i < int256(_instructions.length); ++i) {
            (slotIds,) = _listData(superToken, subscriber);
            uint256 currentLength = slotIds.length;

            int256 instruction = _instructions[uint256(i)];

            uint8 randomSlotIdToClear = uint8(uint256(instruction));
            randomSlotIdToClear = uint8(bound(uint256(randomSlotIdToClear), 0, type(uint8).max));

            // clearSlot when number is less than 0 AND there are slots to clear
            if (instruction < 0 && slotIds.length > 0) {
                if (_slotExists(slotIds, randomSlotIdToClear)) {
                    _clearSlot(superToken, subscriber, randomSlotIdToClear);

                    (slotIds,) = _listData(superToken, subscriber);
                    // [ASSERT]: ONE_LESS_SLOT_AFTER_CLEAR
                    assertEq(slotIds.length, currentLength - 1);

                    bool slotExists = _slotExists(slotIds, randomSlotIdToClear);
                    // [ASSERT]: SLOT_NO_LONGER_EXISTS_AFTER_CLEAR
                    assert(!slotExists);
                    numSlotIds--;
                }
            }

            // FILL when number is greater than 0 AND the slotIds isn't maxed out
            if (instruction >= 0 && slotIds.length < type(uint8).max) {
                _findEmptySlotAndFill(superToken, subscriber, fakeId);
                (slotIds,) = _listData(superToken, subscriber);
                // [ASSERT]: ONE_MORE_SLOT_AFTER_FILL
                assertEq(slotIds.length, currentLength + 1);
                numSlotIds++;
            }
        }

        (slotIds,) = _listData(superToken, subscriber);
        assertEq(numSlotIds, slotIds.length);
    }

    function _slotExists(uint32[] memory _slotIds, uint8 _slotId) private pure returns (bool slotExists) {
        // if the last element of _slotIds is less than the inputted _slotId, we know that
        // _slotId does not exist in the _slotIds array
        if (_slotIds.length > 0 && _slotIds[_slotIds.length - 1] < _slotId) {
            return false;
        }

        for (uint8 i = 0; i < _slotIds.length; ++i) {
            if (_slotIds[i] == _slotId) slotExists = true;
        }
    }
}
