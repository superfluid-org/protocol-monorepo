{-# LANGUAGE DerivingStrategies     #-}
{-# LANGUAGE FunctionalDependencies #-}
module Money.Theory.SemanticMoney
    ( -- * Semantic Money Classes & Primitives
        MonetaryUnit (settle, settledAt, flowRate, rtb)
    , IndexedValue (shift1, flow1)
    , prim2, shift2, flow2, shiftFlow2a, shiftFlow2b
    , MonetaryParticle (align2)
      -- * Semantic Money Instances
    , BasicParticle (..)
    , UniversalIndex (..)
    , PDP_Index (..), PDP_Member (..), PDP_MemberMU, pdp_UpdateMember2
      -- * Re-export Monetary Types
    , module Money.Theory.MonetaryTypes
    ) where
--
import           Data.Default               (Default (..))
--
import           Money.Theory.MonetaryTypes


------------------------------------------------------------------------------------------------------------------------
-- General Payment Primitives
------------------------------------------------------------------------------------------------------------------------

-- | A monetary unit and its operators.
class (MonetaryTypes mt, t ~ MT_TIME mt, v ~ MT_VALUE mt) =>
      MonetaryUnit mt t v mu | mu -> mt where
    settle    :: t -> mu -> mu
    settledAt :: mu -> t
    flowRate  :: mu -> v
    rtb       :: mu -> t -> v

-- | An indexed monetary value and its 1-primitive operators.
class (MonetaryUnit mt t v ix, u ~ MT_UNIT mt, Monoid ix) =>
      IndexedValue mt t v u ix | ix -> mt where
    shift1 :: v -> ix -> (ix, v)
    flow1  :: v -> ix -> (ix, v)

--
-- polymorphic 2-primitives for indexed values
--

-- | 2-primitive higher order function
prim2 ::
    (IndexedValue mt t v u a, IndexedValue mt t v u b) =>
    ((a, b) -> (a, b)) -> t -> (a, b) -> (a, b)
prim2 op t' (a, b) = op (settle t' a, settle t' b)

-- | shift2, right side biased error term adjustment
shift2 ::
    (IndexedValue mt t v u a, IndexedValue mt t v u b) =>
    v -> t -> (a, b) -> (a, b)
shift2 amount = prim2 op
    where op (a, b) = let (b', amount') = shift1 amount b
                          (a', _) = shift1 (-amount') a
                      in  (a', b')

-- | flow2, right side biased error term adjustment
flow2 ::
    (IndexedValue mt t v u a, IndexedValue mt t v u b) =>
    v -> t -> (a, b) -> (a, b)
flow2 r = prim2 op
    where op (a, b) = let (b', r') = flow1 r b
                          (a', _) = flow1 (-r') a
                      in  (a', b')

-- | shiftFlow2 for the left side (a), right side biased error term adjustment
shiftFlow2a ::
    (IndexedValue mt t v u a, IndexedValue mt t v u b) =>
    v -> t -> (a, b) -> (a, b)
shiftFlow2a dr t (a, b) =
    let ( _, b1) = flow2 (flowRate a) t (a, mempty)
        (a', b2) = flow2 (-flowRate a + dr) t (a, mempty)
    in  (a', b <> b1 <> b2)

-- | shiftFlow2 for the right side (b), right side biased error term adjustment
shiftFlow2b ::
    (IndexedValue mt t v u a, IndexedValue mt t v u b) =>
    v -> t -> (a, b) -> (a, b)
shiftFlow2b dr t (a, b) =
    let (a1,  _) = flow2 (-flowRate b) t (mempty, b)
        (a2, b') = flow2 (flowRate b + dr) t (mempty, b)
    in  (a <> a1 <> a2, b')

class IndexedValue mt t v u mp =>
      MonetaryParticle mt t v u mp where
    -- | Value alignment 2-primitive, right side biased
    --
    -- NOTE:
    -- * On right side biased operations:
    --   1) Right side produces error term with which left side is adjusted accordingly.
    --   2) The adjustment must not produce new error term, or otherwise it would require recursive adjustments.
    align2 :: forall a. IndexedValue mt t v u a => u -> u -> (mp, a) -> (mp, a)

------------------------------------------------------------------------------------------------------------------------
-- Basic Particle: building block for indexes
------------------------------------------------------------------------------------------------------------------------

data BasicParticle mt = BasicParticle
    { bp_settled_at    :: MT_TIME  mt
    , bp_settled_value :: MT_VALUE mt
    , bp_flow_rate     :: MT_VALUE mt
    }

deriving stock instance MonetaryTypes mt => Eq (BasicParticle mt)

instance MonetaryTypes mt => Semigroup (BasicParticle mt) where
    a@(BasicParticle t1 _ _) <> b@(BasicParticle t2 _ _) = BasicParticle t' (sv1 + sv2) (r1 + r2)
        -- The binary operator supports negative time values while abiding the monoidal laws.
        -- The practical semantics of values of mixed-sign is not of the concern of this specification.
        where t' | t1 == 0 = t2 | t2 == 0 = t1 | otherwise = max t1 t2
              (BasicParticle _ sv1 r1) = settle t' a
              (BasicParticle _ sv2 r2) = settle t' b

instance MonetaryTypes mt => Monoid (BasicParticle mt) where
    mempty = BasicParticle 0 0 0

instance (MonetaryTypes mt, t ~ MT_TIME mt, v ~ MT_VALUE mt) =>
         MonetaryUnit mt t v (BasicParticle mt) where
    settle t' a = a { bp_settled_at = t'
                    , bp_settled_value = rtb a t'
                    }
    settledAt = bp_settled_at
    flowRate = bp_flow_rate
    rtb (BasicParticle t s r) t' = r `mt_v_mul_t` (t' - t) + s

instance (MonetaryTypes mt, t ~ MT_TIME mt, v ~ MT_VALUE mt, u ~ MT_UNIT mt) =>
         IndexedValue mt t v u (BasicParticle mt) where

    shift1 x a = (a { bp_settled_value = bp_settled_value a + x }, x)
    flow1 r' a = (a { bp_flow_rate = r' }, r')

instance (MonetaryTypes mt, t ~ MT_TIME mt, v ~ MT_VALUE mt, u ~ MT_UNIT mt) =>
         MonetaryParticle mt t v u (BasicParticle mt) where
    align2 u u' (b, a) = (b', a')
        where r = flowRate b
              (r', er') = if u' == 0 then (0, r `mt_v_mul_u` u) else r `mt_v_mul_u_qr_u` (u, u')
              b' = fst . flow1 r' $ b
              a' = fst . flow1 (er' + flowRate a) $ a

