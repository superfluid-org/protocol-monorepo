import {type RelevantAddresses} from '@superfluid-finance/sdk-core';

import {createMostSpecificTag} from '../cacheTags/CacheTagTypes';

export const provideSpecificCacheTagsFromRelevantAddresses = (
    chainId: number,
    relevantAddresses: RelevantAddresses
) => {
    if (relevantAddresses.tokens.length) {
        return relevantAddresses.tokens
            .map((tokenAddress: string) =>
                [createMostSpecificTag({chainId, address1: tokenAddress})].concat(
                    relevantAddresses.accounts.map((accountAddress: string) =>
                        createMostSpecificTag({chainId, address1: tokenAddress, address2: accountAddress})
                    )
                )
            )
            .flat();
    } else if (relevantAddresses.accounts.length) {
        return relevantAddresses.accounts.map((accountAddress: string) =>
            createMostSpecificTag({chainId, address1: accountAddress})
        );
    } else {
        return [createMostSpecificTag({chainId})];
    }
};
