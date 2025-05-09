{-# OPTIONS_GHC -Wno-missing-signatures #-}
{-# LANGUAGE OverloadedStrings #-}

module Money.Systems.Superfluid.DecayingFlowAgreement_test (tests) where

import           Control.Monad.IO.Class
import           Lens.Micro
import           Math.Extras.Double                                                  (fuzzyEq)
import           Test.Hspec                                                          (HasCallStack)
import           Test.HUnit

import qualified Money.Systems.Superfluid.Agreements.Universal.DecayingFlowAgreement as DFA
import qualified Money.Systems.Superfluid.Agreements.UniversalIndex                  as UIDX
import qualified Money.Systems.Superfluid.MonetaryUnitData.DecayingFlow              as DFMUD
--
import qualified Money.Systems.Superfluid.Instances.Simple.System                    as SF
--
import           Money.Systems.Superfluid.TokenTester

-- =====================================================================================================================
-- * Testing Utilities
--

tolerance = 1e5

newtype FuzzyEqDouble = FuzzyEqDouble Double deriving (Show)
instance Eq FuzzyEqDouble where
    (FuzzyEqDouble a) == (FuzzyEqDouble b) = fuzzyEq tolerance a b

assertFuzzilyEqualWith a b = assertEqual "~=" (FuzzyEqDouble a) (FuzzyEqDouble b)

expectΕValTo :: HasCallStack => SF.SimpleAddress -> (Double -> Assertion) -> TokenTester ()
expectΕValTo addr expr = do
    acc <- runToken $ SF.getAccount addr
    let εVal = acc ^. (SF.universalData . UIDX.dfa_lenses . DFMUD.εVal)
    liftIO $ expr εVal

expectDistributionLimitTo :: HasCallStack => (SF.SimpleAddress, SF.SimpleAddress) -> (SF.Wad -> Assertion) -> TokenTester ()
expectDistributionLimitTo (sender, receiver) expr = do
    flow <- runToken $ SF.getDecayingFlow sender receiver
    liftIO $ expr $ DFA.distribution_limit flow

-- 1x test unit for distribution limit
u1x = SF.toWad (42 :: Double)
u1xd = let (SF.Wad d) = u1x in fromInteger d :: Double

-- =====================================================================================================================
-- * Test Scenarios
--

simple1to1ScenarioTest = TokenTestCase TokenTestSpec
    { testCaseLabel = "Simple 1to1 Scenario Test"
    , testAddressesToInit = ["alice", "bob", "carol"]
    , testAccountInitBalance = constInitBalance
    } (\ctx -> do
    let [alice, bob, carol] = testAddresses ctx
    -- T0: test initial condition
    expectZeroTotalValue
    accounts' <- runToken SF.listAccounts
    liftIO $ assertEqual "expected number of accounts" 4 (length accounts')

    -- T1: test initial condition
    -- creating flow: alice -> bob @ 0.0001/s
    runToken $ SF.updateDecayingFlow alice bob u1x
    expectΕValTo alice $ assertEqual' (-u1xd)
    expectΕValTo bob   $ assertEqual'   u1xd
    expectΕValTo carol $ assertEqual'      0
    expectDistributionLimitTo (alice, bob)   $ assertEqual' u1x
    expectDistributionLimitTo (alice, carol) $ assertEqual'   0

    -- T2: move time forward and test balance moves
    timeTravel $ 3600 * 24
    expectAccountBalanceTo alice $ assertBoolWith' (< constInitBalance)
    expectAccountBalanceTo bob   $ assertBoolWith' (> constInitBalance)
    expectAccountBalanceTo carol $ assertBoolWith' (== constInitBalance)
    expectZeroTotalValueFuzzily 0 -- 0 tolerance
      )

simple1to2ScenarioTest = TokenTestCase TokenTestSpec
    { testCaseLabel = "Simple 1to2 Scenario Test"
    , testAddressesToInit = ["alice", "bob", "carol"]
    , testAccountInitBalance = constInitBalance
    } (\ctx -> do
    -- T0: test initial condition
    let [alice, bob, carol] = testAddresses ctx
    runToken $ SF.updateDecayingFlow alice bob        u1x
    runToken $ SF.updateDecayingFlow alice carol (u1x * 2)
    expectΕValTo alice $ assertFuzzilyEqualWith ((-3) * u1xd)
    expectΕValTo bob   $ assertFuzzilyEqualWith     u1xd
    expectΕValTo carol $ assertFuzzilyEqualWith  (2 * u1xd)
    expectDistributionLimitTo (alice, bob)   $ assertEqual'    u1x
    expectDistributionLimitTo (alice, carol) $ assertEqual' ( 2 * u1x)

    -- T1: move time forward and test balance moves
    timeTravel $ 3600 * 24
    expectAccountBalanceTo alice $ assertBoolWith' (< constInitBalance)
    expectAccountBalanceTo bob   $ assertBoolWith' (> constInitBalance)
    expectAccountBalanceTo carol $ assertBoolWith' (> constInitBalance)
    expectZeroTotalValueFuzzily tolerance
    )

simpleLoopScenarioTest = TokenTestCase TokenTestSpec
    { testCaseLabel = "Simple Loop Scenario Test"
    , testAddressesToInit = ["alice", "bob", "carol"]
    , testAccountInitBalance = constInitBalance
    } (\ctx -> do
    -- T0: test initial condition
    let [alice, bob, carol] = testAddresses ctx
    runToken $ SF.updateDecayingFlow alice bob   u1x
    runToken $ SF.updateDecayingFlow bob   carol u1x
    runToken $ SF.updateDecayingFlow carol alice u1x
    expectΕValTo alice $ assertEqual' 0
    expectΕValTo bob   $ assertEqual' 0
    expectΕValTo carol $ assertEqual' 0
    expectDistributionLimitTo (alice, bob)   $ assertEqual' u1x
    expectDistributionLimitTo (bob,   carol) $ assertEqual' u1x
    expectDistributionLimitTo (carol, alice) $ assertEqual' u1x

    -- T1: move time forward and test balance moves
    timeTravel $ 3600 * 24
    expectAccountBalanceTo alice $ assertBoolWith' (== constInitBalance)
    expectAccountBalanceTo bob   $ assertBoolWith' (== constInitBalance)
    expectAccountBalanceTo carol $ assertBoolWith' (== constInitBalance)
    expectZeroTotalValueFuzzily 0 -- 0 tolerance
    )

tests = createTokenTestSuite "DecayingFlowAgreement System Testsuite"
    [ simple1to1ScenarioTest
    , simple1to2ScenarioTest
    , simpleLoopScenarioTest
    ]