------------------------------------------------------------------------------------------------------------------------
-- Univeral Index
------------------------------------------------------------------------------------------------------------------------

-- | A newtype wrapper of an underlying monetary unit @wp@, with a parameterized @mt@.
newtype UniversalIndex mt wp = UniversalIndex wp

deriving newtype instance (MonetaryTypes mt, Eq wp) => Eq (UniversalIndex mt wp)
deriving newtype instance (MonetaryTypes mt, Semigroup wp) => Semigroup (UniversalIndex mt wp)
deriving newtype instance (MonetaryTypes mt, Monoid wp) => Monoid (UniversalIndex mt wp)
deriving newtype instance MonetaryUnit mt t v wp => MonetaryUnit mt t v (UniversalIndex mt wp)
deriving newtype instance IndexedValue mt t v u wp => IndexedValue mt t v u (UniversalIndex mt wp)
deriving newtype instance MonetaryParticle mt t v u wp => MonetaryParticle mt t v u (UniversalIndex mt wp)

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
    ( IndexedValue mt t v u a
    , MonetaryParticle mt t v u wp
    , mu ~ PDP_MemberMU mt wp
    ) =>
    u -> t -> (a, mu) -> (a, mu)
pdp_UpdateMember2 u' t' (a, (b, pm)) = (a'', (b'', pm''))
    where (PDP_Index tu mpi, pm'@(PDP_Member u _ _)) = settle t' (b, pm)
          tu' = tu + u' - u
          (mpi', a'') = align2 tu tu' (mpi, settle t' a)
          b''  = PDP_Index tu' mpi'
          pm'' = pm' { pdpm_owned_unit = u', pdpm_synced_wp = mpi' }

--
-- PDP_Index as MonetaryIndex
--

instance MonetaryUnit mt t v wp =>
         MonetaryUnit mt t v (PDP_Index mt wp) where
    settle t' a@(PDP_Index _ mpi) = a { pdpi_wp = settle t' mpi }
    settledAt (PDP_Index _ mpi) = settledAt mpi
    flowRate (PDP_Index _ mpi) = flowRate mpi
    rtb (PDP_Index _ mpi) = rtb mpi

instance (MonetaryTypes mt, Semigroup wp) => Semigroup (PDP_Index mt wp) where
    -- The binary operator supports negative unit values while abiding the monoidal laws.
    -- The practical semantics of values of mixed-sign is not of the concern of this specification.
    (PDP_Index u1 a) <> (PDP_Index u2 b) = PDP_Index u' (a <> b)
        where u' | u1 == 0 = u2 | u2 == 0 = u1 | otherwise = max u1 u2

instance (MonetaryTypes mt, Monoid wp) => Monoid (PDP_Index mt wp) where
    mempty = PDP_Index 0 mempty

instance MonetaryParticle mt t v u wp =>
         IndexedValue mt t v u (PDP_Index mt wp) where
    shift1 x a@(PDP_Index tu mpi) = (a { pdpi_wp = mpi' }, x' `mt_v_mul_u` tu)
        where (mpi', x') = if tu == 0 then (mpi, 0) else shift1 (x `mt_v_div_u` tu) mpi

    flow1 r' a@(PDP_Index tu mpi) = (a { pdpi_wp = mpi' }, r'' `mt_v_mul_u` tu)
        where (mpi', r'') = if tu == 0 then flow1 0 mpi else flow1 (r' `mt_v_div_u` tu) mpi

--
-- PDP_MemberMU as MonetaryUnit
--

instance (MonetaryTypes mt, Monoid wp) =>
         Default (PDP_Member mt wp) where
    def = PDP_Member 0 0 mempty

instance MonetaryUnit mt t v wp =>
         MonetaryUnit mt t v (PDP_MemberMU mt wp) where
    settle t' (pix, pm) = (pix', pm')
        where sv' = rtb (pix, pm) t'
              pix'@(PDP_Index _ mpi') = settle t' pix
              pm' = pm { pdpm_settled_value = sv', pdpm_synced_wp = mpi' }

    settledAt (_, PDP_Member _ _ mps) = settledAt mps

    flowRate (PDP_Index _ mpi, PDP_Member u _ _) = flowRate mpi `mt_v_mul_u` u

    rtb (PDP_Index _ mpi, PDP_Member u sv mps) t' = sv +
        -- let ti = bp_settled_at mpi
        --     ts = bp_settled_at mps
        -- in (rtb mpi t' - rtb mps ti) -- include index's current accruals for the member
        -- +  (rtb mps ti - rtb mps ts) -- cancel out-of-sync member's rtb between [ts:ti]
        -- =>
        (rtb mpi t' - rtb mps (settledAt mps)) `mt_v_mul_u` u
