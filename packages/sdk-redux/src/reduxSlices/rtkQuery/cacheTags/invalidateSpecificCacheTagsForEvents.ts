import {type ThunkDispatch, type UnknownAction} from '@reduxjs/toolkit';
import {type AllEvents} from '@superfluid-finance/sdk-core';
import uniqBy from 'lodash.uniqby';

import {getRpcApiSlice, getSubgraphApiSlice} from '../../../sdkReduxConfig';

import {createSpecificTags} from './CacheTagTypes';

/**
 * Get all the possible event tags. Run a deduplication to avoid unnecessary work in the redux store.
 */
export const getSpecificCacheTagsToInvalidateForEvents = (chainId: number, events: AllEvents[]) =>
    uniqBy(events.map((event) => [...getEventSpecificTags(event, chainId)]).flat(), (tag) => tag.type + tag.id);

/**
 * Based on event type, invalidate all possible relevant cache tags.
 * Cache tag invalidation will trigger re-querying of data.
 * @private
 * @category Cache Tags
 */
export const invalidateSpecificCacheTagsForEvents = (
    chainId: number,
    events: AllEvents[],
    dispatch: ThunkDispatch<any, any, UnknownAction>
) => {
    const tagsToInvalidate = getSpecificCacheTagsToInvalidateForEvents(chainId, events);

    dispatch(getRpcApiSlice().util.invalidateTags(tagsToInvalidate));
    dispatch(getSubgraphApiSlice().util.invalidateTags(tagsToInvalidate));
};

const getEventSpecificTags = (event: AllEvents, chainId: number) => {
    switch (event.name) {
        case 'SubscriptionApproved':
        case 'IndexDistributionClaimed':
        case 'IndexSubscribed':
        case 'IndexUnitsUpdated':
        case 'IndexUnsubscribed':
        case 'SubscriptionDistributionClaimed':
        case 'SubscriptionRevoked':
        case 'SubscriptionUnitsUpdated':
            return createSpecificTags({
                chainId,
                address1: event.token,
                address2: event.publisher,
                address3: event.subscriber,
            });
        case 'IndexCreated':
        case 'IndexUpdated':
            return createSpecificTags({
                chainId,
                address1: event.token,
                address2: event.publisher,
            });
        case 'FlowUpdated':
            return createSpecificTags({
                chainId,
                address1: event.token,
                address2: event.sender,
                address3: event.receiver,
            });
        case 'TokenUpgraded':
        case 'TokenDowngraded':
            return createSpecificTags({
                chainId,
                address1: event.token,
                address2: event.account,
            });
        case 'Transfer':
            return createSpecificTags({
                chainId,
                address1: event.token,
                address2: event.from,
                address3: event.to,
            });
        case 'AgreementLiquidatedV2':
            return [
                createSpecificTags({
                    chainId,
                    address1: event.token,
                    address2: event.liquidatorAccount,
                }),
                createSpecificTags({
                    chainId,
                    address1: event.token,
                    address2: event.rewardAmountReceiver,
                }),
                createSpecificTags({
                    chainId,
                    address1: event.token,
                    address2: event.targetAccount,
                }),
            ].flat();
        case 'AgreementLiquidatedBy':
            return [
                createSpecificTags({
                    chainId,
                    address1: event.token,
                    address2: event.penaltyAccount,
                }),
                createSpecificTags({
                    chainId,
                    address1: event.token,
                    address2: event.bondAccount,
                }),
                createSpecificTags({
                    chainId,
                    address1: event.token,
                    address2: event.rewardAmount,
                }),
            ].flat();
        case 'CustomSuperTokenCreated':
            return createSpecificTags({
                chainId,
                address1: event.token,
            });
        case 'Minted':
            return createSpecificTags({
                chainId,
                address1: event.to,
            });
        case 'Sent':
            return createSpecificTags({
                chainId,
                address1: event.to,
            });
        case 'SuperTokenLogicUpdated':
        case 'SuperTokenCreated':
            return createSpecificTags({
                chainId,
                address1: event.token,
            });
        case 'TrustedForwarderChanged':
            return createSpecificTags({
                chainId,
                address1: event.superToken,
            });
        case 'AgreementClassRegistered':
        case 'AgreementClassUpdated':
        case 'AppRegistered':
        case 'Burned':
        case 'CFAv1LiquidationPeriodChanged':
        case 'ConfigChanged':
        case 'PPPConfigurationChanged':
        case 'GovernanceReplaced':
        case 'Jail':
        case 'RewardAddressChanged':
        case 'RoleAdminChanged':
        case 'RoleGranted':
        case 'RoleRevoked':
        case 'SuperTokenFactoryUpdated':
        case 'SuperTokenLogicCreated':
            return [];
        default:
            console.warn(
                `Unknown event [${
                    (event as any)?.name
                }] in "invalidateCacheTagsForEvents" for @superfluid-finance/sdk-redux. Cache might not be invalidated properly.`
            );
            return [];
    }
};
