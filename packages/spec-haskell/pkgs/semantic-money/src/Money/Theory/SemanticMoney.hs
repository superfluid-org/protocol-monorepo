{-# LANGUAGE DerivingStrategies     #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE TypeFamilyDependencies #-}

module Money.Theory.SemanticMoney where

import           Data.Default (Default (..))
import           Data.Kind    (Type)


-- | Type system trite: types used in semantic money
--
-- Note:
--   * Index related types through associated type families.
--   * Use type family dependencies to make these types to the index type injective.
class ( Integral (MT_TIME  mt)
      , Integral (MT_VALUE mt)
      , Integral (MT_UNIT  mt)
      , Integral (MT_FLOWRATE mt)
      ) => MonetaryTypes mt where
    mt_v_mul_t :: MT_VALUE mt -> MT_TIME mt -> MT_VALUE mt
    mt_v_mul_t v t = v * (fromInteger . toInteger) t
    mt_v_mul_u :: MT_VALUE mt -> MT_UNIT mt -> MT_VALUE mt
    mt_v_mul_u v u = v * (fromInteger . toInteger) u
    mt_v_div_u :: MT_VALUE mt -> MT_UNIT mt -> MT_VALUE mt
    mt_v_div_u v u = let u' = (fromInteger . toInteger) u in v `div` u'
    mt_v_mul_u_qr_u :: MT_VALUE mt -> (MT_UNIT mt, MT_UNIT mt) -> (MT_VALUE mt, MT_VALUE mt)
    mt_v_mul_u_qr_u v (u1, u2) = (v * (fromInteger . toInteger) u1) `quotRem` (fromInteger . toInteger) u2


    mt_fr_mul_t :: MT_FLOWRATE mt -> MT_TIME mt -> MT_VALUE mt
    mt_fr_mul_t r t = (fromInteger . toInteger) r * (fromInteger . toInteger) t
    mt_fr_mul_u :: MT_FLOWRATE mt -> MT_UNIT mt -> MT_FLOWRATE mt
    mt_fr_mul_u r u = r * (fromInteger . toInteger) u
    mt_fr_div_u :: MT_FLOWRATE mt -> MT_UNIT mt -> MT_FLOWRATE mt
    mt_fr_div_u r u = let u' = (fromInteger . toInteger) u in r `div` u'
    mt_fr_mul_u_qr_u :: MT_FLOWRATE mt -> (MT_UNIT mt, MT_UNIT mt) -> (MT_FLOWRATE mt, MT_FLOWRATE mt)
    mt_fr_mul_u_qr_u r (u1, u2) = (r * (fromInteger . toInteger) u1) `quotRem` (fromInteger . toInteger) u2

    type family MT_TIME  mt = (t :: Type) | t -> mt
    type family MT_VALUE mt = (v :: Type) | v -> mt
    type family MT_UNIT  mt = (u :: Type) | u -> mt
    type family MT_FLOWRATE mt = (fr :: Type) | fr -> mt
--
-- General Payment Primitives
--

class ( MonetaryTypes mt, t ~ MT_TIME mt, v ~ MT_VALUE mt
      , fr ~ MT_FLOWRATE mt) => MonetaryUnit mt t v fr mu | mu -> mt where
    settle    :: t -> mu -> mu
    settledAt :: mu -> t
    flowRate  :: mu -> fr
    rtb       :: mu -> t -> v

 -- * On right side biased operations:
 --   1) Right side produces error term with which left side is adjusted accordingly.
 --   2) The adjustment must not produce new error term, or otherwise it would require recursive adjustments.

class ( MonetaryTypes mt, t ~ MT_TIME mt, v ~ MT_VALUE mt, u ~ MT_UNIT mt
      , MonetaryUnit mt t v fr ix, Monoid ix
      ) => Index mt t v u fr ix | ix -> mt where
    shift1 :: v -> ix -> (ix, v)
    flow1  :: fr -> ix -> (ix, fr)

class ( MonetaryTypes mt, t ~ MT_TIME mt, v ~ MT_VALUE mt, u ~ MT_UNIT mt
      , fr ~ MT_FLOWRATE mt, MonetaryUnit mt t v fr mp, Index mt t v u fr mp
      ) => MonetaryParticle mt t v u  fr mp where
    -- align 2-primitive, right side biased
    align2 :: forall a. Index mt t v u fr a => u -> u -> (mp, a) -> (mp, a)

-- polymorphic 2-primitives
--

-- 2-primitive higher order function
prim2 :: (Index mt t v u fr a, Index mt t v u  fr b)
      => ((a, b) -> (a, b)) -> t -> (a, b) -> (a, b)
prim2 op t' (a, b) = op (settle t' a, settle t' b)

