
import Parser
import Semantic

import Control.Monad
import Control.Exception
import System.IO
import System.Exit

main :: IO ()
main = catch (liftM semanticAnalyze
              (parseProgram "test/sort.c") >>= print) err
    where
      err e = do
        hPutStrLn stderr $ show (e :: SomeException)
        exitFailure
