{-# OPTIONS_GHC -Wall #-}
{-# LANGUAGE TupleSections,
             MultiParamTypeClasses,
             FlexibleInstances #-}

module RPGServer.Global.Settings ( Settings(..),
                                   getSettings ) where

import RPGServer.Common
import Control.Monad.Trans.Reader           ( ReaderT,
                                              asks,
                                              runReaderT )
import Control.Monad.IO.Class               ( MonadIO )
import System.IO                            ( stdout )
import qualified Options.Applicative        as O
import Data.Semigroup                       ((<>))
import qualified System.Log                 as L
import qualified Database.PostgreSQL.Simple as PG


data Settings = Settings {
  logThresh         :: L.Level,
  tcpPort           :: Int,
  pgSettings        :: PG.ConnectInfo,
  saveUtterances    :: Bool
}


instance Show Settings where
  show s = intercalate "\t\n" $ map f [
    ("log threshold",                     show $ logThresh s),
    ("tcp port",                          show $ tcpPort s),
    ("postgres settings",                 show $ pgSettings s),
    ("save utterances to db",             show $ saveUtterances s)
    ]
    where f (k, v) = k ++ ": " ++ v

------------------------------------------------------------

data Subsettings = Subsettings {
  debug       :: Bool,
  _tcpPort    :: Int,
  _saveUtt    :: Bool
}


getSubsettings :: O.Parser Subsettings
getSubsettings = Subsettings
                 <$> O.switch
                 ( O.long "debug"
                   <> O.short 'd'
                   <> O.help "run in debug mode, generating more output" )
                 <*> O.option O.auto
                 ( O.long "tcpport"
                   <> O.short 'p'
                   <> O.help "port number of TCP listener"
                   <> O.value 11237
                   <> O.showDefault
                   <> O.metavar "INT" )
                 <*> O.switch
                 ( O.long "save_utterances"
                   <> O.short 'u'
                   <> O.help "save utterances to DB?"
                   -- <> O.value False
                   -- <> O.showDefault
                 )


getSettings :: IO Settings
getSettings = O.execParser opts >>= ss2s where
  opts = O.info (getSubsettings O.<**> O.helper)
         ( O.fullDesc
           <> O.progDesc "RPG Server"
           <> O.header "rpg - a text-based RPG" )


ss2s :: Subsettings -> IO Settings
ss2s s = return $ Settings {
  logThresh         = if (debug s) then L.Debug else L.Info,
  tcpPort           = _tcpPort s,
  pgSettings        = pg,
  saveUtterances    = _saveUtt s
}
  where pg = PG.ConnectInfo "localhost" 5432 "rpg" "" "rpg"

------------------------------------------------------------

instance MonadIO m => L.LogThreshold (ReaderT Settings m) where
  logThreshold = asks logThresh

instance (MonadIO m, Show t) => L.Log (ReaderT Settings m) t where
  logWrite lev msg = do
    runReaderT (L.logWrite lev $ show msg) . (, stdout) =<< L.logThreshold
