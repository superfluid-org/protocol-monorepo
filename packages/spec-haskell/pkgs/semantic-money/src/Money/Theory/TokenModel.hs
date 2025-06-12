module Money.Theory.TokenModel where
--
import           Money.Theory.SemanticMoney


data TokenEvent mt acc where
    TransferEvent :: forall mt acc {t} {v} {u}.
        MonetaryTypes'tvu mt t v u =>
        t -> acc -> acc -> v -> TokenEvent mt acc
    -- UpdateFlowEvent :: forall mt acc {t} {v} {u}.
    --     MonetaryTypes'tvu mt t v u =>
    --     t -> acc -> acc -> v -> TokenEvent mt acc

data TokenModel mt acc
