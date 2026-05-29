{-# LANGUAGE FunctionalDependencies #-}
module Money.Theory.TokenModel
    ( TokenEvent (..)
    , TokenModel (initToken, tokenAccounts, processOneTokenEvent, processTokenEvents, isTokenSolvent)
    ) where
--
import           Money.Theory.SemanticMoney


data TokenEvent mt acc where
    TransferEvent :: forall mt acc {t} {v}.
        MonetaryTypes'tv mt t v =>
        t -> acc -> acc -> v -> TokenEvent mt acc
    UpdateFlowEvent :: forall mt acc {t} {fr}.
        MonetaryTypes'tr mt t fr =>
        t -> acc -> acc -> fr -> TokenEvent mt acc

class MonetaryUnit mt mu =>
      TokenModel mt mu acc token | token -> mu acc where
    initToken :: token

    tokenAccounts :: token -> [mu]

    processOneTokenEvent :: token -> TokenEvent mt acc -> token

    processTokenEvents :: token -> [TokenEvent mt acc] -> token
    processTokenEvents = foldl' processOneTokenEvent

    isTokenSolvent :: token -> Bool
    isTokenSolvent = (== 0) . length . (rtb <$>) . tokenAccounts
