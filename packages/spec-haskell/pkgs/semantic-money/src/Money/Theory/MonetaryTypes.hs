{-# LANGUAGE DefaultSignatures      #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE TypeFamilyDependencies #-}
module Money.Theory.MonetaryTypes
    ( MonetaryTypes
      ( MT_TIME, MT_VALUE, MT_UNIT
      , mt_v_mul_t, mt_v_mul_u, mt_v_div_u, mt_v_mul_u_qr_u
      )
    , MonetaryTypes'tv, MonetaryTypes'tvu
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
      , Eq (MT_UNIT mt), Ord (MT_UNIT mt), Num (MT_UNIT mt)
      ) =>
      MonetaryTypes mt where
    mt_v_mul_t :: MT_VALUE mt -> MT_TIME mt -> MT_VALUE mt
    default mt_v_mul_t ::
        Integral (MT_TIME mt) =>
        MT_VALUE mt -> MT_TIME mt -> MT_VALUE mt
    mt_v_mul_t v t = v * (fromInteger . toInteger) t

    mt_v_mul_u :: MT_VALUE mt -> MT_UNIT mt -> MT_VALUE mt
    default mt_v_mul_u ::
        Integral (MT_UNIT mt) =>
        MT_VALUE mt -> MT_UNIT mt -> MT_VALUE mt
    mt_v_mul_u v u = v * (fromInteger . toInteger) u

    mt_v_div_u :: MT_VALUE mt -> MT_UNIT mt -> MT_VALUE mt
    default mt_v_div_u ::
        (Integral (MT_VALUE mt), Integral (MT_UNIT mt)) =>
        MT_VALUE mt -> MT_UNIT mt -> MT_VALUE mt
    mt_v_div_u v u = let u' = (fromInteger . toInteger) u in v `div` u'

    mt_v_mul_u_qr_u :: MT_VALUE mt -> (MT_UNIT mt, MT_UNIT mt) -> (MT_VALUE mt, MT_VALUE mt)
    default mt_v_mul_u_qr_u ::
        (Integral (MT_VALUE mt), Integral (MT_UNIT mt)) =>
        MT_VALUE mt -> (MT_UNIT mt, MT_UNIT mt) -> (MT_VALUE mt, MT_VALUE mt)
    mt_v_mul_u_qr_u v (u1, u2) = (v * (fromInteger . toInteger) u1) `quotRem` (fromInteger . toInteger) u2

    type family MT_TIME  mt = (t :: Type) | t -> mt
    type family MT_VALUE mt = (v :: Type) | v -> mt
    type family MT_UNIT  mt = (u :: Type) | u -> mt
    -- TODO: type family MT_FLOWRATE mt = (fr :: Type) | fr -> mt

type MonetaryTypes'tv mt t v = (MonetaryTypes mt, t ~ MT_TIME mt, v ~ MT_VALUE mt)
type MonetaryTypes'tvu mt t v u = (MonetaryTypes mt, t ~ MT_TIME mt, v ~ MT_VALUE mt, u ~ MT_UNIT mt)
