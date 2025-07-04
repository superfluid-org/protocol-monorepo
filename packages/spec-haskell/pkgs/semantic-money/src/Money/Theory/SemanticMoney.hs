{-# LANGUAGE FunctionalDependencies #-}
module Money.Theory.SemanticMoney
    ( -- * Semantic Money Classes & Primitives
      MonetaryUnit (settle, settledAt, flowRate, rtb)
    , any_mu_settle_idempotency, any_mu_constant_rtb, any_mu_constant_flow
    , MonetaryParticle (shift1, flow1)
    , any_mp_shift1_reversible, any_mp_flow1_reversible
    , shift2a, shift2b, flow2a, flow2b, align2a, align2b
      -- * Semantic Money Instances
    , BasicParticle (..)
    , PDP_Index (..), PDP_Member (..), PDP_MemberMU, pdp_UpdateMember2
      -- * Re-export Monetary Types
    , module Money.Theory.MonetaryTypes
    ) where
-- base
import           Control.Exception          (assert)
import           Data.Tuple                 (swap)
-- default
import           Data.Default               (Default (..))
--
import           Money.Theory.MonetaryTypes


------------------------------------------------------------------------------------------------------------------------
-- General Payment Primitives
------------------------------------------------------------------------------------------------------------------------

--
-- Monetary value and its laws.
--

-- | A monetary unit and its operators.
class (MonetaryTypes mt, Eq mu) =>
      MonetaryUnit mt mu | mu -> mt where
    -- | Settle the monetary unit @mu@ at time @t@.
    settle    :: t ~ MT_TIME mt => t -> mu -> mu
    -- | Get the settled time of the monetary unit @mu@.
    settledAt :: t ~ MT_TIME mt => mu -> t
    -- | Get the flow rate of the monetary unit @mu@ at time @t@.
    flowRate  :: MonetaryTypes'tr mt t fr => mu -> t -> fr
    -- | Get the real-time balance of the monetary unit @mu@ at time @t@.
    rtb       :: MonetaryTypes'tvr mt t v fr => mu -> t -> v

any_mu_settle_idempotency :: (MonetaryUnit mt mu, t ~ MT_TIME mt) => mu -> t -> Bool
any_mu_settle_idempotency a t =
    settledAt (settle t a) == t &&
    settle t a == settle t (settle t a)

any_mu_constant_rtb :: (MonetaryUnit mt mu, t ~ MT_TIME mt) => mu -> t -> t -> t -> Bool
any_mu_constant_rtb a t1 t2 t3 =
    rtb (settle t1 a) t3 == rtb a t3 &&
    rtb (settle t2 a) t3 == rtb a t3 &&
    rtb (settle t2 (settle t1 a)) t3 == rtb a t3

any_mu_constant_flow :: (MonetaryUnit mt mu, t ~ MT_TIME mt) => mu -> t -> Bool
any_mu_constant_flow a dt =
    rtb a t + flowRate a t `mt_fr_mul_t` dt == rtb a (t + dt)
    where t = settledAt a

--
-- Monetary particle, and its polymorphic 2-primitives.
--

-- | A monetary particle and its operators (1-primitives).
class (MonetaryUnit mt mp, Monoid mp) =>
      MonetaryParticle mt mp | mp -> mt where
    shift1 :: v ~ MT_VALUE mt => v -> mp -> (mp, v)
    flow1  :: fr ~ MT_FLOWRATE mt => fr -> mp -> (mp, fr)

any_mp_shift1_reversible :: (MonetaryParticle mt mp, t ~ MT_TIME mt, v ~ MT_VALUE mt) => mp -> v -> Bool
any_mp_shift1_reversible a v =
    rtb a t + v' == rtb a' t &&
    a'' == a &&
    v'' == -v'
    where t = settledAt a
          (a', v') = shift1 v a
          (a'', v'') = shift1 (-v') a'

any_mp_flow1_reversible :: (MonetaryParticle mt mp, t ~ MT_TIME mt, fr ~ MT_FLOWRATE mt) => mp -> fr -> Bool
any_mp_flow1_reversible a fr =
    fr' == flowRate a' t &&
    a'' == a &&
    fr'' == flowRate a t
    where t = settledAt a
          (a', fr') = flow1 fr a
          (a'', fr'') = flow1 (flowRate a t) a'

-- $SideBiasedOps
--
-- == Note on side-biased operations:
--   1) Left side produces error term with which right side is adjusted accordingly, and vice versa.
--   2) The adjustment must not produce new error term, or otherwise it would require recursive adjustments.

