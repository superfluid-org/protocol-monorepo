import {type ThunkDispatch, type UnknownAction} from '@reduxjs/toolkit';

import {getFramework} from '../../../sdkReduxConfig';
import {MillisecondTimes} from '../../../utils';
import {type TransactionInfo} from '../../argTypes';

import {invalidateSpecificCacheTagsForEvents} from './invalidateSpecificCacheTagsForEvents';

/**
 * Monitors given address for next event to invalidate cache and then stops.
 * NOTE: Optimizations for robustness could be done here.
 * @private
 * @category Cache Tags
 */
export const monitorAddressForNextEventToInvalidateCache = async (
    address: string,
    transactionInfo: TransactionInfo,
    dispatch: ThunkDispatch<any, any, UnknownAction>
) => {
    const framework = await getFramework(transactionInfo.chainId);
    framework.query.on(
        (events, unsubscribe) => {
            invalidateSpecificCacheTagsForEvents(transactionInfo.chainId, events, dispatch);
            unsubscribe();
        },
        MillisecondTimes.OneSecond,
        address,
        MillisecondTimes.OneMinute
    );
};
