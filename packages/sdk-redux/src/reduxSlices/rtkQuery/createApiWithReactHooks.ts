import {createApi} from '@reduxjs/toolkit/query/react';

import {initializeRpcApiSlice} from '../../sdkReduxInitialization';

/**
 * For creating RTK-Query API (e.g. "sfApi") with auto-generated React Hooks.
 *
 * Read more: https://redux-toolkit.js.org/rtk-query/api/created-api/hooks
 */
export const createApiWithReactHooks = createApi;

initializeRpcApiSlice((options) => createApi(options));
