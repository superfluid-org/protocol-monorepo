module Money.Theory.TokenModel.TwoPhaseTokenModel where
-- containers
import qualified Data.IntMap.Lazy           as IntMap
--
import           Money.Theory.SemanticMoney
import           Money.Theory.TokenModel


data TwoPhaseParticle mt = MkTwoPhaseParticle
    { confirmedParticle :: BasicParticle mt
    , pendingParticle   :: BasicParticle mt
    }
    deriving Eq

instance MonetaryTypes mt => MonetaryUnit mt (TwoPhaseParticle mt) where
    settle t (MkTwoPhaseParticle p_c p_p) = MkTwoPhaseParticle p_c (settle t p_p)
    settledAt = settledAt . pendingParticle
    flowRate mu t =
        flowRate (confirmedParticle mu) t +
        if t > settledAt (confirmedParticle mu) then flowRate (pendingParticle mu) t else 0
    rtb mu t =
        rtb (confirmedParticle mu) t +
        if t > settledAt (confirmedParticle mu) then rtb (pendingParticle mu) t else 0

type Account = Int

data TwoPhaseTokenModel mt = MkTwoPhaseTokenModel
    { accounts :: IntMap.IntMap (TwoPhaseParticle mt) -- ^ accounts indexed by Int
    , pools    :: IntMap.IntMap (PDP_Index mt (TwoPhaseParticle mt)) -- ^ pools indexed by Int
    }

instance MonetaryTypes mt => TokenModel mt (TwoPhaseParticle mt) Account (TwoPhaseTokenModel mt) where
    -- initToken
    -- tokenAccounts
    -- processOneTokenEvent
