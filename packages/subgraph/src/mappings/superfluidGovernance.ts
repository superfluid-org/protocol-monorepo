import {
    ConfigChanged,
    RewardAddressChanged,
    CFAv1LiquidationPeriodChanged,
    TrustedForwarderChanged,
    PPPConfigurationChanged,
    SuperTokenMinimumDepositChanged,
} from "../../generated/templates/SuperfluidGovernance/SuperfluidGovernanceBase";
import {
    CFAv1LiquidationPeriodChangedEvent,
    ConfigChangedEvent,
    RewardAddressChangedEvent,
    PPPConfigurationChangedEvent,
    TrustedForwarderChangedEvent,
    SuperTokenMinimumDepositChangedEvent,
} from "../../generated/schema";
import { createEventID, initializeEventEntity } from "../utils";
import { TOGA } from "../../generated/templates";
import { getOrInitTokenGovernanceConfig } from "../mappingHelpers";

export function handleConfigChanged(event: ConfigChanged): void {
    const eventId = createEventID("ConfigChanged", event);
    const ev = new ConfigChangedEvent(eventId);
    initializeEventEntity(ev, event, [event.address, event.params.host, event.params.superToken])

    ev.governanceAddress = event.address;
    ev.host = event.params.host;
    ev.superToken = event.params.superToken;
    ev.key = event.params.key;
    ev.isKeySet = event.params.isKeySet;
    ev.value = event.params.value;
    ev.save();
}

export function handleRewardAddressChanged(event: RewardAddressChanged): void {
    const eventId = createEventID("RewardAddressChanged", event);
    const ev = new RewardAddressChangedEvent(eventId);
    initializeEventEntity(ev, event, [event.address, event.params.host, event.params.superToken, event.params.rewardAddress]);

    ev.governanceAddress = event.address;
    ev.host = event.params.host;
    ev.superToken = event.params.superToken;
    ev.isKeySet = event.params.isKeySet;
    ev.rewardAddress = event.params.rewardAddress;
    ev.save();

    // Update reward address for token or default governance configs
    const governanceConfig = getOrInitTokenGovernanceConfig(
        event.block,
        event.params.superToken
    );
    governanceConfig.rewardAddress = event.params.rewardAddress;
    governanceConfig.updatedAtBlockNumber = event.block.number;
    governanceConfig.updatedAtTimestamp = event.block.timestamp;
    governanceConfig.save();

    // Create data source template for new TOGA contract
    // and start indexing events
    // @note The subgraph will start capturing TOGA events
    // which occur once this event is emitted for a valid TOGA address
    TOGA.create(event.params.rewardAddress);
}

export function handleCFAv1LiquidationPeriodChanged(
    event: CFAv1LiquidationPeriodChanged
): void {
    const eventId = createEventID("CFAv1LiquidationPeriodChanged", event);
    const ev = new CFAv1LiquidationPeriodChangedEvent(eventId);
    initializeEventEntity(ev, event, [event.address, event.params.host, event.params.superToken]);

    ev.governanceAddress = event.address;
    ev.host = event.params.host;
    ev.superToken = event.params.superToken;
    ev.isKeySet = event.params.isKeySet;
    ev.liquidationPeriod = event.params.liquidationPeriod;
    ev.save();

    // Update cfav1 liquidation period for token or default governance configs
    const governanceConfig = getOrInitTokenGovernanceConfig(
        event.block,
        event.params.superToken
    );
    governanceConfig.liquidationPeriod = event.params.liquidationPeriod;
    governanceConfig.updatedAtBlockNumber = event.block.number;
    governanceConfig.updatedAtTimestamp = event.block.timestamp;
    governanceConfig.save();
}

export function handlePPPConfigurationChanged(
    event: PPPConfigurationChanged
): void {
    const eventId = createEventID("PPPConfigurationChanged", event);
    const ev = new PPPConfigurationChangedEvent(eventId);
    initializeEventEntity(ev, event, [event.address, event.params.host, event.params.superToken]);

    ev.governanceAddress = event.address;
    ev.host = event.params.host;
    ev.superToken = event.params.superToken;
    ev.isKeySet = event.params.isKeySet;
    ev.liquidationPeriod = event.params.liquidationPeriod;
    ev.patricianPeriod = event.params.patricianPeriod;
    ev.save();

    // Update cfav1 liquidation period and patrician period for token or default governance configs
    const governanceConfig = getOrInitTokenGovernanceConfig(
        event.block,
        event.params.superToken
    );
    governanceConfig.liquidationPeriod = event.params.liquidationPeriod;
    governanceConfig.patricianPeriod = event.params.patricianPeriod;
    governanceConfig.updatedAtBlockNumber = event.block.number;
    governanceConfig.updatedAtTimestamp = event.block.timestamp;
    governanceConfig.save();
}

export function handleTrustedForwarderChanged(
    event: TrustedForwarderChanged
): void {
    const eventId = createEventID("TrustedForwarderChanged", event);
    const ev = new TrustedForwarderChangedEvent(eventId);
    initializeEventEntity(ev, event, [
        event.address,
        event.params.host,
        event.params.superToken,
        event.params.forwarder,
    ]);

    ev.governanceAddress = event.address;
    ev.host = event.params.host;
    ev.superToken = event.params.superToken;
    ev.isKeySet = event.params.isKeySet;
    ev.forwarder = event.params.forwarder;
    ev.enabled = event.params.enabled;
    ev.save();
}

export function handleSuperTokenMinimumDepositChanged(
    event: SuperTokenMinimumDepositChanged
): void {
    const eventId = createEventID("SuperTokenMinimumDepositChanged", event);
    const ev = new SuperTokenMinimumDepositChangedEvent(eventId);
    initializeEventEntity(ev, event, [event.address, event.params.host, event.params.superToken]);

    ev.governanceAddress = event.address;
    ev.host = event.params.host;
    ev.superToken = event.params.superToken;
    ev.isKeySet = event.params.isKeySet;
    ev.minimumDeposit = event.params.minimumDeposit;
    ev.save();

    // Update minimum deposit for token or default governance configs
    const governanceConfig = getOrInitTokenGovernanceConfig(
        event.block,
        event.params.superToken
    );
    governanceConfig.minimumDeposit = event.params.minimumDeposit;
    governanceConfig.updatedAtBlockNumber = event.block.number;
    governanceConfig.updatedAtTimestamp = event.block.timestamp;
    governanceConfig.save();
}
