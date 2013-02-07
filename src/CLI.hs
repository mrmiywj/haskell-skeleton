{- CLI -- command-line options
Copyright (C) 2013  Benjamin Barenblat <bbaren@mit.edu>

This file is a part of decafc.

decafc is free software: you can redistribute it and/or modify it under the
terms of the MIT (X11) License as described in the LICENSE file.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE.  See the X11 license for more details. -}
module CLI (getConfiguration) where

import Control.Applicative ((<$>))
import Control.Monad (foldM)
import Control.Monad.Error (ErrorT(..), runErrorT)
import Control.Monad.Trans (liftIO)
import Data.List.Split (wordsBy)
import System.Console.GetOpt
import System.Environment (getArgs, getProgName)
import Text.Printf (printf)

import Configuration


--------------------------------- FlagAction ----------------------------------

-- I'll describe the behavior of each flag in terms of a 'FlagAction':
type FlagAction = Configuration -> Either String Configuration

{- Later, I'll 'foldM' over a list of FlagActions to apply them to a
configuration type.  If a FlagAction fails (e.g., because it was unable to
parse an argument), it'll return a 'Left', in which case the error will be
detectable at the end of the fold.  (Of course, I won't be able to recover from
command-line errors, but this seems reasonable behavior for a compiler. -}


------------------------------- Available flags -------------------------------

generateUsage :: IO String
generateUsage = do
  firstLine <- generateSummary
  return $ unlines [ firstLine
                   , usageInfo "Summary of options:" options
                   , "Long description of options:"
                   , longDescription
                   ]

generateSummary :: IO String
generateSummary =
  printf "%s [options] <filename>"
         <$> getProgName

options :: [OptDescr FlagAction]
options = [ Option ['t'] ["target"]
                   (ReqArg (\stage -> \conf -> do
                                         parsedStage <- readStage stage
                                         return $ conf { target = parsedStage })
                           "<stage>")
                   "compile to the given stage"
          , Option ['o'] ["output"]
                   (ReqArg (\outfile -> \conf ->
                                         Right $ conf { explicitOutput = Just outfile })
                           "<outfile>")
                   "write output to <outfile>"
          , Option ['O'] ["opt"]
                   (ReqArg (\optSpec -> \conf -> do
                                           parsedOptSpec <- readOptimizationSpec optSpec
                                           return $ conf { opt = parsedOptSpec })
                           "<(opt|-opt|all)...>")
                   "perform the listed optimizations"
          , Option ['d'] ["debug"]
                   (NoArg (\conf -> Right $ conf { debug = True }))
                   "print debugging information"
          ]

longDescription :: String
longDescription = unlines [ "  -t <stage>          <stage> is one of \"scan\", \"parse\", \"inter\", or \"assembly\"."
                          , "  --target=<stage>    Compilation will proceed to the given stage and halt there."
                          , "  "
                          , "  -d                  Print debugging information.  If this option is not given,"
                          , "  --debug             then there will be no output to the screen on successful"
                          , "  "
                          , "  -O <optspec>        Perform the listed optimizations.  <optspec> is a comma-"
                          , "  --opt=<optspec>     separated list of optimization names, or the special symbol"
                          , "                      \"all\", meaning all possible optimizations.  You may"
                          , "                      explicitly disable an optimization by prefixing its name"
                          , "                      '-'.  As an example, \"hoistLoop,-unrollLoops\" will enable"
                          , "                      hoisting of loop invariant code but will disable loop"
                          , "                      unrolling."
                          , "  "
                          , "  -o <outfile>        Write output to <outfile>.  If this option is not given,"
                          , "  --output=<outfile>  output will be written to a file with the same base name as"
                          , "                      the input file and the extension changed according to the"
                          , "                      final stage executed."
                          ]


---------------------------- Reading option specs -----------------------------

readStage :: String -> Either String CompilerStage
readStage stageString =
  case reads stageString of
    [(stage, "")] -> Right stage
    _ -> Left $ printf "Unknown stage \"%s\"" stageString

readOptimizationSpec :: String -> Either String OptimizationSpecification
readOptimizationSpec optString =
  let opts = wordsBy (==',') optString in
  if "all" `elem` opts
  then Right All
  else Right $ Some $ map (\optSpec -> case optSpec of
                                         ('-':optName) -> Disable optName
                                         optName -> Enable optName)
                          opts


------------------------------ Main entry points ------------------------------

{-| Parses command-line options, returning a 'Configuration' describing the
behavior of the compiler. -}
getConfiguration :: IO (Either String Configuration)
getConfiguration = runErrorT $ do
  -- Fetch the arguments and process them.
  args <- liftIO getArgs
  let (flagActions, nonOptions, errors) = getOpt Permute options args
  -- If there were any errors, notify the monad.
  mapM_ (hoistEither . Left) errors
  {- Construct the options struct by applying the 'flagActions' to the default
  configuration. -}
  selectedOptions <-
    hoistEither $ foldM (flip id) defaultConfiguration flagActions
  -- What file are we reading?
  inputFileName <-
    hoistEither $ maybeToEither "No input file specified" $ headMay nonOptions
  return $ selectedOptions { input = inputFileName }


----------------------------------- Utility -----------------------------------

headMay :: [a] -> Maybe a
headMay [] = Nothing
headMay (x:_) = Just x

maybeToEither :: e -> Maybe a -> Either e a
maybeToEither _ (Just a) = Right a
maybeToEither msg Nothing = Left msg

hoistEither :: (Monad m) => Either e a -> ErrorT e m a
hoistEither = ErrorT . return