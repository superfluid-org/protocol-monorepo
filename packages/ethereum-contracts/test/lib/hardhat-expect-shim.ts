import {expect} from "chai";
import {extendEnvironment} from "hardhat/config";
import {lazyObject} from "hardhat/plugins";

import "hardhat/types";

declare module "hardhat/types/runtime" {
    interface HardhatRuntimeEnvironment {
        expect: typeof expect;
    }
}

extendEnvironment((env) => {
    env.expect = lazyObject(() => expect);
});
