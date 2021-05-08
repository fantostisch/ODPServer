module JDNProtocolSpec (spec) where

import qualified Data.ByteString.UTF8 as BSU
import JDNProtocol
import Test.Hspec

spec :: Spec
spec = do
  describe "JDNProtocol" $ do
    it "has a ping message with correct prefix" $ do
      BSU.toString JDNProtocol.ping `shouldBe` "000f{\"func\":\"ping\"}"

    it "has a pong message with correct prefix" $ do
      BSU.toString JDNProtocol.pong `shouldBe` "000f{\"func\":\"pong\"}"
