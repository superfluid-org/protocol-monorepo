> -- -*- fill-column: 70; -*-

\ignore{
\begin{code}

{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE GADTs #-}
module Money.Theory.PaymentPrimitives
    -- $intro
    --
    ( MoneyDistributionModel
    , 𝓜
    , 𝓜' (..)
    , sem𝓜
    ) where

import Data.Coerce ( coerce )

import Money.Theory.MoneyDistribution
\end{code}
}

\begin{haddock}
\begin{code}
{- $intro

Here is the denotational semantics of payment primitives of modern
payment system.

-}
\end{code}
\end{haddock}

\begin{code}
-- | Type synonym for ⟦𝓜⟧.
type MoneyDistributionModel' md = forall ν t u.
    ( MoneyDistribution md
    , ν ~ MD_MVAL md
    , t ~ MD_TS md
    , u ~ MD_MU md
    ) => u -> t -> ν

-- | ⟦𝓜⟧ - methematical model of meaning in money distribution.
data MoneyDistributionModel md = MkMoneyDistributionModel
    (MoneyDistributionModel' md)
\end{code}

\begin{code}
-- | Semigroup class instance ⟦𝓜⟧.
instance ( MoneyDistribution md
         ) => Semigroup (MoneyDistributionModel md) where
    -- ⊕: monoid binary operator
    (MkMoneyDistributionModel ma) <> (MkMoneyDistributionModel mb) =
        MkMoneyDistributionModel (\u t -> ma u t + mb u t)

-- | Monoid class instance ⟦𝓜⟧.
instance ( MoneyDistribution md
         ) => Monoid (MoneyDistributionModel md) where
    -- ∅: monoid empty set
    mempty = MkMoneyDistributionModel (\_ _ -> 0)
\end{code}

\begin{code}
-- | Index abstraction.
class Eq u => Index k u | k -> u where
    ρ :: k -> u -> Double

-- | Universal index.
data UniversalIndex u = MkUniversalIndex u
instance Eq u => Index (UniversalIndex u) u where
    ρ (MkUniversalIndex u) u' = if u == u' then 1 else 0
\end{code}

\begin{code}
-- | 𝓜' - syntactic category using index abstraction.
data 𝓜' ν t u =
    forall k1 k2. (Index k1 u, Index k2 u) => TransferI k1 k2 ν |
    forall k1 k2. (Index k1 u, Index k2 u) => FlowI k1 k2 ν t

-- | Type synonym for 𝓜' using type family.
type 𝓜 md = forall ν t u.
    ( MoneyDistribution md
    , ν ~ MD_MVAL md
    , t ~ MD_TS md
    , u ~ MD_MU md
    ) => 𝓜' ν t u

-- | ⟦.⟧ - semantic function of 𝓜.
sem :: MoneyDistribution md
    => 𝓜 md -> MoneyDistributionModel' md
sem (TransferI ka kb amount) = \u _ ->
    let x = fromIntegral amount
    in ceiling $ -(x * ρ ka u) + x * ρ kb u
sem (FlowI ka kb r t') = \u t ->
    let x = fromIntegral $ -(r * coerce(t - t'))
    in ceiling $ -(x * ρ ka u) + x * ρ kb u
-- GHC 9.4.2 bug re non-exhaustive pattern matching?
sem _ = error "huh?"

-- | ⟦.⟧ - semantic function of 𝓜.
sem𝓜 :: MoneyDistribution md
     => 𝓜 md -> MoneyDistributionModel md
sem𝓜 s = MkMoneyDistributionModel (sem s)
\end{code}
