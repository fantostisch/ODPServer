module ODPException
  ( ODPException (..),
  )
where

import Control.Exception.Base (Exception)

data ODPException
  = InvalidRequest String
  | JDNCommunicationError String
  deriving (Show)

instance Exception ODPException