-- shift2, right side biased error term adjustment
shift2 :: (Index mt t v u fr a, Index mt t v u fr b)
       => v -> t -> (a, b) -> (a, b)
shift2 amount = prim2 op
    where op (a, b) = let (b', amount') = shift1 amount b
                          (a', _) = shift1 (-amount') a
                      in  (a', b')

-- flow2, right side biased error term adjustment
flow2 :: (Index mt t v u fr a, Index mt t v u fr b)
      => fr -> t -> (a, b) -> (a, b)
flow2 r = prim2 op
    where op (a, b) = let (b', r') = flow1 r b
                          (a', _) = flow1 (-r') a
                      in  (a', b')

-- shiftFlow2 for the left side (a), right side biased error term adjustment
shiftFlow2a :: (Index mt t v u fr a, Index mt t v u fr b)
            => fr -> t -> (a, b) -> (a, b)
shiftFlow2a dr t (a, b) = let ( _, b1) = flow2 (flowRate a) t (a, mempty)
                              (a', b2) = flow2 (-flowRate a + dr) t (a, mempty)
                          in  (a', b <> b1 <> b2)

-- shiftFlow2 for the right side (b), right side biased error term adjustment
shiftFlow2b :: (Index mt t v u fr a, Index mt t v u fr b)
            => fr -> t -> (a, b) -> (a, b)
shiftFlow2b dr t (a, b) = let (a1,  _) = flow2 (-flowRate b) t (mempty, b)
                              (a2, b') = flow2 (flowRate b + dr) t (mempty, b)
                          in  (a <> a1 <> a2, b')

--
-- Univeral Index
--

newtype UniversalIndex mt wp = UniversalIndex wp
deriving newtype instance ( MonetaryTypes mt
                          , Eq wp ) => Eq (UniversalIndex mt wp)
deriving newtype instance ( MonetaryTypes mt
                          , Semigroup wp ) => Semigroup (UniversalIndex mt wp)
deriving newtype instance ( MonetaryTypes mt
                          , Monoid wp ) => Monoid (UniversalIndex mt wp)
deriving newtype instance ( MonetaryTypes mt, t ~ MT_TIME mt, v ~ MT_VALUE mt, fr ~ MT_FLOWRATE mt
                          , MonetaryUnit mt t v fr wp ) => MonetaryUnit mt t v fr (UniversalIndex mt wp)
deriving newtype instance ( MonetaryTypes mt, t ~ MT_TIME mt, v ~ MT_VALUE mt, u ~ MT_UNIT mt, fr ~ MT_FLOWRATE mt
                          , Monoid wp
                          , Index mt t v u fr wp ) => Index mt t v u fr (UniversalIndex mt wp)

--
-- Proportional Distribution Pool
--

data PDPoolIndex mt wp = PDPoolIndex { pdidx_total_units :: MT_UNIT mt
                                     , pdidx_wp          :: wp -- wrapped particle
                                     }
instance ( MonetaryTypes mt, t ~ MT_TIME mt, v ~ MT_VALUE mt, fr ~ MT_FLOWRATE mt
         , MonetaryUnit mt t v fr wp) => MonetaryUnit mt t v fr (PDPoolIndex mt wp) where
    settle t' a@(PDPoolIndex _ mpi) = a { pdidx_wp = settle t' mpi }
    settledAt (PDPoolIndex _ mpi) = settledAt mpi
    flowRate (PDPoolIndex _ mpi) = flowRate mpi
    rtb (PDPoolIndex _ mpi) = rtb mpi

instance (MonetaryTypes mt, Semigroup wp) => Semigroup (PDPoolIndex mt wp) where
    -- The binary operator supports negative unit values while abiding the monoidal laws.
    -- The practical semantics of values of mixed-sign is not of the concern of this specification.
    (PDPoolIndex u1 a) <> (PDPoolIndex u2 b) = PDPoolIndex u' (a <> b)
        where u' | u1 == 0 = u2 | u2 == 0 = u1 | otherwise = max u1 u2

instance (MonetaryTypes mt, Monoid wp) => Monoid (PDPoolIndex mt wp) where
    mempty = PDPoolIndex 0 mempty

instance ( MonetaryTypes mt, t ~ MT_TIME mt, v ~ MT_VALUE mt, u ~ MT_UNIT mt, fr ~ MT_FLOWRATE mt
         , MonetaryParticle mt t v u fr wp) => Index mt t v u fr (PDPoolIndex mt wp) where
    shift1 x a@(PDPoolIndex tu mpi) = (a { pdidx_wp = mpi' }, x' `mt_v_mul_u` tu)
        where (mpi', x') = if tu == 0 then (mpi, 0) else shift1 (x `mt_v_div_u` tu) mpi

    flow1 r' a@(PDPoolIndex tu mpi) = (a { pdidx_wp = mpi' }, r'' `mt_fr_mul_u` tu)
        where (mpi', r'') = if tu == 0 then flow1 0 mpi else flow1 (r' `mt_fr_div_u` tu) mpi

data PDPoolMember mt wp = PDPoolMember { pdpm_owned_unit    :: MT_UNIT mt
                                       , pdpm_settled_value :: MT_VALUE mt
                                       , pdpm_synced_wp     :: wp
                                       }
instance ( MonetaryTypes mt, t ~ MT_TIME mt, v ~ MT_VALUE mt, u ~ MT_UNIT mt, fr ~ MT_FLOWRATE mt
         , Monoid wp ) => Default (PDPoolMember mt wp) where def = PDPoolMember 0 0 mempty
type PDPoolMemberMU mt wp = (PDPoolIndex mt wp, PDPoolMember mt wp)

pdpUpdateMember2 :: ( MonetaryTypes mt, t ~ MT_TIME mt, v ~ MT_VALUE mt, u ~ MT_UNIT mt, fr ~ MT_FLOWRATE mt
                    , Index mt t v u fr a
                    , MonetaryParticle mt t v u fr wp
                    , mu ~ PDPoolMemberMU mt wp
                    ) => u -> t -> (a, mu) -> (a, mu)
pdpUpdateMember2 u' t' (a, (b, pm))  = (a'', (b'', pm''))
    where (PDPoolIndex tu mpi, pm'@(PDPoolMember u _ _)) = settle t' (b, pm)
          tu' = tu + u' - u
          (mpi', a'') = align2 tu tu' (mpi, settle t' a)
          b''  = PDPoolIndex tu' mpi'
          pm'' = pm' { pdpm_owned_unit = u', pdpm_synced_wp = mpi' }

instance ( MonetaryTypes mt, t ~ MT_TIME mt, v ~ MT_VALUE mt, fr ~ MT_FLOWRATE mt
         , MonetaryUnit mt t v fr wp) => MonetaryUnit mt t v fr (PDPoolMemberMU mt wp) where
    settle t' (pix, pm) = (pix', pm')
        where sv' = rtb (pix, pm) t'
              pix'@(PDPoolIndex _ mpi') = settle t' pix
              pm' = pm { pdpm_settled_value = sv', pdpm_synced_wp = mpi' }

    settledAt (_, PDPoolMember _ _ mps) = settledAt mps

    flowRate (PDPoolIndex _ mpi, PDPoolMember u _ _) = flowRate mpi `mt_fr_mul_u` u

    rtb (PDPoolIndex _ mpi, PDPoolMember u sv mps) t' = sv +
        -- let ti = bp_settled_at mpi
        --     ts = bp_settled_at mps
        -- in (rtb mpi t' - rtb mps ti) -- include index's current accruals for the member
        -- +  (rtb mps ti - rtb mps ts) -- cancel out-of-sync member's rtb between [ts:ti]
        -- =>
        (rtb mpi t' - rtb mps (settledAt mps)) `mt_v_mul_u` u

--
-- Particles: building block for indexes
--

data BasicParticle mt = BasicParticle { bp_settled_at    :: MT_TIME  mt
                                      , bp_settled_value :: MT_VALUE mt
                                      , bp_flow_rate     :: MT_FLOWRATE mt
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

instance ( MonetaryTypes mt, t ~ MT_TIME mt, v ~ MT_VALUE mt, fr ~ MT_FLOWRATE mt
         ) => MonetaryUnit mt t v fr (BasicParticle mt) where
    settle t' a = a { bp_settled_at = t'
                    , bp_settled_value = rtb a t'
                    }
    settledAt = bp_settled_at
    flowRate = bp_flow_rate
    rtb (BasicParticle t s r) t' = r `mt_fr_mul_t` (t' - t) + s

instance ( MonetaryTypes mt, t ~ MT_TIME mt, v ~ MT_VALUE mt, u ~ MT_UNIT mt, fr ~ MT_FLOWRATE mt
         ) => Index mt t v u fr (BasicParticle mt) where

    shift1 x a = (a { bp_settled_value = bp_settled_value a + x }, x)
    flow1 r' a = (a { bp_flow_rate = r' }, r')

instance ( MonetaryTypes mt, t ~ MT_TIME mt, v ~ MT_VALUE mt, u ~ MT_UNIT mt, f ~ MT_FLOWRATE mt ) =>
  MonetaryParticle mt t v u f (BasicParticle mt) where
  align2 u u' (b, a) = (b', a')
    where
      r = flowRate b
      (r', er') = if u' == 0 then (0, r `mt_fr_mul_u` u) else r `mt_fr_mul_u_qr_u` (u, u')
      b' = fst . flow1 r' $ b
      a' = fst . flow1 (er' + flowRate a) $ a