-- | Shift value for the left side (a) or right side (b).
shift2a, shift2b ::
    (MonetaryTypes'tv mt t v, MonetaryParticle mt a, MonetaryParticle mt b) =>
    v -> t -> (a, b) -> (a, b)
shift2a v t (a, b) =
    let (a', v') = shift1 v (settle t a)
        -- we assume second flow1 produces no more error term.
        (b', v'') = shift1 (-v') (settle t b)
    in assert (v'' == -v') (a', b')
shift2b v t (a, b) = swap (shift2a (-v) t (b, a))

-- | Shifting flow for the left side (a) or right side (b).
flow2a, flow2b ::
    (MonetaryTypes'tr mt t fr, MonetaryParticle mt a, MonetaryParticle mt b) =>
    fr -> t -> (a, b) -> (a, b)
flow2a dfr t (a, b) =
    let (b1, fr_a) = flow1 (flowRate a t) (settle t mempty)
        (b2, fr_a') = flow1 (-fr_a + dfr) (settle t mempty)
        (a', fr_a'') = flow1 (-fr_a') (settle t a)
    in assert (fr_a' == -fr_a'') (a', b <> b1 <> b2)
flow2b dfr t (a, b) = swap (flow2a (-dfr) t (b, a))

-- | Flow rates alignment on unit changes for the left side (a) or right side (b).
align2a, align2b ::
    (MonetaryParticle mt a, MonetaryParticle mt b) =>
    MT_UNIT mt -> MT_UNIT mt -> MT_TIME mt -> (a, b) -> (a, b)
align2a u u' t (a, b) = (a', b')
    where fr = flowRate a t
          (fr', e) = if u' == 0 then (0, fr `mt_fr_mul_u` u) else fr `mt_fr_mul_u_qr_u` (u, u')
          a' = fst (flow1 fr' a)
          b' = fst (flow1 (e + flowRate b t) b)
align2b u u' t (a, b) = swap (align2a u u' t (b, a))

------------------------------------------------------------------------------------------------------------------------
-- Basic Particle: building block for indexes
------------------------------------------------------------------------------------------------------------------------

data BasicParticle mt = BasicParticle
    { bp_settled_at    :: MT_TIME mt
    , bp_settled_value :: MT_VALUE mt
    , bp_flow_rate     :: MT_FLOWRATE mt
    }

deriving instance MonetaryTypes mt => Eq (BasicParticle mt)

instance MonetaryTypes mt => Semigroup (BasicParticle mt) where
    a@(BasicParticle t1 _ _) <> b@(BasicParticle t2 _ _) = BasicParticle t' (sv1 + sv2) (r1 + r2)
        -- The binary operator supports negative time values while abiding the monoidal laws.
        -- The practical semantics of values of mixed-sign is not of the concern of this specification.
        where t' = if (abs t2) > (abs t1) then t2 else t1
              (BasicParticle _ sv1 r1) = settle t' a
              (BasicParticle _ sv2 r2) = settle t' b

instance MonetaryTypes mt => Monoid (BasicParticle mt) where
    mempty = BasicParticle 0 0 0

instance MonetaryTypes mt =>
         MonetaryUnit mt (BasicParticle mt) where
    settle t' a = a { bp_settled_at = t'
                    , bp_settled_value = rtb a t'
                    }
    settledAt = bp_settled_at
    flowRate = const . bp_flow_rate
    rtb (BasicParticle t s r) t' = r `mt_fr_mul_t` (t' - t) + s

instance MonetaryTypes mt =>
         MonetaryParticle mt (BasicParticle mt) where
    shift1 x a = (a { bp_settled_value = bp_settled_value a + x }, x)
    flow1 r' a = (a { bp_flow_rate = r' }, r')

------------------------------------------------------------------------------------------------------------------------
-- Proportional Distribution Pool (PDP)
------------------------------------------------------------------------------------------------------------------------

data PDP_Index mt wp = PDP_Index
    { pdpi_total_units :: MT_UNIT mt
    , pdpi_wp          :: wp -- wrapped particle
    }

data PDP_Member mt wp = PDP_Member
    { pdpm_owned_unit    :: MT_UNIT mt
    , pdpm_settled_value :: MT_VALUE mt
    , pdpm_synced_wp     :: wp
    }

type PDP_MemberMU mt wp = (PDP_Index mt wp, PDP_Member mt wp)

pdp_UpdateMember2 ::
    ( u ~ MT_UNIT mt, t ~ MT_TIME mt
    , MonetaryParticle mt a
    , MonetaryParticle mt wp
    , mu ~ PDP_MemberMU mt wp
    ) =>
    u -> t -> (a, mu) -> (a, mu)
pdp_UpdateMember2 u' t' (a, (b, pm)) = (a'', (b'', pm''))
    where (PDP_Index tu mpi, pm'@(PDP_Member u _ _)) = settle t' (b, pm)
          tu' = tu + u' - u
          (mpi', a'') = align2b tu tu' t' (mpi, settle t' a)
          b''  = PDP_Index tu' mpi'
          pm'' = pm' { pdpm_owned_unit = u', pdpm_synced_wp = mpi' }

--
-- PDP_Index as MonetaryIndex
--

deriving instance (MonetaryTypes mt, Eq wp) => Eq (PDP_Index mt wp)

instance (MonetaryTypes mt, Semigroup wp) => Semigroup (PDP_Index mt wp) where
    -- The binary operator supports negative unit values while abiding the monoidal laws.
    -- The practical semantics of values of mixed-sign is not of the concern of this specification.
    (PDP_Index u1 a) <> (PDP_Index u2 b) = PDP_Index u' (a <> b)
        where u' | u1 == 0 = u2 | u2 == 0 = u1 | otherwise = max u1 u2

instance (MonetaryTypes mt, Monoid wp) => Monoid (PDP_Index mt wp) where
    mempty = PDP_Index 0 mempty

instance MonetaryUnit mt wp =>
         MonetaryUnit mt (PDP_Index mt wp) where
    settle t' a@(PDP_Index _ mpi) = a { pdpi_wp = settle t' mpi }
    settledAt (PDP_Index _ mpi) = settledAt mpi
    flowRate (PDP_Index tu mpi) t = flowRate mpi t `mt_fr_mul_u` tu
    rtb (PDP_Index tu mpi) t = rtb mpi t `mt_v_mul_u` tu

instance MonetaryParticle mt wp =>
         MonetaryParticle mt (PDP_Index mt wp) where
    shift1 x a@(PDP_Index tu mpi) = (a { pdpi_wp = mpi' }, x' `mt_v_mul_u` tu)
        where (mpi', x') = if tu == 0 then (mpi, 0) else shift1 (x `mt_v_quot_u` tu) mpi

    flow1 r' a@(PDP_Index tu mpi) = (a { pdpi_wp = mpi' }, r'' `mt_fr_mul_u` tu)
        where (mpi', r'') = if tu == 0 then flow1 0 mpi else flow1 (r' `mt_fr_quot_u` tu) mpi

