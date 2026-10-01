{-# LANGUAGE LambdaCase #-}
module Money.Theory.TokenModel.NaiveTokenModel where
-- containers
import qualified Data.IntMap.Lazy           as IntMap
--
import           Money.Theory.SemanticMoney
import           Money.Theory.TokenModel


type Account = Int

data NaiveTokenModel mt = MkNaiveTokenModel
    { accounts :: IntMap.IntMap (BasicParticle mt) -- ^ accounts indexed by Int
    , pools    :: IntMap.IntMap (PDP_Index mt (BasicParticle mt)) -- ^ pools indexed by Int
    }

instance MonetaryTypes mt =>
         TokenModel mt (BasicParticle mt) Account (NaiveTokenModel mt) where
    initToken = MkNaiveTokenModel IntMap.empty IntMap.empty

    tokenAccounts = (snd <$>) . IntMap.toList . accounts

    processOneTokenEvent (MkNaiveTokenModel accs pools) = \case
        TransferEvent t from to amount -> go2 from to (shift2a amount t)
        UpdateFlowEvent t from to rate -> go2 from to (flow2a rate t)
        where go2 from to op =
                  let sender = IntMap.findWithDefault mempty from accs
                      receiver = IntMap.findWithDefault mempty from accs
                      (sender', receiver') = op (sender, receiver)
                      accs' = IntMap.insert from sender'
                              $ IntMap.insert to receiver'
                              $ accs
                  in MkNaiveTokenModel accs' pools
