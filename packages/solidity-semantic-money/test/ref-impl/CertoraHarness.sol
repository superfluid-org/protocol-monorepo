// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import { ToySuperfluidPool } from "../../src/ref-impl/ToySuperfluidToken.sol";


contract CertoraSuperfluidPool1 is ToySuperfluidPool {
    constructor (address admin) {
        initialize(admin);
    }
}

contract CertoraSuperfluidPool2 is ToySuperfluidPool {
    constructor (address admin) {
        initialize(admin);
    }
}

// contract CertoraSuperfluidToken is ToySuperfluidToken {
//
//     /* event SET_UINDEX(address owner, FlowRate r0, FlowRate r1); */
//
//     /* function _setUIndex(bytes memory eff, address owner, BasicParticle memory p) */
//     /*     internal virtual override */
//     /* { */
//     /* uIndexes[owner].settled_at = p.settled_at; */
//     /* uIndexes[owner].settled_value = p.settled_value; */
//     /* uIndexes[owner].flow_rate = p.flow_rate; */
//     /*     FlowRate r0 = uIndexes[owner].flow_rate; */
//     /*     super._setUIndex(eff, owner, p); */
//     /*     FlowRate r1 = uIndexes[owner].flow_rate; */
//     /*     emit SET_UINDEX(owner, r0, r1); */
//     /* } */
//
//     /* function _setPDPIndex(bytes memory /\*eff*\/, address pool, PDPoolIndex memory p) */
//     /*     internal virtual override */
//     /* { */
//     /*     assert(ISuperfluidPool(pool).operatorSetIndex(p)); */
//     /* } */
//
// }
