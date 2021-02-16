module Debug
  ( debug,
  )
where

import qualified Settings

debug :: IO () -> IO ()
debug a =
  if Settings.debugEnabled
    then a
    else pure ()
