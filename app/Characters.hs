{-# LANGUAGE OverloadedStrings #-}

module Characters
  ( aTozLower,
    aTozUpper,
    numeric,
    aToZLowerUpperNumeric,
  )
where

import Data.Text (Text)
import qualified Data.Text as Text

aTozLower :: Text
aTozLower = "abcdefghijklmnopqrstuvwxyz"

aTozUpper :: Text
aTozUpper = Text.toUpper aTozLower

numeric :: Text
numeric = "01234567890"

aToZLowerUpperNumeric :: Text
aToZLowerUpperNumeric = aTozLower <> aTozUpper <> numeric
