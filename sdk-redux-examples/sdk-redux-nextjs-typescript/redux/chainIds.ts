export const chainIds = [
    // 100, // XDAI //TODO(KK): No infura support
    137, // MATIC
    43113 , // OP Sepolia
];

export type Network = {
    name: string;
    chainId: number;
};

export const networks: Network[] = [
    {
        name: "matic",
        chainId: 137,
    },
    {
        name: "fuji",
        chainId: 43113 ,
    },
];

export const networksByName = new Map(
    networks.map((x) => [x.name.toLowerCase(), x])
);

export const networksByChainId = new Map(networks.map((x) => [x.chainId, x]));

export const findNetwork = (x: unknown): Network | undefined => {
    if (typeof x === "string") {
        return networksByName.get(x.toLowerCase());
    }
};
