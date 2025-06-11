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
    arbitrary = TestTime <$> arbitrary

newtype TestMValue = TestMValue Integer deriving (Enum, Eq, Ord, Num, Real, Integral, Show)
instance Arbitrary TestMValue where
    arbitrary = TestMValue <$> arbitrary

newtype TestMUnit = TestMUnit Integer deriving (Enum, Eq, Ord, Num, Real, Integral, Show)
instance Arbitrary TestMUnit where
    arbitrary = TestMUnit <$> arbitrary

data TestMonetaryTypes
instance MonetaryTypes TestMonetaryTypes where
    type MT_TIME  TestMonetaryTypes = TestTime
    type MT_VALUE TestMonetaryTypes = TestMValue
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

-- PDP_Index
--
type TestPDP_Index = PDP_Index TestMonetaryTypes TesBasicParticle
deriving instance Show TestPDP_Index
deriving instance Eq TestPDP_Index
instance Arbitrary TestPDP_Index where
    arbitrary = PDP_Index <$> arbitrary <*> arbitrary

-- PDP_Member
--

type TestPDP_Member = PDP_Member TestMonetaryTypes TesBasicParticle
deriving instance Show TestPDP_Member
deriving instance Eq TestPDP_Member
instance Arbitrary TestPDP_Member where
    arbitrary = PDP_Member <$> arbitrary <*> arbitrary <*> arbitrary

type TestPDP_MemberMU = PDP_MemberMU TestMonetaryTypes TesBasicParticle
