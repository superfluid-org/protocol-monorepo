{-# LANGUAGE DefaultSignatures      #-}
{-# LANGUAGE TypeFamilyDependencies #-}
module Money.Theory.MonetaryTypes where
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
    -- TODO: Do we need FlowRate type?
