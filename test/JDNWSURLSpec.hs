module JDNWSURLSpec (spec) where

import Data.Either
import Data.Functor ((<&>))
import JDNWSURL
import Test.Hspec

spec :: Spec
spec = do
  describe "JDNWSURL" $ do
    it "allows all known JDN websocket URLS" $ do
      [ "ire-prod-drs.justdancenow.com",
        "sap-prod-drs.justdancenow.com",
        "sin-prod-drs.justdancenow.com",
        "vir-prod-drs.justdancenow.com"
        ]
        `shouldSatisfy` all (\host -> (JDNWSURL.newJDNWSURL host [] <&> JDNWSURL.host) == Right host)

    it "does not allow domains not from JDN" $ do
      [ "example.org",
        "ire-prod-drs.justdancenow.com.nl",
        "ire-prod-drs.justdancenow.co",
        "ire-prod-drs.justdancenow.com-justdancenow.com",
        "ire-prod-drs-justdancenow.com"
        ]
        `shouldSatisfy` all (\host -> Data.Either.isLeft (JDNWSURL.newJDNWSURL host []))
