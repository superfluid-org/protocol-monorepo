// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.23;

import { console, console2 } from "forge-std/Test.sol";

import { FoundrySuperfluidTester, SuperTokenV1Library } from "../FoundrySuperfluidTester.sol";
import { ISuperfluid } from "../../../contracts/superfluid/Superfluid.sol";
import { ISuperToken } from "../../../contracts/superfluid/SuperToken.sol";
import { IConstantFlowAgreementV1 } from "../../../contracts/agreements/ConstantFlowAgreementV1.sol";
import { CFASuperAppBase } from "../../../contracts/apps/CFASuperAppBase.sol";
import { SuperTokenV1Library } from "../../../contracts/apps/SuperTokenV1Library.sol";

using SuperTokenV1Library for ISuperToken;

enum Modes {
    DO_NOTHING,
    FORWARD_HALF, // forward with half flowrate
    FORWARD_ALL, // forward with full flowrate
    MAX_OUT // forward with the max flowrate allowed by app credit granted
}

// helper free functions

function modeToText(Modes mode) pure returns (string memory) {
    if (mode == Modes.DO_NOTHING) return "DO_NOTHING";
    if (mode == Modes.FORWARD_HALF) return "FORWARD_HALF";
    if (mode == Modes.FORWARD_ALL) return "FORWARD_ALL";
    if (mode == Modes.MAX_OUT) return "MAX_OUT";
    return "UNKNOWN";
}

// right-shifts (deposit) amounts by 32 bits
// this makes them more human-readable
// (mitigation for the 32 bit clipping forcing a high floor)
function scaleDiv32(uint256 deposit) pure returns (uint256) {
    return deposit >> 32;
}

function toU256(int96 x) pure returns (uint256) {
    return uint256(int256(x));
}


/// A SuperApp which forwards incoming streams partially, fully or maxing out the app credit
contract ForwardingSuperApp is CFASuperAppBase {
    ISuperToken public superToken;
    address public receiver;
    Modes public mode; // 0 do nothing, 1: forward half, 2: forward all, 3: max out
    bytes public inCtx; // ctx when entering the callback
    bytes public outCtx; // ctx when leaving the callback

    constructor(ISuperfluid host_, ISuperToken superToken_, address receiver_) CFASuperAppBase(host_) {
        selfRegister(true, true, true);
        receiver = receiver_;
        superToken = superToken_;
    }

    function isAcceptedSuperToken(ISuperToken superToken_) public view override returns (bool) {
        return superToken_ == superToken;
    }

    function setMode(Modes mode_) public {
        mode = mode_;
    }

    function onFlowCreated(ISuperToken, address sender, bytes calldata ctx)
        internal override returns (bytes memory newCtx)
    {
        inCtx = ctx;
        newCtx = ctx;
        if (mode != Modes.DO_NOTHING) {
            newCtx = superToken.createFlowWithCtx(receiver, _getOutFr(sender, newCtx), newCtx);
        }
        outCtx = newCtx;
    }

    function onFlowUpdated(ISuperToken, address sender, int96 /*prevFr*/, uint256 /*lastTs*/, bytes calldata ctx)
        internal override returns (bytes memory newCtx)
    {
        inCtx = ctx;
        newCtx = ctx;
        if (mode != Modes.DO_NOTHING) {
            newCtx = superToken.updateFlowWithCtx(receiver, _getOutFr(sender, newCtx), newCtx);
        }
        outCtx = newCtx;
    }

    function _getOutFr(address sender, bytes memory ctx) internal view returns(int96) {
        (,int96 fr,,) = superToken.getFlowInfo(sender, address(this));

        if (mode == Modes.FORWARD_HALF) {
            return fr / 2; // half the incoming fr
        } else if (mode == Modes.FORWARD_ALL) {
            return fr; // full incoming fr
        } else if (mode == Modes.MAX_OUT) {
            ISuperfluid.Context memory c = HOST.decodeCtx(ctx);
            IConstantFlowAgreementV1 cfa = IConstantFlowAgreementV1(address(HOST.getAgreementClass(CFAV1_TYPE)));
            int96 maxFr = cfa.getMaximumFlowRateFromDeposit(superToken, c.appCreditGranted);
            return maxFr; // max possible with deposit
        }
        return 0;
    }
}

contract AppCreditTest is FoundrySuperfluidTester {
    ForwardingSuperApp app;

    constructor() FoundrySuperfluidTester(3) { }

    function setUp() public override {
        super.setUp();
        app = new ForwardingSuperApp(sf.host, superToken, bob);
    }

    function testUpdateFlowWithMinDeposit() public {
        _setMinimumDeposit(1e3 << 32); // 1k shifted by clipping
        app.setMode(Modes.FORWARD_ALL);

        vm.startPrank(alice);
        superToken.createFlow(address(app), 4);
        _printStatsExtended("#1: alice -> app createFlow");
        // here as expected the deposit is 2 * minDeposit and owedDeposit is minDeposit
        vm.stopPrank();

        (,uint256 depositPreUpdate,,) = superToken.realtimeBalanceOfNow(alice);

        vm.startPrank(alice);
        superToken.updateFlow(address(app), 8);
        _printStatsExtended("#2: alice -> app updateFlow");

        (,uint256 depositPostUpdate,,) = superToken.realtimeBalanceOfNow(alice);
        assertGe(depositPostUpdate, depositPreUpdate, "deposit shouldn't decrease");

        vm.stopPrank();
    }

    // HELPERS

    function _setMinimumDeposit(uint256 md) internal {
        console2.log("Minimum deposit %d (raw: %d)", scaleDiv32(md), md);
        vm.startPrank(address(sf.governance.owner()));
        sf.governance.setSuperTokenMinimumDeposit(sf.host, superToken, md);
        vm.stopPrank();
    }

    function _printStats(string memory tag) internal view {
        console.log("===== %s | app mode %s | blocktime %d =====", tag, modeToText(app.mode()), block.timestamp);
        (,int96 oFr, uint256 oDeposit, uint256 oOwedDeposit) = superToken.getFlowInfo(alice, address(app));
        (,int96 iFr, uint256 iDeposit, uint256 iOwedDeposit) = superToken.getFlowInfo(address(app), bob);
        console2.log("  alice -> app FR %d, deposit %d", toU256(oFr), scaleDiv32(oDeposit), scaleDiv32(oOwedDeposit));
        console2.log("  app -> bob FR %d, deposit %d", toU256(iFr), scaleDiv32(iDeposit), scaleDiv32(iOwedDeposit));
        _logAppCreditState(app.inCtx(),  "ctx in ");
        _logAppCreditState(app.outCtx(), "ctx out");
    }

    function _printStatsExtended(string memory tag) internal view{
        _printStats(tag);
        _printAccStats(alice, "alice");
        _printAccStats(address(app), "app");
    }

    function _printAccStats(address acc, string memory tag) internal view {
        console.log("  == acc %s ==", tag);
        (int256 availBal, uint256 deposit, uint256 owedDeposit,) = superToken.realtimeBalanceOfNow(acc);
        console2.log("  realtimeBalance %d", availBal);
        console2.log("  deposit", scaleDiv32(deposit), scaleDiv32(owedDeposit));
    }

    function _logAppCreditState(bytes memory ctx, string memory tag) internal view {
        ISuperfluid.Context memory c = sf.host.decodeCtx(ctx);
        console2.log("  APP %s: credit granted|used",
            tag, scaleDiv32(c.appCreditGranted), scaleDiv32(uint256(c.appCreditUsed)));
    }
}