--
-- PDP_Member
--

instance (MonetaryTypes mt, Monoid wp) =>
         Default (PDP_Member mt wp) where
    def = PDP_Member 0 0 mempty

deriving instance (MonetaryTypes mt, Eq wp) => Eq (PDP_Member mt wp)

--
-- PDP_MemberMU as MonetaryUnit
--

instance MonetaryUnit mt wp =>
         MonetaryUnit mt (PDP_MemberMU mt wp) where
    settle t' (pix, pm) = (pix', pm')
        where sv' = rtb (pix, pm) t'
              pix'@(PDP_Index _ mpi') = settle t' pix
              pm' = pm { pdpm_settled_value = sv', pdpm_synced_wp = mpi' }

    settledAt (_, PDP_Member _ _ mps) = settledAt mps

    flowRate (PDP_Index _ mpi, PDP_Member u _ _) t = flowRate mpi t `mt_fr_mul_u` u

    rtb (PDP_Index _ mpi, PDP_Member u sv mps) t' = sv +
        -- let ti = bp_settled_at mpi
        --     ts = bp_settled_at mps
        -- in (rtb mpi t' - rtb mps ti) -- include index's current accruals for the member
        -- +  (rtb mps ti - rtb mps ts) -- cancel out-of-sync member's rtb between [ts:ti]
        -- =>
        (rtb mpi t' - rtb mps (settledAt mps)) `mt_v_mul_u` u
