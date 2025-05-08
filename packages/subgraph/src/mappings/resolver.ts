import { Address, Bytes, ethereum } from "@graphprotocol/graph-ts";
import { RoleAdminChanged, RoleGranted, RoleRevoked, Set } from "../../generated/ResolverV1/Resolver";
import {
    ResolverEntry,
    RoleAdminChangedEvent,
    RoleGrantedEvent,
    RoleRevokedEvent,
    SetEvent,
    Token,
} from "../../generated/schema";
import { createEventID, initializeEventEntity, ZERO_ADDRESS } from "../utils";

export function handleRoleAdminChanged(event: RoleAdminChanged): void {
    const eventId = createEventID("RoleAdminChanged", event);
    const ev = new RoleAdminChangedEvent(eventId);
    initializeEventEntity(ev, event, [event.params.previousAdminRole, event.params.newAdminRole]);

    ev.role = event.params.role;
    ev.previousAdminRole = event.params.previousAdminRole;
    ev.newAdminRole = event.params.newAdminRole;
    ev.save();
}

export function handleRoleGranted(event: RoleGranted): void {
    const eventId = createEventID("RoleGranted", event);
    const ev = new RoleGrantedEvent(eventId);
    initializeEventEntity(ev, event, [event.params.account, event.params.sender]);

    ev.role = event.params.role;
    ev.account = event.params.account;
    ev.sender = event.params.sender;
    ev.save();
}
export function handleRoleRevoked(event: RoleRevoked): void {
    const eventId = createEventID("RoleRevoked", event);
    const ev = new RoleRevokedEvent(eventId);
    initializeEventEntity(ev, event, [event.params.account, event.params.sender]);

    ev.role = event.params.role;
    ev.account = event.params.account;
    ev.sender = event.params.sender;
    ev.save();
}

function getIsToken(id: string): boolean {
    return Token.load(id) != null;
}

function getOrInitResolverEntry(id: string, target: Address, block: ethereum.Block): ResolverEntry {
    let resolverEntry = ResolverEntry.load(id);

    const isListed = target.notEqual(ZERO_ADDRESS);

    if (resolverEntry == null) {
        resolverEntry = new ResolverEntry(id);
        resolverEntry.createdAtBlockNumber = block.number;
        resolverEntry.createdAtTimestamp = block.timestamp;
        resolverEntry.targetAddress = target;
        // on initialization, we are unlikely to set this to zero address
        // if we do, this gets fixed in subsequent set events
        resolverEntry.isToken = getIsToken(target.toHex());
    }

    // we only update this if the target is not equal to the zero address
    if (isListed) {
        resolverEntry.isToken = getIsToken(target.toHex());
    }
    resolverEntry.updatedAtBlockNumber = block.number;
    resolverEntry.updatedAtTimestamp = block.timestamp;
    resolverEntry.isListed = isListed;

    resolverEntry.save();

    return resolverEntry as ResolverEntry;
}

export function handleSet(event: Set): void {
    _createSetEvent(event, event.params.target, event.params.name);

    const resolverEntry = getOrInitResolverEntry(event.params.name.toHex(), event.params.target, event.block);

    // upon initial setting, we will know if this address belongs to a token contract
    if (resolverEntry.isToken) {
        // we first try to load token from targetAddress, this will return null if
        // a token was set, unset and on the next set
        let token = Token.load(resolverEntry.targetAddress.toHex());
        // we catch this edge case here and we use the newly set address to load the token
        // we are assuming the token address here is being properly set and that it points
        // to a token which has already been indexed
        if (!token) {
            token = Token.load(event.params.target.toHex());
        }
        if (token) {
            if (event.params.target.equals(ZERO_ADDRESS)) {
                token.isListed = false;
            } else {
                token.isListed = true;
            }
            token.save();
        }
    }
    resolverEntry.targetAddress = event.params.target;
    resolverEntry.save();
}

function _createSetEvent(event: ethereum.Event, target: Bytes, name: Bytes): void {
    const eventId = createEventID("Set", event);
    const ev = new SetEvent(eventId);
    initializeEventEntity(ev, event, [target]);

    ev.hashedName = name;
    ev.target = target;
    ev.resolverEntry = name.toHex();
    ev.save();
}
