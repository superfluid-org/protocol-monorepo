module Money.Theory.TokenModel.TwoPhaseTokenModel where
-- containers
import qualified Data.IntMap.Lazy           as IntMap
--
import           Money.Theory.SemanticMoney
import           Money.Theory.TokenModel


data TwoPhaseParticle mt = TwoPhaseParticle
    { confirmedParticle :: BasicParticle mt
    , pendingParticle   :: BasicParticle mt
    }
    deriving Eq

instance MonetaryTypes mt => MonetaryUnit mt (TwoPhaseParticle mt) where
    settle t (TwoPhaseParticle p_c p_p) = TwoPhaseParticle p_c (settle t p_p)
    settledAt = settledAt . pendingParticle
    flowRate mu t = flowRate (confirmedParticle mu) t + flowRate (pendingParticle mu) t
    rtb mu t = rtb (confirmedParticle mu) t + rtb (pendingParticle mu) t

syncPhase :: t ~ MT_TIME mt => TwoPhaseParticle mt -> t -> TwoPhaseParticle mt
syncPhase = undefined

type Account = Int

data TwoPhaseTokenModel mt = MkTwoPhaseTokenModel
    { accounts :: IntMap.IntMap (TwoPhaseParticle mt) -- ^ accounts indexed by Int
    , pools    :: IntMap.IntMap (PDP_Index mt (TwoPhaseParticle mt)) -- ^ pools indexed by Int
    }

instance MonetaryTypes mt => TokenModel mt (TwoPhaseParticle mt) Account (TwoPhaseTokenModel mt) where
    -- initToken
    -- tokenAccounts
    -- processOneTokenEvent
