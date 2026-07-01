/**
 * @dev Parse colon marked arguments
 *
 * NOTE:
 * Provide arguments to the script through ":" separator
 */
function parseColonArgs(argv) {
    const argIndex = argv.indexOf(":");
    if (argIndex < 0) {
        console.log("No colon arguments");
        return [];
    } else {
        const args = argv.slice(argIndex + 1);
        return args;
    }
}

/**
 * @dev Script runner for logic function
 *
 * This is development framework dependent, and it's currently for Truffle.
 *
 * runnerOpts.skipArgv:
 *   - most scripts supports argv followed by an options, but for compatibility issue
 *     some script wants to skip the argv. This option enables the hack.
 */
module.exports = function (ctxFn, logicFn, runnerOpts) {
    return async function (cb, argv, options = {}) {
        try {
            const {artifacts, web3} = ctxFn();

            let args;
            if (runnerOpts.skipArgv) {
                // skip argv arguments
                options = argv || {};
            } else {
                // Parse colon indicated arguments
                args = parseColonArgs(argv || process.argv);
                runnerOpts.doNotPrintColonArgs ||
                    console.log("Colon arguments", args);
            }

            // normalize web3 environment
            if (!options.web3) {
                throw Error(
                    "A web3 instance is not provided."
                );
            }
            global.web3 = options.web3;

            // Use common environment variables
            options.protocolReleaseVersion =
                options.protocolReleaseVersion ||
                process.env.RELEASE_VERSION ||
                "test";
            console.log(
                "protocol release version:",
                options.protocolReleaseVersion
            );

            const retVal = await logicFn(args, options);
            cb();
            return retVal;
        } catch (err) {
            cb(err);
        }
    };
};
