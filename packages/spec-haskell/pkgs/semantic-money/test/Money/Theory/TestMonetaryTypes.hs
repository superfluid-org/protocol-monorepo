{-# LANGUAGE TypeFamilies #-}

module Money.Theory.TestMonetaryTypes where

import           Test.QuickCheck

import           Money.Theory.SemanticMoney


-- TestMonetaryTypes
--

newtype TestTime = TestTime Integer deriving (Enum, Eq, Ord, Num, Real, Integral, Show)
instance Arbitrary TestTime where
    arbitrary = TestTime <$> arbitrary

newtype TestMValue = TestMValue Integer deriving (Enum, Eq, Ord, Num, Real, Integral, Show)
instance Arbitrary TestMValue where
    arbitrary = TestMValue <$> arbitrary

newtype TestMUnit = TestMUnit Integer deriving (Enum, Eq, Ord, Num, Real, Integral, Show)
instance Arbitrary TestMUnit where
    arbitrary = TestMUnit <$> arbitrary

newtype TestMFlowRate = TestMFlowRate Integer deriving (Enum, Eq, Ord, Num, Real, Integral, Show)
instance Arbitrary TestMFlowRate where
    arbitrary = TestMFlowRate <$> arbitrary

data TestMonetaryTypes
instance MonetaryTypes TestMonetaryTypes where
    type MT_TIME  TestMonetaryTypes = TestTime
    type MT_VALUE TestMonetaryTypes = TestMValue
    type MT_FLOWRATE TestMonetaryTypes = TestMFlowRate
    type MT_UNIT  TestMonetaryTypes = TestMUnit
deriving instance Show (BasicParticle TestMonetaryTypes)

-- TesBasicParticle
--
type TesBasicParticle = BasicParticle TestMonetaryTypes
instance Arbitrary TesBasicParticle where
    arbitrary = BasicParticle <$> arbitrary <*> arbitrary <*> arbitrary

-- TesBasicParticle
--
type TestUniversalIndex = UniversalIndex TestMonetaryTypes TesBasicParticle
deriving instance Show TestUniversalIndex
instance Arbitrary TestUniversalIndex where
    arbitrary = UniversalIndex <$> arbitrary

-- PDPoolIndex
--
type TestPDPoolIndex = PDPoolIndex TestMonetaryTypes TesBasicParticle
deriving instance Show TestPDPoolIndex
deriving instance Eq TestPDPoolIndex
instance Arbitrary TestPDPoolIndex where
    arbitrary = PDPoolIndex <$> arbitrary <*> arbitrary

-- PDPoolMember
--

type TestPDPoolMember = PDPoolMember TestMonetaryTypes TesBasicParticle
deriving instance Show TestPDPoolMember
deriving instance Eq TestPDPoolMember
instance Arbitrary TestPDPoolMember where
    arbitrary = PDPoolMember <$> arbitrary <*> arbitrary <*> arbitrary

type TestPDPoolMemberMU = PDPoolMemberMU TestMonetaryTypes TesBasicParticle
