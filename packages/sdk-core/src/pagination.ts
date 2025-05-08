import { ILightEntity } from "./interfaces";

/**
 * Paging Helper Class
 */
export type Paging = {
    readonly take: number;
    readonly skip?: number;
    readonly lastId?: string;
    readonly pageNumber?: number;
};

/**
 * For paginating Subgraph queries by using skip and take approach. Good for small result sets, not performant for large sets.
 * Use {@link LastIdPaging} for most performant pagination strategy.
 * NOTE: Also known as "offset based pagination".
 */
export type SkipPaging = {
    readonly take: number;
    readonly skip: number;
};

/**
 * For paginating Subgraph queries by using the last ID of the previous paged result to get the next page.
 * Relies on Subgraph ordering ID's in ascending order which it always does unless the results are ordered by `id` in `desc` order.
 * NOTE: Also known as "cursor based pagination".
 */
export type LastIdPaging = {
    readonly take: number;
    readonly lastId: string;
};

/**
 * WARNING: Works only with the new QueryHandlers.
 * Essentially the same as @see SkipPaging but with more UI pagination friendly API.
 */
export type PageNumberPaging = {
    /**
     * "Page size" in other words.
     */
    readonly take: number;
    /**
     * Page number starts from 1.
     */
    readonly pageNumber: number;
};

/**
 * WARNING: Works only with number literal of @see Number.POSITIVE_INFINITY.
 * WARNING: Works only with the new QueryHandlers.
 * Recursively gets all the possible Subgraph results.
 */
export type AllPaging = {
    readonly take: number;
};

/**
 * PagedResult Interface
 */
export interface PagedResult<T extends ILightEntity> {
    /**
     * The pagination used for current data.
     */
    readonly paging: Paging;
    /**
     * {@link Paging} for getting the next page.
     * `undefined` when there's no next page.
     */
    readonly nextPaging?: Paging;

    /**
     * @obsolete Use `items` instead.
     */
    readonly data: T[];
    readonly items: T[];
}

/**
 * Factory function to create a {@link PagedResult}.
 * @param dataPlusOne Subgraph queries are executed with one extra result to get which is over the {@link Paging} `take` amount.
 * @param paging
 */
export const createPagedResult = <T extends ILightEntity>(
    dataPlusOne: T[],
    paging: Paging
): PagedResult<T> => {
    const hasNextPage = dataPlusOne.length > paging.take;
    const data = dataPlusOne.slice(0, paging.take);
    const lastId = data.slice(-1)[0]?.id;

    return {
        paging: { skip: paging.skip, take: paging.take },
        nextPaging: hasNextPage
            ? isSkipPaging(paging)
                ? nextSkipPaging(paging)
                : isLastIdPaging(paging)
                  ? nextLastIdPaging(paging, lastId!)
                  : isPageNumberPaging(paging)
                    ? nextPageNumberPaging(paging)
                    : undefined
            : undefined,
        data: data,
        items: data,
    };
};

export function isSkipPaging(paging?: Paging): paging is SkipPaging {
    return paging?.skip !== undefined;
}

export function isPageNumberPaging(
    paging?: Paging
): paging is PageNumberPaging {
    return (paging as PageNumberPaging)?.pageNumber !== undefined;
}

export function isLastIdPaging(paging?: Paging): paging is LastIdPaging {
    return paging?.lastId !== undefined;
}

export function isAllPaging(paging?: Paging): paging is AllPaging {
    return (
        paging !== undefined &&
        !paging.skip &&
        paging.lastId === undefined &&
        paging.take === Infinity
    );
}

export const createSkipPaging = ({
    skip = 0,
    take = 100,
} = {}): SkipPaging => ({
    skip: skip,
    take: take,
});

export const createPageNumberPaging = ({
    pageNumber = 1,
    take = 100,
} = {}): PageNumberPaging => ({
    take: take,
    pageNumber: pageNumber,
});

export const createLastIdPaging = ({
    lastId = "",
    take = 100,
} = {}): LastIdPaging => ({
    take: take,
    lastId: lastId,
});

/**
 * Gets the next page given the skip/take used to initialize the `PagedResult` interface.
 * @returns the `Paging` class with the next page
 */
export const nextSkipPaging = (paging: SkipPaging): SkipPaging => ({
    skip: paging.skip + paging.take,
    take: paging.take,
});

export const nextPageNumberPaging = (
    paging: PageNumberPaging
): PageNumberPaging => ({
    pageNumber: paging.pageNumber + 1,
    take: paging.take,
});

export const nextLastIdPaging = (
    paging: LastIdPaging,
    nextLastId: string
): LastIdPaging => ({
    take: paging.take,
    lastId: nextLastId,
});

/**
 * Used to determine whether there is another page for pagination.
 * @returns the user's specified `take` plus one
 */
export const takePlusOne = (paging: Paging) => {
    return paging.take + 1;
};
