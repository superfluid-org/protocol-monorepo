{- HLINT ignore "Monoid law, left identity"  -}
{- HLINT ignore "Monoid law, right identity"  -}
{-# OPTIONS_GHC -Wno-missing-signatures #-}

module Money.Theory.SemanticMoney_prop (tests) where
--
import           Data.Default
import           Test.Hspec
import           Test.QuickCheck
-- containers
import qualified Data.IntMap                    as IntMap
--
import           Money.Theory.SemanticMoney
import           Money.Theory.TestMonetaryTypes


--------------------------------------------------------------------------------
-- Monetary Units Laws: settle-idempotency, constant-rtb
--------------------------------------------------------------------------------

mu_settle_idempotency :: ( MonetaryUnit TestMonetaryTypes TestTime TestMValue TestMFlowRate mu
                      , Eq mu
                      ) => mu -> TestTime -> Bool
mu_settle_idempotency a t =
    settledAt (settle t a) == t &&
    settle t a == settle t (settle t a)
mu_constant_rtb :: ( MonetaryUnit TestMonetaryTypes TestTime TestMValue TestMFlowRate mu
                   ) => mu -> TestTime -> TestTime -> TestTime -> Bool
mu_constant_rtb a t1 t2 t3 =
    rtb (settle t1 a) t3 == rtb a t3 &&
    rtb (settle t2 a) t3 == rtb a t3 &&
    rtb (settle t2 (settle t1 a)) t3 == rtb a t3

bp_settle_idempotency (a :: TesBasicParticle) = mu_settle_idempotency a
bp_constant_rtb (a :: TesBasicParticle) = mu_constant_rtb a
uidx_settle_idempotency (a :: TestUniversalIndex) = mu_settle_idempotency a
uidx_constant_rtb (a :: TestUniversalIndex) = mu_constant_rtb a
pdidx_settle_idempotency (a :: TestPDPoolIndex) = mu_settle_idempotency a
pdidx_constant_rtb (a :: TestPDPoolIndex) = mu_constant_rtb a
pdmb_settle_idempotency (a :: TestPDPoolMemberMU) = mu_settle_idempotency a
pdmb_constant_rtb (a :: TestPDPoolIndex) t1 u1 t2 u2 = mu_constant_rtb b''
    -- adding two members to an existing index
    where (a', b') = pdpUpdateMember2 u1 t1 (a, (a, def))
          (_, b'') = pdpUpdateMember2 u2 t2 (a', b')

mu_laws = describe "monetary unit laws" $ do
    it "bp settle idempotency" $ property bp_settle_idempotency
    it "bp constant rtb" $ property bp_constant_rtb
    it "uidx settle idempotency" $ property uidx_settle_idempotency
    it "uidx constant rtb" $ property uidx_constant_rtb
    it "pdidx settle idempotency" $ property pdidx_settle_idempotency
    it "pdidx constant rtb" $ property pdidx_constant_rtb
    it "pdmb settle idempotency" $ property pdmb_settle_idempotency
    it "pdmb contant rtb" $ property pdmb_constant_rtb

--------------------------------------------------------------------------------
-- Monoidal Laws For Basic Particles and Indexes
--------------------------------------------------------------------------------

bp_monoid_identity (a :: TesBasicParticle) = a == a <> mempty && a == mempty <> a
bp_monoid_assoc (a :: TesBasicParticle) b c = (a <> b) <> c == a <> (b <> c)
uidx_monoid_identity (a :: TestUniversalIndex) = a == a <> mempty && a == mempty <> a
uidx_monoid_assoc (a :: TestUniversalIndex) b c = (a <> b) <> c == a <> (b <> c)
pdidx_monoid_identity (a :: TestPDPoolIndex) = a == a <> mempty && a == mempty <> a
pdidx_monoid_assoc (a :: TestPDPoolIndex) b c = (a <> b) <> c == a <> (b <> c)

mp_monoid_laws = describe "monetary particles monoidal laws" $ do
    it "bp monoid identity law" $ property bp_monoid_identity
    it "bp monoid associativity law" $ property bp_monoid_assoc
    it "uidx monoid identity law" $ property uidx_monoid_identity
    it "uidx monoid associativity law" $ property uidx_monoid_assoc
    it "pdidx monoid identity law" $ property pdidx_monoid_identity
    it "pdidx monoid associativity law" $ property pdidx_monoid_assoc

--------------------------------------------------------------------------------
-- 1to1 2-primitives
--------------------------------------------------------------------------------

uu_f1_f2 f1 f2 t1 {- f1 -} t2 {- f2 -} t3 =
    0 == rtb a' t3 + rtb b' t3
    where (a, b) = (mempty :: TestUniversalIndex, mempty :: TestUniversalIndex)
          (a', b') = f2 t2 (f1 t1 (a, b))

uu_shift2_shift2 x1 x2 = uu_f1_f2 (shift2 x1) (shift2 x2)
uu_flow2_flow2 r1 r2 = uu_f1_f2 (flow2 r1) (flow2 r2)
uu_shift2_flow2 x r = uu_f1_f2 (shift2 x) (flow2 r)
uu_flow2_shift2 r x = uu_f1_f2 (flow2 r) (shift2 x)

one2one_tests = describe "1to1 2-primitives" $ do
    it "uidx:uidx shift2 shift2" $ property uu_shift2_shift2
    it "uidx:uidx flow2 flow2"  $ property uu_flow2_flow2
    it "uidx:uidx shift2 flow2" $ property uu_shift2_flow2
    it "uidx:uidx flow2 shift2" $ property uu_flow2_shift2

--------------------------------------------------------------------------------
-- 1toN proportional distribution 2-primitives
--------------------------------------------------------------------------------

updp_u1_f1_u1_f2 f1 f2 t1 u1 t2 {- f1 -} t3 {- f2 -} t4 u2 t5 =
    pdidx_total_units b'' == u2 &&
    0 == rtb a'' t5 + rtb (b'', b1') t5
    where (a, (b, b1)) = pdpUpdateMember2 u1 t1 (mempty :: TestUniversalIndex, (mempty :: TestPDPoolIndex, def))
          (a', b') = f2 t3 (f1 t2 (a, b))
          (a'', (b'', b1')) = pdpUpdateMember2 u2 t4 (a', (b', b1))

updp_u1_f1_u2_f2 f1 f2 t1 u1 t2 {- f1 -} t3 u2 t4 {- f2 -} t5 =
    pdidx_total_units b''' == u1 + u2 &&
    0 == rtb a''' t5 + rtb (b''', b1) t5 + rtb (b''', b2) t5
    where (a, (b, b1)) = pdpUpdateMember2 u1 t1 (mempty :: TestUniversalIndex, (mempty :: TestPDPoolIndex, def))
          (a', b') = f1 t2 (a, b)
          (a'', (b'', b2)) = pdpUpdateMember2 u2 t3 (a', (b', def :: TestPDPoolMember))
          (a''', b''') = f2 t4 (a'', b'')

updp_u1_shift2_u1_shift2 x1 x2 = updp_u1_f1_u1_f2 (shift2 x1) (shift2 x2)
updp_u1_flow2_u1_flow2 r1 r2 = updp_u1_f1_u1_f2 (flow2 r1) (flow2 r2)
updp_u1_shift2_u1_flow2 x r = updp_u1_f1_u1_f2 (shift2 x) (flow2 r)
updp_u1_flow2_u1_shift2 r x = updp_u1_f1_u1_f2 (shift2 r) (flow2 x)
updp_u1_shift2_u2_shift2 x1 x2 = updp_u1_f1_u2_f2 (shift2 x1) (shift2 x2)
updp_u1_flow2_u2_flow2 r1 r2 = updp_u1_f1_u2_f2 (flow2 r1) (flow2 r2)
updp_u1_flow2_u2_shift2 r x = updp_u1_f1_u2_f2 (flow2 r) (shift2 x)
updp_u1_shift2_u2_flow2 x r = updp_u1_f1_u2_f2 (shift2 x) (flow2 r)

one2n_pd_tests = describe "1toN proportional distribution 2-primitives" $ do
    it "uidx:pdidx u1 shift2 u1 shift2" $ property updp_u1_shift2_u1_shift2
    it "uidx:pdidx u1 flow2  u1 flow2"  $ property updp_u1_flow2_u1_flow2
    it "uidx:pdidx u1 shift2 u1 flow2"  $ property updp_u1_shift2_u1_flow2
    it "uidx:pdidx u1 flow2  u1 shift2" $ property updp_u1_flow2_u1_shift2
    it "uidx:pdidx u1 shift2 u2 shift2" $ property updp_u1_shift2_u2_shift2
    it "uidx:pdidx u1 flow2  u2 flow2"  $ property updp_u1_flow2_u2_flow2
    it "uidx:pdidx u1 flow2  u2 shift2" $ property updp_u1_flow2_u2_shift2
    it "uidx:pdidx u1 shift2 u2 flow2"  $ property updp_u1_shift2_u2_flow2

--------------------------------------------------------------------------------
-- (Constant Rate) Flow 2-Primitive
--------------------------------------------------------------------------------

uu_flow2 (a :: TestUniversalIndex) (b :: TestUniversalIndex) t1 r1 t2 r2 t3 =
    flowRate b' == r2 && flowRate a' == -r2 &&
    r1 `mt_fr_mul_t` (t2 - t1) + r2 `mt_fr_mul_t` (t3 - t2) == rtb b' t3 - rtb b t1
    where (a', b') = flow2 r2 t2 (flow2 r1 t1 (a, b))

updp_flow2 (a :: TestUniversalIndex) t1 r1 t2 r2 t3 =
    flowRate b'' == r2 && flowRate a'' == -r2 &&
    flowRate (b'', b1') == r2 &&
    r1 `mt_fr_mul_t` (t2 - t1) + r2 `mt_fr_mul_t` (t3 - t2) == rtb (b'', b1') t3 - rtb (b', b1') t1
    where (a', (b', b1')) = pdpUpdateMember2 1 t1 (a, (mempty :: TestPDPoolIndex, def))
          (a'', b'') = flow2 r2 t2 (flow2 r1 t1 (a', b'))

uu_shiftFlow2a (a :: TestUniversalIndex) (b :: TestUniversalIndex) t1 r1 t2 r2 t3 =
    flowRate b' - flowRate b == r1 + r2 && flowRate a' - flowRate a == -r1 -r2 &&
    rtb b' t3 - rtb b t3 == rtb a t3 - rtb a' t3 &&
    -- for shift flow semantics: rtb b' t3 - (rtb b t3 - rtb b t1) - rtb b t1 == rtb b' t3 - rtb b t3
    r1 `mt_fr_mul_t` (t2 - t1) + (r1 + r2) `mt_fr_mul_t` (t3 - t2) == rtb b' t3 - rtb b t3
    where (a', b') = shiftFlow2a r2 t2 (shiftFlow2a r1 t1 (a, b))

uu_shiftFlow2b (a :: TestUniversalIndex) (b :: TestUniversalIndex) t1 r1 t2 r2 t3 =
    flowRate b' - flowRate b == r1 + r2 && flowRate a' - flowRate a == -r1 -r2 &&
    rtb b' t3 - rtb b t3 == rtb a t3 - rtb a' t3 &&
    -- ditto
    r1 `mt_fr_mul_t` (t2 - t1) + (r1 + r2) `mt_fr_mul_t` (t3 - t2) == rtb b' t3 - rtb b t3
    where (a', b') = shiftFlow2b r2 t2 (shiftFlow2b r1 t1 (a, b))

-- NOTE: updp_shiftFlow2a is an invalid property due to right side biansed error term adjustment.

updp_shiftFlow2b (a :: TestUniversalIndex) t1 r1 t2 r2 t3 =
    flowRate b'' - flowRate b' == r1 + r2 && flowRate a'' - flowRate a' == -r1 -r2 &&
    flowRate (b'', b1') == r1 + r2 &&
    rtb (b'', b1') t3 - rtb (b', b1') t3 == rtb a' t3 - rtb a'' t3 &&
    -- ditto
    r1 `mt_fr_mul_t` (t2 - t1) + (r1 + r2) `mt_fr_mul_t` (t3 - t2) == rtb (b'', b1') t3 - rtb (b', b1') t3
    where (a', (b', b1')) = pdpUpdateMember2 1 t1 (a, (mempty :: TestPDPoolIndex, def))
          (a'', b'') = shiftFlow2b r2 t2 (shiftFlow2b r1 t1 (a', b'))

flow2_tests = describe "flow2 tests" $ do
    it "uidx:uidx flow2" $ property uu_flow2
    it "uidx:pdidx flow2" $ property updp_flow2
    it "uidx:uidx shiftFlow2a" $ property uu_shiftFlow2a
    it "uidx:uidx shiftFlow2b" $ property uu_shiftFlow2b
    it "uidx:pdidx shiftFlow2b" $ property updp_shiftFlow2b

process_one_transfer_event :: Bool
process_one_transfer_event = (s IntMap.! 0) 0 == -100 && (s IntMap.! 1) 0 == 100
  where s = naiveSystemSnapshot . processEvents $
            ([ Transfer 0 {- t -} 0 1 100
             ] :: [MoneyEvent' TestMonetaryTypes Int])

navive_event_processing = describe "naive event processing" $ do
  it "simple demonstrative case" process_one_transfer_event

tests = describe "Semantic money properties" $ do
    mu_laws
    mp_monoid_laws
    one2one_tests
    one2n_pd_tests
    flow2_tests
    navive_event_processing
