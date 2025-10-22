import {isPlainObject} from '@reduxjs/toolkit';
import {type SerializeQueryArgs} from '@reduxjs/toolkit/query';

import {mutationOverridesKey, mutationSignerKey} from '../../utils';

export const getSerializeQueryArgs =
    (): SerializeQueryArgs<any> =>
    ({endpointName, queryArgs, endpointDefinition}) => {
        // NOTE: The code below is taken from Redux Toolkit's repository from `defaultSerializeQueryArgs.ts`.

        // Comment from RTK-Query: Sort the object keys before stringifying, to prevent useQuery({ a: 1, b: 2 }) having a different cache key than useQuery({ b: 2, a: 1 })
        return `${endpointName}(${JSON.stringify(queryArgs, (_key, value) =>
            isPlainObject(value)
                ? Object.keys(value)
                      .sort()
                      .reduce<any>((acc, key) => {
                          // Don't cache non-serializable data from mutation args.
                          if (endpointDefinition.type === 'mutation') {
                              if (key === mutationOverridesKey || key === mutationSignerKey) {
                                  return acc;
                              }
                          }

                          acc[key] = normalizeValue((value as any)[key]);
                          return acc;
                      }, {})
                : normalizeValue(value)
        )})`;
    };

// TODO(KK): The logic below is duplicated in SDK-Core. Think of a way of sharing it.

// NOTE: Regex taken from Ethers.
const isAddressRegex = /^(0x)?[0-9a-fA-F]{40}$/;

// Normalize addresses and empty strings for cache keys.
const normalizeValue = (value: unknown) => lowerCaseIfAddress(undefinedIfEmpty(value));

const undefinedIfEmpty = (value: unknown) => {
    if (value === '') {
        return undefined;
    }
    return value;
};

const lowerCaseIfAddress = (value: unknown): unknown => {
    if (typeof value === 'string') {
        if (value.match(isAddressRegex)) {
            return value.toLowerCase();
        }
    }

    if (Array.isArray(value)) {
        return value.map((x) => lowerCaseIfAddress(x));
    }

    return value;
};
