import { Address, BigInt } from "@graphprotocol/graph-ts";
import { assert, describe, test } from "matchstick-as";
import { handleMinted } from "../../src/mappings/superToken";
import { handleCustomSuperTokenCreated } from "../../src/mappings/superTokenFactory";
import { ZERO_ADDRESS } from "../../src/utils";
import { bob, alice, resolverAddress } from "../constants";
import { stringToBytes } from "../converters";
import {
    mockedGetHost,
    mockedGetUnderlyingToken,
    mockedTokenName,
    mockedTokenSymbol,
    mockedTokenDecimals,
    mockedTokenTotalSupply,
    mockedResolverGet,
} from "../mockedFunctions";
import { createMintedEvent } from "../superToken/superToken.helper";
import { createCustomSuperTokenCreatedEvent } from "../superTokenFactory/superTokenFactory.helper";

// Issue originally reported here: https://github.com/superfluid-finance/protocol-monorepo/issues/1815
describe("ALEPH Total Supply Bug", () => {
    test("superTokenFactory: handleCustomSuperTokenCreated() + handleMinted() - totalSupply", () => {
        const superToken = bob;
        const totalSupply = BigInt.fromI32(100);
        const data = stringToBytes("");
        const operatorData = stringToBytes("");

        // necessary mock function calls for getOrInitSuperToken
        mockedGetHost(superToken);
        mockedGetUnderlyingToken(superToken, ZERO_ADDRESS.toHex());
        mockedTokenName(superToken, "tokenName");
        mockedTokenSymbol(superToken, "tokenSymbol");
        mockedTokenDecimals(superToken, 18);
        mockedResolverGet(resolverAddress, "supertokens.v1.tokenSymbol", ZERO_ADDRESS.toHexString());

        // unused mocked function call after change in this commit (removing total supply RPC call in getOrInitSuperToken)
        mockedTokenTotalSupply(superToken, totalSupply);

        // create mock events
        const customSuperTokenCreatedEvent = createCustomSuperTokenCreatedEvent(superToken);

        const mintedEvent = createMintedEvent(bob, alice, totalSupply, data, operatorData);
        // modify the minted event address to be the superToken address
        mintedEvent.address = Address.fromString(superToken);

        // handle mock events with handlers
        handleCustomSuperTokenCreated(customSuperTokenCreatedEvent);
        handleMinted(mintedEvent);

        assert.fieldEquals("TokenStatistic", superToken, "totalSupply", totalSupply.toString());
    });
});
