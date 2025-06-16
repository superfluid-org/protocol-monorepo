{-# LANGUAGE TypeFamilies #-}
module Money.Theory.TestMonetaryTypes where
-- quickcheck
import           Test.QuickCheck
--
import           Money.Theory.SemanticMoney


-- TestMonetaryTypes
--

newtype TestTime = TestTime Integer deriving (Enum, Eq, Ord, Num, Real, Integral, Show)
instance Arbitrary TestTime where
    arbitrary = TestTime <$> choose (0, 2 ^ (32 :: Integer))

newtype TestMValue = TestMValue Integer deriving (Enum, Eq, Ord, Num, Real, Integral, Show)
instance Arbitrary TestMValue where
    arbitrary = TestMValue <$> arbitrary -- choose (0, 2 ^ (32 :: Integer))

newtype TestMFlowRate = TestMFlowRate Integer deriving (Enum, Eq, Ord, Num, Real, Integral, Show)
instance Arbitrary TestMFlowRate where
    arbitrary = TestMFlowRate <$> arbitrary -- choose (0, 2 ^ (32 :: Integer))

newtype TestMUnit = TestMUnit Integer deriving (Enum, Eq, Ord, Num, Real, Integral, Show)
instance Arbitrary TestMUnit where
    arbitrary = TestMUnit <$> arbitrary -- choose (0, 2 ^ (32 :: Integer))

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

-- TestUniversalIndex
--
type TestUniversalIndex = TesBasicParticle

-- TestPDP_Index, TestPDP_Member, TestPDP_MemberMU
--
type TestPDP_Index = PDP_Index TestMonetaryTypes TesBasicParticle
deriving instance Show TestPDP_Index
instance Arbitrary TestPDP_Index where
    arbitrary = PDP_Index <$> arbitrary <*> arbitrary

type TestPDP_Member = PDP_Member TestMonetaryTypes TesBasicParticle
deriving instance Show TestPDP_Member
instance Arbitrary TestPDP_Member where
    arbitrary = PDP_Member <$> arbitrary <*> arbitrary <*> arbitrary

type TestPDP_MemberMU = PDP_MemberMU TestMonetaryTypes TesBasicParticle
