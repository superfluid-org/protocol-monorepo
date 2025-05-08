import {
    CustomSuperTokenCreated,
    SuperTokenCreated,
    SuperTokenLogicCreated,
} from "../../generated/SuperTokenFactory/ISuperTokenFactory";
import {
    CustomSuperTokenCreatedEvent,
    SuperTokenCreatedEvent,
    SuperTokenLogicCreatedEvent,
} from "../../generated/schema";
import {
    createEventID,
    initializeEventEntity,
    tokenHasValidHost,
} from "../utils";
import { getOrInitSuperToken } from "../mappingHelpers";
import { getHostAddress } from "../addresses";

export function handleSuperTokenCreated(event: SuperTokenCreated): void {
    const hostAddress = getHostAddress();
    const hasValidHost = tokenHasValidHost(hostAddress, event.params.token);
    if (!hasValidHost) {
        return;
    }
    const eventId = createEventID("SuperTokenCreated", event);
    const ev = new SuperTokenCreatedEvent(eventId);
    initializeEventEntity(ev, event, [event.params.token]);

    ev.token = event.params.token;
    ev.save();

    getOrInitSuperToken(event, event.params.token, "SuperTokenCreated");
}

export function handleCustomSuperTokenCreated(
    event: CustomSuperTokenCreated
): void {
    const hostAddress = getHostAddress();
    const hasValidHost = tokenHasValidHost(hostAddress, event.params.token);
    if (!hasValidHost) {
        return;
    }
    const eventId = createEventID("CustomSuperTokenCreated", event);
    const ev = new CustomSuperTokenCreatedEvent(eventId);
    initializeEventEntity(ev, event, [event.params.token]);
    ev.token = event.params.token;
    ev.save();

    getOrInitSuperToken(event, event.params.token, "CustomSuperTokenCreated");
}

export function handleSuperTokenLogicCreated(
    event: SuperTokenLogicCreated
): void {
    const hostAddress = getHostAddress();
    const hasValidHost = tokenHasValidHost(hostAddress, event.params.tokenLogic);
    if (!hasValidHost) {
        return;
    }
    const eventId = createEventID("SuperTokenLogicCreated", event);
    const ev = new SuperTokenLogicCreatedEvent(eventId);
    initializeEventEntity(ev, event, [event.params.tokenLogic]);

    ev.tokenLogic = event.params.tokenLogic;
    ev.save();
}
