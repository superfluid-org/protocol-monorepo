{-# LANGUAGE LambdaCase #-}
module Money.Theory.TokenModel where
-- containers
import qualified Data.IntMap                as IntMap
--
import           Money.Theory.SemanticMoney


data TokenEvent mt acc where
    TransferEvent :: forall mt acc {t} {v}.
        MonetaryTypes'tv mt t v =>
        t -> acc -> acc -> v -> TokenEvent mt acc
    UpdateFlowEvent :: forall mt acc {t} {fr}.
        MonetaryTypes'tr mt t fr =>
        t -> acc -> acc -> fr -> TokenEvent mt acc

type Account = Int

------------------------------------------------------------------------------------------------------------------------
-- NaiveTokenModel
------------------------------------------------------------------------------------------------------------------------

data NaiveTokenModel mt acc = MkNaiveTokenModel
    { accounts :: IntMap.IntMap (BasicParticle mt) -- ^ accounts indexed by Int
    , pools    :: IntMap.IntMap (PDP_Index mt (BasicParticle mt)) -- ^ pools indexed by Int
    }

naiveProcessOneEvent ::
    MonetaryTypes mt =>
    NaiveTokenModel mt Account ->
    TokenEvent mt Account ->
    NaiveTokenModel mt Account
naiveProcessOneEvent (MkNaiveTokenModel accs pools) = \case
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

naiveProcessEvents ::
    MonetaryTypes mt =>
    [TokenEvent mt Account] ->
    NaiveTokenModel mt Account
naiveProcessEvents = foldl' naiveProcessOneEvent (MkNaiveTokenModel IntMap.empty IntMap.empty)

naiveSystemSnapshot ::
    MonetaryTypes'tv mt t v =>
    NaiveTokenModel mt Account ->
    IntMap.IntMap (t -> v)
naiveSystemSnapshot = (rtb <$>) . accounts
