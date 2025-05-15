import { type SdkReduxConfig } from '../sdkReduxConfig';

// Solution inspired by: https://stackoverflow.com/a/69429093
declare global {
    var sdkReduxConfig: SdkReduxConfig;
}
