import {
    AgreementClassRegisteredEvent,
    AgreementClassUpdatedEvent,
    AppRegisteredEvent,
    GovernanceReplacedEvent,
    JailEvent,
    SFMeta,
    SuperTokenFactoryUpdatedEvent,
    SuperTokenLogicUpdatedEvent,
} from "../../generated/schema";
import {
    AgreementClassRegistered,
    AgreementClassUpdated,
    AppRegistered,
    GovernanceReplaced,
    Jail,
    SuperTokenFactoryUpdated,
    SuperTokenLogicUpdated,
} from "../../generated/Host/ISuperfluid";
import { createEventID, initializeEventEntity } from "../utils";
import { commitHash, configuration, branch, packageVersion } from "../meta.ignore";
import { ethereum } from "@graphprotocol/graph-ts";
import { SuperfluidGovernance } from "../../generated/templates";

export function handleGovernanceReplaced(event: GovernanceReplaced): void {
    const eventId = createEventID("GovernanceReplaced", event);
    const ev = new GovernanceReplacedEvent(eventId);
    initializeEventEntity(ev, event, [event.params.oldGov, event.params.newGov]);
    ev.oldGovernance = event.params.oldGov;
    ev.newGovernance = event.params.newGov;
    ev.save();

    // Create data source template for new Governance contract
    // and start indexing events
    // @note The subgraph will not capture governance events
    // which occur prior to this event being emitted
    SuperfluidGovernance.create(event.params.newGov);
}

export function handleAgreementClassRegistered(
    event: AgreementClassRegistered
): void {
    const eventId = createEventID("AgreementClassRegistered", event);
    const ev = new AgreementClassRegisteredEvent(eventId);
    initializeEventEntity(ev, event, [event.params.code]);
    ev.agreementType = event.params.agreementType;
    ev.code = event.params.code;
    ev.save();

    initSFMetaOnce(event);
}

export function handleAgreementClassUpdated(
    event: AgreementClassUpdated
): void {
    const eventId = createEventID("AgreementClassUpdated", event);
    const ev = new AgreementClassUpdatedEvent(eventId);
    initializeEventEntity(ev, event, [event.params.code]);

    ev.agreementType = event.params.agreementType;
    ev.code = event.params.code;
    ev.save();

    // NOTE: It appears there are no AgreementClassRegisteredEvents on Goerli
    initSFMetaOnce(event);
}

export function handleSuperTokenFactoryUpdated(
    event: SuperTokenFactoryUpdated
): void {
    const eventId = createEventID("SuperTokenFactoryUpdated", event);
    const ev = new SuperTokenFactoryUpdatedEvent(eventId);
    initializeEventEntity(ev, event, [event.params.newFactory]);

    ev.newFactory = event.params.newFactory;
    ev.save();
}

export function handleSuperTokenLogicUpdated(
    event: SuperTokenLogicUpdated
): void {
    const eventId = createEventID("SuperTokenLogicUpdated", event);
    const ev = new SuperTokenLogicUpdatedEvent(eventId);
    initializeEventEntity(ev, event, [event.params.token, event.params.code]);

    ev.token = event.params.token;
    ev.code = event.params.code;
    ev.save();
}

export function handleAppRegistered(event: AppRegistered): void {
    const ev = new AppRegisteredEvent(createEventID("AppRegistered", event));
    initializeEventEntity(ev, event, [event.params.app]);

    ev.app = event.params.app;
    ev.save();
}

export function handleJail(event: Jail): void {
    const ev = new JailEvent(createEventID("Jail", event));
    initializeEventEntity(ev, event, [event.params.app]);

    ev.app = event.params.app;
    ev.reason = event.params.reason;
    ev.save();
}

function initSFMetaOnce(event: ethereum.Event): void {
    let sfMeta = SFMeta.load(commitHash);
    if (sfMeta == null) {
        sfMeta = new SFMeta(commitHash);
        sfMeta.timestamp = event.block.timestamp;
        sfMeta.blockNumber = event.block.number;
        sfMeta.configuration = configuration;
        sfMeta.branch = branch;
        sfMeta.packageVersion = packageVersion;
        sfMeta.save();
    }
}
