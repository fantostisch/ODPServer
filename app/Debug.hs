module Debug
  ( debug,
  )
where

--todo: specify option when compiling?
debugEnabled :: Bool
debugEnabled = False

debug :: IO () -> IO ()
debug a =
  if debugEnabled
    then a
    else pure ()
