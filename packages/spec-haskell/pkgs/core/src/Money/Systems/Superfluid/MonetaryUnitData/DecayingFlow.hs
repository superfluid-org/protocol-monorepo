{-# LANGUAGE DerivingVia            #-}
{-# LANGUAGE FunctionalDependencies #-}

-- | Decaying Flow Agreement (DFA)
--
-- NOTE: The formulas can be obtained from the output of maths/DFA.py
module Money.Systems.Superfluid.MonetaryUnitData.DecayingFlow
    ( MonetaryUnitLenses(..)
    , MonetaryUnitData (..)
    ) where

import           Data.Default                         (Default (..))
import           Data.Kind                            (Type)
import           Lens.Internal

import           Money.Systems.Superfluid.SystemTypes


class ( Default amuLs
      , SuperfluidSystemTypes sft
      ) => MonetaryUnitLenses amuLs sft | amuLs -> sft where
    decayingFactor  :: Lens' amuLs (SFT_FLOAT sft)
    settledAt       :: Lens' amuLs (SFT_TS sft)
    αVal            :: Lens' amuLs (SFT_FLOAT sft)
    εVal            :: Lens' amuLs (SFT_FLOAT sft)

type MonetaryUnitData :: Type -> Type -> Type
newtype MonetaryUnitData amuLs sft = MkMonetaryUnitData { getMonetaryUnitLenses :: amuLs } deriving (Default)

instance MonetaryUnitLenses amuLs sft => Semigroup (MonetaryUnitData amuLs sft) where
    -- Formula:
    --   aad_mappend(a, b) = DFA_AAD
    --     { t_s = t_s'
    --     , α   = α * e ^ (λ * (t_s - t_s')) - ε'
    --     , ε   = ε + ε'
    --     }
    --     where { t_s = t_s,  αVal = α,  εVal = ε  } = a
    --           { t_s = t_s', αVal = α', εVal = ε' } = b
    MkMonetaryUnitData a <> MkMonetaryUnitData b =
        let c = a & set  settledAt     (b^.settledAt)
                  & over αVal          (\α -> α * exp (-(λ * t_Δ)) - ε')
                  & over εVal          (+ ε')
        in MkMonetaryUnitData c
        where ε'  = b^.εVal
              λ   = b^.decayingFactor
              t_Δ = fromIntegral (b^.settledAt - a^.settledAt)

instance MonetaryUnitLenses amuLs sft => MonetaryUnitDataClass (MonetaryUnitData amuLs sft) sft where
    -- | Provided balance by DFA
    --
    -- Formula:
    --   rtb(aad, t) = α * e ^ (-λ * (t - t_s)) + ε
    --       where { t_s = t_s, αVal = α, εVal = ε } = aad
    balanceProvided (MkMonetaryUnitData a) t =
        let b = ceiling $ α * exp ((-λ) * t_Δ) + ε
        in  typedValuesToRTB [ (mkAnyTypedValue . MkUntappedValue) b ]
        where t_s   = a^.settledAt
              α     = a^.αVal
              ε     = a^.εVal
              λ     = a^.decayingFactor
              t_Δ   = fromIntegral (t - t_s)
