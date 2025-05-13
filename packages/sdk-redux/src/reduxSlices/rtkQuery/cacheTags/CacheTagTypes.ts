import {insertIf, typeGuard} from '../../../utils';
import {type NothingString} from '../../argTypes';

/**
 * Cache tag types for queries. Read more about caching from RTK-Query documentation: https://redux-toolkit.js.org/rtk-query/usage/automated-refetching#cache-tags
 * Types of our cache tags:
 * - GENERAL: Very general tagging of the query, e.g. only to the specificity of the chain. These tags are rarely invalidated.
 * - SPECIFIC: As specific tagging of the query as possible, e.g. chain + token + address. These tags are often invalidated when listening to blockchain events.
 */
export type CacheTagType = 'GENERAL' | 'SPECIFIC';

export const cacheTagTypes = typeGuard<CacheTagType[]>(['GENERAL', 'SPECIFIC']);

/**
 * Create a cache tag for RTK-Query.
 */
const createTag = (type: CacheTagType, ...keys: (string | number | undefined)[]) => ({
    type: type,
    id: keys
        .filter((x) => x !== undefined)
        .join('_')
        .toLowerCase(),
});

/**
 * NOTE:
 * Always order addresses in the following priority (if all addresses present):
 * * 1. SuperToken Address
 * * 2. Publisher / Sender / From Address
 * * 3. Subscriber / Receiver / To Address
 * If an address is not present then the rest of the addresses move up in priority.
 * @private
 * @category Cache Tags
 */
type CacheTagPayload = {
    chainId: number;
    address1?: string | NothingString;
    address2?: string | NothingString;
    address3?: string | NothingString;
};

const createTags = (
    tagType: CacheTagType,
    {chainId, address1, address2, address3}: CacheTagPayload
): ReturnType<typeof createTag>[] =>
    [
        createTag(tagType, chainId),
        ...insertIf(address1, () => [createTag(tagType, chainId, address1!)]),
        ...insertIf(address2, () => [
            createTag(tagType, chainId, address2!),
            createTag(tagType, chainId, address1!, address2!),
        ]),
        ...insertIf(address3, () => [
            createTag(tagType, chainId, address3!),
            createTag(tagType, chainId, address1!, address3!),
            createTag(tagType, chainId, address1!, address2!, address3!),
        ]),
    ].flat();

export const createSpecificTags = (payload: CacheTagPayload) => createTags('SPECIFIC', payload);

export const createMostSpecificTag = (payload: CacheTagPayload) => createTags('SPECIFIC', payload).reverse()[0];

/**
 * Not going more general than the chain for now.
 */
export const createGeneralTags = ({chainId}: {chainId: number}) => createTags('GENERAL', {chainId});
