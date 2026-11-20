{-# LANGUAGE DefaultSignatures      #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE TypeFamilyDependencies #-}
module Money.Theory.MonetaryTypes
    ( MonetaryTypes
      ( MT_TIME, MT_VALUE, MT_FLOWRATE, MT_UNIT
      , mt_fr_mul_t
      , mt_v_mul_u, mt_v_quot_u, mt_v_mul_u_qr_u
      , mt_fr_mul_u, mt_fr_quot_u, mt_fr_mul_u_qr_u
      )
    , MonetaryTypes'tv, MonetaryTypes'tr, MonetaryTypes'tvr, MonetaryTypes'tvru
    ) where
-- base
import           Data.Kind (Type)


-- | Type system trite: types used in semantic money
--
-- Note:
--   * Index related types through associated type families.
--   * Use type family dependencies to make these types to the index type injective.
class ( Eq (MT_TIME mt), Ord (MT_TIME mt), Num (MT_TIME mt)
      , Eq (MT_VALUE mt), Ord (MT_VALUE mt), Num (MT_VALUE mt)
      , Eq (MT_FLOWRATE mt), Ord (MT_FLOWRATE mt), Num (MT_FLOWRATE mt)
      , Eq (MT_UNIT mt), Ord (MT_UNIT mt), Num (MT_UNIT mt)
      ) =>
      MonetaryTypes mt where
    mt_fr_mul_t :: MT_FLOWRATE mt -> MT_TIME mt -> MT_VALUE mt
    default mt_fr_mul_t ::
        (Integral (MT_TIME mt), Integral (MT_FLOWRATE mt))=>
        MT_FLOWRATE mt -> MT_TIME mt -> MT_VALUE mt
    mt_fr_mul_t fr t = fromInteger (toInteger fr * toInteger t)

    mt_v_mul_u :: MT_VALUE mt -> MT_UNIT mt -> MT_VALUE mt
    default mt_v_mul_u ::
        Integral (MT_UNIT mt) =>
        MT_VALUE mt -> MT_UNIT mt -> MT_VALUE mt
    mt_v_mul_u v u = v * (fromInteger . toInteger) u

    mt_v_quot_u :: MT_VALUE mt -> MT_UNIT mt -> MT_VALUE mt
    default mt_v_quot_u ::
        (Integral (MT_VALUE mt), Integral (MT_UNIT mt)) =>
        MT_VALUE mt -> MT_UNIT mt -> MT_VALUE mt
    mt_v_quot_u v u = let u' = (fromInteger . toInteger) u in v `quot` u'

    mt_v_mul_u_qr_u :: MT_VALUE mt -> (MT_UNIT mt, MT_UNIT mt) -> (MT_VALUE mt, MT_VALUE mt)
    default mt_v_mul_u_qr_u ::
        (Integral (MT_VALUE mt), Integral (MT_UNIT mt)) =>
        MT_VALUE mt -> (MT_UNIT mt, MT_UNIT mt) -> (MT_VALUE mt, MT_VALUE mt)
    mt_v_mul_u_qr_u v (u1, u2) = (v * (fromInteger . toInteger) u1) `quotRem` (fromInteger . toInteger) u2

    mt_fr_mul_u :: MT_FLOWRATE mt -> MT_UNIT mt -> MT_FLOWRATE mt
    default mt_fr_mul_u ::
        Integral (MT_UNIT mt) =>
        MT_FLOWRATE mt -> MT_UNIT mt -> MT_FLOWRATE mt
    mt_fr_mul_u fr u = fr * (fromInteger . toInteger) u

    mt_fr_quot_u :: MT_FLOWRATE mt -> MT_UNIT mt -> MT_FLOWRATE mt
    default mt_fr_quot_u ::
        (Integral (MT_FLOWRATE mt), Integral (MT_UNIT mt)) =>
        MT_FLOWRATE mt -> MT_UNIT mt -> MT_FLOWRATE mt
    mt_fr_quot_u fr u = let u' = (fromInteger . toInteger) u in fr `quot` u'

    mt_fr_mul_u_qr_u :: MT_FLOWRATE mt -> (MT_UNIT mt, MT_UNIT mt) -> (MT_FLOWRATE mt, MT_FLOWRATE mt)
    default mt_fr_mul_u_qr_u ::
        (Integral (MT_FLOWRATE mt), Integral (MT_UNIT mt)) =>
        MT_FLOWRATE mt -> (MT_UNIT mt, MT_UNIT mt) -> (MT_FLOWRATE mt, MT_FLOWRATE mt)
    mt_fr_mul_u_qr_u fr (u1, u2) = (fr * (fromInteger . toInteger) u1) `quotRem` (fromInteger . toInteger) u2

    type family MT_TIME  mt = (t :: Type) | t -> mt
    type family MT_VALUE mt = (v :: Type) | v -> mt
    type family MT_FLOWRATE mt = (fr :: Type) | fr -> mt
    type family MT_UNIT  mt = (u :: Type) | u -> mt

type MonetaryTypes'tv mt t v = (MonetaryTypes mt, t ~ MT_TIME mt, v ~ MT_VALUE mt)
type MonetaryTypes'tr mt t fr = (MonetaryTypes mt, t ~ MT_TIME mt, fr ~ MT_FLOWRATE mt)
type MonetaryTypes'tvr mt t v fr = (MonetaryTypes'tv mt t v, MonetaryTypes'tr mt t fr)
type MonetaryTypes'tvru mt t v fr u = (MonetaryTypes'tvr mt t v fr, u ~ MT_UNIT mt)
