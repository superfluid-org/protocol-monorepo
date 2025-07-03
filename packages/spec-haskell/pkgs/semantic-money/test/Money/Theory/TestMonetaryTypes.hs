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
    arbitrary = TestTime <$> arbitrary -- choose (0, 2 ^ (32 :: Integer))

newtype TestMValue = TestMValue Integer deriving (Enum, Eq, Ord, Num, Real, Integral, Show)
instance Arbitrary TestMValue where
    arbitrary = TestMValue <$> arbitrary

newtype TestMFlowRate = TestMFlowRate Integer deriving (Enum, Eq, Ord, Num, Real, Integral, Show)
instance Arbitrary TestMFlowRate where
    arbitrary = TestMFlowRate <$> arbitrary

newtype TestMUnit = TestMUnit Integer deriving (Enum, Eq, Ord, Num, Real, Integral, Show)
instance Arbitrary TestMUnit where
    arbitrary = TestMUnit <$> choose (0, 2 ^ (32 :: Integer))

data TestMonetaryTypes
instance MonetaryTypes TestMonetaryTypes where
    type MT_TIME  TestMonetaryTypes = TestTime
    type MT_VALUE TestMonetaryTypes = TestMValue
    type MT_FLOWRATE TestMonetaryTypes = TestMFlowRate
    type MT_UNIT  TestMonetaryTypes = TestMUnit
deriving instance Show (BasicParticle TestMonetaryTypes)

-- TestBasicParticle
--
type TestBasicParticle = BasicParticle TestMonetaryTypes
instance Arbitrary TestBasicParticle where
    arbitrary = BasicParticle <$> arbitrary <*> arbitrary <*> arbitrary

-- TestPDP_Index, TestPDP_Member, TestPDP_MemberMU
--
type TestPDP_Index = PDP_Index TestMonetaryTypes TestBasicParticle
deriving instance Show TestPDP_Index
instance Arbitrary TestPDP_Index where
    arbitrary = PDP_Index <$> arbitrary <*> arbitrary

type TestPDP_Member = PDP_Member TestMonetaryTypes TestBasicParticle
deriving instance Show TestPDP_Member
instance Arbitrary TestPDP_Member where
    arbitrary = PDP_Member <$> arbitrary <*> arbitrary <*> arbitrary

type TestPDP_MemberMU = PDP_MemberMU TestMonetaryTypes TestBasicParticle
